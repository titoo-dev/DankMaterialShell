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
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.cornerRadius
            readonly property bool hot: dropChoose.island._dropHalf === "left"
            color: hot ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : Theme.surfaceContainerHigh
            border.width: hot ? 1 : 0
            border.color: Theme.primary
            Column {
                anchors.centerIn: parent
                spacing: 2
                DankIcon { name: "inventory_2"; size: 22; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText { text: I18n.tr("Shelf"); font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText; anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.cornerRadius
            readonly property bool hot: dropChoose.island._dropHalf === "right"
            color: hot ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : Theme.surfaceContainerHigh
            border.width: hot ? 1 : 0
            border.color: Theme.primary
            Column {
                anchors.centerIn: parent
                spacing: 2
                DankIcon { name: "send_to_mobile"; size: 22; color: Theme.primary; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText {
                    text: "→ " + (TailscaleService.defaultPeer ? (TailscaleService.defaultPeer.hostname || "") : "")
                    font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
