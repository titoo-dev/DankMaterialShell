import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// COMPACT (rest): just the clock — ongoing states (privacy capture, battery
// low) detach into the satellite bubble instead of crowding the pill (iOS).
// In notch mode the content flanks a central "camera" instead (MacBook):
// leading weather/date | lens | trailing clock.
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

    // leading cluster (notch mode only): weather, or the date when unavailable
    Row {
        visible: island.notchMode
        spacing: 3
        anchors.verticalCenter: parent.verticalCenter
        DankIcon {
            visible: island.weatherReady
            name: island.weatherIcon; size: 13; color: island.subText
            anchors.verticalCenter: parent.verticalCenter
        }
        StyledText {
            text: island.weatherReady ? island.weatherTemp : island.dayShort
            color: island.subText; font.pixelSize: Theme.fontSizeSmall
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    CameraLens { visible: island.notchMode; anchors.verticalCenter: parent.verticalCenter }
    StyledText {
        text: island.clockShort
        color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
        anchors.verticalCenter: parent.verticalCenter
    }
}
