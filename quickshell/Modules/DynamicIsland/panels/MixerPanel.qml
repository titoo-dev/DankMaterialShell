import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Common
import qs.Services
import qs.Widgets

// Per-application volume mixer (drill-down, island-native): every playback
// stream gets its own slider + mute. Windows 11 has this; macOS doesn't.
Column {
    id: mixCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "mixer" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "mixer" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    // live playback streams (lazy-loaded panel: only exists while the view shows)
    readonly property var streams: Pipewire.nodes.values.filter(n => n && n.audio && n.isSink && n.isStream)
    // bind the streams so their volume/mute properties stay live
    PwObjectTracker { objects: mixCol.streams }

    // header: back · title
    Item {
        width: parent.width; height: 34
        Rectangle {
            id: mxBack
            width: 30; height: 30; radius: 9
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: mxBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: mxBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: mxBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
        }
        StyledText {
            anchors.left: mxBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Volume Mixer"); color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
        }
    }

    // one card per playback stream — adaptive height, capped
    Flickable {
        width: parent.width; height: Math.min(mixList.height, 300); clip: true
        contentHeight: mixList.height; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: mixList
            width: parent.width; spacing: Theme.spacingS
            StyledText {
                width: parent.width; height: 48
                visible: mixCol.streams.length === 0
                text: I18n.tr("Nothing is playing"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: ScriptModel { values: mixCol.streams }
                Rectangle {
                    width: mixList.width; height: 64; radius: 14
                    color: Theme.surfaceLight
                    readonly property bool muted: modelData.audio ? modelData.audio.muted : false

                    DankIcon {
                        id: mxIco
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.top: parent.top; anchors.topMargin: 9
                        name: "graphic_eq"; size: 18
                        color: parent.muted ? island.subText : island.accent
                    }
                    Column {
                        anchors.left: mxIco.right; anchors.leftMargin: Theme.spacingS
                        anchors.right: mxMute.left; anchors.rightMargin: Theme.spacingS
                        anchors.top: parent.top; anchors.topMargin: 5; spacing: 0
                        StyledText {
                            width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: AudioService.displayName(modelData) || I18n.tr("Stream")
                            color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                        }
                        StyledText {
                            width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: (modelData.properties && modelData.properties["media.name"]) ? modelData.properties["media.name"] : ""
                            visible: text.length > 0
                            color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2
                        }
                    }
                    Rectangle {  // per-stream mute
                        id: mxMute
                        width: 28; height: 28; radius: 9
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingS; anchors.top: parent.top; anchors.topMargin: 5
                        color: mxMuteArea.containsMouse ? Theme.primaryHover : "transparent"
                        DankIcon {
                            anchors.centerIn: parent; size: 16
                            name: parent.parent.muted ? "volume_off" : "volume_up"
                            color: parent.parent.muted ? Theme.error : island.textColor
                        }
                        MouseArea {
                            id: mxMuteArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
                        }
                    }
                    DankSlider {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingM; anchors.rightMargin: Theme.spacingM
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                        height: 26
                        value: modelData.audio ? Math.round(modelData.audio.volume * 100) : 0
                        onSliderValueChanged: newValue => { if (modelData.audio) modelData.audio.volume = newValue / 100 }
                    }
                }
            }
        }
    }
}
