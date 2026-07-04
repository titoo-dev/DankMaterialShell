import QtQuick
import qs.Common
import qs.Widgets

// iOS-style fat slider (island design language): the whole capsule is the
// control and the icon lives inside the fill — no thin track, no floating
// thumb. A value readout fades in at the right while interacting.
//
// The fill is a plain antialiased rounded Rectangle (no ClippingRectangle:
// shader clipping blurred the curved edge) with a min-width clamp so its cap
// stays a clean capsule at low values (iOS). Smoothing is applied to `frac`
// (the VALUE), never to the width geometry — a width Behavior lagged behind
// the pill's expansion spring and read as a fake 0→value sweep on every open.
Item {
    id: cs
    property string icon: ""
    property string accessibleName: I18n.tr("Level")
    property real frac: 0
    property bool dim: false   // muted look: grey fill
    // opt-in: a TAP on the icon zone fires iconClicked (e.g. mute) instead of
    // seeking; dragging out of the zone falls back to normal value adjustment
    property bool iconClickable: false
    signal moved(real f)
    signal iconClicked()
    height: 36
    property real dragFrac: 0
    // true while the press is actually adjusting the value (not an icon tap)
    property bool adjusting: false
    readonly property real shownFrac: adjusting ? dragFrac : frac
    Behavior on frac { enabled: !cs.adjusting; NumberAnimation { duration: 120 } }
    Rectangle {   // track
        anchors.fill: parent
        radius: height / 2
        color: Theme.surfaceLight
        antialiasing: true
    }
    Rectangle {   // fill: capsule with a min width so the cap never squishes
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: cs.shownFrac <= 0.001 ? 0 : Math.max(height, cs.shownFrac * cs.width)
        height: parent.height
        radius: height / 2
        antialiasing: true
        color: cs.dim ? Theme.surfaceVariant : Theme.primary
        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
    }
    DankIcon {
        anchors.left: parent.left; anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        name: cs.icon; size: 18; filled: true
        color: (cs.shownFrac > 0.001 && !cs.dim) ? Theme.primaryText : Theme.surfaceText
        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
    }
    StyledText {   // value readout, revealed while interacting
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(cs.shownFrac * 100) + "%"
        color: (cs.shownFrac > 0.88 && !cs.dim) ? Theme.primaryText : Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall - 2; font.bold: true
        opacity: (csArea.containsMouse || csArea.pressed) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
    }
    MouseArea {
        id: csArea
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        property bool iconPress: false
        property real pressX: 0
        function fAt(mx) { return Math.max(0, Math.min(1, mx / width)) }
        onPressed: mouse => {
            pressX = mouse.x
            iconPress = cs.iconClickable && mouse.x <= 36
            if (!iconPress) {
                cs.adjusting = true
                cs.dragFrac = fAt(mouse.x)
                cs.moved(cs.dragFrac)
            }
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            // an icon press that moves becomes a normal drag
            if (iconPress && Math.abs(mouse.x - pressX) > 5) { iconPress = false; cs.adjusting = true }
            if (cs.adjusting) { cs.dragFrac = fAt(mouse.x); cs.moved(cs.dragFrac) }
        }
        onReleased: {
            if (iconPress) cs.iconClicked()
            iconPress = false
            cs.adjusting = false
        }
        onCanceled: { iconPress = false; cs.adjusting = false }
        // wheel over the capsule = fine adjustment (±5%)
        onWheel: wheel => {
            const next = Math.max(0, Math.min(1, cs.frac + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)))
            cs.moved(next)
            wheel.accepted = true
        }
        Accessible.role: Accessible.Slider
        Accessible.name: cs.accessibleName
    }
}
