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

    // ---- satellite bubble (iOS split-island): while the pill rests, the
    // highest-priority ONGOING state detaches as a small circle to its right ----
    readonly property string satKind: {
        if (PrivacyService.screensharingActive) return "screenshare"
        if (PrivacyService.microphoneActive) return "mic"
        if (PrivacyService.cameraActive) return "cam"
        if (tsNeedsAttention) return "tailscale"
        if (batAvailable && !charging && batPct <= 20) return "battery"
        return ""
    }
    readonly property string satIcon: {
        if (satKind === "screenshare") return "screen_share"
        if (satKind === "mic") return "mic"
        if (satKind === "cam") return "videocam"
        if (satKind === "tailscale") return tsConnected ? "device_hub" : "vpn_key_off"
        if (satKind === "battery") return Theme.getBatteryIcon(batPct, charging, batAvailable)
        return ""
    }
    // iOS colour language: orange = capture/warning, green = camera, red = battery
    readonly property color satColor: satKind === "cam" ? Theme.success : (satKind === "battery" ? Theme.error : Theme.warning)

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

    // ---- Tailscale (live activity) ----
    readonly property bool tsFeature: SettingsData.dynamicIslandTailscale
    readonly property bool tsAvailable: tsFeature && TailscaleService.available
    readonly property bool tsConnected: TailscaleService.connected
    readonly property int  tsPeerCount: TailscaleService.onlinePeerCount
    readonly property bool tsUsingExitNode: TailscaleService.usingExitNode
    readonly property string tsExitNodeName: TailscaleService.exitNodeName
    readonly property bool tsNeedsAttention: tsFeature && TailscaleService.needsAttention
    readonly property string tsStatusKind: TailscaleService.statusKind
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
    readonly property string dayShort: Qt.formatDateTime(clock.date, "ddd d")
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
    // keep the Tailscale subscription live while the feature is enabled & the
    // backend supports it, so the at-rest indicator/satellite reflect real state
    Loader {
        active: root.tsAvailable
        sourceComponent: Component { Ref { service: TailscaleService } }
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
    // pointer is over the media scrubber: the global wheel→volume stands down
    property bool seekHover: false

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
    property string panelView: "controls"   // "controls" | "wifi" | "bluetooth" | "audio" | "input" | "notifications" | "calendar" | "monitor" | "wallpaper" | "apps" | "clipboard" | "emoji" | "power" | "mixer" | "privacy" | "shelf" | "tailscale"
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
    // Denominator for the presenter bar fill. Volume must scale against the
    // device max (AudioService.sinkMaxVolume) exactly like the system VolumeOSD
    // slider (maximum: sinkMaxVolume) — otherwise the island bar and the OSD bar
    // would show a different fill for the same level. Brightness/battery are 0..100.
    // (PresenterPane divides by this; without it frac is NaN and no segment lights up.)
    readonly property int presenterMax: presenterKind === "volume" ? AudioService.sinkMaxVolume : 100
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
    // Insertion reality on this setup, by target window:
    //   - native Wayland TERMINALS (ghostty, ...): wtype types the emoji directly
    //     → true auto-insert. (Ctrl+V wouldn't paste in a terminal anyway.)
    //   - native Wayland GUI apps (Chrome, Discord — all Ozone/Electron, so NOT
    //     XWayland): wtype "types" with rc=0 but the app silently drops it, because
    //     wtype emits unicode by hot-swapping the virtual-keyboard keymap and
    //     Chromium/GTK ignore that. So we wl-copy the emoji and fire a synthetic
    //     Ctrl+V (plain keysyms, which they DO accept) → true auto-paste.
    //   - XWayland apps: wtype can't reach them and there's no ydotool/xdotool here,
    //     so we just put the emoji on the clipboard and the user presses Ctrl+V.
    // Close the island first, then re-focus the previously active window (Lua: hl.dsp.focus).
    property string _typePending: ""
    // address of the window to type into, captured CONTINUOUSLY while the
    // island is at rest — i.e. the app the user was working in BEFORE opening
    // the picker. Querying `hyprctl activewindow` at insert time is wrong:
    // since the window split the island no longer covers the screen, so by
    // then focus-follows-mouse has made "active" whatever sits under the
    // cursor (often nothing useful right after clicking the island).
    property string _typeAddr: ""
    onActiveWinChanged: if (mode !== "expanded") _captureTypeTarget()
    function _captureTypeTarget() {
        if (CompositorService.isNiri) { _typeAddr = ""; return }
        const tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (var i = 0; i < tls.length; i++) {
            if (tls[i] && tls[i].wayland === activeWin) {
                _typeAddr = tls[i].address ?? ""
                return
            }
        }
    }
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
            // $1 = text, $2 = target window address captured BEFORE the island
            // opened (may be empty → fall back to whatever is active now)
            Quickshell.execDetached(["sh", "-c",
                "a=\"$2\"; "
                + "if [ -z \"$a\" ]; then a=$(hyprctl activewindow | awk 'NR==1{print $2}'); fi; "
                + "[ -n \"$a\" ] && hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:0x${a#0x}\\\" })\" >/dev/null 2>&1; "
                + "sleep 0.12; "
                + "info=$([ -n \"$a\" ] && hyprctl clients | grep -A 30 \"Window $a \"); "
                + "xwl=0; printf %s \"$info\" | grep -m1 -q 'xwayland: 1' && xwl=1; "
                + "cls=$(printf %s \"$info\" | grep -m1 'class:' | awk '{print $2}'); "
                + "isterm=0; printf %s \"$cls\" | grep -qiE 'ghostty|kitty|foot|alacritty|wezterm|konsole|xterm|urxvt|tilix|terminal' && isterm=1; "
                // XWayland: wtype can't reach it, no ydotool/xdotool here → clipboard only (manual paste).
                + "if [ \"$xwl\" = \"1\" ]; then out=$(printf %s \"$1\" | wl-copy 2>&1); rc=xwl-copy:$?; "
                // native Wayland terminal: direct type works (and Ctrl+V isn't paste in a terminal).
                + "elif [ \"$isterm\" = \"1\" ] && command -v wtype >/dev/null 2>&1; then out=$(wtype \"$1\" 2>&1); rc=type:$?; "
                // native Wayland GUI (Chromium/Electron/GTK drop wtype's unicode keymap swap):
                // copy then fire a synthetic Ctrl+V — standard keysyms they DO accept.
                // Chrome reads the clipboard ASYNC, so the Ctrl+V frame paints before the
                // emoji lands and (thinking it's unfocused) it schedules no redraw → blank
                // until a focus change. A caret nudge (Left+Right, net-zero) AFTER the paste
                // forces a fresh frame so the emoji shows immediately.
                + "else printf %s \"$1\" | wl-copy; sleep 0.1; wtype -M ctrl -k v -m ctrl; rc=paste:$?; sleep 0.1; out=$(wtype -k Left -k Right 2>&1); fi; "
                + "echo \"$(date +%T) addr=$a xwl=$xwl cls=$cls term=$isterm rc=$rc out=$out\" >> /tmp/island-emoji.log",
                "island-emoji", e, root._typeAddr])
        }
    }

    // idle/media linger after pointer-leave; the expanded panel is dismissed by a
    // click outside (scrim), not by this timer (macOS behaviour).
    Timer { id: hideTimer; interval: 1800; onTriggered: root.settle() }

    // ---------- Shelf (drop files/links/text onto the island) ----------
    // a drag hovering the pill auto-opens the shelf view; leaving without
    // dropping restores the previous rest state
    property bool _shelfAutoOpened: false
    // a drag is hovering the pill right now (drives the panel's drop affordance);
    // suppressed while the drag is one of OUR OWN items leaving the shelf
    readonly property bool shelfDropHover: shelfDrop.containsDrag && !shelfDragActive
    // an item is being dragged OUT of the shelf: the scrim must unmap or it
    // swallows the drop targeted at other apps' windows
    property bool shelfDragActive: false
    // shelf feedback for adds that happen while the island is closed (IPC, …)
    Connections {
        target: ShelfService
        function onAdded(n) {
            if (root.mode !== "expanded")
                root.pushActivity("place_item", I18n.tr("Added to Shelf") + (n > 1 ? " • " + n : ""))
        }
    }

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
    // ---- Live Activities: a priority queue of glanceable splashes ----
    // (charging, BT connect, focus, screen recording, …). Priority 2 preempts
    // whatever splash is showing; lower priorities queue behind it and play in
    // order. Nothing shows (or queues) over the expanded panel — the user is
    // busy there — which also fixes the old showSplash stomping the hub.
    property var _activities: []
    function pushActivity(icon, label, opts) {
        if (!ready || !isFocusedScreen || mode === "expanded") return
        const a = {
            icon: icon, label: label,
            priority: (opts && opts.priority !== undefined) ? opts.priority : 1,
            duration: (opts && opts.duration) ? opts.duration : 2600
        }
        if (mode === "presenter" && presenterKind === "splash" && splashTimer.running) {
            if (a.priority >= 2) { _showActivity(a); return }
            const q = _activities
            q.push(a)
            q.sort((x, y) => y.priority - x.priority)
            _activities = q
            return
        }
        _showActivity(a)
    }
    function _showActivity(a) {
        splashIcon = a.icon; splashLabel = a.label
        presenterKind = "splash"
        if (mode !== "presenter") { mode = "presenter"; bump() }
        splashTimer.interval = a.duration
        splashTimer.restart()
    }
    // back-compat shim for the existing call sites
    function showSplash(icon, label) { pushActivity(icon, label) }
    Timer {
        id: splashTimer
        interval: 2600
        onTriggered: {
            if (root._activities.length > 0) {
                const q = root._activities
                const next = q.shift()
                root._activities = q
                root._showActivity(next)
            } else {
                root.settle()
            }
        }
    }

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
        pushActivity(charging ? "battery_charging_full" : "battery_full",
                     (charging ? I18n.tr("Charging") : I18n.tr("On battery")) + " • " + batPct + "%")
    }
    // Live Activity: screen recording / sharing started or ended (high priority —
    // the user should always notice their screen being captured)
    property bool _screenshare: PrivacyService.screensharingActive
    on_ScreenshareChanged: {
        if (!ready) return
        pushActivity(_screenshare ? "screen_share" : "stop_screen_share",
                     _screenshare ? I18n.tr("Screen sharing started") : I18n.tr("Screen sharing ended"),
                     { priority: 2 })
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
        // inject text through the emoji-picker insertion path (debug/scripting)
        function onTypeRequested(text) {
            if (!root.isFocusedScreen)
                return
            root.insertText(text)
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
    // single source of truth for "the pill window holds the keyboard"
    readonly property bool kbGrabActive: mode === "expanded"
        && (_kbViews.indexOf(panelView) !== -1 || (panelView === "wifi" && wifiNeedsKeyboard))
    // On Hyprland, keyboard focus comes from the hyprland-focus-grab protocol
    // (same pattern as DankModal): OnDemand + HyprlandFocusGrab engages
    // immediately on open and releases cleanly on close while the pill window
    // STAYS MAPPED. An Exclusive grab is unusable here: Hyprland only honours
    // its release on UNMAP, and blinking the pill window (unmap → remap a few
    // frames later) races Quickshell's surface state — the remap is silently
    // lost and the island never comes back (the old wallpaper/emoji toggle-off
    // bug). Exclusive remains as the non-Hyprland fallback, where flipping
    // back to None on a mapped surface is honoured.
    HyprlandFocusGrab {
        windows: [pillWindow]
        active: CompositorService.useHyprlandFocusGrab && root.kbGrabActive
    }

    // ---------- windows ----------

    // click-outside-to-dismiss scrim (macOS): a SEPARATE fullscreen surface
    // mapped only while the panel is expanded. Layer-shell puts a freshly
    // mapped surface on top of its layer, so the pill and the banner stack are
    // SUBTRACTED from its input region — clicks on them fall through to their
    // own windows, clicks anywhere else dismiss.
    PanelWindow {
        id: scrimWindow
        screen: root.modelData
        // unmapped while a shelf item is dragged out — the drop must reach the
        // window UNDER the scrim, not the scrim itself
        visible: root.mode === "expanded" && !root.shelfDragActive
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
        // grab the keyboard only while an inline reply field is open. Same
        // strategy as the pill window: on Hyprland an Exclusive grab on a
        // still-mapped surface never releases, so use the focus-grab protocol.
        WlrLayershell.keyboardFocus: notifBanners.needsKeyboard
            ? (CompositorService.useHyprlandFocusGrab ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
            : WlrKeyboardFocus.None
        color: "transparent"
        anchors { top: true; right: true }
        implicitWidth: 440
        implicitHeight: 720
        mask: Region { item: notifBanners }
        NotificationBanners { id: notifBanners; island: root }
    }
    HyprlandFocusGrab {
        windows: [bannerWindow]
        active: CompositorService.useHyprlandFocusGrab && bannerWindow.visible && notifBanners.needsKeyboard
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
        // arrow navigation, Wi-Fi while a password prompt is open. On Hyprland
        // the HyprlandFocusGrab above provides the immediate engage/release;
        // OnDemand just lets the surface accept the focus it hands us. Elsewhere
        // fall back to an Exclusive (modal) grab, released when panelView leaves.
        WlrLayershell.keyboardFocus: root.kbGrabActive
            ? (CompositorService.useHyprlandFocusGrab ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
            : WlrKeyboardFocus.None
        mask: Region {
            // drop the pill from the input region while it's hidden for
            // fullscreen, so top-center clicks reach the app underneath
            Region { item: root.pillSuppressed ? null : pill }
            Region { item: satellite.active ? satellite : null }
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

        // liquid bridge for the satellite detach/merge (metaball feel): a neck
        // of island colour connecting pill edge and bubble, thick at birth,
        // stretching thin and snapping just before full separation
        Canvas {
            id: goo
            readonly property real t: Math.max(0, Math.min(1, satellite.out))
            visible: satellite.visible && t > 0.02 && t < 0.96
            opacity: (1 - Math.pow(t, 3)) * pill.opacity
            x: pill.x + pill.width - 3
            y: pill.y
            width: Math.max(1, satellite.x + satellite.width * (1 - satellite.scale) / 2 - x + 3)
            height: pill.height
            antialiasing: true
            onTChanged: requestPaint()
            onWidthChanged: requestPaint()
            onVisibleChanged: if (visible) requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const W = width, H = height, cy = H / 2
                const rL = (H / 2) * (1 - 0.55 * t)            // attach radius, pill side
                const rR = (H / 2) * (0.90 - 0.50 * t)         // attach radius, bubble side
                const neck = (H / 2) * Math.pow(1 - t, 1.5) * 0.85   // mid half-thickness
                ctx.beginPath()
                ctx.moveTo(0, cy - rL)
                ctx.quadraticCurveTo(W * 0.5, cy - neck, W, cy - rR)
                ctx.lineTo(W, cy + rR)
                ctx.quadraticCurveTo(W * 0.5, cy + neck, 0, cy + rL)
                ctx.closePath()
                ctx.fillStyle = Qt.rgba(root.islandColor.r, root.islandColor.g, root.islandColor.b, root.islandColor.a)
                ctx.fill()
            }
        }

        // iOS "split island": an ongoing secondary activity (privacy capture,
        // battery low) detaches as a satellite bubble while the pill rests —
        // springs out of the pill's right edge, gets reabsorbed on expansion.
        Item {
            id: satellite
            readonly property bool active: !root.pillSuppressed && root.satIcon !== ""
                && (root.mode === "compact" || root.mode === "chip")
            // 0 = merged into the pill, 1 = detached; spring gives the pop-out
            property real out: active ? 1 : 0
            Behavior on out { SpringAnimation { spring: 4.2; damping: 0.3; epsilon: 0.004 } }
            // keep the last glyph through the retract animation (satIcon clears
            // the same frame the state ends, which would blank the merging bubble)
            property string shownIcon: ""
            Connections {
                target: root
                function onSatIconChanged() { if (root.satIcon !== "") satellite.shownIcon = root.satIcon }
            }
            Component.onCompleted: shownIcon = root.satIcon
            width: pill.height; height: pill.height
            x: pill.x + pill.width - width + (width + 7) * out
            y: pill.y
            scale: 0.5 + 0.5 * Math.max(0, out)
            opacity: Math.max(0, Math.min(1, out)) * pill.opacity
            visible: out > 0.02 && pill.visible
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true; shadowColor: "#000000"
                shadowBlur: 0.8; shadowVerticalOffset: 3; shadowOpacity: 0.4
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.islandColor
                border.width: 1
                border.color: Qt.rgba(root.satColor.r, root.satColor.g, root.satColor.b, 0.45)
            }
            DankIcon {
                anchors.centerIn: parent
                name: satellite.shownIcon
                size: 15
                color: root.satColor
                filled: true
                // soft breathing pulse — ongoing capture should feel alive
                SequentialAnimation on scale {
                    running: satellite.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.18; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // per-activity expanded layout: privacy bubbles drill straight
                // into the live-captures view, battery falls back to the hub
                onClicked: {
                    if (root.satKind === "mic" || root.satKind === "cam" || root.satKind === "screenshare")
                        root.openPanel("privacy")
                    else if (root.satKind === "tailscale")
                        root.openPanel("tailscale")
                    else
                        root.mode = "expanded"
                    root.bump()
                }
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

            // ---- scroll over the island -> volume (except over the scrubber,
            // where the wheel seeks instead — see MediaPane.seekArea) ----
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (root.seekHover) return
                    if (!root.audioNode) return
                    const step = (event.angleDelta.y > 0 ? 0.05 : -0.05)
                    root.audioNode.volume = Math.max(0, Math.min(1, root.audioNode.volume + step))
                    AudioService.playVolumeChangeSoundIfEnabled()   // macOS-style volume tick
                }
            }

            // ---- press-and-hold (the signature iOS island gesture; matters on
            // touch, where there is no hover to auto-expand the rest states) ----
            TapHandler {
                onLongPressed: {
                    if (root.mode === "chip") { root.mode = "media"; root.bump() }
                    else if (root.mode === "compact" || root.mode === "idle") { root.mode = "expanded"; root.bump() }
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

            // ---- Shelf drop target (external Wayland DnD) ----
            // One DropArea for the whole pill: hovering it with a drag unfolds
            // the island straight into the shelf view (which grows this very
            // area), dropping anywhere on the pill files the payload.
            DropArea {
                id: shelfDrop
                anchors.fill: parent
                onEntered: drag => {
                    if (!drag.hasUrls && !drag.hasText) { drag.accepted = false; return }
                    if (root.mode !== "expanded") {
                        root._shelfAutoOpened = true
                        root.bump()
                    }
                    root.openPanel("shelf")
                }
                onExited: {
                    // drag pulled away without dropping: fold back to rest
                    if (root._shelfAutoOpened) {
                        root._shelfAutoOpened = false
                        root.closeIsland()
                    }
                }
                onDropped: drop => {
                    root._shelfAutoOpened = false
                    if (drop.hasUrls)
                        ShelfService.addUrls(drop.urls)
                    else if (drop.hasText)
                        ShelfService.addText(drop.text)
                    drop.accept(Qt.CopyAction)
                    root.bump()
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
