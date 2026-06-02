import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// PRESENTER: volume / brightness / battery OSD + Bluetooth splash.
// FIXED width (matches presenter pillW - margins) so the progress bar keeps its
// correct proportion and just scales/fades in. Reads island state via `island`.
Item {
    id: presenterPane
    property var island: null
    width: 320 - Theme.spacingL * 2
    height: parent.height
    anchors.centerIn: parent
    opacity: island.mode === "presenter" ? 1 : 0
    visible: opacity > 0
    scale: island.mode === "presenter" ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
    Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

    readonly property bool isSplash: island.presenterKind === "splash"

    DankIcon {
        id: pIcon
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        name: island.presenterIcon; size: 24; color: island.accent
    }
    Rectangle {
        anchors.left: pIcon.right; anchors.leftMargin: Theme.spacingM
        anchors.right: pVal.left; anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        height: 6; radius: 3; color: Theme.surfaceVariant
        visible: !presenterPane.isSplash
        Rectangle {
            // parent width is now constant → only animates on real value changes
            width: parent.width * Math.max(0, Math.min(1, island.presenterValue / 100))
            height: parent.height; radius: parent.radius; color: island.accent
            Behavior on width { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.emphasizedEasing } }
        }
    }
    StyledText {
        id: pVal
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        text: island.presenterValue + "%"
        visible: !presenterPane.isSplash
        color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
    }
    StyledText {  // splash label (e.g. "AirPods connected")
        anchors.left: pIcon.right; anchors.leftMargin: Theme.spacingM
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: presenterPane.isSplash
        text: island.splashLabel
        elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
        color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
    }
}
