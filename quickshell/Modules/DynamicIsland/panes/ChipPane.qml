import QtQuick
import QtQuick.Shapes
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
    Item {  // album art wrapped in a circular progress ring (Apple "Live Activity" feel)
        width: 26; height: 26
        anchors.verticalCenter: parent.verticalCenter
        Shape {  // faint track
            anchors.fill: parent; antialiasing: true
            visible: island.mediaLen > 0
            ShapePath {
                strokeWidth: 2; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                strokeColor: Qt.rgba(island.accent.r, island.accent.g, island.accent.b, 0.22)
                PathAngleArc { centerX: 13; centerY: 13; radiusX: 11.5; radiusY: 11.5; startAngle: -90; sweepAngle: 360 }
            }
        }
        Shape {  // progress
            anchors.fill: parent; antialiasing: true
            visible: island.mediaLen > 0
            ShapePath {
                strokeWidth: 2; capStyle: ShapePath.RoundCap; fillColor: "transparent"
                strokeColor: island.accent
                PathAngleArc {
                    centerX: 13; centerY: 13; radiusX: 11.5; radiusY: 11.5
                    startAngle: -90; sweepAngle: 360 * island.mediaFrac
                    Behavior on sweepAngle { NumberAnimation { duration: 900; easing.type: Easing.OutSine } }
                }
            }
        }
        Rectangle {
            width: 20; height: 20; radius: 6; clip: true; color: Theme.primaryBackground
            anchors.centerIn: parent
            Image { anchors.fill: parent; source: island.player ? (island.player.trackArtUrl ?? "") : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
            DankIcon { anchors.centerIn: parent; name: "music_note"; size: 12; color: island.accent; visible: !(island.player && island.player.trackArtUrl) }
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
    // central "notch" gap + trailing clock (Apple leading/trailing split)
    Item { width: Theme.spacingM; height: 1; anchors.verticalCenter: parent.verticalCenter }
    StyledText {
        text: island.clockShort
        color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true
        anchors.verticalCenter: parent.verticalCenter
    }
}
