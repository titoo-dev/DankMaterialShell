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
                // active view height (drives the pill height in the controller)
                readonly property real viewHeight: !island ? 0 : (island.panelView === "wifi" ? wifiCol.implicitHeight : island.panelView === "bluetooth" ? btCol.implicitHeight : island.panelView === "audio" ? audioCol.implicitHeight : island.panelView === "notifications" ? notifCol.implicitHeight : island.panelView === "calendar" ? calCol.implicitHeight : island.panelView === "apps" ? appCol.implicitHeight : island.panelView === "clipboard" ? clipCol.implicitHeight : ccColumn.implicitHeight)
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
                                { icon: "apps",            which: "apps",          tip: I18n.tr("Apps") },
                                { icon: "notifications",   which: "notifications", tip: I18n.tr("Notifications") },
                                { icon: "calendar_month",  which: "calendar",      tip: I18n.tr("Calendar") },
                                { icon: "content_paste",   which: "clipboard",     tip: I18n.tr("Clipboard") },
                                { icon: "tune",            which: "control",       tip: I18n.tr("All settings") }
                            ]
                            Item {
                                width: parent.width / 5; height: 34
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
                                            // most surfaces are island-native now; only "control" (full settings) opens a DMS popout
                                            if (modelData.which === "notifications") island.panelView = "notifications"
                                            else if (modelData.which === "calendar") island.panelView = "calendar"
                                            else if (modelData.which === "apps") island.panelView = "apps"
                                            else if (modelData.which === "clipboard") island.panelView = "clipboard"
                                            else { island.openMenu(modelData.which); island.pinned = false; island.settle() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- drill-down detail views (extracted into panels/) ----
                WifiPanel          { id: wifiCol;  island: ccPanel.island }
                NotificationsPanel { id: notifCol; island: ccPanel.island }
                BluetoothPanel     { id: btCol;    island: ccPanel.island }
                AudioPanel         { id: audioCol; island: ccPanel.island }
                CalendarPanel      { id: calCol;   island: ccPanel.island }
                SpotlightPanel     { id: appCol;   island: ccPanel.island }
                ClipboardPanel     { id: clipCol;  island: ccPanel.island }
            }
