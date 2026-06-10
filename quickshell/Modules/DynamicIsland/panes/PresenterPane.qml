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
    MouseArea {  // volume OSD: the icon is a mute toggle
        anchors.fill: pIcon; anchors.margins: -6
        visible: island.presenterKind === "volume"
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (island.audioNode) island.audioNode.muted = !island.audioNode.muted
            island.holdPresenter()
        }
    }
    // 16 discrete segments (macOS OSD), draggable to set the level directly
    Item {
        id: segBar
        anchors.left: pIcon.right; anchors.leftMargin: Theme.spacingM
        anchors.right: pVal.left; anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        height: 10
        visible: !presenterPane.isSplash
        readonly property int segs: 16
        readonly property real segGap: 2
        readonly property bool adjustable: island.presenterKind === "volume" || island.presenterKind === "brightness"
        readonly property real frac: Math.max(0, Math.min(1, island.presenterValue / 100))
        Row {
            anchors.fill: parent
            spacing: segBar.segGap
            Repeater {
                model: segBar.segs
                Rectangle {
                    width: (segBar.width - (segBar.segs - 1) * segBar.segGap) / segBar.segs
                    height: parent.height; radius: 2
                    color: (index + 0.5) / segBar.segs <= segBar.frac ? island.accent : Theme.surfaceVariant
                    Behavior on color { ColorAnimation { duration: 80 } }
                }
            }
        }
        MouseArea {
            anchors.fill: parent; anchors.topMargin: -10; anchors.bottomMargin: -10
            enabled: segBar.adjustable
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            function apply(mx) {
                const f = Math.max(0, Math.min(1, mx / segBar.width))
                if (island.presenterKind === "volume" && island.audioNode) {
                    island.audioNode.muted = false
                    island.audioNode.volume = f
                } else if (island.presenterKind === "brightness") {
                    DisplayService.setBrightness(Math.round(f * 100), "", true)
                }
                island.holdPresenter()
            }
            onPressed: mouse => apply(mouse.x)
            onPositionChanged: mouse => { if (pressed) apply(mouse.x) }
        }
    }
    StyledText {
        id: pVal
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        // muted ≠ 0%: say so instead of lying about the level (macOS shows the
        // slashed icon + empty bar, never a fake value)
        text: (island.presenterKind === "volume" && island.muted) ? I18n.tr("Muted") : island.presenterValue + "%"
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
