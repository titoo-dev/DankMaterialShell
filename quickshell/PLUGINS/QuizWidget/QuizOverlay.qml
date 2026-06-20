import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

PanelWindow {
    id: overlay

    property var question: null
    property string nudge: "Quiz dispo"
    property string emoji: "🦉"
    property int animIndex: 0       // 0=bounce 1=shake 2=pulse 3=swing
    readonly property int animCount: 4
    signal dismissed()
    signal snoozeRequested(int ms)

    property string mode: "hidden" // "hidden"|"pending"|"open"|"feedback"
    property int selected: -1

    onAnimIndexChanged: pill.resetPillTransforms()
    onModeChanged: if (overlay.mode === "pending") pill.resetPillTransforms()

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

            // --- Animations d'attention variées (index aléatoire par message), façon Duolingo ---
            transform: [
                Translate { id: animTrans },
                Rotation { id: animRot; origin.x: pill.width / 2; origin.y: 0 },
                Scale { id: animScale; origin.x: pill.width / 2; origin.y: pill.height / 2 }
            ]

            function resetPillTransforms() {
                animTrans.y = 0;
                animRot.angle = 0;
                animScale.xScale = 1;
                animScale.yScale = 1;
            }

            // 0 — Bounce 🦘
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 0
                loops: Animation.Infinite
                NumberAnimation { target: animTrans; property: "y"; from: 0; to: -12; duration: 240; easing.type: Easing.OutQuad }
                NumberAnimation { target: animTrans; property: "y"; to: 0; duration: 520; easing.type: Easing.OutBounce }
                PauseAnimation { duration: 2200 }
            }

            // 1 — Shake 🫨
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 1
                loops: Animation.Infinite
                SequentialAnimation {
                    loops: 3
                    NumberAnimation { target: animRot; property: "angle"; to: 7; duration: 70 }
                    NumberAnimation { target: animRot; property: "angle"; to: -7; duration: 70 }
                }
                NumberAnimation { target: animRot; property: "angle"; to: 0; duration: 70 }
                PauseAnimation { duration: 2400 }
            }

            // 2 — Pulse 💓
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 2
                loops: Animation.Infinite
                SequentialAnimation {
                    loops: 2
                    ParallelAnimation {
                        NumberAnimation { target: animScale; property: "xScale"; to: 1.12; duration: 180; easing.type: Easing.OutQuad }
                        NumberAnimation { target: animScale; property: "yScale"; to: 1.12; duration: 180; easing.type: Easing.OutQuad }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: animScale; property: "xScale"; to: 1.0; duration: 220; easing.type: Easing.InQuad }
                        NumberAnimation { target: animScale; property: "yScale"; to: 1.0; duration: 220; easing.type: Easing.InQuad }
                    }
                }
                PauseAnimation { duration: 2200 }
            }

            // 3 — Swing 🎐
            SequentialAnimation {
                running: overlay.mode === "pending" && overlay.animIndex === 3
                loops: Animation.Infinite
                NumberAnimation { target: animRot; property: "angle"; to: 10; duration: 200; easing.type: Easing.OutQuad }
                NumberAnimation { target: animRot; property: "angle"; to: -7; duration: 280; easing.type: Easing.InOutQuad }
                NumberAnimation { target: animRot; property: "angle"; to: 4; duration: 240; easing.type: Easing.InOutQuad }
                NumberAnimation { target: animRot; property: "angle"; to: 0; duration: 200; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 2400 }
            }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                StyledText { text: overlay.emoji; font.pixelSize: Theme.fontSizeLarge; anchors.verticalCenter: parent.verticalCenter }
                StyledText { text: overlay.nudge; font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
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
