# Tailscale Live Activity in the Dynamic Island — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface Tailscale status in the Dynamic Island — a persistent at-rest indicator, transient splashes on state changes, a warning satellite, and a drill-in detail panel — using the island's existing live-activity primitives.

**Architecture:** Direct wiring. Extend the existing `TailscaleService` singleton with derived properties, then consume them from `DynamicIsland.qml` (pass-through props + splash `Connections` + satellite), `IdlePane.qml` (mini-indicator), and a new `panels/TailscalePanel.qml` (drill view), gated by a new settings toggle. No new framework, no required Go changes.

**Tech Stack:** QML (Quickshell), QtQuick. Backend data already flows from the Go `DMSService` socket; no Go changes in v1.

## Global Constraints

- **No `console.*` in QML** — a pre-commit hook rejects `console.log/error/info/warn/debug`. Use the `Log` service (`root.log.debug(...)`) where logging is needed. (TailscaleService already has `readonly property var log: Log.scoped("TailscaleService")`.)
- **Settings persistence** lives in three places that must stay in sync: the property in `quickshell/Common/SettingsData.qml`, the spec entry in `quickshell/Common/settings/SettingsSpec.js`, and (for UI) a toggle in `quickshell/Modules/Settings/DankBarTab.qml`. Use `SettingsData.set("key", value)` to write.
- **Existing NM `vpn_lock` indicator** in `IdlePane.qml` (driven by `island.vpnOn` / `NetworkService.vpnConnected`) stays untouched; Tailscale gets a separate glyph.
- **QML has no unit-test harness in this repo.** The per-task "test cycle" is: `make lint-qml` (syntax/type lint — see note below) + commit; runtime behavior is verified end-to-end in Task 9. `make lint-qml` resolves a Qt6 `qmllint`; if none is installed on the host it exits without checking — in that case rely on the Task 9 runtime verification.
- **Running the working tree:** the live `dms.service` may run the Nix *store* build, not the working tree. Before runtime verification, ensure the working-tree override is active (Task 0).

---

### Task 0: Activate the working-tree shell (verification prerequisite)

So that QML edits are actually exercised by the running shell. This is a local environment step, not a code change — do it once, do not commit anything.

**Files:** none (systemd user override on the local machine).

- [ ] **Step 1: Check what the running service executes**

Run: `systemctl --user show dms.service -p ExecStart | tr ' ' '\n' | grep -E 'dms|store|Projects'`
Expected: if it shows `/nix/store/...-dms-shell.../bin/dms run --session`, the store build is live and edits will NOT be picked up → continue. If it already shows `-c /home/titosy/Projects/DankMaterialShell/quickshell`, skip to Step 3.

- [ ] **Step 2: Re-enable the working-tree override and restart**

```bash
cd ~/.config/systemd/user/dms.service.d
[ -f override.conf.disabled ] && mv override.conf.disabled override.conf
systemctl --user daemon-reload
systemctl --user restart dms.service
```

The override content (already present) is:
```ini
[Service]
ExecStart=
ExecStart=/run/current-system/sw/bin/dms -c /home/titosy/Projects/DankMaterialShell/quickshell run --session
```

- [ ] **Step 3: Confirm the working tree is live**

Run: `systemctl --user show dms.service -p ExecStart | grep -o 'Projects/DankMaterialShell/quickshell'`
Expected: `Projects/DankMaterialShell/quickshell` (the shell now hot-reloads the edited QML files).

---

### Task 1: Service derived properties (`TailscaleService.qml`)

**Files:**
- Modify: `quickshell/Services/TailscaleService.qml` (add derived props after the existing `onlinePeerCount` block, ~line 71)

**Interfaces:**
- Consumes: existing `allPeersList`, `onlinePeerCount`, `connected`, `available`, `backendState`.
- Produces: `activeExitNode: var|null`, `usingExitNode: bool`, `exitNodeName: string`, `statusKind: string` (`"running"|"starting"|"stopped"|"needsLogin"|"needsAuth"|"error"`), `needsAttention: bool`.

- [ ] **Step 1: Add the derived properties**

Insert after the `readonly property int onlinePeerCount: onlinePeers.length` line:

