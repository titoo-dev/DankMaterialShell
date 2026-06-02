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
    readonly property color islandColor: SettingsData.dynamicIslandBlur ? Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.8) : Theme.surfaceContainer
    readonly property color accent:      Theme.primary
    readonly property color textColor:   Theme.surfaceText
    readonly property color subText:     Theme.surfaceVariantText

    // ---------- live data ----------
    readonly property var player: MprisController.activePlayer
    readonly property bool playing: player ? player.isPlaying : false

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
    onLatestPopupChanged: {
        if (latestPopup && ready && isFocusedScreen)
            showNotif()
        else if (!latestPopup && mode === "notif")
            settle()   // popup expired — don't sit on a blank notif
    }

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

    property string presenterKind: "volume"   // "volume" | "brightness" | "battery"
    // live & reactive: the OSD value/icon track the real system state directly, so
    // they stay in sync with the user's action even while it's already showing
    // (no stale imperative snapshot — derived props lag a tick at change-time)
    readonly property int presenterValue: {
        if (presenterKind === "battery") return batPct
        if (presenterKind === "brightness") return DisplayService.brightnessLevel
        return muted ? 0 : volPct   // volume
    }
    readonly property string presenterIcon: {
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
    Timer { id: hideTimer; interval: 1800; onTriggered: root.settle() }

    function showPresenter(kind) {
        if (!ready || !isFocusedScreen) return
        if (mode === "notif") return   // don't stomp an active notification
        presenterKind = kind   // value/icon follow reactively from here
        mode = "presenter"
        bump()
        presenterTimer.restart()
    }
    Timer { id: presenterTimer; interval: 1500; onTriggered: root.settle() }

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
        switch (which) {
        case "apps":          PopoutService.toggleDankLauncherV2(); break
        case "dash":          PopoutService.toggleDankDash(0, sx, sy, w, "center", modelData); break
        case "notifications":
            // the bar (suppressed in island mode) normally activates this LazyLoader;
            // do it ourselves so notificationCenterPopout exists before toggling
            if (PopoutService.notificationCenterLoader)
                PopoutService.notificationCenterLoader.active = true
            PopoutService.toggleNotificationCenter(sx, sy, w, "center", modelData)
            break
        case "control":
            if (PopoutService.controlCenterLoader)
                PopoutService.controlCenterLoader.active = true
            PopoutService.toggleControlCenter(sx, sy, w, "center", modelData)
            break
        case "clipboard":     PopoutService.openClipboardHistory(); break
        }
    }

    // ---------- target geometry per mode ----------
    readonly property real screenW: modelData?.width ?? 1920
    readonly property real pillW: {
        switch (mode) {
        case "chip":      return 168
        case "media": {
            // grow so the title fits, clamped to the screen
            const titleW = Math.min(Math.max(mTitle.implicitWidth, mArtist.implicitWidth, mEyebrow.implicitWidth), 360)
            const content = 44 + Theme.spacingM + titleW + Theme.spacingS + controls.implicitWidth + 20
            return Math.max(410, Math.min(content, screenW - 40))
        }
        case "expanded":  return 488
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
        case "expanded":  return 80
        case "idle":      return 50
        case "notif":     return 80
        case "presenter": return 48
        case "chip":      return 34
        default:          return 28   // compact
        }
    }
    readonly property real pillRadius: (mode === "compact" || mode === "chip") ? 12 : 22

    // ---------- window ----------
    WlrLayershell.namespace: "dms:dynamic-island"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    implicitWidth: 620
    implicitHeight: 300
    anchors { top: true; left: true }
    WlrLayershell.margins {
        left: Math.max(0, ((modelData?.width ?? 1920) - root.implicitWidth) / 2)
        top: 4
    }

    mask: Region { item: pill }

    Item {
        id: stage
        anchors.fill: parent
        readonly property real cx: width / 2

        Rectangle {
            id: pill
            x: stage.cx - width / 2
            y: 0
            width: root.pillW
            height: root.pillH
            radius: root.pillRadius
            color: root.islandColor
            readonly property bool alertBorder: root.privacyActive || (root.mode === "notif" && root.notifCritical)
            border.width: alertBorder ? 1.5 : 1
            border.color: alertBorder ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.7) : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)
            Behavior on border.color { ColorAnimation { duration: Theme.mediumDuration } }
            antialiasing: true
            clip: true

            Behavior on width   { SpringAnimation { spring: 5.0; damping: 0.36; mass: 1.0; epsilon: 0.2 } }
            Behavior on height  { SpringAnimation { spring: 5.0; damping: 0.36; mass: 1.0; epsilon: 0.2 } }
            Behavior on radius  { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }

            property real bumpScale: 1.0
            scale: (bgClick.pressed ? 0.985 : 1.0) * bumpScale
            Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }

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

            // reusable morph: scale+fade content per mode
            // (each block sets `visible/opacity/scale` from root.mode)

            // ===== COMPACT (rest): clock only =====
            Row {
                id: compactRow
                anchors.centerIn: parent
                spacing: Theme.spacingS
                opacity: root.mode === "compact" ? 1 : 0
                visible: opacity > 0
                scale: root.mode === "compact" ? 1 : 0.9
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

                // at-rest status: privacy (mic/cam/screen-share) + battery-low
                Row {
                    spacing: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.privacyActive || (root.batAvailable && root.batPct <= 20 && !root.charging)
                    DankIcon { visible: PrivacyService.microphoneActive; name: "mic"; size: 14; color: Theme.error; filled: true; anchors.verticalCenter: parent.verticalCenter }
                    DankIcon { visible: PrivacyService.cameraActive; name: "videocam"; size: 14; color: Theme.error; filled: true; anchors.verticalCenter: parent.verticalCenter }
                    DankIcon { visible: PrivacyService.screensharingActive; name: "screen_share"; size: 14; color: Theme.warning; filled: true; anchors.verticalCenter: parent.verticalCenter }
                    DankIcon { visible: root.batAvailable && root.batPct <= 20 && !root.charging; name: "battery_alert"; size: 14; color: Theme.error; anchors.verticalCenter: parent.verticalCenter }
                }
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
                Rectangle {
                    width: 20; height: 20; radius: 6; clip: true; color: Theme.primaryBackground
                    anchors.verticalCenter: parent.verticalCenter
                    Image { anchors.fill: parent; source: root.player ? (root.player.trackArtUrl ?? "") : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                    DankIcon { anchors.centerIn: parent; name: "music_note"; size: 12; color: root.accent; visible: !(root.player && root.player.trackArtUrl) }
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
                                Image {
                                    anchors.centerIn: parent; width: 17; height: 17
                                    source: modelData.icon ?? ""
                                    sourceSize.width: 17; sourceSize.height: 17
                                }
                                MouseArea {
                                    id: trayArea
                                    anchors.fill: parent
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
                }
            }

            // ===== EXPANDED: launchers for the real DMS menus =====
            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingL
                opacity: root.mode === "expanded" ? 1 : 0
                visible: opacity > 0
                scale: root.mode === "expanded" ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

                Repeater {
                    model: [
                        { icon: "apps",          which: "apps" },
                        { icon: "dashboard",     which: "dash" },
                        { icon: "notifications", which: "notifications" },
                        { icon: "settings",      which: "control" },
                        { icon: "content_paste", which: "clipboard" }
                    ]
                    Rectangle {
                        width: 52; height: 52; radius: 16
                        color: btnArea.containsMouse ? Theme.primaryHover : Theme.surfaceLight
                        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                        scale: btnArea.pressed ? 0.88 : 1.0
                        Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                        DankIcon {
                            anchors.centerIn: parent; name: modelData.icon
                            size: 25; color: btnArea.containsMouse ? root.accent : root.textColor
                        }
                        MouseArea {
                            id: btnArea; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.openMenu(modelData.which); root.pinned = false; root.settle() }
                        }
                    }
                }
            }

            // ===== NOTIF: live notification content (+stacking badge) =====
            Item {
                anchors.fill: parent; anchors.margins: 9
                opacity: root.mode === "notif" ? 1 : 0
                visible: opacity > 0
                scale: root.mode === "notif" ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

                Rectangle {
                    id: nicon
                    width: 48; height: 48; radius: 14; clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.primaryBackground
                    Image {
                        anchors.fill: parent; anchors.margins: 6
                        source: root.latestPopup ? (root.latestPopup.cleanImage || root.latestPopup.appIcon || "") : ""
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }
                    DankIcon {
                        anchors.centerIn: parent; name: "notifications"
                        size: 22; color: root.accent
                        visible: !(root.latestPopup && (root.latestPopup.cleanImage || root.latestPopup.appIcon))
                    }
                }
                Column {
                    anchors.left: nicon.right; anchors.leftMargin: Theme.spacingM
                    anchors.right: notifRight.left; anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    StyledText {  // app-name eyebrow
                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                        text: root.latestPopup ? (root.latestPopup.appName || "") : ""
                        visible: text.length > 0
                        color: root.accent; font.pixelSize: Theme.fontSizeSmall - 1
                        font.bold: true; font.capitalization: Font.AllUppercase
                    }
                    StyledText {  // summary / title
                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                        text: root.latestPopup ? (root.latestPopup.summary || root.latestPopup.appName || "") : ""
                        visible: text.length > 0
                        color: root.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                    }
                    StyledText {  // body
                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                        text: root.latestPopup ? (root.latestPopup.body || "") : ""
                        visible: text.length > 0
                        color: root.subText; font.pixelSize: Theme.fontSizeSmall
                    }
                }
                // body click: trigger the notification's default action if it has
                // one, else open the notification center (below the buttons)
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const def = root.defaultAction()
                        if (def && def.invoke) {
                            def.invoke()
                            if (root.latestPopup) root.latestPopup.popup = false
                            root.settle()
                        } else {
                            root.openMenu("notifications"); root.settle()
                        }
                    }
                }
                Row {
                    id: notifRight
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS
                    Repeater {  // notification action buttons (e.g. Reply / Mark as read)
                        model: root.notifActions
                        Rectangle {
                            height: 30; radius: 15
                            width: Math.min(actionLabel.implicitWidth + Theme.spacingM * 2, 140)
                            anchors.verticalCenter: parent.verticalCenter
                            color: actArea.containsMouse ? Theme.primary : Theme.primarySelected
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            StyledText {
                                id: actionLabel
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, 140 - Theme.spacingM * 2)
                                text: modelData.text || I18n.tr("Open")
                                elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                                color: actArea.containsMouse ? Theme.primaryText : root.accent
                                font.pixelSize: Theme.fontSizeSmall; font.bold: true
                            }
                            MouseArea {
                                id: actArea; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData && modelData.invoke) modelData.invoke()
                                    if (root.latestPopup) root.latestPopup.popup = false
                                    root.settle()
                                }
                            }
                        }
                    }
                    Rectangle {
                        id: badge
                        width: 26; height: 26; radius: 13
                        color: badgeArea.containsMouse ? Theme.primary : Theme.primarySelected
                        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                        visible: root.popups.length > 1
                        anchors.verticalCenter: parent.verticalCenter
                        StyledText {
                            anchors.centerIn: parent; text: "+" + (root.popups.length - 1)
                            color: badgeArea.containsMouse ? Theme.primaryText : root.accent
                            font.pixelSize: Theme.fontSizeSmall; font.bold: true
                        }
                        ToolTip.visible: badgeArea.containsMouse
                        ToolTip.text: I18n.tr("Clear all")
                        ToolTip.delay: 400
                        MouseArea {
                            id: badgeArea; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { NotificationService.dismissAllPopups(); root.settle() }
                        }
                    }
                    Rectangle {  // ✕ quick-dismiss
                        width: 28; height: 28; radius: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: closeArea.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                        DankIcon { anchors.centerIn: parent; name: "close"; size: 18; color: closeArea.containsMouse ? Theme.error : root.subText }
                        ToolTip.visible: closeArea.containsMouse
                        ToolTip.text: I18n.tr("Dismiss")
                        ToolTip.delay: 400
                        MouseArea {
                            id: closeArea; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (root.latestPopup) root.latestPopup.popup = false; root.settle() }
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
                        root.pinned = true
                        root.mode = "expanded"
                    }
                }
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
