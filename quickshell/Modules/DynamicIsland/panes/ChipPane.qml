import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// CHIP (rest + media): tiny now-playing with album-art progress ring + EQ.
// Reads island state via `island`.
Row {
    id: chipRow
    property var island: null
    anchors.centerIn: parent
    spacing: Theme.spacingS
    opacity: island.mode === "chip" ? 1 : 0
    visible: opacity > 0
    scale: island.mode === "chip" ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
    Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }
    Item {  // circular album art hugged by the progress ring (Apple "Live Activity" feel)
        width: 28; height: 28
        anchors.verticalCenter: parent.verticalCenter
        // circular avatar: true rounded clip so the art FILLS the disc — the old
        // bbox `clip` let the square art's corners paint over the ring
        ClippingRectangle {
            anchors.centerIn: parent
            width: 22; height: 22; radius: 11
            color: Theme.primaryBackground
            Image { id: chipArtImg; anchors.fill: parent; source: island.player ? (island.player.trackArtUrl ?? "") : ""; fillMode: Image.PreserveAspectCrop; cache: false; asynchronous: true; visible: status === Image.Ready }
            DankIcon { anchors.centerIn: parent; name: "music_note"; size: 12; color: island.accent; visible: chipArtImg.status !== Image.Ready }
        }
        Shape {  // faint track, above the avatar so the ring always reads on top
            anchors.fill: parent; antialiasing: true
            visible: island.mediaLen > 0
            ShapePath {
                strokeWidth: 2; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                strokeColor: Qt.rgba(island.accent.r, island.accent.g, island.accent.b, 0.22)
                PathAngleArc { centerX: 14; centerY: 14; radiusX: 12.5; radiusY: 12.5; startAngle: -90; sweepAngle: 360 }
            }
        }
        Shape {  // progress
            anchors.fill: parent; antialiasing: true
            visible: island.mediaLen > 0
            // ease the once-a-second position ticks, but SNAP on any rewind
            // (track change, seek back) — easing a shrinking sweep plays the
            // whole ring backwards for 900 ms
            NumberAnimation { id: chipArcAnim; target: chipArc; property: "sweepAngle"; duration: 900; easing.type: Easing.OutSine }
            ShapePath {
                strokeWidth: 2; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                strokeColor: island.accent
                PathAngleArc {
                    id: chipArc
                    centerX: 14; centerY: 14; radiusX: 12.5; radiusY: 12.5
                    startAngle: -90
                    readonly property real target: 360 * island.mediaFrac
                    onTargetChanged: {
                        chipArcAnim.stop()
                        if (target < sweepAngle) {
                            sweepAngle = target
                        } else {
                            chipArcAnim.to = target
                            chipArcAnim.start()
                        }
                    }
                    Component.onCompleted: sweepAngle = target
                }
            }
        }
        // tap the art = play/pause without expanding (touch: no hover-expand there)
        MouseArea {
            anchors.fill: parent; anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: if (island.player) island.player.togglePlaying()
        }
    }
    Row {
        spacing: 2; height: 16; anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: 5
            Rectangle {
                width: 2.5; radius: 1.25; color: island.accent
                anchors.verticalCenter: parent.verticalCenter
                height: island.eqHeight(index)
                Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutSine } }
            }
        }
    }
    // central gap + trailing clock (Apple leading/trailing split)
    Item { width: Theme.spacingM; height: 1; anchors.verticalCenter: parent.verticalCenter }
    StyledText {
        text: island.clockShort
        color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true
        anchors.verticalCenter: parent.verticalCenter
    }
}
