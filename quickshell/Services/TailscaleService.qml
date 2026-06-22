pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root
    readonly property var log: Log.scoped("TailscaleService")

    property int refCount: 0

    onRefCountChanged: {
        if (refCount > 0) {
            ensureSubscription();
        } else if (refCount === 0 && DMSService.activeSubscriptions.includes("tailscale")) {
            DMSService.removeSubscription("tailscale");
        }
    }

    function ensureSubscription() {
        if (refCount <= 0)
            return;
        if (!DMSService.isConnected)
            return;
        if (DMSService.activeSubscriptions.includes("tailscale"))
            return;
        if (DMSService.activeSubscriptions.includes("all"))
            return;
        DMSService.addSubscription("tailscale");
        if (available) {
            getStatus();
        }
    }

    property bool connected: false
    property string version: ""
    property string backendState: ""
    property string magicDnsSuffix: ""
    property string tailnetName: ""
    property var selfNode: null
    property var peers: []

    property bool available: false
    property bool stateInitialized: false

    readonly property var allPeersList: {
        const result = [];
        if (selfNode)
            result.push(selfNode);
        if (peers)
            result.push(...peers);
        return result;
    }

    readonly property var onlinePeers: allPeersList.filter(p => p.online)

    readonly property var myPeers: {
        if (!selfNode)
            return allPeersList;
        return allPeersList.filter(p => isMine(p));
    }

    readonly property var myOnlinePeers: {
        if (!selfNode)
            return onlinePeers;
        return allPeersList.filter(p => p.online && isMine(p));
    }

    readonly property int onlinePeerCount: onlinePeers.length

    // the peer currently used as this node's exit node (the `exitNode` flag is
    // already populated per-peer by the Go backend), or null if none
    readonly property var activeExitNode: {
        const list = allPeersList
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].exitNode)
                return list[i]
        }
        return null
    }
    readonly property bool usingExitNode: activeExitNode !== null
    readonly property string exitNodeName: activeExitNode ? (activeExitNode.hostname || "") : ""

    // coarse health bucket derived from the daemon's backendState
    readonly property string statusKind: {
        switch (backendState) {
        case "Running":          return "running"
        case "Starting":
        case "NoState":          return "starting"
        case "Stopped":          return "stopped"
        case "NeedsLogin":       return "needsLogin"
        case "NeedsMachineAuth": return "needsAuth"
        default:                 return backendState === "" ? "starting" : "error"
        }
    }
    // something the user should notice: daemon down / login needed / auth needed
    // / unreachable, or connected-but-isolated (no peers reachable)
    readonly property bool needsAttention: available
        && ((statusKind !== "running" && statusKind !== "starting")
            || (connected && onlinePeerCount === 0))

    // ---- login flow (pkexec tailscale up) ----
    property string authUrl: ""
    property bool loginInProgress: false
    property string loginError: ""
    property string _tsBin: "tailscale"   // pkexec sanitizes PATH → need an absolute path

    // resolve the tailscale binary's absolute path once
    Process {
        running: true
        command: ["sh", "-c", "command -v tailscale || echo tailscale"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = (text || "").trim();
                if (t.length > 0)
                    root._tsBin = t.split("\n")[0];
            }
        }
    }

    function login() {
        if (loginInProgress)
            return;
        loginError = "";
        authUrl = "";
        loginInProgress = true;
        loginProc.command = ["pkexec", root._tsBin, "up"];
        loginProc._lastErr = "";
        loginProc.running = true;
    }

    function cancelLogin() {
        if (loginProc.running)
            loginProc.running = false;
        loginInProgress = false;
        authUrl = "";
    }

    Process {
        id: loginProc
        running: false
        property string _lastErr: ""
        function _scan(line) {
            if (!line || root.authUrl.length > 0)
                return;
            let m = line.match(/https?:\/\/\S*login\.tailscale\.com\S*/);
            if (!m)
                m = line.match(/https?:\/\/\S+/);
            if (m)
                root.authUrl = m[0];
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => loginProc._scan(data)
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                loginProc._scan(data);
                if (data && data.length > 0)
                    loginProc._lastErr = data;
            }
        }
        onExited: exitCode => {
            root.loginInProgress = false;
            if (exitCode === 0) {
                root.authUrl = "";        // authenticated; subscription flips `connected`
                root.loginError = "";
            } else if (exitCode === 126 || exitCode === 127) {
                root.loginError = I18n.tr("Login cancelled");
                root.authUrl = "";
            } else {
                root.loginError = loginProc._lastErr.length > 0 ? loginProc._lastErr : I18n.tr("Login failed");
            }
        }
    }

    // clear login state once we are connected
    onConnectedChanged: if (connected) {
        authUrl = "";
        loginInProgress = false;
        loginError = "";
    }

    readonly property string socketPath: Quickshell.env("DMS_SOCKET")

    Component.onCompleted: {
        if (socketPath && socketPath.length > 0) {
            checkDMSCapabilities();
        }
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                checkDMSCapabilities();
                ensureSubscription();
            }
        }
    }

    Connections {
        target: DMSService
        enabled: DMSService.isConnected

        function onTailscaleStateUpdate(data) {
            root.log.debug("Subscription update received");
            updateState(data);
        }

        function onCapabilitiesReceived() {
            checkDMSCapabilities();
        }
    }

    function checkDMSCapabilities() {
        if (!DMSService.isConnected)
            return;
        if (DMSService.capabilities.length === 0)
            return;
        const wasAvailable = available;
        available = DMSService.capabilities.includes("tailscale");

        if (!available)
            return;
        if (!stateInitialized) {
            stateInitialized = true;
            getStatus();
        }
        if (!wasAvailable)
            ensureSubscription();
    }

    function getStatus() {
        if (!available)
            return;
        DMSService.sendRequest("tailscale.getStatus", null, response => {
            if (response.result) {
                updateState(response.result);
            }
        });
    }

    function updateState(data) {
        if (!data)
            return;
        connected = data.connected || false;
        version = data.version || "";
        backendState = data.backendState || "";
        magicDnsSuffix = data.magicDnsSuffix || "";
        tailnetName = data.tailnetName || "";
        selfNode = data.self || null;
        peers = data.peers || [];
    }

    function refresh(callback) {
        if (!available)
            return;
        DMSService.sendRequest("tailscale.refresh", null, response => {
            if (callback)
                callback(response);
        });
    }

    function isMine(peer) {
        const myOwner = selfNode ? (selfNode.owner || "") : "";
        if (peer.owner === myOwner && myOwner !== "")
            return true;
        if (peer.tags && peer.tags.length > 0)
            return true;
        return false;
    }

    function searchPeers(query, list) {
        const base = list || allPeersList;
        if (!query || query.length === 0)
            return base;
        const q = query.toLowerCase();
        return base.filter(p => {
            if (p.hostname && p.hostname.toLowerCase().includes(q))
                return true;
            if (p.dnsName && p.dnsName.toLowerCase().includes(q))
                return true;
            if (p.tailscaleIp && p.tailscaleIp.includes(q))
                return true;
            if (p.os && p.os.toLowerCase().includes(q))
                return true;
            return false;
        });
    }
}
