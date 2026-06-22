pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

// Taildrop over Tailscale: send files to a peer (`tailscale file cp`) and
// auto-receive incoming files (`tailscale file get`, polled into a dedicated
// folder). Shell-out only; no Go backend changes. Requires the user to have run
// `sudo tailscale set --operator=$USER` once (else file ops are root-only).
Singleton {
    id: root
    readonly property var log: Log.scoped("TaildropService")

    // dedicated receive folder (avoids mistaking unrelated downloads for receipts)
    readonly property string receiveDir: {
        const cfg = SettingsData.taildropReceiveDir
        if (cfg && cfg.length > 0)
            return cfg
        return Paths.strip(StandardPaths.writableLocation(StandardPaths.DownloadLocation)) + "/Taildrop"
    }

    property bool needsOperatorSetup: false
    property bool sending: false

    signal sendStarted(string label, string peerHost)
    signal sendFinished(string label, string peerHost, bool ok, string error)
    signal received(string name)

    function _basename(p) {
        const s = String(p)
        return s.substring(s.lastIndexOf("/") + 1) || s
    }

    // ---- SEND: tailscale file cp <paths...> <ip>: ----
    function send(paths, peer) {
        if (!paths || paths.length === 0 || !peer)
            return
        const ip = peer.tailscaleIp || ""
        if (ip.length === 0)
            return
        const host = peer.hostname || ip
        const label = paths.length === 1 ? _basename(paths[0]) : (paths.length + " " + I18n.tr("files"))
        sendProc._label = label
        sendProc._host = host
        sendProc._err = ""
        sendProc.command = ["tailscale", "file", "cp"].concat(paths).concat([ip + ":"])
        root.sending = true
        root.sendStarted(label, host)
        sendProc.running = true
    }

    Process {
        id: sendProc
        property string _label: ""
        property string _host: ""
        property string _err: ""
        running: false
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => { if (data && data.length > 0) sendProc._err = data }
        }
        onExited: exitCode => {
            root.sending = false
            const ok = exitCode === 0
            if (!ok && /access denied|--operator/i.test(sendProc._err))
                root.needsOperatorSetup = true
            root.sendFinished(sendProc._label, sendProc._host, ok, sendProc._err)
        }
    }

    // ---- RECEIVE: poll `tailscale file get` into receiveDir, diff for new files ----
    property var _seen: ({})
    property bool _seeded: false

    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: SettingsData.taildropReceive && TailscaleService.connected && !root.needsOperatorSetup
        onRunningChanged: if (!running) root._seeded = false   // re-seed next time we start
        onTriggered: if (!getProc.running) getProc.running = true
    }

    Process {
        id: getProc
        running: false
        property var _lines: []
        command: ["sh", "-c",
            'd="$1"; mkdir -p "$d"; out=$(tailscale file get --conflict=rename "$d" 2>&1); echo "GET:$?:$out"; ls -1 "$d"',
            "_", root.receiveDir]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => getProc._lines.push(data)
        }
        onExited: exitCode => {
            const lines = getProc._lines
            getProc._lines = []
            if (lines.length === 0)
                return
            const head = lines[0] || ""
            if (/access denied|--operator/i.test(head)) {
                root.needsOperatorSetup = true
                return
            }
            const listing = lines.slice(1).filter(s => s && s.length > 0)
            if (!root._seeded) {
                const seed = {}
                for (const f of listing)
                    seed[f] = true
                root._seen = seed
                root._seeded = true
                return
            }
            const next = {}
            const fresh = []
            for (const f of listing) {
                next[f] = true
                if (!root._seen[f])
                    fresh.push(f)
            }
            root._seen = next
            for (const f of fresh)
                root.received(f)
        }
    }
}
