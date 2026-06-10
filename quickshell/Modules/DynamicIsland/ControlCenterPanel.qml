import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import "panels"

// Expanded mode = inline macOS-style Control Center + drill-down views.
// Reads/writes island state via `island`; exposes `viewHeight` for geometry.
            Item {
                id: ccPanel
                property var island: null
                // active view height (drives the pill height in the controller):
                // the hub when showing "controls", else whatever the loader holds
                readonly property real viewHeight: !island ? 0
                    : island.panelView === "controls" ? ccColumn.implicitHeight
                    : (drillLoader.item ? drillLoader.item.implicitHeight : ccColumn.implicitHeight)
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                opacity: island.mode === "expanded" ? 1 : 0
                visible: opacity > 0
                scale: island.mode === "expanded" ? 1 : 0.94
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
                    opacity: island.panelView === "controls" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { x: island.panelView === "controls" ? 0 : -24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                    // ---- header: identity + session orbs (lock / settings / power) ----
                    Item {
                        width: parent.width; height: 40
                        Row {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS
                            DankCircularImage {
                                width: 36; height: 36
                                anchors.verticalCenter: parent.verticalCenter
                                imageSource: {
                                    if (!PortalService.profileImage || PortalService.profileImage === "") return ""
                                    return PortalService.profileImage.startsWith("/") ? "file://" + PortalService.profileImage : PortalService.profileImage
                                }
                                fallbackIcon: "person"
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; spacing: 0
                                StyledText {
                                    text: UserInfoService.fullName || UserInfoService.username || I18n.tr("User")
                                    color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                                    elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                                }
                                StyledText {
                                    text: I18n.tr("Control Center")
                                    color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1
                                }
                            }
                        }
                        // three frosted "orb" buttons — lift + glow on hover, power tinted danger
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS
                            Repeater {
                                model: [
                                    { key: "lock",     icon: "lock",                tip: I18n.tr("Lock"),     danger: false },
                                    { key: "settings", icon: "settings",            tip: I18n.tr("Settings"), danger: false },
                                    { key: "power",    icon: "power_settings_new",  tip: I18n.tr("Power"),    danger: true  }
                                ]
                                Rectangle {
                                    readonly property bool danger: modelData.danger
                                    width: 36; height: 36; radius: 18
                                    color: orbArea.containsMouse
                                        ? (danger ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.20)
                                                  : Qt.rgba(island.accent.r, island.accent.g, island.accent.b, 0.18))
                                        : Theme.surfaceLight
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    border.width: orbArea.containsMouse ? 1 : 0
                                    border.color: danger ? Theme.error : island.accent
                                    scale: orbArea.pressed ? 0.88 : 1.0
                                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                    DankIcon {
                                        anchors.centerIn: parent; name: modelData.icon; size: 18
                                        color: orbArea.containsMouse ? (danger ? Theme.error : island.accent) : island.textColor
                                        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    }
                                    ToolTip.visible: orbArea.containsMouse; ToolTip.text: modelData.tip; ToolTip.delay: 400
                                    MouseArea {
                                        id: orbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.key === "lock") { island.closeIsland(); IdleService.lockRequested() }
                                            else if (modelData.key === "settings") { island.closeIsland(); PopoutService.openSettings() }
                                            else island.panelView = "power"
                                        }
                                    }
                                }
                            }
                        }
                    }

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
                                    DankIcon { anchors.horizontalCenter: parent.horizontalCenter; name: parent.parent.ic; size: 20; color: parent.parent.on ? Theme.primaryText : island.textColor }
                                    StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.lbl; font.pixelSize: Theme.fontSizeSmall - 2; color: parent.parent.on ? Theme.primaryText : island.subText }
                                }
                                // small chevron hinting the tile drills into a detail view
                                DankIcon {
                                    visible: parent.key === "wifi" || parent.key === "bt"
                                    anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 5
                                    name: "chevron_right"; size: 13; color: parent.on ? Theme.primaryText : island.subText
                                }
                                MouseArea {
                                    id: tileArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (key === "wifi") { island.panelView = "wifi"; NetworkService.scanWifiNetworks() }
                                        else if (key === "bt") { island.panelView = "bluetooth"; if (BluetoothService.adapter && BluetoothService.enabled) BluetoothService.adapter.discovering = true }
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
                            width: parent.width - 120
                            leftIcon: island.muted ? "volume_off" : "volume_up"
                            value: island.volPct
                            onSliderValueChanged: newValue => { if (island.audioNode) island.audioNode.volume = newValue / 100 }
                        }
                        Rectangle {  // per-app volume mixer (drills into the mixer view)
                            width: 32; height: 32; radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: mixArea.containsMouse ? Theme.primaryHover : Theme.surfaceLight
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            scale: mixArea.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                            DankIcon { anchors.centerIn: parent; name: "tune"; size: 17; color: mixArea.containsMouse ? island.accent : island.textColor }
                            MouseArea { id: mixArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "mixer" }
                        }
                        Rectangle {  // output device picker (drills into the audio view)
                            width: 32; height: 32; radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: outArea.containsMouse ? Theme.primaryHover : Theme.surfaceLight
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            scale: outArea.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                            DankIcon { anchors.centerIn: parent; name: "speaker"; size: 17; color: outArea.containsMouse ? island.accent : island.textColor }
                            MouseArea { id: outArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "audio" }
                        }
                        Rectangle {  // input device picker (drills into the input view)
                            width: 32; height: 32; radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: inArea.containsMouse ? Theme.primaryHover : Theme.surfaceLight
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            scale: inArea.pressed ? 0.9 : 1.0
                            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                            DankIcon { anchors.centerIn: parent; name: "mic"; size: 17; color: inArea.containsMouse ? island.accent : island.textColor }
                            MouseArea { id: inArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "input" }
                        }
                    }

                    // ---- now playing (when a player is active) ----
                    Rectangle {
                        width: parent.width; height: 48; radius: 14
                        color: Theme.surfaceLight
                        visible: island.player
                        Rectangle {
                            id: ccArt
                            width: 34; height: 34; radius: 9; clip: true
                            anchors.left: parent.left; anchors.leftMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                            color: Theme.primaryBackground
                            Image { id: ccArtImg; anchors.fill: parent; source: island.player ? (island.player.trackArtUrl ?? "") : ""; fillMode: Image.PreserveAspectCrop; cache: false; asynchronous: true; visible: status === Image.Ready }
                            // fall back on the real load status — art URLs are often transient tmp files that vanish
                            DankIcon { anchors.centerIn: parent; name: "music_note"; size: 16; color: island.accent; visible: ccArtImg.status !== Image.Ready }
                        }
                        Column {
                            anchors.left: ccArt.right; anchors.leftMargin: Theme.spacingS
                            anchors.right: ccTransport.left; anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter; spacing: 0
                            StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: island.player ? (island.player.trackTitle || I18n.tr("Unknown")) : ""; color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                            StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: island.player ? (island.player.trackArtist || "") : ""; color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1 }
                        }
                        Row {
                            id: ccTransport
                            anchors.right: parent.right; anchors.rightMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            Repeater {
                                // STATIC model — see MediaPane: keeps the buttons alive across play/pause
                                model: ["prev", "play", "next"]
                                Rectangle {
                                    readonly property bool big: modelData === "play"
                                    readonly property bool en: modelData === "play" ? !!island.player
                                                             : modelData === "prev" ? !!(island.player && island.player.canGoPrevious)
                                                             : !!(island.player && island.player.canGoNext)
                                    readonly property string glyph: modelData === "play" ? (island.playing ? "pause" : "play_arrow")
                                                                  : modelData === "prev" ? "skip_previous" : "skip_next"
                                    function act() {
                                        if (!island.player) return
                                        if (modelData === "play") island.player.togglePlaying()
                                        else if (modelData === "prev") island.player.previous()
                                        else island.player.next()
                                    }
                                    width: 32; height: 32; radius: 10
                                    color: ccBtn.containsMouse && en ? Theme.primaryHover : "transparent"
                                    opacity: en ? 1 : 0.35
                                    scale: ccBtn.pressed && en ? 0.86 : 1.0
                                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                    DankIcon { anchors.centerIn: parent; name: parent.glyph; size: parent.big ? 22 : 18; color: island.accent }
                                    MouseArea { id: ccBtn; anchors.fill: parent; hoverEnabled: true; enabled: parent.en; cursorShape: Qt.PointingHandCursor; onClicked: parent.act() }
                                }
                            }
                        }
                    }

                    // ---- footer: island-native drill views ----
                    Row {
                        width: parent.width
                        Repeater {
                            model: [
                                { icon: "apps",            which: "apps",          tip: I18n.tr("Apps") },
                                { icon: "notifications",   which: "notifications", tip: I18n.tr("Notifications") },
                                { icon: "calendar_month",  which: "calendar",      tip: I18n.tr("Calendar") },
                                { icon: "monitoring",      which: "monitor",       tip: I18n.tr("System") },
                                { icon: "wallpaper",       which: "wallpaper",     tip: I18n.tr("Wallpaper") },
                                { icon: "mood",            which: "emoji",         tip: I18n.tr("Emoji") },
                                { icon: "content_paste",   which: "clipboard",     tip: I18n.tr("Clipboard") },
                                { icon: "place_item",      which: "shelf",         tip: I18n.tr("Shelf") }
                            ]
                            Item {
                                width: parent.width / 8; height: 34
                                Rectangle {
                                    anchors.centerIn: parent; width: 34; height: 30; radius: 9
                                    color: ftArea.containsMouse ? Theme.primaryHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    scale: ftArea.pressed ? 0.9 : 1.0
                                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                    DankIcon { anchors.centerIn: parent; name: modelData.icon; size: 19; color: ftArea.containsMouse ? island.accent : island.subText }
                                    ToolTip.visible: ftArea.containsMouse; ToolTip.text: modelData.tip; ToolTip.delay: 400
                                    MouseArea {
                                        id: ftArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        // every footer surface is an island-native drill view now
                                        onClicked: island.panelView = modelData.which
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- drill-down detail views, LAZY (panels/) ----
                // Only the ACTIVE view exists; previously all 12 panels were
                // instantiated eagerly per monitor, their Repeaters/bindings live
                // even while the island rested. The registry is the single source
                // of truth mapping panelView -> component.
                readonly property var viewRegistry: ({
                    "wifi": wifiComp, "bluetooth": btComp, "audio": audioComp,
                    "input": inputComp, "notifications": notifComp, "calendar": calComp,
                    "apps": appsComp, "clipboard": clipComp, "emoji": emojiComp,
                    "power": powerComp, "monitor": monComp, "wallpaper": wpComp,
                    "mixer": mixerComp, "privacy": privacyComp, "shelf": shelfComp
                })
                Component { id: wifiComp;  WifiPanel          { island: ccPanel.island } }
                Component { id: btComp;    BluetoothPanel     { island: ccPanel.island } }
                Component { id: audioComp; AudioPanel         { island: ccPanel.island } }
                Component { id: inputComp; InputPanel         { island: ccPanel.island } }
                Component { id: notifComp; NotificationsPanel { island: ccPanel.island } }
                Component { id: calComp;   CalendarPanel      { island: ccPanel.island } }
                Component { id: appsComp;  SpotlightPanel     { island: ccPanel.island } }
                Component { id: clipComp;  ClipboardPanel     { island: ccPanel.island } }
                Component { id: emojiComp; EmojiPanel         { island: ccPanel.island } }
                Component { id: powerComp; PowerPanel         { island: ccPanel.island } }
                Component { id: monComp;   SystemMonitorPanel { island: ccPanel.island } }
                Component { id: wpComp;    WallpaperPanel     { island: ccPanel.island } }
                Component { id: mixerComp; MixerPanel         { island: ccPanel.island } }
                Component { id: privacyComp; PrivacyPanel     { island: ccPanel.island } }
                Component { id: shelfComp; ShelfPanel         { island: ccPanel.island } }

                Loader {
                    id: drillLoader
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    sourceComponent: (ccPanel.island && ccPanel.viewRegistry[ccPanel.island.panelView]) || null
                    transform: Translate { id: drillSlide; x: 0 }
                    onLoaded: drillEnter.restart()
                }
                // generic drill-in transition (the outgoing view is torn down, the
                // hub's own fade keeps the visual continuity)
                ParallelAnimation {
                    id: drillEnter
                    NumberAnimation { target: drillLoader; property: "opacity"; from: 0; to: 1; duration: Theme.shortDuration }
                    NumberAnimation { target: drillSlide; property: "x"; from: 24; to: 0; duration: Theme.shortDuration; easing.type: Easing.OutQuad }
                }
            }
