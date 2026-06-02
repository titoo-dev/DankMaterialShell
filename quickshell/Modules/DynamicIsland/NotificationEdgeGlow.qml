import QtQuick
import qs.Common

// Full-screen ambient edge lighting that pulses when a notification arrives
// (macOS/iOS "edge glow" vibe). Visual-only: lives in `stage` but is NOT part
// of the input mask, so it stays fully click-through. Accent-colored, or red
// for critical notifications.
Item {
    id: edgeGlow
    property var island: null
    anchors.fill: parent

    // 0 -> 1 -> 0 pulse driven by flash(); color set per-notification
    property real pulse: 0
    property color glowColor: Theme.primary
    readonly property real thickness: 150
    readonly property real maxAlpha: 0.55

    visible: pulse > 0
    z: -2   // behind the pill, in front of the scrim

    function flash(color) {
        glowColor = color
        pulseAnim.restart()
    }

    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: edgeGlow; property: "pulse"; to: 1; duration: 220; easing.type: Easing.OutQuad }
        NumberAnimation { target: edgeGlow; property: "pulse"; to: 0; duration: 1100; easing.type: Easing.InQuad }
    }

    // top
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: edgeGlow.thickness
        opacity: edgeGlow.pulse * edgeGlow.maxAlpha
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: edgeGlow.glowColor }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    // bottom
    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: edgeGlow.thickness
        opacity: edgeGlow.pulse * edgeGlow.maxAlpha
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: edgeGlow.glowColor }
        }
    }
    // left
    Rectangle {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: edgeGlow.thickness
        opacity: edgeGlow.pulse * edgeGlow.maxAlpha
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: edgeGlow.glowColor }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    // right
    Rectangle {
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: edgeGlow.thickness
        opacity: edgeGlow.pulse * edgeGlow.maxAlpha
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: edgeGlow.glowColor }
        }
    }
}
