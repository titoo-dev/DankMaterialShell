# Tailscale "lancée" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an exit-node selector, per-peer latency, and a "send to default device" two-zone drop surface to the island's Tailscale integration.

**Architecture:** `TailscaleService` gains exit-node candidate reads (`tailscale status --json`), set/clear actions (`pkexec`), per-peer ping (`tailscale ping`), and default-device helpers. `TailscalePanel` renders the exit-node section, latency pills, and a star toggle. `DynamicIsland`'s pill drop opens a visual two-zone surface that routes by drop X position.

**Tech Stack:** QML (Quickshell), `Quickshell.Io` `Process`/`SplitParser`/`StdioCollector`, `pkexec` + DMS polkit agent, the `tailscale` CLI.

## Global Constraints

- **No `console.*` in QML** — use the `Log` service.
- **`pkexec` sanitizes PATH** → privileged calls use the resolved `_tsBin` absolute path (already on `TailscaleService` from the login flow). Non-privileged calls (`tailscale ping`, `tailscale status`) use bare `tailscale` (normal PATH).
- **Process API:** `onExited: exitCode => {…}`; `stdout`/`stderr` = `SplitParser { splitMarker: "\n"; onRead }` or `StdioCollector { onStreamFinished }`.
- **No `qmllint`** → verify via the live working-tree shell journal + screenshots.
- **pkexec exit codes:** 126/127 = cancelled (treat as no-op, no error).
- Builds on existing `TailscaleService`: `allPeersList`, `myOnlinePeers`, `isMine(peer)`, `connected`, `usingExitNode`, `exitNodeName`, `_tsBin`, `getStatus()`, and the existing `pings`-free state.
- Reuse `DankButton`, `DankActionButton`, `DankIcon`, `StyledText` (`qs.Widgets`).

---

### Task 1: `TailscaleService` — exit-node candidates + set/clear + ping + default device

**Files:**
- Modify: `quickshell/Services/TailscaleService.qml` (add after the login-flow block)

**Interfaces:**
- Consumes: `allPeersList`, `myOnlinePeers`, `_tsBin`, `getStatus()`, `SettingsData.taildropDefaultPeer` (Task 2).
- Produces: `exitNodePeers: var`, `exitNodeError: string`, `setExitNode(peer)`, `clearExitNode()`, `refreshExitInfo()`, `pings: var` (map ip→{ms,route,state}), `pingMyOnline()`, `pingPeer(ip)`, `defaultPeer: var`, `defaultPeerOnline: bool`. Consumed by Tasks 3-4.

- [ ] **Step 1: Add the block**

After the `onConnectedChanged` login-clear handler, add:

```qml
    // ---- exit-node candidates (read directly from `tailscale status --json`) ----
    property var exitNodeOfferIps: ({})
    property string exitNodeError: ""
    function refreshExitInfo() {
        exitInfoProc.running = true;
    }
    Process {
        id: exitInfoProc
        running: false
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text || "{}");
                    const offers = {};
                    const collect = n => {
                        if (n && n.ExitNodeOption && n.TailscaleIPs && n.TailscaleIPs.length > 0)
                            offers[n.TailscaleIPs[0]] = true;
                    };
                    if (d.Self)
                        collect(d.Self);
                    if (d.Peer)
                        for (const k in d.Peer)
                            collect(d.Peer[k]);
                    root.exitNodeOfferIps = offers;
                } catch (e) {
                    root.log.warn("status --json parse failed:", e);
                }
            }
        }
    }
    readonly property var exitNodePeers: allPeersList.filter(p => root.exitNodeOfferIps[p.tailscaleIp])

    function setExitNode(peer) {
        if (!peer)
            return;
        const tgt = peer.tailscaleIp || peer.hostname || "";
        if (tgt.length === 0)
            return;
        exitNodeError = "";
        exitNodeProc.command = ["pkexec", root._tsBin, "set", "--exit-node=" + tgt];
        exitNodeProc._err = "";
        exitNodeProc.running = true;
    }
    function clearExitNode() {
        exitNodeError = "";
        exitNodeProc.command = ["pkexec", root._tsBin, "set", "--exit-node="];
        exitNodeProc._err = "";
        exitNodeProc.running = true;
    }
    Process {
        id: exitNodeProc
        running: false
        property string _err: ""
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => { if (data && data.length > 0) exitNodeProc._err = data; }
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.exitNodeError = "";
                root.getStatus();
                root.refreshExitInfo();
            } else if (exitCode !== 126 && exitCode !== 127) {
                root.exitNodeError = exitNodeProc._err.length > 0 ? exitNodeProc._err : I18n.tr("Exit node change failed");
            }
            exitNodeProc._err = "";
        }
    }

    // ---- per-peer latency (tailscale ping, no root; serial queue) ----
    property var pings: ({})   // ip -> { ms: int, route: "direct"|"relay", state: "ok"|"pending"|"fail" }
    property var _pingQueue: []
    function pingMyOnline() {
        const q = [];
        const peers = myOnlinePeers;
        for (var i = 0; i < peers.length; i++) {
            if (peers[i].tailscaleIp)
                q.push(peers[i].tailscaleIp);
        }
        _pingQueue = q;
        _pingNext();
    }
    function pingPeer(ip) {
        if (!ip)
            return;
        const q = _pingQueue.slice();
        q.push(ip);
        _pingQueue = q;
        _pingNext();
    }
    function _pingNext() {
        if (pingProc.running || _pingQueue.length === 0)
            return;
        const q = _pingQueue.slice();
        const ip = q.shift();
        _pingQueue = q;
        const m = Object.assign({}, root.pings);
        m[ip] = { ms: -1, route: "", state: "pending" };
        root.pings = m;
        pingProc._ip = ip;
        pingProc._out = "";
        pingProc.command = ["tailscale", "ping", "--c", "1", "--timeout", "5s", ip];
        pingProc.running = true;
    }
    Process {
        id: pingProc
        running: false
        property string _ip: ""
        property string _out: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => { if (data && data.length > 0) pingProc._out = data; }
        }
        onExited: exitCode => {
            const ip = pingProc._ip;
            const line = pingProc._out;
            const m = Object.assign({}, root.pings);
            const rtt = line.match(/in ([0-9.]+)\s*ms/);
            if (exitCode === 0 && rtt)
                m[ip] = { ms: Math.round(parseFloat(rtt[1])), route: /DERP|relay/i.test(line) ? "relay" : "direct", state: "ok" };
            else
                m[ip] = { ms: -1, route: "", state: "fail" };
            root.pings = m;
            pingProc.running = false;
            root._pingNext();
        }
    }

    // ---- default Taildrop device (set via the star toggle in the panel) ----
    readonly property var defaultPeer: {
        const h = SettingsData.taildropDefaultPeer;
        if (!h || h.length === 0)
            return null;
        const peers = allPeersList;
        for (var i = 0; i < peers.length; i++)
            if (peers[i].hostname === h)
                return peers[i];
        return null;
    }
    readonly property bool defaultPeerOnline: defaultPeer !== null && defaultPeer.online === true
```

- [ ] **Step 2: Verify journal clean**

Run: `sleep 2 && journalctl --user -u dms.service --since "20 seconds ago" | grep -iE "TailscaleService|\.qml:[0-9]|error:|is not defined" | grep -v INFO | tail`
Expected: empty.

- [ ] **Step 3: Commit**

```bash
git add quickshell/Services/TailscaleService.qml
git commit -m "feat(tailscale): exit-node candidates/set/clear + per-peer ping + default device"
```

---

### Task 2: Settings — `taildropDefaultPeer`

**Files:**
- Modify: `quickshell/Common/SettingsData.qml` (after `taildropReceiveDir`)
- Modify: `quickshell/Common/settings/SettingsSpec.js` (after `taildropReceiveDir`)

**Interfaces:**
- Produces: `SettingsData.taildropDefaultPeer: string` (default `""`).

- [ ] **Step 1: SettingsData.qml**

After `property string taildropReceiveDir: ""`, add:

```qml
    property string taildropDefaultPeer: ""
```

- [ ] **Step 2: SettingsSpec.js**

After `taildropReceiveDir: { def: "" },`, add:

```js
    taildropDefaultPeer: { def: "" },
```

- [ ] **Step 3: Verify + commit**

Run: `sleep 2 && journalctl --user -u dms.service --since "15 seconds ago" | grep -iE "SettingsData|\.qml:[0-9]|error:" | grep -v INFO | tail`
Expected: empty.

```bash
git add quickshell/Common/SettingsData.qml quickshell/Common/settings/SettingsSpec.js
git commit -m "feat(taildrop): taildropDefaultPeer setting"
```

---