```qml
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
```

- [ ] **Step 2: Lint**

Run: `make lint-qml`
Expected: no errors reported for `TailscaleService.qml` (or a clean "qmllint unavailable" skip).

- [ ] **Step 3: Commit**

```bash
git add quickshell/Services/TailscaleService.qml
git commit -m "feat(tailscale): derive exit-node + health props on TailscaleService"
```

---

### Task 2: Settings toggle (`SettingsData.qml`, `SettingsSpec.js`, `DankBarTab.qml`)

**Files:**
- Modify: `quickshell/Common/SettingsData.qml:188` (after `dynamicIslandHideOnFullscreen`)
- Modify: `quickshell/Common/settings/SettingsSpec.js:44` (after `dynamicIslandHideOnFullscreen`)
- Modify: `quickshell/Modules/Settings/DankBarTab.qml:251` (after the "Hide on fullscreen" toggle)

**Interfaces:**
- Produces: `SettingsData.dynamicIslandTailscale: bool` (default `true`).

- [ ] **Step 1: Add the property in SettingsData.qml**

After `property bool dynamicIslandHideOnFullscreen: true`, add:

```qml
    property bool dynamicIslandTailscale: true
```

- [ ] **Step 2: Add the spec entry in SettingsSpec.js**

After `dynamicIslandHideOnFullscreen: { def: true },`, add:

```js
    dynamicIslandTailscale: { def: true },
```

- [ ] **Step 3: Add the settings toggle in DankBarTab.qml**

After the "Hide on fullscreen" `DankToggle { ... }` block (closing `}` at line ~251), add:

```qml
                DankToggle {
                    width: parent.width
                    text: I18n.tr("Tailscale status")
                    description: I18n.tr("Show Tailscale connection status in the island: a peer-count indicator at rest, live-activity pops on connect/disconnect and exit-node changes, and a tap-to-open device panel.")
                    enabled: SettingsData.dynamicIslandEnabled
                    checked: SettingsData.dynamicIslandTailscale
                    onToggled: SettingsData.set("dynamicIslandTailscale", checked)
                }
```

- [ ] **Step 4: Lint**

Run: `make lint-qml`
Expected: clean (or qmllint-unavailable skip).

- [ ] **Step 5: Commit**

```bash
git add quickshell/Common/SettingsData.qml quickshell/Common/settings/SettingsSpec.js quickshell/Modules/Settings/DankBarTab.qml
git commit -m "feat(island): add dynamicIslandTailscale setting + toggle"
```

---

### Task 3: Island pass-through props + keep-alive Ref (`DynamicIsland.qml`)

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/DynamicIsland.qml` (mini-indicator data block near line 69; Loader block near the existing Cava/Dgop Loaders ~line 176)

**Interfaces:**
- Consumes: `TailscaleService` derived props (Task 1), `SettingsData.dynamicIslandTailscale` (Task 2).
- Produces (on `root`): `tsFeature: bool`, `tsAvailable: bool`, `tsConnected: bool`, `tsPeerCount: int`, `tsUsingExitNode: bool`, `tsExitNodeName: string`, `tsNeedsAttention: bool`, `tsStatusKind: string`. Consumed by Tasks 4, 5, 6.

- [ ] **Step 1: Add pass-through props**

After the existing `readonly property bool vpnOn: NetworkService.vpnConnected` line (~line 69), add:

```qml
    // ---- Tailscale (live activity) ----
    readonly property bool tsFeature: SettingsData.dynamicIslandTailscale
    readonly property bool tsAvailable: tsFeature && TailscaleService.available
    readonly property bool tsConnected: TailscaleService.connected
    readonly property int  tsPeerCount: TailscaleService.onlinePeerCount
    readonly property bool tsUsingExitNode: TailscaleService.usingExitNode
    readonly property string tsExitNodeName: TailscaleService.exitNodeName
    readonly property bool tsNeedsAttention: tsFeature && TailscaleService.needsAttention
    readonly property string tsStatusKind: TailscaleService.statusKind
