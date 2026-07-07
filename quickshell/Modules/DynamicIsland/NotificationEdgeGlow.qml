import QtQuick
import qs.Common

// Screen-edge outline shine on a new notification: a thin luminous outline
// hugging the screen border, with two bright "comets" travelling the
// perimeter once (opposite sides, one lap) — replaces the old fat ambient
// gradient rim. Visual-only: lives in `stage` but is NOT part of the input
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
    // rainbow mode: the outline runs a full hue wheel around the perimeter
    // (normal notifications); solid colour is kept for critical/status flashes
    property bool rainbow: false
    readonly property color shineColor: Qt.lighter(glowColor, 1.6)
    readonly property color cometCore: rainbow ? Qt.rgba(1, 1, 1, 1) : shineColor
    readonly property color cometEdge: rainbow ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0.85)
    readonly property real inset: 2
    // the hue wheel needs a little more flesh to read as a rainbow
    readonly property real stroke: rainbow ? 4 : 2
    // hue wheel corners (clockwise): TL red -> TR yellow-green -> BR cyan-blue -> BL violet -> back to red
    function hue(h) { return Qt.hsla(h % 1, 0.85, 0.62, 1) }

    visible: pulse > 0
    z: -2   // behind the pill, in front of the scrim

    function flash(color, useRainbow) {
        glowColor = color
        rainbow = useRainbow === true
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

    // ---- the outline: a thin luminous stroke on all four edges.
    // In rainbow mode each edge carries its quarter of the hue wheel, so the
    // four gradients chain into one continuous loop (corner hues shared).
    Rectangle {  // top: red -> yellow-green
        x: edgeGlow.inset; y: edgeGlow.inset
        width: parent.width - edgeGlow.inset * 2; height: edgeGlow.stroke
        color: edgeGlow.glowColor; opacity: edgeGlow.pulse * 0.55
        gradient: edgeGlow.rainbow ? topGrad : null
        Gradient {
            id: topGrad
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: edgeGlow.hue(0.0) }
            GradientStop { position: 0.5; color: edgeGlow.hue(0.125) }
            GradientStop { position: 1.0; color: edgeGlow.hue(0.25) }
        }
    }
    Rectangle {  // right: yellow-green -> cyan-blue
        x: parent.width - edgeGlow.inset - edgeGlow.stroke; y: edgeGlow.inset
        width: edgeGlow.stroke; height: parent.height - edgeGlow.inset * 2
        color: edgeGlow.glowColor; opacity: edgeGlow.pulse * 0.55
        gradient: edgeGlow.rainbow ? rightGrad : null
        Gradient {
            id: rightGrad
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: edgeGlow.hue(0.25) }
            GradientStop { position: 0.5; color: edgeGlow.hue(0.375) }
            GradientStop { position: 1.0; color: edgeGlow.hue(0.5) }
        }
    }
    Rectangle {  // bottom: violet <- cyan-blue (left to right)
        x: edgeGlow.inset; y: parent.height - edgeGlow.inset - edgeGlow.stroke
        width: parent.width - edgeGlow.inset * 2; height: edgeGlow.stroke
        color: edgeGlow.glowColor; opacity: edgeGlow.pulse * 0.55
        gradient: edgeGlow.rainbow ? bottomGrad : null
        Gradient {
            id: bottomGrad
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: edgeGlow.hue(0.75) }
            GradientStop { position: 0.5; color: edgeGlow.hue(0.625) }
            GradientStop { position: 1.0; color: edgeGlow.hue(0.5) }
        }
    }
    Rectangle {  // left: red (top) -> violet (bottom)
        x: edgeGlow.inset; y: edgeGlow.inset
        width: edgeGlow.stroke; height: parent.height - edgeGlow.inset * 2
        color: edgeGlow.glowColor; opacity: edgeGlow.pulse * 0.55
        gradient: edgeGlow.rainbow ? leftGrad : null
        Gradient {
            id: leftGrad
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: edgeGlow.hue(0.0) }
            GradientStop { position: 0.5; color: edgeGlow.hue(0.875) }
            GradientStop { position: 1.0; color: edgeGlow.hue(0.75) }
        }
    }

    // ---- perimeter path the comets follow (clockwise, one lap) ----
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
        property var pin: null
        width: 320; height: 4; radius: 2
        x: pin.x - width / 2
        y: pin.y - height / 2
        rotation: pin.angle
        opacity: edgeGlow.pulse
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: "transparent" }
            GradientStop { position: 0.35; color: edgeGlow.cometEdge }
            GradientStop { position: 0.5;  color: edgeGlow.cometCore }
            GradientStop { position: 0.65; color: edgeGlow.cometEdge }
            GradientStop { position: 1.0;  color: "transparent" }
        }
    }
    Comet { pin: pi1 }
    Comet { pin: pi2 }
}
