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
PanelWindow {
    id: root

    property var modelData
    screen: modelData

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
    readonly property bool glowActive: mode === "media" || mode === "chip" || mode === "notif"

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
    // NotificationService appends new popups, so the freshest is the LAST element
    readonly property var latestPopup: popups.length > 0 ? popups[popups.length - 1] : null
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
    // named actions for the active notif, minus the implicit "default" (body click), capped to keep the pill compact
    readonly property var notifActions: {
        if (!latestPopup || !latestPopup.actions) return []
        var out = []
        for (var i = 0; i < latestPopup.actions.length && out.length < 2; i++) {
            var a = latestPopup.actions[i]
            if (a && a.identifier !== "default" && (a.text || "").length > 0)
                out.push(a)
        }
        return out
    }
    // critical notifications must not auto-dismiss (battery dead, link lost, ...)
    readonly property bool notifCritical: latestPopup ? (latestPopup.urgency === NotificationUrgency.Critical) : false
    // the implicit "default" action (invoked by clicking the notification body)
    function defaultAction() {
        if (!latestPopup || !latestPopup.actions) return null
        for (var i = 0; i < latestPopup.actions.length; i++) {
            var a = latestPopup.actions[i]
            if (a && a.identifier === "default") return a
        }
        return null
    }
    // macOS model: notifications are independent top-right banners (see bannerList),
    // they NEVER take over the island. The pill's old "notif" mode is retired.

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
    Timer { running: true; interval: 1500; onTriggered: root.ready = true }

    // real audio spectrum: hold a ref on CavaService while a visual shows
    Loader {
        active: root.cavaActive
        sourceComponent: Component { Ref { service: CavaService } }
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
    // | "notif" | "presenter"
    property string mode: "compact"
    property bool hovered: false
    property bool pinned: false

    // which view the expanded panel shows: "controls" hub or a drilled-in detail
    property string panelView: "controls"   // "controls" | "wifi" | "bluetooth" | "audio" | "notifications" | "calendar" | "apps" | "clipboard" | "emoji"
    onModeChanged: if (mode !== "expanded") panelView = "controls"   // reset on close
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
        if (presenterKind === "battery") return charging ? "battery_charging_full" : "battery_full"
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
    onPlayingChanged: if (!hovered && !pinned && mode !== "notif" && mode !== "presenter") mode = restMode()

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

    function showNotif() {
        pendingPopup = null
        mode = "notif"; bump()
        // read straight off latestPopup: the derived notifCritical/notifActions
        // bindings haven't recomputed yet in this same tick (would be stale)
        const p = latestPopup
        const crit = p ? (p.urgency === NotificationUrgency.Critical) : false
        var actionable = false
        if (p && p.actions) {
            for (var i = 0; i < p.actions.length; i++) {
                const a = p.actions[i]
                if (a && a.identifier !== "default" && (a.text || "").length > 0) { actionable = true; break }
            }
        }
        // critical stays until dismissed; an actionable notif already under the
        // cursor keeps its buttons (hover transition won't refire to pause it)
        if (crit || (hovered && actionable)) { notifTimer.stop(); return }
        notifTimer.restart()
    }
    Timer { id: notifTimer; interval: 4000; onTriggered: root.settle() }
    // idle/media linger after pointer-leave; the expanded panel is dismissed by a
    // click outside (scrim), not by this timer (macOS behaviour).
    Timer { id: hideTimer; interval: 1800; onTriggered: root.settle() }

    function showPresenter(kind) {
        if (!ready || !isFocusedScreen) return
        if (mode === "notif" || mode === "expanded") return   // don't stomp a notif / the inline control center
        presenterKind = kind   // value/icon follow reactively from here
        mode = "presenter"
        bump()
        presenterTimer.restart()
    }
    Timer { id: presenterTimer; interval: 1500; onTriggered: root.settle() }
    // glanceable splash (Bluetooth connected, …) — icon + label, lingers a bit longer
    function showSplash(icon, label) {
        if (!ready || !isFocusedScreen || mode === "notif") return
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

    // open the real DMS menus, anchored under the island.
    // Popouts center under (triggerX + triggerWidth/2), so triggerX must be the
    // island's LEFT edge (the pill is centered in the screen-centered window).
    function openMenu(which) {
        const sw = modelData?.width ?? 1920
        const w = pill.width
        const sx = (sw - w) / 2
        // anchor below the resting island with a small breathing gap
        const sy = 52
        // a launcher button should OPEN its menu, never toggle it shut: if a popout's
        // shouldBeVisible was left true (stale), toggle() would close it -> "nothing
        // happens". open*() is idempotent. The bar (gone in island mode) normally
        // activates these LazyLoaders, so we do it ourselves before opening.
        switch (which) {
        case "apps":          PopoutService.openDankLauncherV2(); break
        case "dash":          PopoutService.openDankDash(0, sx, sy, w, "center", modelData); break
        case "notifications":
            if (PopoutService.notificationCenterLoader)
                PopoutService.notificationCenterLoader.active = true
            PopoutService.openNotificationCenter(sx, sy, w, "center", modelData)
            break
        case "control":
            if (PopoutService.controlCenterLoader)
                PopoutService.controlCenterLoader.active = true
            PopoutService.openControlCenter(sx, sy, w, "center", modelData)
            break
        case "clipboard":     PopoutService.openClipboardHistory(); break
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
        case "notif":     return notifActions.length > 0 ? 524 : 464
        case "presenter": return 320
        default:          return Math.max(92, compactPane.contentWidth + Theme.spacingL * 2)  // compact
        }
    }
    readonly property real pillH: {
        switch (mode) {
        case "media":     return 78
        case "expanded":  return controlPanel.viewHeight + Theme.spacingM * 2
        case "idle":      return 50
        case "notif":     return 80
        case "presenter": return 48
        case "chip":      return 34
        default:          return 28   // compact
        }
    }
    readonly property real pillRadius: (mode === "compact" || mode === "chip") ? 12 : 22
    // notch mode: flush to the top edge, only the bottom corners round (MacBook look)
    readonly property bool notchMode: SettingsData.dynamicIslandNotchMode

    // ---------- window ----------
    WlrLayershell.namespace: "dms:dynamic-island"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    // keyboard focus only for the search-driven drill views (Spotlight / clipboard) so
    // their text fields can type; everything else stays focus-free (click-through).
    // Exclusive (modal) grab: reliable and engages immediately on open, whereas
    // Hyprland's OnDemand focus-grab only kicks in on a pointer click. Released the
    // instant panelView leaves apps/clipboard; Esc / click-outside scrim / back all exit.
    WlrLayershell.keyboardFocus: {
        if (mode !== "expanded" || (panelView !== "apps" && panelView !== "clipboard" && panelView !== "emoji"))
            return WlrKeyboardFocus.None
        return WlrKeyboardFocus.Exclusive
    }
    color: "transparent"

    // full-screen overlay: input is masked to just the pill (everything else is
    // click-through), EXCEPT while the panel is expanded — then the whole screen
    // is captured so a click anywhere outside the pill dismisses it (macOS style).
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.margins { top: 0; left: 0; right: 0; bottom: 0 }

    // input region = pill (or full screen when expanded) UNION the banner stack,
    // so banner buttons/swipe are clickable while the rest stays click-through
    mask: Region {
        Region { item: root.mode === "expanded" ? stage : pill }
        Region { item: notifBanners }
    }

    Item {
        id: stage
        anchors.fill: parent
        readonly property real cx: width / 2

        // click-outside-to-dismiss scrim (macOS): only live while expanded, sits
        // behind the pill so clicks ON the pill reach its controls
        MouseArea {
            anchors.fill: parent
            z: -5
            enabled: root.mode === "expanded"
            visible: enabled
            onClicked: { root.pinned = false; root.settle() }
        }

        // album-art ambient glow: a heavily-blurred copy of the cover art behind the
        // pill → a soft color bloom in the album's real colors (Apple Music vibe).
        // GPU-only, no colour extraction. Sits OUTSIDE the input mask (passthrough).
        Item {
            id: artGlow
            anchors.centerIn: pill
            width: pill.width + 56
            height: pill.height + 56
            opacity: (root.player && root.player.trackArtUrl && (root.mode === "media" || root.mode === "chip")) ? 0.45 : 0
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

        // ambient screen-edge glow pulse on a new notification (passthrough)
        NotificationEdgeGlow { id: edgeGlow; island: root }

        Rectangle {
            id: pill
            x: stage.cx - width / 2
            y: root.notchMode ? 0 : 4
            width: root.pillW
            height: root.pillH
            radius: root.pillRadius
            // square top corners when docked to the edge (notch), rounded otherwise
            topLeftRadius: root.notchMode ? 0 : root.pillRadius
            topRightRadius: root.notchMode ? 0 : root.pillRadius
            bottomLeftRadius: root.pillRadius
            bottomRightRadius: root.pillRadius
            Behavior on topLeftRadius { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }
            Behavior on topRightRadius { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }
            Behavior on bottomLeftRadius { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }
            Behavior on bottomRightRadius { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }
            color: root.islandColor
            readonly property bool alertBorder: root.privacyActive || (root.mode === "notif" && root.notifCritical)
            border.width: alertBorder ? 1.5 : 1
            border.color: alertBorder ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.7) : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)
            Behavior on border.color { ColorAnimation { duration: Theme.mediumDuration } }
            antialiasing: true
            clip: true

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

            // single effect: dark elevation shadow, morphing into an accent
            // glow during media/chip/notif (replaces the old 2nd MultiEffect)
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

            // glass material: bright specular rim along the top edge + a soft
            // inner shadow at the bottom → "floating glass" depth (macOS vibrancy)
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: pill.radius
                topLeftRadius: pill.topLeftRadius; topRightRadius: pill.topRightRadius
                bottomLeftRadius: pill.bottomLeftRadius; bottomRightRadius: pill.bottomRightRadius
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
                        // keep an actionable notif up while the pointer is on it, so its buttons stay clickable
                        if (root.mode === "notif" && root.notifActions.length > 0)
                            notifTimer.stop()
                        if (root.mode === "compact" || root.mode === "chip") {
                            root.mode = root.playing ? "media" : "idle"
                            root.bump()   // tactile pop as the island unfolds under the pointer
                        }
                    } else if (!root.pinned) {
                        // critical notifs never auto-dismiss; others resume their timer
                        if (root.mode === "notif" && !root.notifCritical)
                            notifTimer.restart()
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

        // macOS-style notification banners (independent, island-styled)
        NotificationBanners { id: notifBanners; island: root }
    }

    // native popup menu for system-tray items (anchored under the icon)
    QsMenuAnchor {
        id: trayMenu
        anchor.window: root
    }

    // subtle "bump" feedback (replaces the old liquid droplet)
    function bump() { bumpAnim.restart() }
    SequentialAnimation {
        id: bumpAnim
        NumberAnimation { target: pill; property: "bumpScale"; to: 1.05; duration: 140; easing.type: Easing.OutBack }
        NumberAnimation { target: pill; property: "bumpScale"; to: 1.0;  duration: 260; easing.type: Easing.OutBack }
    }
}
