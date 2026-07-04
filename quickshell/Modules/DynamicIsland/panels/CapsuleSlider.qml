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
    property real frac: 0
    property bool dim: false   // muted look: grey fill
    signal moved(real f)
    height: 36
    property real dragFrac: 0
    readonly property real shownFrac: csArea.pressed ? dragFrac : frac
    Behavior on frac { enabled: !csArea.pressed; NumberAnimation { duration: 120 } }
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
        function fAt(mx) { return Math.max(0, Math.min(1, mx / width)) }
        onPressed: mouse => { cs.dragFrac = fAt(mouse.x); cs.moved(cs.dragFrac) }
        onPositionChanged: mouse => { if (pressed) { cs.dragFrac = fAt(mouse.x); cs.moved(cs.dragFrac) } }
    }
}
