import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Audio input (microphone) detail view (drill-down, island-styled). Reads/writes island state via `island`.
Column {
    id: inputCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "input" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "input" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    Item {
        width: parent.width; height: 34
        Rectangle {
            id: inBack
            width: 30; height: 30; radius: 9
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: inBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: inBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: inBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
        }
        StyledText { anchors.left: inBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Input"); color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true }
    }

    Flickable {
        width: parent.width; height: Math.min(inList.height, 240); clip: true
        contentHeight: inList.height; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: inList
            width: parent.width; spacing: 4
            StyledText {
                width: parent.width; height: 40
                visible: (AudioService.typedSources || []).length === 0
                text: I18n.tr("No input devices"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: AudioService.typedSources
                Rectangle {
                    readonly property bool isCur: AudioService.source && modelData && AudioService.source.name === modelData.name
                    width: inList.width; height: 46; radius: 12
                    color: (inRowA.containsMouse || isCur) ? Theme.surfaceLight : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    DankIcon {
                        id: inIco
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        name: "mic"; size: 20; color: parent.isCur ? island.accent : island.textColor
                    }
                    StyledText {
                        anchors.left: inIco.right; anchors.leftMargin: Theme.spacingM
                        anchors.right: inChk.left; anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                        text: modelData.description || modelData.name || I18n.tr("Input"); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: parent.isCur
                    }
                    DankIcon { id: inChk; anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter; name: "check_circle"; size: 16; color: island.accent; visible: parent.isCur }
                    MouseArea { id: inRowA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AudioService.setSource(modelData) }
                }
            }
        }
    }
}
