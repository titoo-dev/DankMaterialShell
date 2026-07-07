import QtQuick
import qs.Common

// Screen-edge shine on a new notification: two bright "comets" (lightened
// accent core, soft halo, white-hot spark) travelling the screen border
// once, opposite sides of the loop. No static outline — the comets are the
// whole effect. Visual-only: lives in `stage` but is NOT part of the input
// mask, so it stays fully click-through. Accent-colored, or red for
// critical notifications. One-shot per notification, no idle animation.
Item {
    id: edgeGlow
    property var island: null
    anchors.fill: parent

    // 0 -> 1 -> 0 driven by flash(); color set per-notification
    property real pulse: 0
    // comet lap progress, 0 -> 1 alongside the pulse
    property real prog: 0
    property color glowColor: Theme.primary
    readonly property color shineColor: Qt.lighter(glowColor, 1.6)
    readonly property real inset: 2

    visible: pulse > 0
    z: -2   // behind the pill, in front of the scrim

    function flash(color) {
        glowColor = color
        pulseAnim.restart()
    }

    // soft fade-in, hold while the comets run their lap, soft fade-out
    ParallelAnimation {
        id: pulseAnim
        SequentialAnimation {
            NumberAnimation { target: edgeGlow; property: "pulse"; from: 0; to: 1; duration: 420; easing.type: Easing.OutQuad }
            PauseAnimation { duration: 780 }
            NumberAnimation { target: edgeGlow; property: "pulse"; to: 0; duration: 950; easing.type: Easing.InOutSine }
        }
        NumberAnimation { target: edgeGlow; property: "prog"; from: 0; to: 1; duration: 2150; easing.type: Easing.InOutSine }
    }

    // ---- perimeter path the comets follow (clockwise, one lap),
    // hugging the screen edge — no static outline, the comets ARE the effect
    Path {
        id: perim
        startX: edgeGlow.inset; startY: edgeGlow.inset
        PathLine { x: edgeGlow.width - edgeGlow.inset; y: edgeGlow.inset }
        PathLine { x: edgeGlow.width - edgeGlow.inset; y: edgeGlow.height - edgeGlow.inset }
        PathLine { x: edgeGlow.inset; y: edgeGlow.height - edgeGlow.inset }
        PathLine { x: edgeGlow.inset; y: edgeGlow.inset }
    }
    PathInterpolator { id: pi1; path: perim; progress: edgeGlow.prog }
    PathInterpolator { id: pi2; path: perim; progress: (edgeGlow.prog + 0.5) % 1 }

    // ---- two shine comets, opposite sides of the loop ----
    component Comet: Rectangle {
        id: cometBody
        property var pin: null
        width: 220; height: 3; radius: 1.5
        x: pin.x - width / 2
        y: pin.y - height / 2
        rotation: pin.angle
        opacity: edgeGlow.pulse
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: "transparent" }
            GradientStop { position: 0.35; color: Qt.rgba(edgeGlow.glowColor.r, edgeGlow.glowColor.g, edgeGlow.glowColor.b, 0.85) }
            GradientStop { position: 0.5;  color: edgeGlow.shineColor }
            GradientStop { position: 0.65; color: Qt.rgba(edgeGlow.glowColor.r, edgeGlow.glowColor.g, edgeGlow.glowColor.b, 0.85) }
            GradientStop { position: 1.0;  color: "transparent" }
        }
        // soft halo hugging the comet: wider, taller, faint — reads as bloom
        // along the hairline without adding any extra moving part
        Rectangle {
            z: -1
            anchors.centerIn: parent
            width: cometBody.width * 1.35; height: 10; radius: 5
            opacity: 0.30
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.5;  color: Qt.rgba(edgeGlow.shineColor.r, edgeGlow.shineColor.g, edgeGlow.shineColor.b, 0.8) }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }
        // white-hot spark at the very tip of the shine
        Rectangle {
            anchors.centerIn: parent
            width: 32; height: parent.height + 2; radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.55)
        }
    }
    Comet { pin: pi1 }
    Comet { pin: pi2 }
}
