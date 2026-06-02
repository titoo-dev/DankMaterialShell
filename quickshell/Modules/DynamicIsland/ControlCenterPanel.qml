import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import qs.Widgets

// Expanded mode = inline macOS-style Control Center + drill-down views.
// Reads/writes island state via `island`; exposes `viewHeight` for geometry.
            Item {
                id: ccPanel
                property var island: null
                // active view height (drives the pill height in the controller)
                readonly property real viewHeight: !island ? 0 : (island.panelView === "wifi" ? wifiCol.implicitHeight : island.panelView === "bluetooth" ? btCol.implicitHeight : island.panelView === "audio" ? audioCol.implicitHeight : island.panelView === "notifications" ? notifCol.implicitHeight : ccColumn.implicitHeight)
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
                            width: parent.width - 40
                            leftIcon: island.muted ? "volume_off" : "volume_up"
                            value: island.volPct
                            onSliderValueChanged: newValue => { if (island.audioNode) island.audioNode.volume = newValue / 100 }
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
                            Image { anchors.fill: parent; source: island.player ? (island.player.trackArtUrl ?? "") : ""; fillMode: Image.PreserveAspectCrop; cache: false; visible: status === Image.Ready }
                            DankIcon { anchors.centerIn: parent; name: "music_note"; size: 16; color: island.accent; visible: !(island.player && island.player.trackArtUrl) }
                        }
                        Column {
                            anchors.left: ccArt.right; anchors.leftMargin: Theme.spacingS
                            anchors.right: ccTransport.left; anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter; spacing: 0
                            StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: island.player ? (island.player.trackTitle || "Unknown") : ""; color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                            StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: island.player ? (island.player.trackArtist || "") : ""; color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1 }
                        }
                        Row {
                            id: ccTransport
                            anchors.right: parent.right; anchors.rightMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            Repeater {
                                model: [
                                    { icon: "skip_previous", big: false, en: island.player && island.player.canGoPrevious, act: () => { if (island.player) island.player.previous() } },
                                    { icon: island.playing ? "pause" : "play_arrow", big: true, en: !!island.player, act: () => { if (island.player) island.player.togglePlaying() } },
                                    { icon: "skip_next", big: false, en: island.player && island.player.canGoNext, act: () => { if (island.player) island.player.next() } }
                                ]
                                Rectangle {
                                    width: 32; height: 32; radius: 10
                                    color: ccBtn.containsMouse && modelData.en ? Theme.primaryHover : "transparent"
                                    opacity: modelData.en ? 1 : 0.35
                                    scale: ccBtn.pressed && modelData.en ? 0.86 : 1.0
                                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                    DankIcon { anchors.centerIn: parent; name: modelData.icon; size: modelData.big ? 22 : 18; color: island.accent }
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
                                    DankIcon { anchors.centerIn: parent; name: modelData.icon; size: 19; color: ftArea.containsMouse ? island.accent : island.subText }
                                    ToolTip.visible: ftArea.containsMouse; ToolTip.text: modelData.tip; ToolTip.delay: 400
                                    MouseArea {
                                        id: ftArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            // notifications has an island-native view; others still open DMS popouts
                                            if (modelData.which === "notifications") island.panelView = "notifications"
                                            else { island.openMenu(modelData.which); island.pinned = false; island.settle() }
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
                    opacity: island.panelView === "wifi" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { x: island.panelView === "wifi" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
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
                            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
                            MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
                        }
                        StyledText {
                            anchors.left: backBtn.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
                            text: "Wi-Fi"; color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                        }
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacingXS
                            StyledText {
                                visible: NetworkService.isScanning; text: I18n.tr("Scanning…")
                                color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1; anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {  // radio on/off pill switch
                                width: 44; height: 24; radius: 12
                                anchors.verticalCenter: parent.verticalCenter
                                color: NetworkService.wifiEnabled ? Theme.primary : Theme.surfaceLight
                                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                Rectangle {
                                    width: 18; height: 18; radius: 9; color: NetworkService.wifiEnabled ? Theme.primaryText : island.subText
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
                                color: island.subText; font.pixelSize: Theme.fontSizeSmall
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
                                        size: 20; color: netRow.isConnected ? island.accent : island.textColor
                                    }
                                    Column {
                                        anchors.left: sigIcon.right; anchors.leftMargin: Theme.spacingM
                                        anchors.right: rowRight.left; anchors.rightMargin: Theme.spacingS
                                        anchors.top: parent.top; anchors.topMargin: 6; spacing: 0
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: modelData.ssid || I18n.tr("Unknown"); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: netRow.isConnected }
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: netRow.isConnected ? I18n.tr("Connected") : (modelData.secured ? I18n.tr("Secured") : I18n.tr("Open")); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                                    }
                                    Row {
                                        id: rowRight
                                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.top: parent.top; anchors.topMargin: 13; spacing: Theme.spacingXS
                                        DankIcon { visible: modelData.secured; name: "lock"; size: 14; color: island.subText; anchors.verticalCenter: parent.verticalCenter }
                                        DankIcon { visible: netRow.isConnected; name: "check_circle"; size: 16; color: island.accent; anchors.verticalCenter: parent.verticalCenter }
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
                                            DankIcon { anchors.centerIn: parent; name: "arrow_forward"; size: 16; color: goArea.containsMouse ? Theme.primaryText : island.textColor }
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
                    opacity: island.panelView === "notifications" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { x: island.panelView === "notifications" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
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
                            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
                            MouseArea { id: nBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
                        }
                        StyledText {
                            anchors.left: nBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Notifications"); color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                        }
                        Rectangle {  // clear all
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: clrLabel.implicitWidth + Theme.spacingM; height: 28; radius: 14
                            visible: (NotificationService.notifications || []).length > 0
                            color: clrArea.containsMouse ? Theme.primary : Theme.surfaceLight
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            StyledText { id: clrLabel; anchors.centerIn: parent; text: I18n.tr("Clear all"); font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true; color: clrArea.containsMouse ? Theme.primaryText : island.subText }
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
                                text: I18n.tr("No notifications"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
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
                                        DankIcon { anchors.centerIn: parent; name: "notifications"; size: 18; color: island.accent; visible: nRowImg.status !== Image.Ready }
                                    }
                                    Column {
                                        anchors.left: nRowIco.right; anchors.leftMargin: Theme.spacingM
                                        anchors.right: nRowRight.left; anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                        Row {
                                            width: parent.width; spacing: Theme.spacingXS
                                            StyledText { text: (modelData.appName || ""); color: island.accent; font.pixelSize: Theme.fontSizeSmall - 2; font.bold: true; font.capitalization: Font.AllUppercase; elide: Text.ElideRight; width: Math.min(implicitWidth, parent.width - 60) }
                                            StyledText { text: (modelData.timeStr || ""); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                                        }
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (modelData.summary || modelData.appName || ""); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (modelData.body || ""); visible: text.length > 0; color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1 }
                                    }
                                    Rectangle {  // per-row dismiss
                                        id: nRowRight
                                        width: 26; height: 26; radius: 13
                                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                                        color: nClose.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : "transparent"
                                        opacity: nRowArea.containsMouse ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                                        DankIcon { anchors.centerIn: parent; name: "close"; size: 15; color: nClose.containsMouse ? Theme.error : island.subText }
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
                    opacity: island.panelView === "bluetooth" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { x: island.panelView === "bluetooth" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
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
                            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
                            MouseArea { id: btBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { island.panelView = "controls"; if (BluetoothService.adapter) BluetoothService.adapter.discovering = false } }
                        }
                        StyledText { anchors.left: btBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter; text: "Bluetooth"; color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: 44; height: 24; radius: 12
                            color: BluetoothService.enabled ? Theme.primary : Theme.surfaceLight
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            Rectangle {
                                width: 18; height: 18; radius: 9; color: BluetoothService.enabled ? Theme.primaryText : island.subText
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
                                color: island.subText; font.pixelSize: Theme.fontSizeSmall
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
                                        name: BluetoothService.getDeviceIcon(modelData); size: 20; color: parent.isConn ? island.accent : island.textColor
                                    }
                                    Column {
                                        anchors.left: btIco.right; anchors.leftMargin: Theme.spacingM
                                        anchors.right: btSpin.left; anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 0
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: modelData.name || modelData.deviceName || I18n.tr("Unknown Device"); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: parent.parent.isConn }
                                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (parent.parent.isConn ? I18n.tr("Connected") : I18n.tr("Disconnected")) + ((modelData.batteryAvailable && modelData.battery > 0) ? ("  •  " + Math.round(modelData.battery * 100) + "%") : ""); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                                    }
                                    DankIcon { id: btSpin; anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter; name: parent.isConn ? "check_circle" : "add_circle"; size: 16; color: parent.isConn ? island.accent : island.subText }
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
                    opacity: island.panelView === "audio" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { x: island.panelView === "audio" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
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
                            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
                            MouseArea { id: auBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
                        }
                        StyledText { anchors.left: auBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Output"); color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true }
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
                                text: I18n.tr("No output devices"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
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
                                        name: "speaker"; size: 20; color: parent.isCur ? island.accent : island.textColor
                                    }
                                    StyledText {
                                        anchors.left: auIco.right; anchors.leftMargin: Theme.spacingM
                                        anchors.right: auChk.left; anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                                        text: modelData.description || modelData.name || I18n.tr("Output"); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: parent.isCur
                                    }
                                    DankIcon { id: auChk; anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter; name: "check_circle"; size: 16; color: island.accent; visible: parent.isCur }
                                    MouseArea { id: auRowA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.setSink(modelData) }
                                }
                            }
                        }
                    }
                }
            }
