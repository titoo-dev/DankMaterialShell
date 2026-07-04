import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Audio output detail view (drill-down, island-styled). Reads/writes island state via `island`.
Column {
    id: audioCol
    property var island: null
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
            width: 30; height: 30; radius: width / 2
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
                    width: auList.width; height: 46; radius: height / 2
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