### Task 3: `TailscalePanel` — exit-node section + latency pills + star toggle

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml`

**Interfaces:**
- Consumes: `TailscaleService.exitNodePeers`, `usingExitNode`, `exitNodeName`, `setExitNode`/`clearExitNode`, `pings`, `pingMyOnline`, `refreshExitInfo`, `isMine`, `SettingsData.taildropDefaultPeer`.

- [ ] **Step 1: Refresh exit info + ping on open**

Change the existing `onTsActiveChanged` line:

```qml
    onTsActiveChanged: if (tsActive) {
        TailscaleService.getStatus()
        TailscaleService.refreshExitInfo()
        TailscaleService.pingMyOnline()
    }
```

Also make the refresh button re-ping: in the header `DankActionButton { iconName: "sync" … onClicked: TailscaleService.refresh(null) }`, change to:

```qml
            onClicked: { TailscaleService.refresh(null); TailscaleService.refreshExitInfo(); TailscaleService.pingMyOnline() }
```

- [ ] **Step 2: Add the exit-node section after the status line**

Immediately after the status-line `StyledText { … }` (the tailnet/exit-node line), add:

```qml
    // ---- exit-node selector ----
    Column {
        width: parent.width
        spacing: Theme.spacingXS
        visible: TailscaleService.connected && (TailscaleService.exitNodePeers.length > 0 || TailscaleService.usingExitNode)

        RowLayout {
            width: parent.width
            spacing: Theme.spacingS
            DankIcon { name: "public"; size: 16; color: TailscaleService.usingExitNode ? Theme.primary : Theme.surfaceVariantText; Layout.alignment: Qt.AlignVCenter }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Theme.fontSizeSmall
                color: tsCol.island.textColor
                elide: Text.ElideRight
                text: TailscaleService.usingExitNode ? (I18n.tr("Exit node") + ": " + TailscaleService.exitNodeName) : I18n.tr("Exit node")
            }
            DankButton {
                visible: TailscaleService.usingExitNode
                text: I18n.tr("Disconnect")
                buttonHeight: 26
                backgroundColor: Theme.surfaceContainerHigh
                onClicked: TailscaleService.clearExitNode()
            }
        }
        StyledText {
            width: parent.width
            visible: TailscaleService.exitNodeError.length > 0
            font.pixelSize: 10
            color: Theme.error
            wrapMode: Text.WordWrap
            text: TailscaleService.exitNodeError
        }
        Flow {
            width: parent.width
            spacing: Theme.spacingXS
            Repeater {
                model: TailscaleService.exitNodePeers
                delegate: DankButton {
                    required property var modelData
                    readonly property bool active: TailscaleService.activeExitNode && TailscaleService.activeExitNode.tailscaleIp === modelData.tailscaleIp
                    text: (modelData.hostname || modelData.tailscaleIp) + (active ? " ✓" : "")
                    buttonHeight: 26
                    backgroundColor: active ? Theme.primary : Theme.surfaceContainerHigh
                    textColor: active ? Theme.onPrimary : Theme.surfaceText
                    onClicked: active ? TailscaleService.clearExitNode() : TailscaleService.setExitNode(modelData)
                }
            }
        }
    }
```

- [ ] **Step 3: Add a latency pill to the peer card**

In the peer-card delegate's inner `Column { … }` (the one holding hostname + IP `StyledText`s), add a third `StyledText` after the IP one:

```qml
                            StyledText {
                                readonly property var p: TailscaleService.pings[modelData.tailscaleIp]
                                visible: modelData.online && p !== undefined
                                text: {
                                    if (!p) return ""
                                    if (p.state === "pending") return "…"
                                    if (p.state === "fail") return "—"
                                    return p.ms + " ms · " + (p.route === "relay" ? I18n.tr("relay") : I18n.tr("direct"))
                                }
                                font.pixelSize: 10
                                color: Theme.surfaceVariantText
                            }
```

- [ ] **Step 4: Add the star (default-device) toggle to the peer card**

In the peer-card delegate's `RowLayout { id: peerRow … }`, before the `DankActionButton { iconName: "content_copy" … }`, add:

```qml
                        DankActionButton {
                            visible: TailscaleService.isMine(modelData) && (modelData.tailscaleIp || "").length > 0
                            iconName: modelData.hostname === SettingsData.taildropDefaultPeer ? "star" : "star_border"
                            buttonSize: 20
                            iconSize: 13
                            iconColor: modelData.hostname === SettingsData.taildropDefaultPeer ? Theme.primary : Theme.surfaceVariantText
                            tooltipText: I18n.tr("Default Taildrop device")
                            onClicked: SettingsData.set("taildropDefaultPeer", SettingsData.taildropDefaultPeer === modelData.hostname ? "" : modelData.hostname)
                        }
