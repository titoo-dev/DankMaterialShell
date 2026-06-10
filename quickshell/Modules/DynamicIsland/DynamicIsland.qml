import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import qs.Widgets
import "panes"

// Dynamic Island "style" for DankMaterialShell — minimalist rounded-rectangle.
// Inherits all DMS features (Theme, services, menus). Compact at rest so it
// stays out of the way; springy, modern morph between states.
//
// One Scope per monitor owning FOUR independent layer surfaces (pill strip,
// banners, scrim, edge glow) instead of one permanent full-screen overlay —
// an output with nothing to show maps NOTHING, so fullscreen video keeps
// direct scanout and the compositor stops compositing a dead transparent layer.
Scope {
    id: root

    property var modelData

    readonly property string monitorName: (modelData && modelData.name) ? modelData.name : ""
    // primary screen acts as the fallback "focused" monitor when the compositor
    // reports none — avoids notif/OSD showing on BOTH islands simultaneously
    readonly property bool isPrimaryScreen: (Quickshell.screens && Quickshell.screens.length > 0) ? (Quickshell.screens[0].name === monitorName) : true
    // is this the monitor the user is currently working on? (for notif/OSD)
    readonly property bool isFocusedScreen: {
        if (CompositorService.isNiri)
            return NiriService.currentOutput ? (NiriService.currentOutput === monitorName) : isPrimaryScreen
        return Hyprland.focusedMonitor ? (Hyprland.focusedMonitor.name === monitorName) : isPrimaryScreen
    }
    readonly property bool privacyActive: PrivacyService.microphoneActive || PrivacyService.cameraActive || PrivacyService.screensharingActive
    readonly property bool glowActive: mode === "media" || mode === "chip"

    // focused window (wlr foreign-toplevel; works on Hyprland/niri/sway/...)
    readonly property var activeWin: ToplevelManager.activeToplevel
    readonly property string focusedTitle: {
        const t = (activeWin && activeWin.title) ? activeWin.title : ""
        // drop the trailing " - <browser>" / " — <browser>" suffix for a cleaner title
        return t.replace(/\s*[-—]\s*(Google Chrome|Mozilla Firefox|Chromium|Brave|Microsoft Edge|Vivaldi|Opera)\s*$/i, "")
    }
    readonly property string focusedAppId: (activeWin && activeWin.appId) ? activeWin.appId : ""

    // mini-indicator data
    readonly property bool vpnOn: NetworkService.vpnConnected
    readonly property bool weatherReady: WeatherService.weather && WeatherService.weather.available
    readonly property string weatherTemp: weatherReady ? (((SettingsData.useFahrenheit ? WeatherService.weather.tempF : WeatherService.weather.temp)) + "°") : ""
    readonly property string weatherIcon: weatherReady ? WeatherService.getWeatherIcon(WeatherService.weather.wCode) : "cloud"
    readonly property string kbLayout: CompositorService.isNiri && NiriService.getCurrentKeyboardLayoutName ? (NiriService.getCurrentKeyboardLayoutName() || "") : ""

    // ---------- styling (inherits the live DMS / Matugen theme) ----------
    readonly property color islandColor: SettingsData.dynamicIslandBlur ? Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.72) : Theme.surfaceContainer
    readonly property color accent:      Theme.primary
    readonly property color textColor:   Theme.surfaceText
    readonly property color subText:     Theme.surfaceVariantText

    // ---------- live data ----------
    readonly property var player: MprisController.activePlayer
    readonly property bool playing: player ? player.isPlaying : false

    // shared media progress (used by the chip ring, scrubber, timestamps)
    property int mediaTick: 0
    Timer { interval: 1000; repeat: true; running: root.playing && (root.mode === "chip" || root.mode === "media"); onTriggered: root.mediaTick++ }
    readonly property real mediaLen: MprisController.activePlayerStableLength
    readonly property real mediaFrac: {
        mediaTick
        return (player && mediaLen > 0) ? Math.max(0, Math.min(1, player.position / mediaLen)) : 0
    }
    function fmtTime(sec) {
        if (!sec || sec < 0 || !isFinite(sec)) return "0:00"
        const s = Math.floor(sec % 60), m = Math.floor(sec / 60)
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    readonly property bool batAvailable: BatteryService.batteryAvailable
    readonly property int batPct: BatteryService.batteryLevel
    readonly property bool charging: BatteryService.isCharging

    // compositor-agnostic, PER-MONITOR workspace model (Hyprland + niri)
    readonly property var wsList: {
        const mon = monitorName
        if (CompositorService.isNiri) {
            return (NiriService.allWorkspaces || []).filter(w => !mon || w.output === mon).map(w => ({
                        key: w.id,
                        label: (w.name && String(w.name).length) ? w.name : String((w.idx ?? 0) + 1),
                        focused: w.is_focused === true
                    }))
        }
        // Hyprland: workspaces on THIS monitor, active = this monitor's active ws
        const hm = (Hyprland.monitors ? Hyprland.monitors.values : []).find(m => m.name === mon)
        const activeId = hm && hm.activeWorkspace ? hm.activeWorkspace.id : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1)
        return (Hyprland.workspaces ? Hyprland.workspaces.values : []).filter(w => w.id > 0 && (!mon || (w.monitor && w.monitor.name === mon))).sort((a, b) => a.id - b.id).map(w => ({
                    key: w.id,
                    label: (w.name && String(w.name).length && String(w.name) !== String(w.id)) ? w.name : String(w.id),
                    focused: w.id === activeId
                }))
    }
    function wsActivate(key) {
        if (CompositorService.isNiri)
            NiriService.switchToWorkspace(key)
        else
            Hyprland.dispatch("workspace " + key)
    }

    // local fallback spectrum (used only when the `cava` binary is absent), so
    // we never mutate the shared CavaService.values singleton
    property var eqFallback: [12, 16, 14, 12, 14, 10]
    // real audio-reactive spectrum (DMS CavaService) -> bar height
    function eqHeight(i) {
        const minH = 3, maxH = 16
        const vals = CavaService.cavaAvailable ? CavaService.values : eqFallback
        const raw = (vals && vals.length > i) ? vals[i] : 0
        if (raw <= 0) return minH
        if (raw >= 100) return maxH
        return minH + Math.sqrt(raw * 0.01) * (maxH - minH)
    }
    readonly property bool cavaActive: playing && (mode === "chip" || mode === "media")

    readonly property var trayItems: SystemTray.items ? SystemTray.items.values : []

    readonly property var popups: NotificationService.popups ?? []
    // ambient screen-edge glow pulse whenever a NEW popup arrives (focused screen only)
    property int _popupCount: 0
    onPopupsChanged: {
        if (popups.length > _popupCount && ready && isFocusedScreen && !SessionData.doNotDisturb) {
            const p = popups[popups.length - 1]
            const crit = p ? (p.urgency === NotificationUrgency.Critical) : false
            edgeGlow.flash(crit ? Theme.error : Theme.primary)
        }
        _popupCount = popups.length
    }
    // macOS model: notifications are independent top-right banners (NotificationBanners),
    // they NEVER take over the island.

    readonly property var audioNode: AudioService.sink && AudioService.sink.audio ? AudioService.sink.audio : null
    readonly property int volPct: audioNode ? Math.round(audioNode.volume * 100) : 0
    readonly property bool muted: audioNode ? audioNode.muted : false

    SystemClock { id: clock; precision: SystemClock.Minutes }
    // formatted clock strings exposed to the extracted at-rest panes (panes/)
    readonly property string clockShort: Qt.formatDateTime(clock.date, "HH:mm")
    readonly property string clockLong: Qt.formatDateTime(clock.date, "ddd  HH:mm")
    // open a tray item's context menu (anchored by the idle pane, owned here)
    function openTrayMenu(menuObj, rect) { trayMenu.menu = menuObj; trayMenu.anchor.rect = rect; trayMenu.open() }

    // avoid presenter flashes during startup
    property bool ready: false
    Timer { running: true; interval: 1500; onTriggered: { root.ready = true; root._updateFullscreen() } }

    // real audio spectrum: hold a ref on CavaService while a visual shows
    Loader {
        active: root.cavaActive
        sourceComponent: Component { Ref { service: CavaService } }
    }
    // system monitor: stream cpu/memory/network/system stats from the native
    // DgopService backend ONLY while the monitor drill view is open (3s cadence),
    // so polling stays idle the rest of the time.
    Loader {
        active: root.mode === "expanded" && root.panelView === "monitor"
        sourceComponent: Component {
            QtObject {
                Component.onCompleted: DgopService.addRef(["cpu", "memory", "network", "system"])
                Component.onDestruction: DgopService.removeRef(["cpu", "memory", "network", "system"])
            }
        }
    }
    // fallback animation when the `cava` binary isn't installed
    Timer {
        interval: 90; repeat: true
        running: root.cavaActive && !CavaService.cavaAvailable
        onTriggered: root.eqFallback = [Math.random() * 60 + 12, Math.random() * 72 + 16, Math.random() * 66 + 14, Math.random() * 60 + 12, Math.random() * 66 + 14, Math.random() * 50 + 10]
    }

    // Frosted blur is opt-in via SettingsData.dynamicIslandBlur. Runtime layer
    // rules are rejected by current Hyprland, so blur requires a sourced config
    // snippet (see island-lab/README) — the surface just goes translucent here.

    // ---------- state machine ----------
    // "compact"(rest) | "chip"(rest+media) | "idle" | "media" | "expanded"
    // | "presenter"
    property string mode: "compact"
    property bool hovered: false
    property bool pinned: false

    // Hide the island pill when THIS monitor shows a fullscreen window (movies,
    // focus sessions). The OSD (presenter) and an explicitly-opened panel
    // (expanded, e.g. via keybind) still show so feedback / actions keep working;
    // notification banners live in a separate window item and are unaffected.
    // Recomputed on compositor toplevel/workspace changes (same trigger DankBar
    // auto-hide uses). Toggle: SettingsData.dynamicIslandHideOnFullscreen.
    property bool hasFullscreenOnScreen: false
    function _updateFullscreen() {
        hasFullscreenOnScreen = CompositorService.hasFullscreenToplevelOnScreen(modelData)
    }
    readonly property bool pillSuppressed: SettingsData.dynamicIslandHideOnFullscreen
        && hasFullscreenOnScreen && mode !== "presenter" && mode !== "expanded"
    Connections {
        target: CompositorService
        function onToplevelsChanged() { root._updateFullscreen() }
    }
    Connections {
        target: NiriService
        function onAllWorkspacesChanged() { root._updateFullscreen() }
    }

    // which view the expanded panel shows: "controls" hub or a drilled-in detail
    property string panelView: "controls"   // "controls" | "wifi" | "bluetooth" | "audio" | "input" | "notifications" | "calendar" | "monitor" | "wallpaper" | "apps" | "clipboard" | "emoji" | "power"
    onModeChanged: if (mode !== "expanded") panelView = "controls"   // reset on close
    onPanelViewChanged: if (panelView !== "wifi") wifiNeedsKeyboard = false
    // open the expanded panel directly on a given detail view
    function openPanel(view) { panelView = view; pinned = true; mode = "expanded" }

    property string presenterKind: "volume"   // "volume" | "brightness" | "battery" | "splash"
    // a "splash" is a glanceable Live-Activity (e.g. Bluetooth connected): icon + label, no bar
    property string splashIcon: "bluetooth_connected"
    property string splashLabel: ""
    // live & reactive: the OSD value/icon track the real system state directly, so
    // they stay in sync with the user's action even while it's already showing
    // (no stale imperative snapshot — derived props lag a tick at change-time)
    readonly property int presenterValue: {
        if (presenterKind === "battery") return batPct
        if (presenterKind === "brightness") return DisplayService.brightnessLevel
        return muted ? 0 : volPct   // volume
    }
    readonly property string presenterIcon: {
        if (presenterKind === "splash") return splashIcon
        if (presenterKind === "battery") return Theme.getBatteryIcon(batPct, charging, batAvailable)
        if (presenterKind === "brightness") return "brightness_6"
        if (muted) return "volume_off"   // volume
        if (volPct === 0) return "volume_mute"
        return volPct < 50 ? "volume_down" : "volume_up"
    }

    function restMode() { return playing ? "chip" : "compact" }
    function settle() {
        if (pinned) return
        if (hovered) { mode = playing ? "media" : "idle"; return }
        mode = restMode()
    }
    // fully collapse the island from a panel action (lock/power/settings):
    // drop the pin and force a rest mode even while the pointer is over it.
    function closeIsland() { panelView = "controls"; pinned = false; mode = restMode() }
    // never yank the expanded control center (or an active OSD) away just because
    // playback started/stopped — only the rest modes follow the player
    onPlayingChanged: if (!hovered && !pinned && mode !== "presenter" && mode !== "expanded") mode = restMode()

    // ---------- insert the emoji into the focused app (emoji picker) ----------
    // Wayland vs XWayland reality on this setup:
    //   - native Wayland apps: wtype types the emoji directly → true auto-insert.
    //   - XWayland apps (Discord, ...): wtype can't reach them, ydotool can't type
    //     emoji or send a working modifier combo, and a synthetic Ctrl+V right after
    //     the island's keyboard grab is unreliable. So we just put the emoji on the
    //     clipboard and the user presses Ctrl+V (their manual paste always works).
    // Close the island first, then re-focus the previously active window (Lua: hl.dsp.focus).
    property string _typePending: ""
    function insertText(text) {
        if (!text || text.length === 0) return
        _typePending = text
        panelView = "controls"; pinned = false; settle()
        insertTimer.restart()
    }
    Timer {
        id: insertTimer
        interval: 180   // let the Exclusive grab actually release first
        onTriggered: {
            if (root._typePending.length === 0) return
            const e = root._typePending
            root._typePending = ""
            Quickshell.execDetached(["sh", "-c",
                "info=$(hyprctl activewindow); a=$(echo \"$info\" | awk 'NR==1{print $2}'); "
                + "[ -n \"$a\" ] && hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:0x${a#0x}\\\" })\" >/dev/null 2>&1; "
                + "sleep 0.12; "
                + "if ! echo \"$info\" | grep -q 'xwayland: 1' && command -v wtype >/dev/null 2>&1; then wtype \"$1\"; "
                + "else printf %s \"$1\" | wl-copy; fi",
                "island-emoji", e])
        }
    }

    // idle/media linger after pointer-leave; the expanded panel is dismissed by a
    // click outside (scrim), not by this timer (macOS behaviour).
    Timer { id: hideTimer; interval: 1800; onTriggered: root.settle() }

    function showPresenter(kind) {
        if (!ready || !isFocusedScreen) return
        if (mode === "expanded") return   // don't stomp the inline control center
        presenterKind = kind   // value/icon follow reactively from here
        if (mode !== "presenter") {
            mode = "presenter"
            bump()   // pop once on appearance, not on every step while showing
        }
        presenterTimer.restart()
    }
    // keep the OSD up while the user is interacting with it (drag / mute click)
    function holdPresenter() { if (mode === "presenter") presenterTimer.restart() }
    Timer { id: presenterTimer; interval: 1500; onTriggered: root.settle() }
    // glanceable splash (Bluetooth connected, …) — icon + label, lingers a bit longer
    function showSplash(icon, label) {
        if (!ready || !isFocusedScreen) return
        splashIcon = icon; splashLabel = label
        presenterKind = "splash"
        mode = "presenter"
        bump()
        splashTimer.restart()
    }
    Timer { id: splashTimer; interval: 2600; onTriggered: root.settle() }

    // Live-Activity splash when a Bluetooth device connects
    property bool btConnected: BluetoothService.connected
    function connectedBtName() {
        const ds = BluetoothService.devices
        const arr = ds ? (ds.values ?? ds) : []
        for (var i = 0; i < arr.length; i++) {
            if (arr[i] && arr[i].connected) return arr[i].name || arr[i].deviceName || I18n.tr("Device")
        }
        return I18n.tr("Device")
    }
    onBtConnectedChanged: {
        if (btConnected && ready)
            showSplash("bluetooth_connected", connectedBtName())
    }

    Connections {
        target: root.audioNode
        function onVolumeChanged() { root.showPresenter("volume") }
        function onMutedChanged() { root.showPresenter("volume") }
    }
    Connections {
        target: DisplayService
        function onBrightnessChanged(showOsd) { if (showOsd) root.showPresenter("brightness") }
    }
    // Live Activity: power adapter plugged / unplugged
    onChargingChanged: {
        if (!ready) return
        showSplash(charging ? "battery_charging_full" : "battery_full",
                   (charging ? I18n.tr("Charging") : I18n.tr("On battery")) + " • " + batPct + "%")
    }
    // Live Activity: Focus (Do Not Disturb) toggled
    Connections {
        target: SessionData
        function onDoNotDisturbChanged() {
            if (!root.ready) return
            root.showSplash(SessionData.doNotDisturb ? "do_not_disturb_on" : "do_not_disturb_off",
                            SessionData.doNotDisturb ? I18n.tr("Focus on") : I18n.tr("Focus off"))
        }
    }

    // Super+I (via `dms ipc call island toggle`) -> expand/collapse focused island
    Connections {
        target: IslandHub
        function onToggleRequested() {
            if (!root.isFocusedScreen)
                return
            if (root.mode === "expanded" && root.pinned) {
                root.pinned = false
                root.settle()
            } else {
                root.pinned = true
                root.mode = "expanded"
            }
        }
        // expand always opens (idempotent), unlike toggle
        function onExpandRequested() {
            if (!root.isFocusedScreen)
                return
            root.pinned = true
            root.mode = "expanded"
        }
        // collapse the island no matter what it is showing
        function onCloseRequested() {
            if (!root.isFocusedScreen)
                return
            root.pinned = false
            root.panelView = "controls"
            root.settle()
        }
        // step back one level: a drill view returns to the hub, the hub closes
        function onBackRequested() {
            if (!root.isFocusedScreen)
                return
            if (root.mode === "expanded" && root.panelView !== "controls") {
                root.panelView = "controls"
            } else {
                root.pinned = false
                root.settle()
            }
        }
        // open straight to a drill view (e.g. Super+Space -> Spotlight); pressing
        // the same bind again while it's showing toggles the island shut
        function onOpenViewRequested(view) {
            if (!root.isFocusedScreen)
                return
            if (root.mode === "expanded" && root.panelView === view && root.pinned) {
                root.pinned = false
                root.settle()
            } else {
                root.openPanel(view)
            }
        }
    }

    // ---------- target geometry per mode ----------
    readonly property real screenW: modelData?.width ?? 1920
    readonly property real pillW: {
        switch (mode) {
        case "chip":      return 220
        case "media": {
            // grow so the title fits, clamped to the screen
            const content = 44 + Theme.spacingM + mediaPane.titleW + Theme.spacingS + mediaPane.controlsWidth + 20
            return Math.max(410, Math.min(content, screenW - 40))
        }
        case "expanded":  return 460
        case "idle": {
            // grow when the side clusters are wide so the centre title never collapses
            const need = idlePane.wsWidth + idlePane.clusterWidth + 90 + Theme.spacingL * 2 + Theme.spacingM * 2
            return Math.max(480, Math.min(need, screenW - 40))
        }
        case "presenter": return 320
        default:          return Math.max(92, compactPane.contentWidth + Theme.spacingL * 2)  // compact
        }
    }
    readonly property real pillH: {
        switch (mode) {
        case "media":     return 78
        case "expanded":  return controlPanel.viewHeight + Theme.spacingM * 2
        case "idle":      return 50
        case "presenter": return 48
        case "chip":      return 34
        default:          return 28   // compact
        }
    }
    readonly property real pillRadius: (mode === "compact" || mode === "chip") ? 12 : 22
    // notch mode: flush to the top edge, only the bottom corners round (MacBook look)
    readonly property bool notchMode: SettingsData.dynamicIslandNotchMode
    // radius of the concave flare where the notch meets the screen's top edge
    readonly property real notchCornerR: 13

    // keyboard-driven drill views (the controller-level list; the pill window
    // derives its keyboardFocus from it)
    readonly property var _kbViews: ["apps", "clipboard", "emoji", "wallpaper"]
    // the Wi-Fi view grabs the keyboard only while an inline password prompt is
    // open (set by WifiPanel) — without it the field can never receive input
    property bool wifiNeedsKeyboard: false

    // ---------- windows ----------

    // click-outside-to-dismiss scrim (macOS): a SEPARATE fullscreen surface
    // mapped only while the panel is expanded. Layer-shell puts a freshly
    // mapped surface on top of its layer, so the pill and the banner stack are
    // SUBTRACTED from its input region — clicks on them fall through to their
    // own windows, clicks anywhere else dismiss.
    PanelWindow {
        id: scrimWindow
        screen: root.modelData
        visible: root.mode === "expanded"
        WlrLayershell.namespace: "dms:dynamic-island-scrim"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        mask: Region {
            x: 0; y: 0
            width: scrimWindow.width; height: scrimWindow.height
            Region { x: pill.x; y: pill.y; width: pill.width; height: pill.height; intersection: Intersection.Subtract }
            Region { x: scrimWindow.width - notifBanners.width - 16; y: 0; width: notifBanners.width + 16; height: notifBanners.height + 24; intersection: Intersection.Subtract }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: { root.pinned = false; root.settle() }
        }
    }

    // ambient screen-edge glow on a new notification: fullscreen but VISUAL
    // ONLY (empty input mask = fully click-through), mapped just for the ~2s
    // pulse. Lives on the Top layer so it never paints OVER the island/banners
    // (Overlay) and stays beneath fullscreen apps.
    PanelWindow {
        id: glowWindow
        screen: root.modelData
        visible: edgeGlow.pulse > 0
        WlrLayershell.namespace: "dms:dynamic-island-glow"
        WlrLayershell.layer: WlrLayershell.Top
        WlrLayershell.exclusiveZone: -1
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        mask: Region {}
        NotificationEdgeGlow { id: edgeGlow; island: root; anchors.fill: parent }
    }

    // macOS-style notification banners: a fixed top-right strip mapped only
    // while popups exist; input limited to the actual banner stack
    PanelWindow {
        id: bannerWindow
        screen: root.modelData
        visible: root.isFocusedScreen && root.popups.length > 0
        WlrLayershell.namespace: "dms:dynamic-island-banners"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        // grab the keyboard only while an inline reply field is open
        WlrLayershell.keyboardFocus: notifBanners.needsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        anchors { top: true; right: true }
        implicitWidth: 440
        implicitHeight: 720
        mask: Region { item: notifBanners }
        NotificationBanners { id: notifBanners; island: root }
    }

    // the island itself: a top strip tall enough for the largest expanded
    // state (fixed height — resizing a layer surface every spring frame would
    // hammer the compositor with configures). Input is masked to the pill;
    // the strip is otherwise click-through. Unmapped entirely while hidden
    // for a fullscreen window.
    PanelWindow {
        id: pillWindow
        screen: root.modelData
        visible: pill.opacity > 0
        WlrLayershell.namespace: "dms:dynamic-island"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        color: "transparent"
        anchors { top: true; left: true; right: true }
        implicitHeight: 620
        // keyboard focus for the keyboard-driven drill views: the search ones
        // (Spotlight / clipboard / emoji) need it to type, the wallpaper grid for
        // arrow navigation, Wi-Fi while a password prompt is open. Exclusive
        // (modal) grab: engages immediately on open, whereas Hyprland's OnDemand
        // only kicks in on a pointer click. Released the instant panelView leaves.
        WlrLayershell.keyboardFocus: {
            if (root.mode !== "expanded")
                return WlrKeyboardFocus.None
            if (root._kbViews.indexOf(root.panelView) !== -1)
                return WlrKeyboardFocus.Exclusive
            if (root.panelView === "wifi" && root.wifiNeedsKeyboard)
                return WlrKeyboardFocus.Exclusive
            return WlrKeyboardFocus.None
        }
        mask: Region {
            // drop the pill from the input region while it's hidden for
            // fullscreen, so top-center clicks reach the app underneath
            Region { item: root.pillSuppressed ? null : pill }
        }

    Item {
        id: stage
        anchors.fill: parent
        readonly property real cx: width / 2

        // album-art ambient glow: a heavily-blurred copy of the cover art behind the
        // pill → a soft color bloom in the album's real colors (Apple Music vibe).
        // GPU-only, no colour extraction. Sits OUTSIDE the input mask (passthrough).
        Item {
            id: artGlow
            anchors.centerIn: pill
            width: pill.width + 56
            height: pill.height + 56
            opacity: (!root.pillSuppressed && root.player && root.player.trackArtUrl && (root.mode === "media" || root.mode === "chip")) ? 0.45 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.mediumDuration } }
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64; autoPaddingEnabled: true }
            Image {
                anchors.fill: parent
                source: root.player ? (root.player.trackArtUrl ?? "") : ""
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
                cache: true; asynchronous: true
            }
        }

        // unified island body: fill + border + glow drawn as ONE silhouette so
        // every effect traces the true shape (incl. the concave macOS notch
        // flares), instead of the rectangular content host. Sits behind the
        // pill, mirroring its geometry/transforms so they morph in lockstep.
        readonly property real notchFlare: root.notchMode ? root.notchCornerR : 0
        NotchVisual {
            id: notchVisual
            notchMode: root.notchMode
            flare: root.notchCornerR
            cornerRadius: pill.radius
            x: pill.x - stage.notchFlare
            y: pill.y
            width: pill.width + stage.notchFlare * 2
            height: pill.height
            fillColor: root.islandColor
            strokeWidth: pill.alertBorder ? 1.5 : 1
            strokeColor: pill.alertBorder
                ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.7)
                : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)
            Behavior on strokeColor { ColorAnimation { duration: Theme.mediumDuration } }
            antialiasing: true
            visible: pill.visible
            opacity: pill.opacity
            scale: pill.scale
            transform: Scale {
                origin.x: notchVisual.width / 2; origin.y: notchVisual.height / 2
                xScale: pill.squashX; yScale: pill.squashY
            }
            // dark elevation shadow, morphing into an accent glow during
            // media/chip/notif — now cast by the real notch silhouette
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: root.glowActive ? root.accent : "#000000"
                shadowBlur: root.glowActive ? 1.0 : 0.8
                shadowVerticalOffset: root.glowActive ? 0 : 4
                shadowScale: root.glowActive ? 1.04 : 1.0
                shadowOpacity: root.glowActive ? 0.55 : 0.4
                Behavior on shadowColor { ColorAnimation { duration: Theme.mediumDuration } }
                Behavior on shadowOpacity { NumberAnimation { duration: Theme.mediumDuration } }
            }
        }

        Rectangle {
            id: pill
            x: stage.cx - width / 2
            y: root.notchMode ? 0 : 4
            width: root.pillW
            height: root.pillH
            radius: root.pillRadius
            // fill + border + glow are drawn by notchVisual (the unified
            // silhouette); the pill itself is just the transparent, clipped
            // host for the content panes + interaction handlers.
            color: "transparent"
            readonly property bool alertBorder: root.privacyActive
            antialiasing: true
            clip: true

            // fade the whole island away while a fullscreen window owns this screen
            // (presenter OSD / expanded panel are exempt via pillSuppressed)
            opacity: root.pillSuppressed ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.standardEasing } }

            // Apple-style morph: gentle overshoot, height a touch bouncier than
            // width so the shape "pops" organically rather than sliding linearly
            Behavior on width   { SpringAnimation { spring: 5.0; damping: 0.40; mass: 1.0; epsilon: 0.2 } }
            Behavior on height  { SpringAnimation { spring: 5.4; damping: 0.30; mass: 1.0; epsilon: 0.2 } }
            Behavior on radius  { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }

            property real bumpScale: 1.0
            scale: (bgClick.pressed ? 0.985 : 1.0) * bumpScale
            Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }

            // squash-and-stretch: on every mode change the pill briefly widens &
            // flattens, then springs back — the signature gelatinous Apple morph
            property real squashX: 1.0
            property real squashY: 1.0
            transform: Scale {
                origin.x: pill.width / 2; origin.y: pill.height / 2
                xScale: pill.squashX; yScale: pill.squashY
            }
            Connections {
                target: root
                function onModeChanged() { squashAnim.restart() }
            }
            SequentialAnimation {
                id: squashAnim
                ParallelAnimation {
                    NumberAnimation { target: pill; property: "squashX"; to: 1.035; duration: 110; easing.type: Easing.OutQuad }
                    NumberAnimation { target: pill; property: "squashY"; to: 0.955; duration: 110; easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    SpringAnimation { target: pill; property: "squashX"; to: 1.0; spring: 4.5; damping: 0.16; epsilon: 0.005 }
                    SpringAnimation { target: pill; property: "squashY"; to: 1.0; spring: 4.5; damping: 0.16; epsilon: 0.005 }
                }
            }

            // glass material: bright specular rim along the top edge + a soft
            // inner shadow at the bottom → "floating glass" depth (macOS vibrancy)
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: pill.radius
                topLeftRadius: root.notchMode ? 0 : pill.radius
                topRightRadius: root.notchMode ? 0 : pill.radius
                bottomLeftRadius: pill.radius
                bottomRightRadius: pill.radius
                z: 0
                gradient: Gradient {
                    GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, root.notchMode ? 0.05 : 0.11) }
                    GradientStop { position: 0.10; color: Qt.rgba(1, 1, 1, 0.0) }
                    GradientStop { position: 0.82; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.10) }
                }
            }

            // reusable morph: scale+fade content per mode
            // each at-rest pane (panes/) sets visible/opacity/scale from root.mode
            // and exposes the widths the pill geometry reads.
            CompactPane   { id: compactPane;   island: root }
            ChipPane      { id: chipPane;       island: root }
            IdlePane      { id: idlePane;       island: root }
            MediaPane     { id: mediaPane;      island: root }

            // ===== EXPANDED: inline Control Center + drill-down views =====
            ControlCenterPanel { id: controlPanel; island: root }

            // ===== PRESENTER: volume / brightness / battery OSD + BT splash =====
            PresenterPane { id: presenterPane; island: root }

            // ---- hover (tracks through child MouseAreas) ----
            HoverHandler {
                id: hoverHandler
                onHoveredChanged: {
                    root.hovered = hovered
                    if (hovered) {
                        hideTimer.stop()
                        if (root.mode === "compact" || root.mode === "chip") {
                            root.mode = root.playing ? "media" : "idle"
                            root.bump()   // tactile pop as the island unfolds under the pointer
                        }
                    } else if (!root.pinned) {
                        // expanded panel = macOS: stays open until a click outside (scrim),
                        // the back button, or Super+I — NOT on pointer-leave
                        if (root.mode !== "expanded")
                            hideTimer.restart()
                    }
                }
            }

            // ---- scroll over the island -> volume ----
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (!root.audioNode) return
                    const step = (event.angleDelta.y > 0 ? 0.05 : -0.05)
                    root.audioNode.volume = Math.max(0, Math.min(1, root.audioNode.volume + step))
                    AudioService.playVolumeChangeSoundIfEnabled()   // macOS-style volume tick
                }
            }

            // ---- background click-to-expand, BELOW content (buttons stay clickable) ----
            MouseArea {
                id: bgClick
                anchors.fill: parent
                z: -1
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) {
                        if (root.audioNode) root.audioNode.muted = !root.audioNode.muted
                        return
                    }
                    if (root.mode === "expanded") {
                        root.pinned = false
                        root.settle()
                    } else {
                        // don't pin on click-expand: the island can't receive clicks
                        // outside its mask, so it auto-collapses once the pointer
                        // leaves (only Super+I pins, for keyboard users)
                        root.mode = "expanded"
                    }
                }
            }
        }

    }
    }

    // native popup menu for system-tray items (anchored under the icon)
    QsMenuAnchor {
        id: trayMenu
        anchor.window: pillWindow
    }

    // subtle "bump" feedback (replaces the old liquid droplet)
    function bump() { bumpAnim.restart() }
    SequentialAnimation {
        id: bumpAnim
        NumberAnimation { target: pill; property: "bumpScale"; to: 1.05; duration: 140; easing.type: Easing.OutBack }
        NumberAnimation { target: pill; property: "bumpScale"; to: 1.0;  duration: 260; easing.type: Easing.OutBack }
    }
}
