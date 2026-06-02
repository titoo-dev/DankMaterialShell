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
    // thin, compact rim of light hugging the screen edge
    readonly property real thickness: 44
    readonly property real maxAlpha: 0.6

    visible: pulse > 0
    z: -2   // behind the pill, in front of the scrim

    function flash(color) {
        glowColor = color
        pulseAnim.restart()
    }

    // gentle breath: soft fade-in, brief hold, soft fade-out (no hard flash/blink)
    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: edgeGlow; property: "pulse"; to: 1; duration: 500; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 450 }
        NumberAnimation { target: edgeGlow; property: "pulse"; to: 0; duration: 1200; easing.type: Easing.InOutSine }
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