```

- [ ] **Step 5: Verify (open panel) + commit**

Run: `dms ipc call island close; sleep 1; dms ipc call island open tailscale; sleep 2; journalctl --user -u dms.service --since "15 seconds ago" | grep -iE "TailscalePanel|\.qml:[0-9]|error:|is not a function" | grep -v INFO | tail`
Expected: `ISLAND_OPEN:tailscale`; grep empty. (You should see latency pills populate on the online peer card; the star is clickable.)

```bash
git add quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml
git commit -m "feat(island): exit-node selector + latency pills + default-device star"
```

---

### Task 4: Two-zone drop surface (`DropChoosePanel.qml`, `DynamicIsland.qml`, `ControlCenterPanel.qml`)

**Files:**
- Create: `quickshell/Modules/DynamicIsland/panels/DropChoosePanel.qml`
- Modify: `quickshell/Modules/DynamicIsland/DynamicIsland.qml` (the `shelfDrop` DropArea + a `_dropHalf` prop)
- Modify: `quickshell/Modules/DynamicIsland/ControlCenterPanel.qml` (register `"dropchoose"`)

**Interfaces:**
- Consumes: `TailscaleService.defaultPeerOnline`, `TailscaleService.defaultPeer`, `TaildropService.send`, `ShelfService.addUrls/addText`, `island._dropHalf`.

- [ ] **Step 1: Create the visual two-zone panel**

Create `quickshell/Modules/DynamicIsland/panels/DropChoosePanel.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Visual-only two-zone drop surface (Shelf | → default device). The actual drop
// is handled by the pill's shelfDrop DropArea, which routes by drop X position;
// this just shows the two halves and highlights the one under the cursor
// (island._dropHalf == "left" | "right").
Item {
    id: dropChoose
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    implicitHeight: 92
    opacity: island.panelView === "dropchoose" ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.cornerRadius
            readonly property bool hot: dropChoose.island._dropHalf === "left"
            color: hot ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : Theme.surfaceContainerHigh
            border.width: hot ? 1 : 0
            border.color: Theme.primary
            Column {
                anchors.centerIn: parent
                spacing: 2
                DankIcon { name: "inventory_2"; size: 22; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText { text: I18n.tr("Shelf"); font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.cornerRadius
            readonly property bool hot: dropChoose.island._dropHalf === "right"
            color: hot ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : Theme.surfaceContainerHigh
            border.width: hot ? 1 : 0
            border.color: Theme.primary
            Column {
                anchors.centerIn: parent
                spacing: 2
                DankIcon { name: "send_to_mobile"; size: 22; color: Theme.primary; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText {
                    text: "→ " + (TailscaleService.defaultPeer ? (TailscaleService.defaultPeer.hostname || "") : "")
                    font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
```

- [ ] **Step 2: Register `"dropchoose"` in ControlCenterPanel.qml**

Add to the `viewRegistry` object and a Component (next to `tsComp`):

```qml
                    "tailscale": tsComp,
                    "dropchoose": dropChooseComp
                })
```
and:
```qml
                Component { id: dropChooseComp; DropChoosePanel { island: ccPanel.island } }
```

- [ ] **Step 3: Wire the pill drop in DynamicIsland.qml**

Add a `_dropHalf` property near the other shelf state (after `property bool _shelfAutoOpened: false`):

```qml
    property string _dropHalf: "left"   // which half of the dropchoose surface the drag is over
```

Replace the `shelfDrop` DropArea body with:

```qml
            DropArea {
                id: shelfDrop
                anchors.fill: parent
                onEntered: drag => {
                    if (!drag.hasUrls && !drag.hasText) { drag.accepted = false; return }
                    if (root.mode !== "expanded") {
                        root._shelfAutoOpened = true
                        root.bump()
                    }
                    // a file drag with a configured online default device → offer the
                    // two-zone chooser; otherwise the plain shelf
                    if (drag.hasUrls && TailscaleService.defaultPeerOnline)
                        root.openPanel("dropchoose")
                    else
                        root.openPanel("shelf")
                }
                onPositionChanged: drag => {
                    if (root.panelView === "dropchoose")
                        root._dropHalf = (drag.x > shelfDrop.width / 2) ? "right" : "left"
                }
                onExited: {
                    if (root._shelfAutoOpened) {
                        root._shelfAutoOpened = false
                        root.closeIsland()
                    }
                }
                onDropped: drop => {
                    root._shelfAutoOpened = false
                    if (root.panelView === "dropchoose" && drop.hasUrls && drop.x > shelfDrop.width / 2) {
                        // right half → Taildrop to the default device
                        const paths = []
                        for (var i = 0; i < drop.urls.length; i++) {
                            const u = String(drop.urls[i])
                            if (u.startsWith("file://"))
                                paths.push(decodeURIComponent(u.substring(7)))
                        }
                        if (paths.length > 0 && TailscaleService.defaultPeer)
                            TaildropService.send(paths, TailscaleService.defaultPeer)
                    } else if (drop.hasUrls) {
                        ShelfService.addUrls(drop.urls)
                    } else if (drop.hasText) {
                        ShelfService.addText(drop.text)
                    }
                    drop.accept(Qt.CopyAction)
                    root.bump()
                }
            }
```

Ensure `TaildropService` and `TailscaleService` are reachable — `DynamicIsland.qml` already imports `qs.Services`.

- [ ] **Step 4: Verify (simulate a drag is hard; check load + registry) + commit**

Run: `sleep 2 && journalctl --user -u dms.service --since "20 seconds ago" | grep -iE "DropChoosePanel|DynamicIsland|ControlCenterPanel|\.qml:[0-9]|error:|is not defined" | grep -v INFO | tail`
Expected: empty. Then `dms ipc call island open dropchoose` is NOT valid (not in IslandHub views; it's drag-only) — instead confirm the registry compiles by opening another view: `dms ipc call island open tailscale` works.

```bash
git add quickshell/Modules/DynamicIsland/panels/DropChoosePanel.qml quickshell/Modules/DynamicIsland/ControlCenterPanel.qml quickshell/Modules/DynamicIsland/DynamicIsland.qml
git commit -m "feat(island): two-zone drop surface — Shelf or Taildrop-to-default-device"
```

---

### Task 5: Verification

- [ ] **Step 1: No QML errors anywhere**

Run: `journalctl --user -u dms.service --since "3 minutes ago" | grep -iE "TailscaleService|TailscalePanel|DropChoosePanel|\.qml:[0-9]|TypeError|is not a function|is not defined" | grep -v INFO | tail -20`
Expected: empty.

- [ ] **Step 2: Latency renders**

Open the panel (SUPER+ALT+T) → the online peer card (self counts? no — `myOnlinePeers` excludes nothing; self IS online and mine) shows a "N ms · direct/relay" pill or "—". Confirm via screenshot.

- [ ] **Step 3: Exit-node section**

If any tailnet device offers exit, the exit-node section lists it with a button. On this tailnet none may offer exit → the section stays hidden (expected). Force-render via temp `visible: true` + screenshot to confirm layout, then revert.

- [ ] **Step 4: Star toggle**

Click the star on an owned peer card → `SettingsData.taildropDefaultPeer` updates (the star fills). Re-click clears it.

- [ ] **Step 5: Two-zone drop (user, needs an online default device)**

Star an online device, then drag a file onto the island → two zones appear (Shelf | → device); the half under the cursor highlights; drop right → Taildrop send pop, drop left → added to Shelf.

- [ ] **Step 6: Final**

Run: `git status` → clean (all committed; unrelated QuizWidget edits, if any, untouched).

---

## Self-Review

**Spec coverage:**
- Exit-node candidates (QML `status --json` read) → Task 1 ✅; set/clear (pkexec) → Task 1 ✅; panel section → Task 3 ✅
- Per-peer latency (ping, serial queue, parse) → Task 1 ✅; pills + ping-on-open → Task 3 ✅
- Default device (`taildropDefaultPeer`, star) → Task 2 + Task 3 ✅; helpers `defaultPeer`/`defaultPeerOnline` → Task 1 ✅
- Two-zone drop surface (visual + X-position routing) → Task 4 ✅
- Error/edges: pkexec cancel 126/127 ignored (Task 1); ping fail → "—" (Task 1/3); default peer offline → right zone absent (`defaultPeerOnline` gate, Task 4); non-file drop → shelf only (Task 4 branches on `drop.hasUrls`) ✅
- Testing → Task 5 ✅

**Placeholder scan:** none — all code complete.

**Type consistency:** `exitNodePeers`/`exitNodeError`/`setExitNode`/`clearExitNode`/`refreshExitInfo`/`pings`/`pingMyOnline`/`defaultPeer`/`defaultPeerOnline` defined in Task 1, used verbatim in Tasks 3-4. `activeExitNode` is an existing property. `taildropDefaultPeer` consistent Tasks 1-3. `_dropHalf` defined + used in Task 4. `DropChoosePanel`/`dropChooseComp`/`"dropchoose"` consistent in Task 4. `Theme.onPrimary` — verify it exists (fallback `Theme.background` if not).
```
