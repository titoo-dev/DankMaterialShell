pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

// Generic live-activity store: scriptable, multi-activity, updatable progress.
// Driven by IPC (see IslandHub.activity). Ephemeral — not persisted.
Singleton {
    id: root
    readonly property var log: Log.scoped("ActivityService")

    // each: { id, label, icon, progress (-1=indeterminate | 0..100), state, _expireAt }
    property var activities: []
    readonly property int runningCount: activities.filter(a => a.state === "running").length
    readonly property var primary: {
        const r = activities.filter(a => a.state === "running");
        if (r.length > 0)
            return r[0];
        return activities.length > 0 ? activities[0] : null;
    }
    signal activityFinished(string id, bool ok)
    signal activityDismissed(string id)

    // glanceable history: splashes are fire-and-forget, so keep the last few
    // here for the Activities drill ("what just popped?"). Newest first,
    // RAM only. each: { icon, label, ts }
    property var recents: []
    function record(icon, label) {
        if (!label || label.length === 0)
            return;
        const arr = recents.slice();
        arr.unshift({ icon: (icon && icon.length > 0) ? icon : "info", label: label, ts: Date.now() });
        if (arr.length > 20)
            arr.length = 20;
        recents = arr;
    }

    function _find(id) {
        for (var i = 0; i < activities.length; i++)
            if (activities[i].id === id)
                return i;
        return -1;
    }

    function start(id, label, icon) {
        if (!id || id.length === 0)
            return;
        const arr = activities.slice();
        const i = _find(id);
        const entry = {
            id: id,
            label: (label && label.length > 0) ? label : id,
            icon: (icon && icon.length > 0) ? icon : "deployed_code",
            progress: i >= 0 ? arr[i].progress : -1,
            state: "running",
            _expireAt: Date.now() + 3600000
        };
        // refresh-style producers (agenda) call start() repeatedly: update in
        // place so a repeated start never steals primary from another activity
        if (i >= 0)
            arr[i] = entry;
        else
            arr.unshift(entry);
        activities = arr;
    }
    function progress(id, pct) {
        const i = _find(id);
        if (i < 0)
            return;
        const p = Math.round(pct);
        if (isNaN(p))
            return;
        const arr = activities.slice();
        arr[i] = Object.assign({}, arr[i], { progress: Math.max(0, Math.min(100, p)), _expireAt: Date.now() + 3600000 });
        activities = arr;
    }
    function update(id, label) {
        const i = _find(id);
        if (i < 0 || !label || label.length === 0)
            return;
        const arr = activities.slice();
        arr[i] = Object.assign({}, arr[i], { label: label, _expireAt: Date.now() + 3600000 });
        activities = arr;
    }
    function done(id, label) {
        _finish(id, label, "done", true);
    }
    function fail(id, label) {
        _finish(id, label, "failed", false);
    }
    function _finish(id, label, state, ok) {
        const i = _find(id);
        if (i < 0)
            return;
        const arr = activities.slice();
        const e = Object.assign({}, arr[i], { state: state, _expireAt: Date.now() + 3000 });
        if (label && label.length > 0)
            e.label = label;
        if (ok)
            e.progress = 100;
        arr[i] = e;
        activities = arr;
        record(e.icon, (ok ? "✓ " : "✗ ") + e.label);
        activityFinished(id, ok);
    }
    // user-initiated removal (panel ✕) — unlike stop(), it notifies the
    // producer so it can quit ticking blind (ghost alarm) or resurrecting
    function dismiss(id) {
        activityDismissed(id);
        stop(id);
    }
    function stop(id) {
        const i = _find(id);
        if (i < 0)
            return;
        const arr = activities.slice();
        arr.splice(i, 1);
        activities = arr;
    }

    // prune finished entries after their grace window, and running ghosts after the safety TTL
    Timer {
        interval: 1000
        repeat: true
        running: root.activities.length > 0
        onTriggered: {
            const now = Date.now();
            const arr = root.activities.filter(a => !(a._expireAt > 0 && now >= a._expireAt));
            if (arr.length !== root.activities.length)
                root.activities = arr;
        }
    }
}
