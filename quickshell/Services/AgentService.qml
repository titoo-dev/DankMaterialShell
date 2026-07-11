pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

// Coding-agent sessions (Claude Code) as island live activities — the
// vibe-island port. Events arrive from scripts/dms-agent-hook via
//   dms ipc call island agentEvent '<json>'   (see IslandHub.agentEvent)
// and blocked hooks (permission requests, questions) poll a verdict file in
// $XDG_RUNTIME_DIR/dms-agent/<rid> that decide()/answer() write.
Singleton {
    id: root
    readonly property var log: Log.scoped("AgentService")

    // each: { id, agent, title, cwd, anc: [pids], startTs, lastTs,
    //         state: "working"|"waiting"|"done",
    //         feed: [{tool, detail}] newest-first,
    //         pending: null | {rid, kind: "permission"|"question", tool, detail, q, opts},
    //         model, ctx }
    property var sessions: []
    // provider quota from the statusline wrapper (Pro/Max only, else null):
    // { five: {used_percentage, resets_at}|null, seven: {...}|null }
    property var usage: null
    readonly property int waitingCount: sessions.filter(s => s.state === "waiting").length
    signal sessionWaiting(var session)

    // 1s heartbeat for elapsed-time labels while any session lives
    property real now: Date.now()

    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/dms-agent"
    readonly property string scriptsDir: Theme.shellDir + "/../scripts"

    function _find(id) {
        for (var i = 0; i < sessions.length; i++)
            if (sessions[i].id === id)
                return i;
        return -1;
    }
    function _patch(i, patch) {
        const arr = sessions.slice();
        arr[i] = Object.assign({}, arr[i], patch, { lastTs: Date.now() });
        sessions = arr;
        return arr[i];
    }
    function _ensure(e) {
        let i = _find(e.sid);
        if (i >= 0)
            return i;
        const arr = sessions.slice();
        arr.unshift({
            id: e.sid, agent: "claude", title: I18n.tr("Claude Code"),
            cwd: e.cwd || "", anc: e.anc || [],
            startTs: Date.now(), lastTs: Date.now(),
            state: "working", feed: [], pending: null, model: "", ctx: -1
        });
        sessions = arr;
        return 0;
    }

    function ingest(json) {
        let e;
        try {
            e = JSON.parse(json);
        } catch (err) {
            log.warn("bad agentEvent payload:", json);
            return;
        }
        if (!e || !e.ev)
            return;
        if (e.ev === "usage") {
            if (e.five || e.seven)
                usage = { five: e.five || null, seven: e.seven || null };
            const i = e.sid ? _find(e.sid) : -1;
            if (i >= 0)
                _patch(i, { model: e.model || "", ctx: e.ctx !== undefined ? e.ctx : -1 });
            return;
        }
        if (!e.sid)
            return;
        switch (e.ev) {
        case "start": {
            const i = _ensure(e);
            _patch(i, { cwd: e.cwd || sessions[i].cwd, anc: (e.anc && e.anc.length) ? e.anc : sessions[i].anc });
            break;
        }
        case "prompt": {
            const i = _ensure(e);
            const title = (e.prompt || "").split("\n")[0].slice(0, 80) || sessions[i].title;
            // a new prompt starts a new task: elapsed restarts, done → working
            _patch(i, { title: title, state: "working", pending: null,
                        startTs: Date.now(),
                        cwd: e.cwd || sessions[i].cwd,
                        anc: (e.anc && e.anc.length) ? e.anc : sessions[i].anc });
            break;
        }
        case "tool": {
            const i = _ensure(e);
            const feed = [{ tool: e.tool || "?", detail: e.detail || "" }].concat(sessions[i].feed).slice(0, 6);
            // tools can still run under a pending subagent prompt — never
            // clobber a waiting state from the feed
            _patch(i, sessions[i].state === "waiting" ? { feed: feed } : { feed: feed, state: "working" });
            break;
        }
        case "perm": {
            const i = _ensure(e);
            const s = _patch(i, { state: "waiting",
                                  anc: (e.anc && e.anc.length) ? e.anc : sessions[i].anc,
                                  pending: { rid: e.rid, kind: "permission", tool: e.tool || "?", detail: e.detail || "", q: "", opts: [] } });
            sessionWaiting(s);
            break;
        }
        case "question": {
            const i = _ensure(e);
            const s = _patch(i, { state: "waiting",
                                  pending: { rid: e.rid, kind: "question", tool: "", detail: "", q: e.q || "", opts: e.opts || [] } });
            sessionWaiting(s);
            break;
        }
        case "notify": {
            const i = _find(e.sid);
            if (i < 0)
                break;
            // permission_prompt without a pending request = something our
            // blocking hook couldn't carry (e.g. -p mode); still flag it
            if (e.type === "permission_prompt" && !sessions[i].pending) {
                const s = _patch(i, { state: "waiting" });
                sessionWaiting(s);
            } else if (e.type === "idle_prompt" && !sessions[i].pending) {
                _patch(i, { state: "done" });
            }
            break;
        }
        case "stop": {
            const i = _find(e.sid);
            if (i >= 0)
                _patch(i, { state: "done", pending: null });
            break;
        }
        case "end": {
            const i = _find(e.sid);
            if (i >= 0)
                remove(e.sid);
            break;
        }
        }
        _mirror();
    }

    // ---- actions (panel buttons) ----
    function decide(sid, verdict) { // "allow" | "deny" | "pass"
        const i = _find(sid);
        if (i < 0 || !sessions[i].pending)
            return;
        _writeVerdict(sessions[i].pending.rid, verdict);
        // pass = answer in the terminal: the native prompt appears, still waiting
        _patch(i, verdict === "pass" ? { pending: null } : { pending: null, state: "working" });
        _mirror();
    }
    // keyboard path (IslandHub agentAllow/agentDeny): first pending wins
    function decideFirstWaiting(verdict) {
        const s = sessions.find(x => x.pending && x.pending.kind === "permission");
        if (!s)
            return false;
        decide(s.id, verdict);
        return true;
    }
    function answer(sid, label) {
        const i = _find(sid);
        if (i < 0 || !sessions[i].pending)
            return;
        _writeVerdict(sessions[i].pending.rid, "answer:" + label);
        _patch(i, { pending: null, state: "working" });
        _mirror();
    }
    function jump(sid) {
        const i = _find(sid);
        if (i < 0 || !sessions[i].anc || sessions[i].anc.length === 0)
            return;
        Quickshell.execDetached([scriptsDir + "/dms-agent-jump"].concat(sessions[i].anc.map(p => String(p))));
    }
    function remove(sid) {
        const i = _find(sid);
        if (i < 0)
            return;
        if (sessions[i].pending) // unblock the hook → native prompt takes over
            _writeVerdict(sessions[i].pending.rid, "pass");
        const arr = sessions.slice();
        arr.splice(i, 1);
        sessions = arr;
        ActivityService.stop("agent-" + sid);
    }
    function _writeVerdict(rid, v) {
        Quickshell.execDetached(["sh", "-c", 'printf %s "$0" > "$1.tmp" && mv "$1.tmp" "$1"', v, runDir + "/" + rid]);
    }

    // ---- pill mirroring: one ActivityService entry per session ----
    function _mirror() {
        for (var i = 0; i < sessions.length; i++) {
            const s = sessions[i];
            const aid = "agent-" + s.id;
            const label = s.state === "waiting"
                ? I18n.tr("Needs you") + " · " + s.title
                : s.state === "done" ? "✓ " + s.title : s.title;
            ActivityService.start(aid, label, "smart_toy");
            if (s.state !== "working")
                ActivityService.setState(aid, s.state === "waiting" ? "waiting" : "idle");
        }
    }
    Connections {
        target: ActivityService
        function onActivityDismissed(id) {
            if (id.startsWith("agent-"))
                root.remove(id.slice(6));
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.sessions.length > 0
        onTriggered: {
            root.now = Date.now();
            // safety TTL: a session silent for 2h is a ghost (crashed CLI)
            const cut = root.now - 7200000;
            root.sessions.filter(s => s.lastTs < cut).forEach(s => root.remove(s.id));
        }
    }

    function elapsed(s) {
        const secs = Math.max(0, Math.floor((now - s.startTs) / 1000));
        if (secs < 60)
            return secs + "s";
        if (secs < 3600)
            return Math.floor(secs / 60) + "m" + (secs % 60 ? " " + secs % 60 + "s" : "");
        return Math.floor(secs / 3600) + "h " + Math.floor((secs % 3600) / 60) + "m";
    }
}
