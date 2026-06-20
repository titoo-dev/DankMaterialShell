import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

PanelWindow {
    id: overlay

    property var question: null
    signal dismissed()
    signal snoozeRequested(int ms)

    property string mode: "hidden" // "hidden"|"pending"|"open"|"feedback"
    property int selected: -1

    function showPending() { overlay.selected = -1; overlay.mode = "pending"; overlay.visible = true; }
    function reset() { overlay.mode = "hidden"; overlay.selected = -1; overlay.visible = false; overlay.dismissed(); }

    color: "transparent"
    visible: false

    WlrLayershell.namespace: "dms:quiz"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { bottom: true; right: true }
    WlrLayershell.margins { bottom: Theme.spacingL; right: Theme.spacingL }

    // Marge autour du contenu pour que l'ombre d'ElevationShadow ne soit pas clippée par la fenêtre.
    readonly property real shadowPad: 28

    implicitWidth: content.implicitWidth + overlay.shadowPad * 2
    implicitHeight: content.implicitHeight + overlay.shadowPad * 2

    Item {
        id: content
        anchors.fill: parent
        anchors.margins: overlay.shadowPad
        implicitWidth: card.visible ? card.implicitWidth : pill.implicitWidth
        implicitHeight: card.visible ? card.implicitHeight : pill.implicitHeight
        opacity: overlay.mode === "hidden" ? 0 : 1
        scale: overlay.mode === "hidden" ? 0.9 : 1
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        StyledRect { // pastille
            id: pill
            visible: overlay.mode === "pending"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            implicitWidth: pillRow.implicitWidth + Theme.spacingM * 2
            implicitHeight: pillRow.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)

            ElevationShadow {
                anchors.fill: parent
                z: -1
                level: Theme.elevationLevel2
                targetRadius: pill.radius
                targetColor: pill.color
                borderColor: pill.border.color
                borderWidth: pill.border.width
                shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled
            }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                DankIcon { name: "quiz"; color: Theme.primary; size: Theme.iconSizeSmall }
                StyledText { text: "Quiz dispo"; font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: overlay.mode = "open"
            }
        }

        QuizCard { // carte
            id: card
            visible: overlay.mode === "open" || overlay.mode === "feedback"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            question: overlay.question
            mode: overlay.mode === "feedback" ? "feedback" : "open"
            selected: overlay.selected
            onSelect: (i) => overlay.selected = i
            onSubmit: overlay.mode = "feedback"
            onClose: overlay.reset()
            onSnooze: (ms) => { overlay.snoozeRequested(ms); overlay.reset(); }
        }
    }
}