```

- [ ] **Step 2: Add the keep-alive Ref Loader**

After the existing system-monitor `Loader { active: root.mode === "expanded" && root.panelView === "monitor" ... }` block (~line 191), add:

```qml
    // keep the Tailscale subscription live while the feature is enabled & the
    // backend supports it, so the at-rest indicator/satellite reflect real state
    Loader {
        active: root.tsAvailable
        sourceComponent: Component { Ref { service: TailscaleService } }
    }
```

- [ ] **Step 3: Lint**

Run: `make lint-qml`
Expected: clean (or skip).

- [ ] **Step 4: Commit**

```bash
git add quickshell/Modules/DynamicIsland/DynamicIsland.qml
git commit -m "feat(island): Tailscale pass-through props + keep-alive ref"
```

---

### Task 4: Splash triggers (connect/disconnect, exit-node, health) + satellite (`DynamicIsland.qml`)

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/DynamicIsland.qml` (satellite `satKind`/`satIcon`/`satColor` ~lines 42-57; satellite `onClicked` ~line 866; new `Connections` near the Bluetooth/charging activity wiring ~line 448)

**Interfaces:**
- Consumes: pass-through props (Task 3), existing `pushActivity(icon, label, opts)`, `ready`, `openPanel(view)`.
- Produces: splash side effects; satellite `"tailscale"` kind. No new exported symbols.

- [ ] **Step 1: Add `tailscale` to the satellite kind/icon/color**

In `satKind` (currently checks screenshare/mic/cam/battery), add a Tailscale branch **above** the battery branch:

```qml
    readonly property string satKind: {
        if (PrivacyService.screensharingActive) return "screenshare"
        if (PrivacyService.microphoneActive) return "mic"
        if (PrivacyService.cameraActive) return "cam"
        if (tsNeedsAttention) return "tailscale"
        if (batAvailable && !charging && batPct <= 20) return "battery"
        return ""
    }
```

In `satIcon`, add (above the battery branch):

```qml
        if (satKind === "tailscale") return tsConnected ? "device_hub" : "vpn_key_off"
```

In `satColor`, extend so Tailscale shows a warning color:

```qml
    readonly property color satColor: satKind === "cam" ? Theme.success
        : (satKind === "battery" ? Theme.error
        : (satKind === "tailscale" ? Theme.warning : Theme.warning))
```

- [ ] **Step 2: Route the satellite tap into the Tailscale panel**

In the satellite `MouseArea.onClicked` (currently routes mic/cam/screenshare → `openPanel("privacy")`, else `mode = "expanded"`), add a Tailscale branch:

```qml
                onClicked: {
                    if (root.satKind === "mic" || root.satKind === "cam" || root.satKind === "screenshare")
                        root.openPanel("privacy")
                    else if (root.satKind === "tailscale")
                        root.openPanel("tailscale")
                    else
                        root.mode = "expanded"
                    root.bump()
                }
```

- [ ] **Step 3: Add the splash `Connections`**

After the Focus/DoNotDisturb `Connections` block (~line 481), add:

```qml
    // Live Activity: Tailscale connection + exit-node + health transitions.
    // Guarded by `ready` (skip the startup snapshot) and the feature toggle.
    Connections {
        target: TailscaleService
        enabled: root.tsFeature
        function onConnectedChanged() {
            if (!root.ready) return
            if (TailscaleService.connected)
                root.pushActivity("device_hub", I18n.tr("Tailscale") + " • " + root.tsPeerCount + " " + I18n.tr("online"))
            else
                root.pushActivity("vpn_key_off", I18n.tr("Tailscale disconnected"))
        }
        function onUsingExitNodeChanged() {
            if (!root.ready) return
            root.pushActivity("public", TailscaleService.usingExitNode
                ? (I18n.tr("Exit node") + ": " + TailscaleService.exitNodeName)
                : I18n.tr("Exit node off"))
        }
        function onNeedsAttentionChanged() {
            if (!root.ready || !TailscaleService.needsAttention) return
            const k = TailscaleService.statusKind
            const msg = k === "needsLogin" ? I18n.tr("Tailscale needs login")
                : k === "needsAuth" ? I18n.tr("Tailscale needs device approval")
                : k === "stopped" ? I18n.tr("Tailscale stopped")
                : k === "error" ? I18n.tr("Tailscale unreachable")
                : I18n.tr("Tailscale: no peers reachable")
            root.pushActivity("warning", msg, { priority: 2 })
        }
    }
```

