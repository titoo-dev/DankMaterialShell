import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import qs.Widgets

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
    property string panelView: "controls"   // "controls" | "wifi" | "bluetooth" | "audio" | "notifications"
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
    onChargingChanged: if (ready) showPresenter("battery")

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
            const titleW = Math.min(Math.max(mTitle.implicitWidth, mArtist.implicitWidth, mEyebrow.implicitWidth), 360)
            const content = 44 + Theme.spacingM + titleW + Theme.spacingS + controls.implicitWidth + 20
            return Math.max(410, Math.min(content, screenW - 40))
        }
        case "expanded":  return 460
        case "idle": {
            // grow when the side clusters are wide so the centre title never collapses
            const need = wsRow.implicitWidth + rightCluster.implicitWidth + 90 + Theme.spacingL * 2 + Theme.spacingM * 2
            return Math.max(480, Math.min(need, screenW - 40))
        }
        case "notif":     return notifActions.length > 0 ? 524 : 464
        case "presenter": return 320
        default:          return Math.max(92, compactRow.implicitWidth + Theme.spacingL * 2)  // compact
        }
    }
    readonly property real pillH: {
        switch (mode) {
        case "media":     return 78
        case "expanded":  return (panelView === "wifi" ? wifiCol.implicitHeight : panelView === "bluetooth" ? btCol.implicitHeight : panelView === "audio" ? audioCol.implicitHeight : panelView === "notifications" ? notifCol.implicitHeight : ccColumn.implicitHeight) + Theme.spacingM * 2
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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
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
        Region { item: bannerArea }
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
            // (each block sets `visible/opacity/scale` from root.mode)

            // ===== COMPACT (rest): split leading-status | notch gap | trailing-clock =====
            Row {
                id: compactRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                opacity: root.mode === "compact" ? 1 : 0
                visible: opacity > 0
                scale: root.mode === "compact" ? 1 : 0.9
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

                // leading cluster: privacy (mic/cam/screen-share) + battery-low
                Row {
                    id: cStatus
                    spacing: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.privacyActive || (root.batAvailable && root.batPct <= 20 && !root.charging)
                    DankIcon { visible: PrivacyService.microphoneActive; name: "mic"; size: 14; color: Theme.error; filled: true; anchors.verticalCenter: parent.verticalCenter }
                    DankIcon { visible: PrivacyService.cameraActive; name: "videocam"; size: 14; color: Theme.error; filled: true; anchors.verticalCenter: parent.verticalCenter }
                    DankIcon { visible: PrivacyService.screensharingActive; name: "screen_share"; size: 14; color: Theme.warning; filled: true; anchors.verticalCenter: parent.verticalCenter }
                    DankIcon { visible: root.batAvailable && root.batPct <= 20 && !root.charging; name: "battery_alert"; size: 14; color: Theme.error; anchors.verticalCenter: parent.verticalCenter }
                }
                // central "notch" gap — only present when the leading cluster has content
                Item { width: Theme.spacingL; height: 1; anchors.verticalCenter: parent.verticalCenter; visible: cStatus.visible }
                // trailing cluster: clock
                StyledText {
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: root.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ===== CHIP (rest + media): tiny now-playing =====
            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                opacity: root.mode === "chip" ? 1 : 0
                visible: opacity > 0
                scale: root.mode === "chip" ? 1 : 0.9
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }
                Item {  // album art wrapped in a circular progress ring (Apple "Live Activity" feel)
                    width: 26; height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    Shape {  // faint track
                        anchors.fill: parent; antialiasing: true
                        visible: root.mediaLen > 0
                        ShapePath {
                            strokeWidth: 2; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                            strokeColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                            PathAngleArc { centerX: 13; centerY: 13; radiusX: 11.5; radiusY: 11.5; startAngle: -90; sweepAngle: 360 }
                        }
                    }
                    Shape {  // progress
                        anchors.fill: parent; antialiasing: true
                        visible: root.mediaLen > 0
                        ShapePath {
                            strokeWidth: 2; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                            strokeColor: root.accent
                            PathAngleArc {
                                centerX: 13; centerY: 13; radiusX: 11.5; radiusY: 11.5
                                startAngle: -90; sweepAngle: 360 * root.mediaFrac
                                Behavior on sweepAngle { NumberAnimation { duration: 900; easing.type: Easing.OutSine } }
                            }
                        }
                    }
                    Rectangle {
                        width: 20; height: 20; radius: 6; clip: true; color: Theme.primaryBackground
                        anchors.centerIn: parent
                        Image { anchors.fill: parent; source: root.player ? (root.player.trackArtUrl ?? "") : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                        DankIcon { anchors.centerIn: parent; name: "music_note"; size: 12; color: root.accent; visible: !(root.player && root.player.trackArtUrl) }
                    }
                }
                Row {
                    spacing: 2; height: 16; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: 5
                        Rectangle {
                            width: 2.5; radius: 1.25; color: root.accent
                            anchors.verticalCenter: parent.verticalCenter
                            height: root.eqHeight(index)
                            Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutSine } }
                        }
                    }
                }
                // central "notch" gap + trailing clock (Apple leading/trailing split)
                Item { width: Theme.spacingM; height: 1; anchors.verticalCenter: parent.verticalCenter }
                StyledText {
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: root.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ===== IDLE (hover): workspaces + clock + tray + battery =====
            Item {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingL; anchors.rightMargin: Theme.spacingL
                opacity: root.mode === "idle" ? 1 : 0
                visible: opacity > 0
                scale: root.mode === "idle" ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

                Row {
                    id: wsRow
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    Repeater {
                        model: root.wsList
                        Rectangle {
                            readonly property bool active: modelData.focused
                            width: 30; height: 30; radius: 10
                            color: active ? Theme.primarySelected : (wsArea.containsMouse ? Theme.surfaceHover : "transparent")
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            scale: wsArea.pressed ? 0.86 : 1.0
                            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                            StyledText {
                                anchors.centerIn: parent; text: modelData.label
                                color: active ? root.accent : root.subText
                                font.pixelSize: Theme.fontSizeSmall; font.bold: active
                            }
                            MouseArea {
                                id: wsArea; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.wsActivate(modelData.key)
                            }
                        }
                    }
                }
                // focused window — fills the gap BETWEEN the side clusters and
                // truncates to whatever width is actually available (no overlap)
                Item {
                    id: centerSlot
                    anchors.left: wsRow.right; anchors.leftMargin: Theme.spacingM
                    anchors.right: rightCluster.left; anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    // width comes purely from the anchors -> never collapses
                    StyledText {
                        anchors.fill: parent
                        visible: root.focusedTitle.length > 0
                        text: root.focusedTitle
                        elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: root.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                    }
                    StyledText {
                        anchors.fill: parent
                        visible: root.focusedTitle.length === 0
                        text: Qt.formatDateTime(clock.date, "ddd  HH:mm")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: root.textColor; font.pixelSize: Theme.fontSizeLarge; font.bold: true
                    }
                }
                Row {
                    id: rightCluster
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS
                    StyledText {
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: root.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Row {  // weather
                        spacing: 3; visible: root.weatherReady; anchors.verticalCenter: parent.verticalCenter
                        DankIcon { name: root.weatherIcon; size: Theme.iconSize - 7; color: root.subText; anchors.verticalCenter: parent.verticalCenter }
                        StyledText { text: root.weatherTemp; color: root.textColor; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
                    }
                    DankIcon {  // VPN
                        name: "vpn_lock"; size: Theme.iconSize - 6; color: root.accent
                        visible: root.vpnOn; anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {  // keyboard layout (niri/dwl)
                        text: root.kbLayout.substring(0, 2).toUpperCase()
                        visible: root.kbLayout.length > 0
                        color: root.subText; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Row {
                        spacing: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: root.trayItems
                            Item {
                                width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                                scale: trayArea.pressed ? 0.82 : (trayArea.containsMouse ? 1.12 : 1.0)
                                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                Image {
                                    anchors.centerIn: parent; width: 17; height: 17
                                    source: modelData.icon ?? ""
                                    sourceSize.width: 17; sourceSize.height: 17
                                }
                                MouseArea {
                                    id: trayArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.MiddleButton) {
                                            modelData.secondaryActivate()
                                        } else if (mouse.button === Qt.RightButton && modelData.hasMenu && modelData.menu) {
                                            const p = trayArea.mapToItem(null, 0, 0)
                                            trayMenu.menu = modelData.menu
                                            trayMenu.anchor.rect = Qt.rect(p.x, p.y + trayArea.height, trayArea.width, trayArea.height)
                                            trayMenu.open()
                                        } else {
                                            modelData.activate()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Row {
                        spacing: 4; visible: root.batAvailable; anchors.verticalCenter: parent.verticalCenter
                        DankIcon {
                            name: root.charging ? "battery_charging_full" : "battery_full"
                            size: Theme.iconSize - 5
                            color: root.charging ? Theme.primary : root.subText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: root.batPct + "%"; color: root.textColor; font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // ===== MEDIA (hover + playing): art, title, transport, scrubber =====
            Item {
                anchors.fill: parent
                anchors.leftMargin: 10; anchors.rightMargin: 10
                anchors.topMargin: 9; anchors.bottomMargin: 10
                opacity: root.mode === "media" ? 1 : 0
                visible: opacity > 0
                scale: root.mode === "media" ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

                Rectangle {
                    id: art
                    width: 44; height: 44; radius: 12; clip: true
                    anchors.left: parent.left; anchors.top: parent.top
                    color: Theme.primaryBackground
                    Image {
                        anchors.fill: parent
                        source: root.player ? (root.player.trackArtUrl ?? "") : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }
                    DankIcon {
                        anchors.centerIn: parent; name: "music_note"
                        size: 22; color: root.accent
                        visible: !(root.player && root.player.trackArtUrl)
                    }
                }
                Column {
                    anchors.left: art.right; anchors.leftMargin: Theme.spacingM
                    anchors.right: controls.left; anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: art.verticalCenter
                    spacing: 1
                    StyledText {  // eyebrow: player source / "NOW PLAYING"
                        id: mEyebrow
                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                        text: (root.player && root.player.identity) ? root.player.identity : I18n.tr("Now Playing")
                        color: root.accent; font.pixelSize: Theme.fontSizeSmall - 2
                        font.bold: true; font.capitalization: Font.AllUppercase
                    }
                    StyledText {
                        id: mTitle
                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                        text: root.player ? (root.player.trackTitle || "Unknown") : ""
                        color: root.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                    }
                    StyledText {
                        id: mArtist
                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                        text: root.player ? (root.player.trackArtist || "") : ""
                        color: root.subText; font.pixelSize: Theme.fontSizeSmall
                    }
                }
                Row {
                    id: controls
                    anchors.right: parent.right; anchors.verticalCenter: art.verticalCenter
                    spacing: 0
                    Repeater {
                        model: [
                            { icon: "skip_previous", label: I18n.tr("Previous"), big: false, en: root.player && root.player.canGoPrevious, act: () => { if (root.player) root.player.previous() } },
                            { icon: root.playing ? "pause" : "play_arrow", label: root.playing ? I18n.tr("Pause") : I18n.tr("Play"), big: true, en: !!root.player, act: () => { if (root.player) root.player.togglePlaying() } },
                            { icon: "skip_next", label: I18n.tr("Next"), big: false, en: root.player && root.player.canGoNext, act: () => { if (root.player) root.player.next() } }
                        ]
                        Rectangle {
                            width: 36; height: 36; radius: 12
                            color: cArea.containsMouse && modelData.en ? Theme.primaryHover : "transparent"
                            opacity: modelData.en ? 1 : 0.35
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            scale: cArea.pressed && modelData.en ? 0.86 : 1.0
                            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                            DankIcon { anchors.centerIn: parent; name: modelData.icon; size: modelData.big ? 26 : 20; color: root.accent }
                            ToolTip.visible: cArea.containsMouse && modelData.en
                            ToolTip.text: modelData.label
                            ToolTip.delay: 400
                            MouseArea {
                                id: cArea; anchors.fill: parent; hoverEnabled: true
                                enabled: modelData.en; cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.act()
                            }
                        }
                    }
                }
                Rectangle {
                    id: trackBar
                    anchors.left: art.right; anchors.leftMargin: Theme.spacingM
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 4; radius: 2
                    color: Theme.surfaceVariant
                    property int tick: 0
                    property bool seeking: false
                    property real seekFrac: 0
                    readonly property real frac: {
                        trackBar.tick
                        const len = MprisController.activePlayerStableLength
                        return (root.player && len > 0) ? Math.min(1, root.player.position / len) : 0
                    }
                    readonly property real shownFrac: seeking ? seekFrac : frac
                    Timer { interval: 1000; repeat: true; running: root.mode === "media" && root.playing && !trackBar.seeking; onTriggered: trackBar.tick++ }
                    Rectangle {
                        width: parent.width * trackBar.shownFrac; height: parent.height; radius: parent.radius
                        color: root.accent
                        Behavior on width { enabled: !trackBar.seeking; NumberAnimation { duration: 240 } }
                    }
                    // grab handle (visible while dragging)
                    Rectangle {
                        width: 10; height: 10; radius: 5; color: root.accent
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width * trackBar.shownFrac - width / 2
                        opacity: (seekArea.containsMouse || trackBar.seeking) ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                    }
                    MouseArea {
                        id: seekArea
                        anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.player && root.player.canSeek
                        preventStealing: true
                        function fracAt(mx) { return Math.max(0, Math.min(1, mx / width)) }
                        onPressed: mouse => { trackBar.seeking = true; trackBar.seekFrac = fracAt(mouse.x) }
                        onPositionChanged: mouse => { if (trackBar.seeking) trackBar.seekFrac = fracAt(mouse.x) }
                        onReleased: mouse => {
                            const len = MprisController.activePlayerStableLength
                            if (root.player && len > 0)
                                root.player.position = trackBar.seekFrac * len
                            trackBar.seeking = false
                        }
                        onCanceled: trackBar.seeking = false
                    }
                    // elapsed / remaining timestamps, revealed when scrubbing/hovering the bar
                    property bool timesShown: (seekArea.containsMouse || trackBar.seeking) && root.mediaLen > 0
                    StyledText {
                        anchors.left: parent.left; anchors.bottom: parent.top; anchors.bottomMargin: 4
                        text: { root.mediaTick; return root.fmtTime(trackBar.seeking ? trackBar.seekFrac * root.mediaLen : (root.player ? root.player.position : 0)) }
                        color: root.subText; font.pixelSize: Theme.fontSizeSmall - 3; font.bold: true
                        opacity: trackBar.timesShown ? 0.9 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                    }
                    StyledText {
                        anchors.right: parent.right; anchors.bottom: parent.top; anchors.bottomMargin: 4
                        text: { root.mediaTick; return "-" + root.fmtTime(Math.max(0, root.mediaLen - (trackBar.seeking ? trackBar.seekFrac * root.mediaLen : (root.player ? root.player.position : 0)))) }
                        color: root.subText; font.pixelSize: Theme.fontSizeSmall - 3; font.bold: true
                        opacity: trackBar.timesShown ? 0.9 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                    }
                }
            }

            // ===== EXPANDED: inline Control Center (macOS-style) =====
            Item {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                opacity: root.mode === "expanded" ? 1 : 0
                visible: opacity > 0
                scale: root.mode === "expanded" ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

                // absorb clicks inside the panel so interacting doesn't collapse it
                // (it collapses on pointer-leave via hideTimer, like macOS)
                MouseArea { anchors.fill: parent }

                Column {
                    id: ccColumn
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    spacing: Theme.spacingS
                    // drill-down: hub slides slightly left & fades when a detail view is open
                    opacity: root.panelView === "controls" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { x: root.panelView === "controls" ? 0 : -24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                    // ---- quick-toggle tiles ----
                    Row {
                        id: ccTiles
                        width: parent.width
                        spacing: Theme.spacingS
                        readonly property real tileW: (width - spacing * 3) / 4
                        Repeater {
                            model: ["wifi", "bt", "dnd", "theme"]
                            Rectangle {
                                readonly property string key: modelData
                                readonly property bool on: key === "wifi" ? NetworkService.wifiEnabled
                                    : key === "bt" ? BluetoothService.enabled
                                    : key === "dnd" ? SessionData.doNotDisturb
                                    : Theme.isLightMode
                                readonly property string ic: key === "wifi" ? (NetworkService.wifiEnabled ? "wifi" : "wifi_off")
                                    : key === "bt" ? "bluetooth"
                                    : key === "dnd" ? "do_not_disturb_on"
                                    : (Theme.isLightMode ? "light_mode" : "dark_mode")
                                readonly property string lbl: key === "wifi" ? "Wi-Fi" : key === "bt" ? "Bluetooth" : key === "dnd" ? I18n.tr("Focus") : I18n.tr("Theme")
                                width: ccTiles.tileW; height: 54; radius: 16
                                color: on ? Theme.primary : Theme.surfaceLight
                                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                scale: tileArea.pressed ? 0.93 : 1.0
                                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                Column {
                                    anchors.centerIn: parent; spacing: 2
                                    DankIcon { anchors.horizontalCenter: parent.horizontalCenter; name: parent.parent.ic; size: 20; color: parent.parent.on ? Theme.primaryText : root.textColor }
                                    StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.lbl; font.pixelSize: Theme.fontSizeSmall - 2; color: parent.parent.on ? Theme.primaryText : root.subText }
                                }
                                // small chevron hinting the tile drills into a detail view
                                DankIcon {
                                    visible: parent.key === "wifi" || parent.key === "bt"
                                    anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 5
                                    name: "chevron_right"; size: 13; color: parent.on ? Theme.primaryText : root.subText
                                }
                                MouseArea {
                                    id: tileArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (key === "wifi") { root.panelView = "wifi"; NetworkService.scanWifiNetworks() }
                                        else if (key === "bt") { root.panelView = "bluetooth"; if (BluetoothService.adapter && BluetoothService.enabled) BluetoothService.adapter.discovering = true }
                                        else if (key === "dnd") SessionData.setDoNotDisturb(!SessionData.doNotDisturb)
                                        else Theme.setLightMode(!Theme.isLightMode, true, true)
                                    }
                                }
                            }
                        }
                    }

                    // ---- brightness + volume sliders ----
                    DankSlider {
                        width: parent.width
                        leftIcon: "brightness_6"
                        value: DisplayService.brightnessLevel
                        onSliderValueChanged: newValue => DisplayService.setBrightness(newValue, "", true)
                    }
                    Row {
                        width: parent.width; spacing: Theme.spacingS
                        DankSlider {
                            width: parent.width - 40
                            leftIcon: root.muted ? "volume_off" : "volume_up"
                            value: root.volPct
                            onSliderValueChanged: newValue => { if (root.audioNode) root.audioNode.volume = newValue / 100 }
                        }
                        Rectangle {  // output device picker (drills into the audio view)
                            width: 32; height: 32; radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: outArea.containsMouse ? Theme.primaryHover : Theme.surfaceLight
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            scale: outArea.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                            DankIcon { anchors.centerIn: parent; name: "speaker"; size: 17; color: outArea.containsMouse ? root.accent : root.textColor }
                            MouseArea { id: outArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.panelView = "audio" }
                        }
                    }

                    // ---- now playing (when a player is active) ----
                    Rectangle {
                        width: parent.width; height: 48; radius: 14
                        color: Theme.surfaceLight
                        visible: root.player
                        Rectangle {
                            id: ccArt
                            width: 34; height: 34; radius: 9; clip: true
                            anchors.left: parent.left; anchors.leftMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                            color: Theme.primaryBackground
                            Image { anchors.fill: parent; source: root.player ? (root.player.trackArtUrl ?? "") : ""; fillMode: Image.PreserveAspectCrop; cache: false; visible: status === Image.Ready }
                            DankIcon { anchors.centerIn: parent; name: "music_note"; size: 16; color: root.accent; visible: !(root.player && root.player.trackArtUrl) }
                        }
                        Column {
                            anchors.left: ccArt.right; anchors.leftMargin: Theme.spacingS
                            anchors.right: ccTransport.left; anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter; spacing: 0
                            StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: root.player ? (root.player.trackTitle || "Unknown") : ""; color: root.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                            StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: root.player ? (root.player.trackArtist || "") : ""; color: root.subText; font.pixelSize: Theme.fontSizeSmall - 1 }
                        }
                        Row {
                            id: ccTransport
                            anchors.right: parent.right; anchors.rightMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            Repeater {
                                model: [
                                    { icon: "skip_previous", big: false, en: root.player && root.player.canGoPrevious, act: () => { if (root.player) root.player.previous() } },
                                    { icon: root.playing ? "pause" : "play_arrow", big: true, en: !!root.player, act: () => { if (root.player) root.player.togglePlaying() } },
                                    { icon: "skip_next", big: false, en: root.player && root.player.canGoNext, act: () => { if (root.player) root.player.next() } }
                                ]
                                Rectangle {
                                    width: 32; height: 32; radius: 10
                                    color: ccBtn.containsMouse && modelData.en ? Theme.primaryHover : "transparent"
                                    opacity: modelData.en ? 1 : 0.35
                                    scale: ccBtn.pressed && modelData.en ? 0.86 : 1.0
                                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                    DankIcon { anchors.centerIn: parent; name: modelData.icon; size: modelData.big ? 22 : 18; color: root.accent }
                                    MouseArea { id: ccBtn; anchors.fill: parent; hoverEnabled: true; enabled: modelData.en; cursorShape: Qt.PointingHandCursor; onClicked: modelData.act() }
                                }
                            }
                        }
                    }

                    // ---- footer: access to the heavier DMS surfaces ----
                    Row {
                        width: parent.width
                        Repeater {
                            model: [
                                { icon: "apps",          which: "apps",          tip: I18n.tr("Apps") },
                                { icon: "notifications", which: "notifications", tip: I18n.tr("Notifications") },
                                { icon: "content_paste", which: "clipboard",     tip: I18n.tr("Clipboard") },
                                { icon: "tune",          which: "control",       tip: I18n.tr("All settings") }
                            ]
                            Item {
                                width: parent.width / 4; height: 34
                                Rectangle {
                                    anchors.centerIn: parent; width: 34; height: 30; radius: 9
                                    color: ftArea.containsMouse ? Theme.primaryHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    scale: ftArea.pressed ? 0.9 : 1.0
                                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                    DankIcon { anchors.centerIn: parent; name: modelData.icon; size: 19; color: ftArea.containsMouse ? root.accent : root.subText }
                                    ToolTip.visible: ftArea.containsMouse; ToolTip.text: modelData.tip; ToolTip.delay: 400
                                    MouseArea {
                                        id: ftArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            // notifications has an island-native view; others still open DMS popouts
                                            if (modelData.which === "notifications") root.panelView = "notifications"
                                            else { root.openMenu(modelData.which); root.pinned = false; root.settle() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- WI-FI detail view (drill-down, island-styled) ----
                Column {
                    id: wifiCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    spacing: Theme.spacingS
                    opacity: root.panelView === "wifi" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { x: root.panelView === "wifi" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                    // header: back · title · radio toggle
                    Item {
                        width: parent.width; height: 34
                        Rectangle {
                            id: backBtn
                            width: 30; height: 30; radius: 9
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            color: backArea.containsMouse ? Theme.primaryHover : "transparent"
                            scale: backArea.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: root.textColor }
                            MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.panelView = "controls" }
                        }
                        StyledText {
                            anchors.left: backBtn.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
                            text: "Wi-Fi"; color: root.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                        }
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacingXS
                            StyledText {
                                visible: NetworkService.isScanning; text: I18n.tr("Scanning…")
                                color: root.subText; font.pixelSize: Theme.fontSizeSmall - 1; anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {  // radio on/off pill switch
                                width: 44; height: 24; radius: 12
                                anchors.verticalCenter: parent.verticalCenter
                                color: NetworkService.wifiEnabled ? Theme.primary : Theme.surfaceLight
                                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                Rectangle {
                                    width: 18; height: 18; radius: 9; color: NetworkService.wifiEnabled ? Theme.primaryText : root.subText
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: NetworkService.wifiEnabled ? parent.width - width - 3 : 3
                                    Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.emphasizedEasing } }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NetworkService.toggleWifiRadio() }
                            }
                        }
                    }

                    // scrollable network list — height adapts to content, capped
                    Flickable {
                        width: parent.width; height: Math.min(netCol.height, 232); clip: true
                        contentHeight: netCol.height
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: netCol
                            width: parent.width; spacing: 4
                            StyledText {
                                width: parent.width; height: 40
                                visible: !NetworkService.wifiEnabled || (NetworkService.wifiNetworks || []).length === 0
                                text: !NetworkService.wifiEnabled ? I18n.tr("Wi-Fi is off") : (NetworkService.isScanning ? I18n.tr("Scanning…") : I18n.tr("No networks found"))
                                color: root.subText; font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            Repeater {
                                model: NetworkService.wifiEnabled ? (NetworkService.wifiNetworks || []) : []
                                Rectangle {
                                    id: netRow
                                    readonly property bool isConnected: modelData.ssid === NetworkService.currentWifiSSID
                                    readonly property bool needsPw: modelData.secured && !modelData.saved && !isConnected
                                    property bool pwOpen: false
                                    width: netCol.width
                                    height: pwOpen ? 84 : 46
                                    radius: 12
                                    color: (rowArea.containsMouse || isConnected) ? Theme.surfaceLight : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    Behavior on height { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.emphasizedEasing } }

                                    DankIcon {
                                        id: sigIcon
                                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.top: parent.top; anchors.topMargin: 13
                                        name: (modelData.signal >= 66 ? "network_wifi" : modelData.signal >= 33 ? "network_wifi_3_bar" : "network_wifi_1_bar")
                                        size: 20; color: netRow.isConnected ? root.accent : root.textColor
                                    }
                                    Column {
                                        anchors.left: sigIcon.right; anchors.leftMargin: Theme.spacingM
                                        anchors.right: rowRight.left; anchors.rightMargin: Theme.spacingS
                                        anchors.top: parent.top; anchors.topMargin: 6; spacing: 0
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: modelData.ssid || I18n.tr("Unknown"); color: root.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: netRow.isConnected }
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: netRow.isConnected ? I18n.tr("Connected") : (modelData.secured ? I18n.tr("Secured") : I18n.tr("Open")); color: root.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                                    }
                                    Row {
                                        id: rowRight
                                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.top: parent.top; anchors.topMargin: 13; spacing: Theme.spacingXS
                                        DankIcon { visible: modelData.secured; name: "lock"; size: 14; color: root.subText; anchors.verticalCenter: parent.verticalCenter }
                                        DankIcon { visible: netRow.isConnected; name: "check_circle"; size: 16; color: root.accent; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    MouseArea {
                                        id: rowArea; anchors.fill: parent; anchors.bottomMargin: netRow.pwOpen ? 40 : 0
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (netRow.isConnected) return
                                            if (netRow.needsPw) netRow.pwOpen = !netRow.pwOpen
                                            else NetworkService.connectToWifi(modelData.ssid)
                                        }
                                    }
                                    // inline password entry for secured & unsaved networks
                                    Row {
                                        visible: netRow.pwOpen
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Theme.spacingM
                                        anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                        spacing: Theme.spacingS
                                        DankTextField {
                                            id: pwField
                                            width: parent.width - 40
                                            height: 30
                                            echoMode: TextInput.Password
                                            placeholderText: I18n.tr("Password")
                                            leftIconName: "lock"
                                        }
                                        Rectangle {
                                            width: 32; height: 30; radius: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: goArea.containsMouse ? Theme.primary : Theme.surfaceVariant
                                            DankIcon { anchors.centerIn: parent; name: "arrow_forward"; size: 16; color: goArea.containsMouse ? Theme.primaryText : root.textColor }
                                            MouseArea {
                                                id: goArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: { NetworkService.connectToWifi(modelData.ssid, pwField.text); netRow.pwOpen = false }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- NOTIFICATIONS detail view (drill-down, island-styled) ----
                Column {
                    id: notifCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    spacing: Theme.spacingS
                    opacity: root.panelView === "notifications" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { x: root.panelView === "notifications" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                    // header: back · title · clear-all
                    Item {
                        width: parent.width; height: 34
                        Rectangle {
                            id: nBack
                            width: 30; height: 30; radius: 9
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            color: nBackArea.containsMouse ? Theme.primaryHover : "transparent"
                            scale: nBackArea.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: root.textColor }
                            MouseArea { id: nBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.panelView = "controls" }
                        }
                        StyledText {
                            anchors.left: nBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Notifications"); color: root.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                        }
                        Rectangle {  // clear all
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: clrLabel.implicitWidth + Theme.spacingM; height: 28; radius: 14
                            visible: (NotificationService.notifications || []).length > 0
                            color: clrArea.containsMouse ? Theme.primary : Theme.surfaceLight
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            StyledText { id: clrLabel; anchors.centerIn: parent; text: I18n.tr("Clear all"); font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true; color: clrArea.containsMouse ? Theme.primaryText : root.subText }
                            MouseArea { id: clrArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: NotificationService.clearAllNotifications() }
                        }
                    }

                    // scrollable notification list — adaptive height, capped
                    Flickable {
                        width: parent.width; height: Math.min(nlist.height, 300); clip: true
                        contentHeight: nlist.height
                        boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: nlist
                            width: parent.width; spacing: 4
                            StyledText {
                                width: parent.width; height: 56
                                visible: (NotificationService.notifications || []).length === 0
                                text: I18n.tr("No notifications"); color: root.subText; font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            Repeater {
                                model: NotificationService.notifications
                                Rectangle {
                                    id: nRow
                                    width: nlist.width; height: 66; radius: 12
                                    color: nRowArea.containsMouse ? Theme.surfaceLight : Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.4)
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                                    Rectangle {
                                        id: nRowIco
                                        width: 38; height: 38; radius: 11; clip: true
                                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                                        color: Theme.primaryBackground
                                        Image {
                                            id: nRowImg
                                            anchors.fill: parent; anchors.margins: 5
                                            source: (modelData.cleanImage || modelData.appIcon || "")
                                            fillMode: Image.PreserveAspectFit; cache: false; asynchronous: true
                                            visible: status === Image.Ready
                                        }
                                        DankIcon { anchors.centerIn: parent; name: "notifications"; size: 18; color: root.accent; visible: nRowImg.status !== Image.Ready }
                                    }
                                    Column {
                                        anchors.left: nRowIco.right; anchors.leftMargin: Theme.spacingM
                                        anchors.right: nRowRight.left; anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                        Row {
                                            width: parent.width; spacing: Theme.spacingXS
                                            StyledText { text: (modelData.appName || ""); color: root.accent; font.pixelSize: Theme.fontSizeSmall - 2; font.bold: true; font.capitalization: Font.AllUppercase; elide: Text.ElideRight; width: Math.min(implicitWidth, parent.width - 60) }
                                            StyledText { text: (modelData.timeStr || ""); color: root.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                                        }
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (modelData.summary || modelData.appName || ""); color: root.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (modelData.body || ""); visible: text.length > 0; color: root.subText; font.pixelSize: Theme.fontSizeSmall - 1 }
                                    }
                                    Rectangle {  // per-row dismiss
                                        id: nRowRight
                                        width: 26; height: 26; radius: 13
                                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                                        color: nClose.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : "transparent"
                                        opacity: nRowArea.containsMouse ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                                        DankIcon { anchors.centerIn: parent; name: "close"; size: 15; color: nClose.containsMouse ? Theme.error : root.subText }
                                        MouseArea { id: nClose; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: NotificationService.dismissNotification(modelData) }
                                    }
                                    MouseArea {
                                        id: nRowArea; anchors.fill: parent; hoverEnabled: true; z: -1
                                        onClicked: {
                                            const a = (modelData.actions && modelData.actions.length > 0) ? modelData.actions[0] : null
                                            if (a && a.invoke) { a.invoke(); NotificationService.dismissNotification(modelData) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- BLUETOOTH detail view (drill-down, island-styled) ----
                Column {
                    id: btCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    spacing: Theme.spacingS
                    opacity: root.panelView === "bluetooth" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { x: root.panelView === "bluetooth" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                    Item {
                        width: parent.width; height: 34
                        Rectangle {
                            id: btBack
                            width: 30; height: 30; radius: 9
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            color: btBackArea.containsMouse ? Theme.primaryHover : "transparent"
                            scale: btBackArea.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: root.textColor }
                            MouseArea { id: btBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.panelView = "controls"; if (BluetoothService.adapter) BluetoothService.adapter.discovering = false } }
                        }
                        StyledText { anchors.left: btBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter; text: "Bluetooth"; color: root.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 44; height: 24; radius: 12
                            color: BluetoothService.enabled ? Theme.primary : Theme.surfaceLight
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            Rectangle {
                                width: 18; height: 18; radius: 9; color: BluetoothService.enabled ? Theme.primaryText : root.subText
                                anchors.verticalCenter: parent.verticalCenter
                                x: BluetoothService.enabled ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.emphasizedEasing } }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (BluetoothService.adapter) BluetoothService.adapter.enabled = !BluetoothService.enabled } }
                        }
                    }

                    Flickable {
                        width: parent.width; height: Math.min(btList.height, 240); clip: true
                        contentHeight: btList.height; boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: btList
                            width: parent.width; spacing: 4
                            StyledText {
                                width: parent.width; height: 40
                                visible: !BluetoothService.enabled || (BluetoothService.pairedDevices || []).length === 0
                                text: !BluetoothService.enabled ? I18n.tr("Bluetooth is off") : I18n.tr("No devices")
                                color: root.subText; font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            Repeater {
                                model: BluetoothService.enabled ? (BluetoothService.pairedDevices || []) : []
                                Rectangle {
                                    readonly property bool isConn: modelData.connected
                                    width: btList.width; height: 46; radius: 12
                                    color: (btRowA.containsMouse || isConn) ? Theme.surfaceLight : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    DankIcon {
                                        id: btIco
                                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                                        name: BluetoothService.getDeviceIcon(modelData); size: 20; color: parent.isConn ? root.accent : root.textColor
                                    }
                                    Column {
                                        anchors.left: btIco.right; anchors.leftMargin: Theme.spacingM
                                        anchors.right: btSpin.left; anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 0
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: modelData.name || modelData.deviceName || I18n.tr("Unknown Device"); color: root.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: parent.parent.isConn }
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (parent.parent.isConn ? I18n.tr("Connected") : I18n.tr("Disconnected")) + ((modelData.batteryAvailable && modelData.battery > 0) ? ("  •  " + Math.round(modelData.battery * 100) + "%") : ""); color: root.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                                    }
                                    DankIcon { id: btSpin; anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter; name: parent.isConn ? "check_circle" : "add_circle"; size: 16; color: parent.isConn ? root.accent : root.subText }
                                    MouseArea {
                                        id: btRowA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { if (modelData.connected) modelData.disconnect(); else BluetoothService.connectDeviceWithTrust(modelData) }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- AUDIO OUTPUT detail view (drill-down, island-styled) ----
                Column {
                    id: audioCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    spacing: Theme.spacingS
                    opacity: root.panelView === "audio" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { x: root.panelView === "audio" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                    Item {
                        width: parent.width; height: 34
                        Rectangle {
                            id: auBack
                            width: 30; height: 30; radius: 9
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            color: auBackArea.containsMouse ? Theme.primaryHover : "transparent"
                            scale: auBackArea.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: root.textColor }
                            MouseArea { id: auBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.panelView = "controls" }
                        }
                        StyledText { anchors.left: auBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Output"); color: root.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true }
                    }

                    Flickable {
                        width: parent.width; height: Math.min(auList.height, 240); clip: true
                        contentHeight: auList.height; boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: auList
                            width: parent.width; spacing: 4
                            StyledText {
                                width: parent.width; height: 40
                                visible: (AudioService.typedSinks || []).length === 0
                                text: I18n.tr("No output devices"); color: root.subText; font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            }
                            Repeater {
                                model: AudioService.typedSinks
                                Rectangle {
                                    readonly property bool isCur: AudioService.sink && modelData && AudioService.sink.name === modelData.name
                                    width: auList.width; height: 46; radius: 12
                                    color: (auRowA.containsMouse || isCur) ? Theme.surfaceLight : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    DankIcon {
                                        id: auIco
                                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                                        name: "speaker"; size: 20; color: parent.isCur ? root.accent : root.textColor
                                    }
                                    StyledText {
                                        anchors.left: auIco.right; anchors.leftMargin: Theme.spacingM
                                        anchors.right: auChk.left; anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                                        text: modelData.description || modelData.name || I18n.tr("Output"); color: root.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: parent.isCur
                                    }
                                    DankIcon { id: auChk; anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter; name: "check_circle"; size: 16; color: root.accent; visible: parent.isCur }
                                    MouseArea { id: auRowA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.setSink(modelData) }
                                }
                            }
                        }
                    }
                }
            }

            // ===== PRESENTER: volume / brightness OSD =====
            // FIXED width (matches presenter pillW - margins) so the progress bar
            // keeps its correct proportion and just scales/fades in — the pill
            // shape springs behind it, but the bar never sweeps up from zero.
            Item {
                width: 320 - Theme.spacingL * 2
                height: parent.height
                anchors.centerIn: parent
                opacity: root.mode === "presenter" ? 1 : 0
                visible: opacity > 0
                scale: root.mode === "presenter" ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

                readonly property bool isSplash: root.presenterKind === "splash"

                DankIcon {
                    id: pIcon
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    name: root.presenterIcon; size: 24; color: root.accent
                }
                Rectangle {
                    anchors.left: pIcon.right; anchors.leftMargin: Theme.spacingM
                    anchors.right: pVal.left; anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6; radius: 3; color: Theme.surfaceVariant
                    visible: !parent.isSplash
                    Rectangle {
                        // parent width is now constant → only animates on real value changes
                        width: parent.width * Math.max(0, Math.min(1, root.presenterValue / 100))
                        height: parent.height; radius: parent.radius; color: root.accent
                        Behavior on width { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.emphasizedEasing } }
                    }
                }
                StyledText {
                    id: pVal
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: root.presenterValue + "%"
                    visible: !parent.isSplash
                    color: root.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                }
                StyledText {  // splash label (e.g. "AirPods connected")
                    anchors.left: pIcon.right; anchors.leftMargin: Theme.spacingM
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.isSplash
                    text: root.splashLabel
                    elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                    color: root.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                }
            }

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
                        if (root.mode === "compact" || root.mode === "chip")
                            root.mode = root.playing ? "media" : "idle"
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

        // ===== macOS-style notification banners — collapsible deck (top-right) =====
        // Independent of the island. At rest, multiple notifs collapse into a deck
        // with a count; hovering spreads them out. Island visual language throughout.
        Item {
            id: bannerArea
            width: 392
            anchors.top: parent.top; anchors.right: parent.right
            anchors.topMargin: root.notchMode ? 8 : 14
            anchors.rightMargin: 16
            visible: root.isFocusedScreen && n > 0

            readonly property var items: root.isFocusedScreen ? root.popups : []
            readonly property int n: items.length
            property bool expanded: areaHover.hovered
            readonly property bool collapsed: n > 1 && !expanded
            readonly property real gap: 10
            readonly property real peek: 9   // visible sliver per stacked card when collapsed

            // measured card heights (index -> px), to lay the spread out without a flow layout
            property var hmap: ({})
            function setH(i, h) { var m = hmap; m[i] = h; hmap = m }
            function cardH(i) { return (hmap[i] !== undefined && hmap[i] > 0) ? hmap[i] : 104 }

            readonly property real expandedH: { var s = 0; for (var i = 0; i < n; i++) s += cardH(i); return s + Math.max(0, n - 1) * gap }
            readonly property real collapsedH: cardH(n - 1) + Math.min(n - 1, 2) * peek
            height: n === 0 ? 0 : ((expanded || n === 1) ? expandedH : collapsedH)
            Behavior on height { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }

            HoverHandler { id: areaHover }

            Repeater {
                model: bannerArea.items
                delegate: Item {
                    id: bWrap
                    width: bannerArea.width
                    height: bCard.height
                    property var parentPopup: modelData
                    // rank from the newest popup (0 = newest, shown on top of the deck)
                    readonly property int r: bannerArea.n - 1 - index
                    z: 100 - r
                    transformOrigin: Item.Top

                    onHeightChanged: bannerArea.setH(index, height)
                    Component.onCompleted: bannerArea.setH(index, height)

                    // ---- placement: spread vs collapsed deck ----
                    readonly property real spreadY: {
                        var y = 0
                        for (var rr = 0; rr < r; rr++) y += bannerArea.cardH(bannerArea.n - 1 - rr) + bannerArea.gap
                        return y
                    }
                    readonly property bool active: bannerArea.expanded || bannerArea.n === 1 || r === 0
                    y: (bannerArea.expanded || bannerArea.n === 1) ? spreadY : (Math.min(r, 2) * bannerArea.peek)
                    Behavior on y { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }
                    scale: (bannerArea.expanded || bannerArea.n === 1) ? 1 : (1 - Math.min(r, 2) * 0.05)
                    Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }
                    opacity: (bannerArea.expanded || bannerArea.n === 1 || r < 3) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                    Rectangle {
                        id: bCard
                        width: parent.width
                        height: bCol.implicitHeight + 32   // generous vertical padding (16 top/bottom)
                        x: bCard.swipe
                        radius: 24
                        antialiasing: true
                        readonly property bool crit: modelData && modelData.urgency === NotificationUrgency.Critical
                        property real swipe: 0
                        Behavior on swipe { enabled: !bArea.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                        color: root.islandColor
                        border.width: crit ? 1.5 : 1
                        border.color: crit ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.7) : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: bCard.crit ? Theme.error : "#000000"
                            shadowBlur: bCard.crit ? 1.0 : 0.7
                            shadowVerticalOffset: 3
                            shadowOpacity: bCard.crit ? 0.5 : 0.32
                        }
                        Rectangle {  // glass material
                            anchors.fill: parent; radius: parent.radius; color: "transparent"
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                                GradientStop { position: 0.14; color: Qt.rgba(1, 1, 1, 0.0) }
                                GradientStop { position: 0.85; color: Qt.rgba(0, 0, 0, 0.0) }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.08) }
                            }
                        }

                        Column {
                            id: bCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.topMargin: 16
                            spacing: 10

                            Item {  // header: icon · (app + title + body) · dismiss
                                width: parent.width
                                height: Math.max(46, bText.implicitHeight)
                                Rectangle {
                                    id: bIco
                                    width: 46; height: 46; radius: 14; clip: true
                                    anchors.left: parent.left; anchors.top: parent.top
                                    color: Theme.primaryBackground
                                    Image {
                                        id: bImg
                                        anchors.fill: parent; anchors.margins: 6
                                        source: (modelData.cleanImage || modelData.appIcon || "")
                                        fillMode: Image.PreserveAspectFit; cache: false; asynchronous: true
                                        visible: status === Image.Ready
                                    }
                                    DankIcon { anchors.centerIn: parent; name: "notifications"; size: 22; color: bCard.crit ? Theme.error : root.accent; visible: bImg.status !== Image.Ready }
                                }
                                Column {
                                    id: bText
                                    anchors.left: bIco.right; anchors.leftMargin: 12
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 2
                                    Item {  // eyebrow line: app (left) · time (right)
                                        width: parent.width; height: bApp.implicitHeight
                                        StyledText {
                                            id: bApp
                                            anchors.left: parent.left; anchors.right: bTime.left; anchors.rightMargin: Theme.spacingS
                                            text: (modelData.appName || ""); color: bCard.crit ? Theme.error : root.accent
                                            font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true; font.capitalization: Font.AllUppercase
                                            elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                                        }
                                        StyledText {
                                            id: bTime
                                            anchors.right: parent.right; anchors.baseline: bApp.baseline
                                            text: (modelData.timeStr || ""); color: root.subText; font.pixelSize: Theme.fontSizeSmall - 1
                                        }
                                    }
                                    StyledText {
                                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                                        text: (modelData.summary || modelData.appName || ""); color: root.textColor
                                        font.pixelSize: Theme.fontSizeMedium; font.bold: true
                                    }
                                    StyledText {
                                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                                        text: (modelData.body || ""); visible: text.length > 0; color: root.subText
                                        font.pixelSize: Theme.fontSizeSmall; lineHeight: 1.15
                                    }
                                }
                                Rectangle {  // dismiss ✕ (revealed on hover)
                                    id: bClose
                                    width: 26; height: 26; radius: 13
                                    anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: -2
                                    color: bCloseA.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.55)
                                    opacity: (areaHover.hovered && bWrap.active) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                                    DankIcon { anchors.centerIn: parent; name: "close"; size: 15; color: bCloseA.containsMouse ? Theme.error : root.subText }
                                    MouseArea { id: bCloseA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (modelData) modelData.popup = false }
                                }
                            }

                            Row {  // action chips
                                width: parent.width; spacing: Theme.spacingS
                                visible: bActions.count > 0
                                Repeater {
                                    id: bActions
                                    model: {
                                        var out = []
                                        if (modelData && modelData.actions) {
                                            for (var i = 0; i < modelData.actions.length && out.length < 3; i++) {
                                                var a = modelData.actions[i]
                                                if (a && a.identifier !== "default" && (a.text || "").length > 0) out.push(a)
                                            }
                                        }
                                        return out
                                    }
                                    Rectangle {
                                        height: 32; radius: 16
                                        width: Math.min(bActLbl.implicitWidth + Theme.spacingL * 2, 160)
                                        color: bActA.containsMouse ? Theme.primary : Theme.primarySelected
                                        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                        scale: bActA.pressed ? 0.93 : 1.0
                                        Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                        StyledText { id: bActLbl; anchors.centerIn: parent; width: Math.min(implicitWidth, 160 - Theme.spacingL * 2); text: modelData.text || I18n.tr("Open"); elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; color: bActA.containsMouse ? Theme.primaryText : root.accent; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                                        MouseArea { id: bActA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (modelData && modelData.invoke) modelData.invoke(); if (bWrap.parentPopup) bWrap.parentPopup.popup = false } }
                                    }
                                }
                            }
                        }

                        // auto-dismiss; critical stays; paused while the deck is hovered
                        Timer {
                            interval: 5000; running: !bCard.crit && !areaHover.hovered && modelData !== null
                            onTriggered: if (modelData) modelData.popup = false
                        }
                        // tap = default action; swipe right = dismiss (only the active/top card)
                        MouseArea {
                            id: bArea
                            anchors.fill: parent
                            anchors.rightMargin: 30
                            enabled: bWrap.active
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            property real pressX: 0
                            property bool dragging: false
                            onPressed: mouse => { pressX = mouse.x; dragging = true }
                            onPositionChanged: mouse => { if (dragging) bCard.swipe = Math.max(0, mouse.x - pressX) }
                            onReleased: mouse => {
                                dragging = false
                                if (bCard.swipe > 90) { if (modelData) modelData.popup = false }
                                else if (bCard.swipe < 6) {
                                    if (bannerArea.collapsed) { bannerArea.expanded = true }
                                    else {
                                        var def = null
                                        if (modelData && modelData.actions) for (var i = 0; i < modelData.actions.length; i++) { if (modelData.actions[i] && modelData.actions[i].identifier === "default") { def = modelData.actions[i]; break } }
                                        if (def && def.invoke) { def.invoke(); if (modelData) modelData.popup = false }
                                    }
                                }
                                bCard.swipe = 0
                            }
                            onCanceled: { bArea.dragging = false; bCard.swipe = 0 }
                        }
                    }
                }
            }

            // count chip when collapsed (e.g. "+2") — bottom-right of the deck
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 6
                y: bannerArea.collapsedH - 6
                width: cntLbl.implicitWidth + Theme.spacingM; height: 22; radius: 11
                visible: bannerArea.collapsed && bannerArea.n > 1
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                color: Theme.primary
                z: 200
                StyledText { id: cntLbl; anchors.centerIn: parent; text: "+" + (bannerArea.n - 1); color: Theme.primaryText; font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true }
            }
        }
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
