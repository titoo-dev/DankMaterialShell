import QtQuick

// The dynamic island's body, drawn as ONE continuous silhouette so the fill,
// border and (via layer.effect on the instance) the glow all trace the real
// shape. In notch mode the top corners flare *concavely* into the screen edge
// like a MacBook notch; otherwise it's a plain rounded pill. Sized wider than
// the pill body by `flare` on each side so the flares aren't clipped — the
// caller positions it accordingly.
Canvas {
    id: shape

    property bool notchMode: false
    property color fillColor: "black"
    property color strokeColor: "transparent"
    property real strokeWidth: 1
    property real flare: 13        // concave top-corner radius (notch mode)
    property real cornerRadius: 22 // bottom corners (notch) / all corners (pill)

    antialiasing: true
    onNotchModeChanged: requestPaint()
    onFillColorChanged: requestPaint()
    onStrokeColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onFlareChanged: requestPaint()
    onCornerRadiusChanged: requestPaint()

    // sweep an arc as explicit points (degrees, y-down) — no PathArc direction
    // ambiguity, perfectly smooth at this scale
    function _arc(ctx, cx, cy, r, a0, a1) {
        const n = 18
        for (var i = 0; i <= n; i++) {
            const a = (a0 + (a1 - a0) * (i / n)) * Math.PI / 180
            ctx.lineTo(cx + r * Math.cos(a), cy + r * Math.sin(a))
        }
    }

    function _trace(ctx) {
        const W = width, H = height
        const fr = notchMode ? flare : 0
        // clamp radii so they never overrun a small pill
        const br = Math.max(0, Math.min(cornerRadius, H, (W - 2 * fr) / 2))
        ctx.beginPath()
        if (notchMode) {
            // top-left flare tip → top edge → right flare (concave) → right side
            ctx.moveTo(0, 0)
            ctx.lineTo(W, 0)
            shape._arc(ctx, W, fr, fr, 270, 180)          // right flare, concave
            ctx.lineTo(W - fr, H - br)
            shape._arc(ctx, W - fr - br, H - br, br, 0, 90)   // bottom-right convex
            ctx.lineTo(fr + br, H)
            shape._arc(ctx, fr + br, H - br, br, 90, 180)     // bottom-left convex
            ctx.lineTo(fr, fr)
            shape._arc(ctx, 0, fr, fr, 0, -90)            // left flare, concave
        } else {
            const r = Math.max(0, Math.min(cornerRadius, H / 2, W / 2))
            ctx.moveTo(r, 0)
            ctx.lineTo(W - r, 0)
            shape._arc(ctx, W - r, r, r, 270, 360)
            ctx.lineTo(W, H - r)
            shape._arc(ctx, W - r, H - r, r, 0, 90)
            ctx.lineTo(r, H)
            shape._arc(ctx, r, H - r, r, 90, 180)
            ctx.lineTo(0, r)
            shape._arc(ctx, r, r, r, 180, 270)
        }
        ctx.closePath()
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        shape._trace(ctx)
        ctx.fillStyle = Qt.rgba(fillColor.r, fillColor.g, fillColor.b, fillColor.a)
        ctx.fill()
        if (strokeColor.a > 0 && strokeWidth > 0) {
            ctx.lineWidth = strokeWidth
            ctx.strokeStyle = Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, strokeColor.a)
            ctx.stroke()
        }
    }
}