- [ ] **Step 4: Lint**

Run: `make lint-qml`
Expected: clean (or skip).

- [ ] **Step 5: Commit**

```bash
git add quickshell/Modules/DynamicIsland/DynamicIsland.qml
git commit -m "feat(island): Tailscale connect/exit-node/health splashes + satellite"
```

---

### Task 5: Peer-online splash, noise-tamed (`DynamicIsland.qml`)

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/DynamicIsland.qml` (add a tracking property + a `Connections` block; place next to the Task 4 Connections)

**Interfaces:**
- Consumes: `TailscaleService.myOnlinePeers`, `pushActivity`, `ready`, `tsFeature`.
- Produces: peer-online splash side effects; internal `_tsKnownOnline` (Set of hostnames).

- [ ] **Step 1: Add the tracking state + Connections**

After the Task 4 `Connections` block, add:

```qml
    // peer-online splashes. Tamed: only MY peers, deltas only (the initial set is
    // absorbed without firing), and a burst is coalesced into one "N online" pop.
    property var _tsKnownOnline: ({})   // hostname -> true
    property bool _tsSeeded: false
    function _tsHostsOf(list) {
        const m = {}
        for (var i = 0; i < list.length; i++) {
            const h = list[i] && list[i].hostname
            if (h) m[h] = true
        }
        return m
    }
    Connections {
        target: TailscaleService
        enabled: root.tsFeature
        function onMyOnlinePeersChanged() {
            const cur = root._tsHostsOf(TailscaleService.myOnlinePeers)
            // seed silently on first observation and whenever we were empty
            // (covers connect: the whole set arrives at once and must not splash)
            if (!root._tsSeeded || Object.keys(root._tsKnownOnline).length === 0) {
                root._tsKnownOnline = cur
                root._tsSeeded = true
                return
            }
            const fresh = []
            for (var h in cur) {
                if (!root._tsKnownOnline[h]) fresh.push(h)
            }
            root._tsKnownOnline = cur
            if (!root.ready || fresh.length === 0) return
            if (fresh.length === 1)
                root.pushActivity("device_hub", fresh[0] + " " + I18n.tr("online"))
            else
                root.pushActivity("device_hub", fresh.length + " " + I18n.tr("devices online"))
        }
    }
```

- [ ] **Step 2: Lint**

Run: `make lint-qml`
Expected: clean (or skip).

- [ ] **Step 3: Commit**

```bash
git add quickshell/Modules/DynamicIsland/DynamicIsland.qml
git commit -m "feat(island): Tailscale peer-online splash (deltas only, coalesced)"
```

---

### Task 6: Idle-row mini-indicator (`IdlePane.qml`)

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/panes/IdlePane.qml` (in `rightCluster`, right after the existing VPN `DankIcon` block ~line 132)

**Interfaces:**
- Consumes: `island.tsAvailable`, `island.tsConnected`, `island.tsPeerCount`, `island.tsUsingExitNode`, `island.tsNeedsAttention`, `island.accent`, `island.subText`, `island.openPanel`.
- Produces: a clickable indicator; no exported symbols.

- [ ] **Step 1: Add the Tailscale indicator**

After the VPN `DankIcon { name: "vpn_lock"; ... visible: island.vpnOn ... }` block, add:

```qml
        Row {  // Tailscale: peer count, exit-node glyph, click → panel
            spacing: 3
            visible: island.tsAvailable
            anchors.verticalCenter: parent.verticalCenter
            scale: tsArea.pressed ? 0.86 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon {
                name: "device_hub"
                size: Theme.iconSize - 6
                color: island.tsNeedsAttention ? Theme.warning
                    : (island.tsConnected ? island.accent : island.subText)
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: island.tsConnected
                text: island.tsPeerCount
                color: island.tsNeedsAttention ? Theme.warning : island.textColor
                font.pixelSize: Theme.fontSizeSmall; font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            DankIcon {
                visible: island.tsUsingExitNode
                name: "public"
                size: Theme.iconSize - 8
                color: island.accent
                anchors.verticalCenter: parent.verticalCenter
            }
            MouseArea {
                id: tsArea
                anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: island.openPanel("tailscale")
            }
        }
```

