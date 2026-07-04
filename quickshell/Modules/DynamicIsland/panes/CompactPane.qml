import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// COMPACT (rest): just the clock — ongoing states (privacy capture, battery
// low) detach into the satellite bubble instead of crowding the pill (iOS).
// Reads island state via `island`; exposes `contentWidth` for pill geometry.
Row {
    id: compactRow
    property var island: null
    readonly property real contentWidth: implicitWidth
    anchors.centerIn: parent
    spacing: Theme.spacingXS
    opacity: island.mode === "compact" ? 1 : 0
    visible: opacity > 0
    scale: island.mode === "compact" ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
    Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

    StyledText {
        text: island.clockShort
        color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
        anchors.verticalCenter: parent.verticalCenter
    }
    // Shelf badge: something is parked on the island (count, accent-tinted)
    Row {
        visible: ShelfService.count > 0
        spacing: 2
        anchors.verticalCenter: parent.verticalCenter
        DankIcon {
            name: "place_item"; size: 13; color: island.accent
            anchors.verticalCenter: parent.verticalCenter
        }
        StyledText {
            text: ShelfService.count
            color: island.accent; font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
