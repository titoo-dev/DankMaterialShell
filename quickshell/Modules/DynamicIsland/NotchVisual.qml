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

    // Convex corners are CONTINUOUS-CURVATURE ("squircle", the iOS corner):
    // one cubic per corner that starts its run-in earlier (d ≈ 1.28 r) with
    // handles at ≈ 0.48 d, so curvature ramps up smoothly instead of kicking
    // in abruptly where a circular arc meets the straight edge. The concave
    // notch flares stay circular — that hard curvature IS the MacBook look.
    function _trace(ctx) {
        const W = width, H = height
        const fr = notchMode ? flare : 0
        ctx.beginPath()
        if (notchMode) {
            const br = Math.max(0, Math.min(cornerRadius, H, (W - 2 * fr) / 2))
            const d = Math.min(br * 1.28, H - fr, (W - 2 * fr) / 2)
            const k = d * 0.484
            // top-left flare tip → top edge → right flare (concave) → right side
            ctx.moveTo(0, 0)
            ctx.lineTo(W, 0)
            shape._arc(ctx, W, fr, fr, 270, 180)          // right flare, concave
            ctx.lineTo(W - fr, H - d)
            ctx.bezierCurveTo(W - fr, H - k, W - fr - k, H, W - fr - d, H)   // bottom-right squircle
            ctx.lineTo(fr + d, H)
            ctx.bezierCurveTo(fr + k, H, fr, H - k, fr, H - d)               // bottom-left squircle
            ctx.lineTo(fr, fr)
            shape._arc(ctx, 0, fr, fr, 0, -90)            // left flare, concave
        } else {
            const r = Math.max(0, Math.min(cornerRadius, H / 2, W / 2))
            const d = Math.min(r * 1.28, H / 2, W / 2)
            const k = d * 0.484
            ctx.moveTo(d, 0)
            ctx.lineTo(W - d, 0)
            ctx.bezierCurveTo(W - k, 0, W, k, W, d)           // top-right
            ctx.lineTo(W, H - d)
            ctx.bezierCurveTo(W, H - k, W - k, H, W - d, H)   // bottom-right
            ctx.lineTo(d, H)
            ctx.bezierCurveTo(k, H, 0, H - k, 0, H - d)       // bottom-left
            ctx.lineTo(0, d)
            ctx.bezierCurveTo(0, k, k, 0, d, 0)               // top-left
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
