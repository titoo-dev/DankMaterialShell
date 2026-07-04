import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Visual-only two-zone drop surface (Shelf | → default device). The actual drop
// is handled by the pill's shelfDrop DropArea, which routes by drop X position;
// this just shows the two halves and highlights the one under the cursor
// (island._dropHalf == "left" | "right").
Item {
    id: dropChoose
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    implicitHeight: 92
    opacity: island.panelView === "dropchoose" ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        Rectangle {
            id: zoneLeft
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.cornerRadius
            readonly property bool hot: dropChoose.island._dropHalf === "left"
            // quiet glass; the hovered half gets a half-alpha accent border, never a full fill
            color: hot ? Theme.primaryHover : Theme.surfaceLight
            border.width: hot ? 1 : 0
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            Column {
                anchors.centerIn: parent
                spacing: 2
                DankIcon { name: "inventory_2"; size: 22; color: zoneLeft.hot ? Theme.primary : Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText { text: I18n.tr("Shelf"); font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: zoneLeft.hot ? Theme.primary : Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
        Rectangle {
            id: zoneRight
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.cornerRadius
            readonly property bool hot: dropChoose.island._dropHalf === "right"
            color: hot ? Theme.primaryHover : Theme.surfaceLight
            border.width: hot ? 1 : 0
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            Column {
                anchors.centerIn: parent
                spacing: 2
                DankIcon { name: "send_to_mobile"; size: 22; color: zoneRight.hot ? Theme.primary : Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText {
                    text: "→ " + (TailscaleService.defaultPeer ? (TailscaleService.defaultPeer.hostname || "") : "")
                    font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: zoneRight.hot ? Theme.primary : Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
