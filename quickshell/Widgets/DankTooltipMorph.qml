import QtQuick
import QtQuick.Window
import qs.Common

// The single tooltip capsule of a window — macOS Tahoe language.
//
// A floating glass pill that GROWS out of the button it describes and, while
// the pointer walks a row of buttons, MORPHS across to the next one: it glides,
// resizes to the new label and cross-fades the text instead of blinking out and
// popping back in. All state comes from TooltipManager, so only one capsule is
// ever visible shell-wide; each window's instance renders it only while the
// anchored button lives in THIS window.
//
// Drop one per window, declared LAST (so it paints over everything) and OUTSIDE
// any clipping item:
//
//     Item { id: stage
//         ...content...
//         DankTooltipMorph { anchors.fill: parent }
//     }
Item {
    id: overlay

    // breathing room between the button's edge and the capsule
    property real gap: 8
    property real maxWidth: 320
    property real capsuleHeight: 27
    // Same tone as DankTooltip / DankTooltipV2 — ONE step above the body it
    // floats over, and neutral. `surfaceContainerHighest` reads wrong here: two
    // steps up AND hue-shifted bluer than the island, so the capsule looked like
    // a foreign popup instead of a piece of the island.
    property color surfaceColor: Theme.withAlpha(Theme.surfaceContainerHigh, Math.max(0.92, Theme.popupTransparency))
    property color labelColor: Theme.surfaceText

    z: 10000

    readonly property Item anchorItem: TooltipManager.anchorItem
    readonly property var _anchorWindow: anchorItem ? anchorItem.Window.window : null
    readonly property bool mine: !!_anchorWindow && _anchorWindow === overlay.Window.window
    readonly property bool open: mine && TooltipManager.shown
    readonly property bool reduceMotion: Theme.shortDuration === 0

    // Once the capsule is on screen its moves and resizes animate — that IS the
    // morph. The first placement of a run has to snap instead, or the capsule
    // would fly in from wherever the previous one died.
    readonly property bool morphing: capsule.opacity > 0.06 && !reduceMotion

    readonly property int fadeDuration: Math.round(Theme.shorterDuration * 0.9)
    readonly property int popDuration: Math.round(Theme.shortDuration * 0.75)
    readonly property int morphDuration: Math.round(Theme.mediumDuration * 0.5)

    property real tipX: 0
    property real tipY: 0
    // the side actually used after the flip — decides where the capsule grows from
    property string placedSide: "bottom"

    property string shownText: TooltipManager.text
    // the outgoing label, held alive just long enough to cross-fade away
    property string ghostText: ""
    property string _prevText: ""

    function retarget() {
        const a = overlay.anchorItem;
        if (!a || !overlay.mine)
            return;
        const p = overlay.mapFromItem(a, 0, 0);
        if (!p)
            return;
        const w = capsule.width;
        const h = capsule.height;
        const aw = a.width;
        const ah = a.height;
        let s = TooltipManager.side;
        let nx = 0;
        let ny = 0;
        if (s === "left" || s === "right") {
            ny = p.y + (ah - h) / 2;
            nx = s === "left" ? p.x - w - overlay.gap : p.x + aw + overlay.gap;
            if (s === "right" && nx + w > overlay.width - 4) {
                nx = p.x - w - overlay.gap;
                s = "left";
            } else if (s === "left" && nx < 4) {
                nx = p.x + aw + overlay.gap;
                s = "right";
            }
        } else {
            nx = p.x + (aw - w) / 2;
            ny = s === "top" ? p.y - h - overlay.gap : p.y + ah + overlay.gap;
            if (s === "bottom" && ny + h > overlay.height - 4) {
                ny = p.y - h - overlay.gap;
                s = "top";
            } else if (s === "top" && ny < 4) {
                ny = p.y + ah + overlay.gap;
                s = "bottom";
            }
        }
        overlay.placedSide = s;
        overlay.tipX = Math.round(Math.max(4, Math.min(overlay.width - w - 4, nx)));
        overlay.tipY = Math.round(Math.max(4, Math.min(overlay.height - h - 4, ny)));
    }

    // The anchor MOVES under us: the pill springs between modes, drill views
    // slide in, buttons scale on press. Re-solving every frame keeps the capsule
    // welded to its button — and it only ticks while a tooltip is on screen.
    FrameAnimation {
        running: overlay.mine && (overlay.open || capsule.opacity > 0.01)
        onTriggered: overlay.retarget()
    }

    // TooltipManager publishes text and side BEFORE the anchor, so by the time
    // this fires the capsule already knows its new width — placing it here (and
    // not a frame later) keeps the entrance from flashing at the previous spot
    onAnchorItemChanged: {
        retarget();
        if (morphing)
            squashAnim.restart();
    }
    onOpenChanged: retarget()
    onShownTextChanged: {
        if (morphing && _prevText.length > 0 && _prevText !== shownText) {
            ghostText = _prevText;
            swapAnim.restart();
        }
        _prevText = shownText;
        retarget();
    }

    Rectangle {
        id: capsule

        readonly property real padH: 11
        // gelatinous morph accent, same language as the island pill's squash
        property real squashX: 1
        property real squashY: 1

        x: overlay.tipX
        y: overlay.tipY
        width: Math.min(overlay.maxWidth, label.implicitWidth + padH * 2)
        height: overlay.capsuleHeight
        radius: height / 2
        antialiasing: true
        color: overlay.surfaceColor
        border.width: 1
        // same hairline the island pill draws at rest
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)

        opacity: overlay.open ? 1 : 0
        visible: opacity > 0
        scale: overlay.open ? 1 : 0.82
        // grow out of the edge the capsule is parked against
        transformOrigin: {
            switch (overlay.placedSide) {
            case "top":
                return Item.Bottom;
            case "left":
                return Item.Right;
            case "right":
                return Item.Left;
            default:
                return Item.Top;
            }
        }
        transform: Scale {
            origin.x: capsule.width / 2
            origin.y: capsule.height / 2
            xScale: capsule.squashX
            yScale: capsule.squashY
        }

        Behavior on x {
            enabled: overlay.morphing
            NumberAnimation {
                duration: overlay.morphDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }
        Behavior on y {
            enabled: overlay.morphing
            NumberAnimation {
                duration: overlay.morphDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }
        Behavior on width {
            enabled: overlay.morphing
            NumberAnimation {
                duration: overlay.morphDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.emphasizedDecel
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: overlay.fadeDuration
                easing.type: Easing.OutQuad
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: overlay.popDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
            }
        }

        // glass material: specular light along the top edge, shade at the foot.
        // The pill's exact stops (0.09 white fading out by 10%, 0.08 black at the
        // foot) — a broader falloff visibly lightens a capsule this short, which
        // is half of why the first version read as a lighter, foreign chip.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(1, 1, 1, 0.09)
                }
                GradientStop {
                    position: 0.10
                    color: Qt.rgba(1, 1, 1, 0.0)
                }
                GradientStop {
                    position: 0.82
                    color: Qt.rgba(0, 0, 0, 0.0)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(0, 0, 0, 0.08)
                }
            }
        }

        // Label stack: the incoming text rises into place while the outgoing one
        // lifts away, so a morph RE-LETTERS the capsule instead of swapping it.
        // Clipped, so a longer label can't spill while the capsule is still growing.
        Item {
            id: labelBox
            anchors.fill: parent
            anchors.leftMargin: capsule.padH
            anchors.rightMargin: capsule.padH
            clip: true

            StyledText {
                id: ghost
                anchors.centerIn: parent
                width: Math.min(implicitWidth, labelBox.width)
                text: overlay.ghostText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: overlay.labelColor
                maximumLineCount: 1
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                opacity: 0
                transform: Translate {
                    id: ghostSlide
                }
            }
            StyledText {
                id: label
                anchors.centerIn: parent
                width: Math.min(implicitWidth, labelBox.width)
                text: overlay.shownText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: overlay.labelColor
                maximumLineCount: 1
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                transform: Translate {
                    id: labelSlide
                }
            }
        }

        ParallelAnimation {
            id: swapAnim
            NumberAnimation {
                target: ghost
                property: "opacity"
                from: 1
                to: 0
                duration: overlay.morphDuration
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: ghostSlide
                property: "y"
                from: 0
                to: -7
                duration: overlay.morphDuration
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: label
                property: "opacity"
                from: 0
                to: 1
                duration: overlay.morphDuration
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: labelSlide
                property: "y"
                from: 7
                to: 0
                duration: overlay.morphDuration
                easing.type: Easing.OutCubic
            }
        }

        SequentialAnimation {
            id: squashAnim
            ParallelAnimation {
                NumberAnimation {
                    target: capsule
                    property: "squashX"
                    to: 1.04
                    duration: Math.round(overlay.morphDuration * 0.35)
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: capsule
                    property: "squashY"
                    to: 0.94
                    duration: Math.round(overlay.morphDuration * 0.35)
                    easing.type: Easing.OutQuad
                }
            }
            ParallelAnimation {
                SpringAnimation {
                    target: capsule
                    property: "squashX"
                    to: 1.0
                    spring: 5
                    damping: 0.22
                    epsilon: 0.005
                }
                SpringAnimation {
                    target: capsule
                    property: "squashY"
                    to: 1.0
                    spring: 5
                    damping: 0.22
                    epsilon: 0.005
                }
            }
        }
    }
}
