import QtQuick
import qs.Common
import qs.Widgets

// Shared drill-view header: back chevron + bold title, with an optional
// trailing slot (refresh buttons, toggles, "Clear all"…) anchored right.
// One definition instead of a dozen copy-pastes — and the back button gets
// its accessibility name and a 44 px hit target exactly once.
Item {
    id: header
    property var island: null
    property string title: ""
    // extra content laid out at the right edge (children declared inline land here)
    default property alias trailing: trailingRow.data
    // where the title starts — lets panels anchor custom content next to it
    readonly property alias titleItem: headerTitle

    width: parent.width
    height: 34

    Rectangle {
        id: backBtn
        width: 30; height: 30; radius: width / 2
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        color: backArea.containsMouse ? Theme.primaryHover : "transparent"
        scale: backArea.pressed ? 0.9 : 1.0
        Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
        DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: header.island ? header.island.textColor : Theme.surfaceText }
        MouseArea {
            id: backArea
            // 30 px visual, 44 px touch/click target
            anchors.fill: parent; anchors.margins: -7
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: if (header.island) header.island.panelView = "controls"
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("Back")
            Accessible.onPressAction: clicked(null)
        }
    }

    StyledText {
        id: headerTitle
        anchors.left: backBtn.right; anchors.leftMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        text: header.title
        color: header.island ? header.island.textColor : Theme.surfaceText
        font.pixelSize: Theme.fontSizeMedium; font.bold: true
        Accessible.role: Accessible.Heading
    }

    Row {
        id: trailingRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS
    }
}