- [ ] **Step 2: Lint**

Run: `make lint-qml`
Expected: clean (or skip).

- [ ] **Step 3: Commit**

```bash
git add quickshell/Modules/DynamicIsland/panes/IdlePane.qml
git commit -m "feat(island): Tailscale idle-row indicator (peer count + exit-node)"
```

---

### Task 7: Drill-in panel + registry wiring (`TailscalePanel.qml`, `ControlCenterPanel.qml`, `DynamicIsland.qml`)

**Files:**
- Create: `quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml`
- Modify: `quickshell/Modules/DynamicIsland/ControlCenterPanel.qml:298-319` (registry + Component)
- Modify: `quickshell/Modules/DynamicIsland/DynamicIsland.qml:234` (panelView doc comment — add `"tailscale"`)

**Interfaces:**
- Consumes: `island.panelView`, `island.tsConnected`, `TailscaleService.*` (peers, search, filters, refresh, exitNodeName, tailnetName).
- Produces: `TailscalePanel { island }` component; `"tailscale"` registry key.

- [ ] **Step 1: Create the panel**

Create `quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml`. Modeled on `WifiPanel.qml`'s ref/structure and reusing the peer-list UI from `BuiltinPlugins/TailscaleWidget.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Tailscale drill view for the dynamic island. Mirrors the Control Center
// Tailscale widget (status header + searchable, filterable peer list), refs the
// service only while open.
Item {
    id: tsPanel
    property var island: null
    anchors.fill: parent

    property string searchQuery: ""
    property int filterIndex: 0  // 0=My Online, 1=All Online, 2=All

    opacity: island && island.panelView === "tailscale" ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
    transform: Translate { x: island && island.panelView === "tailscale" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }

    readonly property bool tsActive: island && island.mode === "expanded" && island.panelView === "tailscale"
    onTsActiveChanged: {
        if (tsActive) TailscaleService.addRef()
        else TailscaleService.removeRef()
    }
    Component.onDestruction: if (tsActive) TailscaleService.removeRef()

    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: Theme.spacingS

        // header: back + title + status
        RowLayout {
            width: parent.width
            spacing: Theme.spacingS
            DankActionButton {
                iconName: "arrow_back"
                buttonSize: 28
                iconSize: 16
                onClicked: tsPanel.island.panelView = "controls"
            }
            DankIcon {
                name: "device_hub"
                size: 18
                color: TailscaleService.connected ? Theme.primary : Theme.surfaceVariantText
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                text: I18n.tr("Tailscale")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                Layout.fillWidth: true
            }
            DankActionButton {
                iconName: "sync"
                buttonSize: 28
                iconSize: 16
                iconColor: Theme.surfaceVariantText
                tooltipText: I18n.tr("Refresh")
                onClicked: TailscaleService.refresh(null)
            }
        }

        // status line: tailnet + exit-node
        StyledText {
            width: parent.width
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: {
                if (!TailscaleService.available) return I18n.tr("Tailscale not available")
                if (!TailscaleService.connected) return I18n.tr("Disconnected")
                const parts = []
                if (TailscaleService.tailnetName) parts.push(TailscaleService.tailnetName)
                if (TailscaleService.usingExitNode) parts.push(I18n.tr("via %1").arg(TailscaleService.exitNodeName) + " \u{1F310}")
                return parts.join("  •  ")
            }
        }

        // search
        DankTextField {
            width: parent.width
            placeholderText: I18n.tr("Search devices...")
            leftIconName: "search"
            showClearButton: true
            text: tsPanel.searchQuery
            onTextEdited: tsPanel.searchQuery = text
            visible: TailscaleService.available
        }

        // filter chips
        DankFilterChips {
            width: parent.width
            currentIndex: tsPanel.filterIndex
            showCounts: true
            chipHeight: 26
            visible: TailscaleService.available
            model: [
                { "label": I18n.tr("My Online"), "count": TailscaleService.myOnlinePeers.length },
                { "label": I18n.tr("Online"),    "count": TailscaleService.onlinePeers.length },
                { "label": I18n.tr("All"),        "count": TailscaleService.allPeersList.length }
            ]
            onSelectionChanged: index => tsPanel.filterIndex = index
        }

        // peer list
        DankFlickable {
            width: parent.width
            height: Math.min(contentHeight, 260)
            contentHeight: peerCol.implicitHeight
            clip: true
            visible: TailscaleService.available

            Column {
                id: peerCol
                width: parent.width
                spacing: Theme.spacingXS

                property var filteredPeers: {
                    let base
                    switch (tsPanel.filterIndex) {
                    case 0:  base = TailscaleService.myOnlinePeers; break
                    case 1:  base = TailscaleService.onlinePeers; break
                    case 2:  base = TailscaleService.allPeersList; break
                    default: base = []
                    }
                    if (tsPanel.searchQuery.length > 0)
                        return TailscaleService.searchPeers(tsPanel.searchQuery, base)
                    return base
                }

                Repeater {
                    model: peerCol.filteredPeers
                    delegate: Rectangle {
                        required property var modelData
                        width: peerCol.width
                        height: row.implicitHeight + Theme.spacingS * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest
                        RowLayout {
                            id: row
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingS
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: modelData.online ? "#4caf50" : Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Column {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText {
                                    text: modelData.hostname || ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    width: parent.width
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    text: modelData.tailscaleIp || ""
                                    font.pixelSize: 10
                                    color: Theme.surfaceTextMedium
                                }
                            }
                            DankActionButton {
                                iconName: "content_copy"
                                buttonSize: 20
                                iconSize: 11
                                iconColor: Theme.surfaceVariantText
                                tooltipText: I18n.tr("Copy")
                                onClicked: Quickshell.execDetached(["dms", "cl", "copy", modelData.tailscaleIp])
                            }
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Register the panel in ControlCenterPanel.qml**

Add `"tailscale": tsComp,` to the `viewRegistry` object (line ~298-304):

```qml
                readonly property var viewRegistry: ({
                    "wifi": wifiComp, "bluetooth": btComp, "audio": audioComp,
                    "input": inputComp, "notifications": notifComp, "calendar": calComp,
                    "apps": appsComp, "clipboard": clipComp, "emoji": emojiComp,
                    "power": powerComp, "monitor": monComp, "wallpaper": wpComp,
                    "mixer": mixerComp, "privacy": privacyComp, "shelf": shelfComp,
                    "tailscale": tsComp
                })
```

And add the Component definition next to the others (after `shelfComp`, line ~319):

```qml
                Component { id: tsComp;    TailscalePanel     { island: ccPanel.island } }
```

- [ ] **Step 3: Update the panelView doc comment in DynamicIsland.qml**

Append `| "tailscale"` to the `panelView` property's enumeration comment (line ~234), so the list stays the single documented source of valid views.

- [ ] **Step 4: Lint**

Run: `make lint-qml`
Expected: clean (or skip). In particular confirm `TailscalePanel.qml` parses and the registry edit has no trailing-comma/syntax error.

- [ ] **Step 5: Commit**

```bash
git add quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml quickshell/Modules/DynamicIsland/ControlCenterPanel.qml quickshell/Modules/DynamicIsland/DynamicIsland.qml
git commit -m "feat(island): TailscalePanel drill view + registry wiring"
```

---

### Task 8: IPC reachability (`IslandHub.qml`)

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/IslandHub.qml:25` (the `views` allow-list)

**Interfaces:**
- Consumes: nothing new.
- Produces: `dms ipc call island open tailscale` becomes valid.

- [ ] **Step 1: Add `"tailscale"` to the views list**

```qml
    readonly property var views: ["controls", "wifi", "bluetooth", "audio", "input", "notifications", "calendar", "monitor", "wallpaper", "apps", "clipboard", "emoji", "power", "mixer", "privacy", "shelf", "tailscale"]
```

- [ ] **Step 2: Lint**

Run: `make lint-qml`
Expected: clean (or skip).

- [ ] **Step 3: Commit**

```bash
git add quickshell/Modules/DynamicIsland/IslandHub.qml
git commit -m "feat(island): allow 'open tailscale' via IPC"
```

---

### Task 9: End-to-end runtime verification

**Files:** none (manual verification of the running shell).

Prerequisite: Task 0 done (working tree is live). Tailscale is installed and `tailscale status` works.

- [ ] **Step 1: Confirm the shell reloaded without QML errors**

Run: `journalctl --user -u dms.service -n 60 --no-pager | grep -iE "error|warning|tailscale" | tail -30`
Expected: no QML load errors referencing the edited files. (Some unrelated warnings are normal.)

- [ ] **Step 2: At-rest indicator**

Hover the island to enter `idle` mode. Expected: a `device_hub` glyph + online-peer count appears in the right cluster (separate from the NM `vpn_lock` icon). With Tailscale connected it uses the accent color.

- [ ] **Step 3: Disconnect / connect splashes**

Run: `tailscale down` → expect a "Tailscale disconnected" splash in the island.
Run: `tailscale up` → expect a "Tailscale • N online" splash; the idle indicator shows the count again.

- [ ] **Step 4: Exit-node splash + indicator**

Pick any peer offering exit (or skip if none available):
Run: `tailscale set --exit-node=<peer-host>` → expect "Exit node: <name>" splash and a `public` glyph in the idle indicator + "via <node> 🌐" in the panel header.
Run: `tailscale set --exit-node=` → expect "Exit node off" splash.

- [ ] **Step 5: Drill panel**

Click the idle-row indicator → expect the Tailscale panel (status header, search, filter chips, peer cards with copy-IP). Also test `dms ipc call island open tailscale` → expect `ISLAND_OPEN:tailscale` and the panel opens.

- [ ] **Step 6: Settings toggle**

Open Settings → DankBar/Island → toggle "Tailscale status" off. Expected: the idle indicator disappears and no Tailscale splashes fire. Toggle back on → indicator returns.

- [ ] **Step 7: Peer-online splash (best effort)**

Bring one of your own devices online (e.g. unlock the phone running Tailscale). Expected: a single "<host> online" splash, not a burst, and no splash for the already-online set.

- [ ] **Step 8: Final lint + status**

Run: `make lint-qml && git status`
Expected: lint clean (or skip), working tree clean (all tasks committed).

---

## Self-Review

**Spec coverage:**
- §1 service derived props → Task 1 ✅
- §2 controller pass-through + Ref → Task 3 ✅; splashes + satellite → Tasks 4, 5 ✅
- §3 idle-row indicator → Task 6 ✅
- §4 drill panel → Task 7 ✅
- §5 IPC reachability → Task 8 ✅
- §6 settings → Task 2 ✅
- §7 error/edge cases → covered: `available` gating (Tasks 3/6), startup suppression (`ready` gate Tasks 4/5, `_tsSeeded`/empty-set seeding Task 5), satellite only on `needsAttention` (Task 4); the "Starting" debounce is handled by `statusKind` treating Starting/NoState/"" as `starting` (no disconnect/attention splash), which satisfies the spec's intent without a separate timer.
- §8 testing → Task 9 ✅

**Note on a spec simplification:** the spec mentioned a possible disconnect debounce *timer*. Implemented instead via `statusKind` buckets (Starting/NoState/empty → `"starting"`, which suppresses both the attention splash and is distinct from `"stopped"`). `onConnectedChanged` only fires on the real `connected` boolean from the backend (`backendState === "Running"`), so transient Starting states don't toggle it. This avoids an extra timer while meeting the no-false-disconnect requirement. If real-world flapping appears in Task 9, add a 1.5s settle timer on the disconnect splash.

**Placeholder scan:** none — every code step has complete code.

**Type consistency:** `tsFeature/tsAvailable/tsConnected/tsPeerCount/tsUsingExitNode/tsExitNodeName/tsNeedsAttention/tsStatusKind` defined in Task 3 and used verbatim in Tasks 4-6. `activeExitNode/usingExitNode/exitNodeName/statusKind/needsAttention` defined in Task 1, used in Tasks 3-4. Panel component id `tsComp` and registry key `"tailscale"` consistent across Task 7. IPC view `"tailscale"` consistent across Tasks 7-8.
