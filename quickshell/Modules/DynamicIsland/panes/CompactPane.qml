import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// COMPACT (rest): split leading-status | notch gap | trailing-clock.
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

    // leading cluster: privacy (mic/cam/screen-share) + battery-low
    Row {
        id: cStatus
        spacing: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        visible: island.privacyActive || (island.batAvailable && island.batPct <= 20 && !island.charging)
        // iOS colour language: orange = microphone, green = camera
        DankIcon { visible: PrivacyService.microphoneActive; name: "mic"; size: 14; color: Theme.warning; filled: true; anchors.verticalCenter: parent.verticalCenter }
        DankIcon { visible: PrivacyService.cameraActive; name: "videocam"; size: 14; color: Theme.success; filled: true; anchors.verticalCenter: parent.verticalCenter }
        DankIcon { visible: PrivacyService.screensharingActive; name: "screen_share"; size: 14; color: Theme.warning; filled: true; anchors.verticalCenter: parent.verticalCenter }
        DankIcon { visible: island.batAvailable && island.batPct <= 20 && !island.charging; name: Theme.getBatteryIcon(island.batPct, island.charging, island.batAvailable); size: 14; color: Theme.error; anchors.verticalCenter: parent.verticalCenter }
    }
    // central "notch" gap — only present when the leading cluster has content
    Item { width: Theme.spacingL; height: 1; anchors.verticalCenter: parent.verticalCenter; visible: cStatus.visible }
    // trailing cluster: clock
    StyledText {
        text: island.clockShort
        color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
        anchors.verticalCenter: parent.verticalCenter
    }
}
