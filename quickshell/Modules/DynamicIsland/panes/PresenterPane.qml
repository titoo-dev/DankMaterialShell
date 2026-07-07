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
    width: (island ? island.presenterW : 320) - Theme.spacingL * 2
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
        // the glyph springs in on appearance and whenever the state swaps it
        // (volume→brightness, plug→unplug, queued splashes) — one-shot each time
        SequentialAnimation {
            id: glyphIn
            NumberAnimation { target: pIcon; property: "scale"; from: 0.55; to: 1.12; duration: 130; easing.type: Easing.OutQuad }
            SpringAnimation { target: pIcon; property: "scale"; to: 1.0; spring: 5; damping: 0.25; epsilon: 0.005 }
        }
    }
    Connections {
        target: island
        function onPresenterIconChanged() { if (presenterPane.visible && !island.reduceMotion) glyphIn.restart() }
    }
    onVisibleChanged: if (visible && !island.reduceMotion) glyphIn.restart()
    MouseArea {  // volume OSD: the icon is a mute toggle
        anchors.fill: pIcon; anchors.margins: -6
        visible: island.presenterKind === "volume"
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (island.audioNode) island.audioNode.muted = !island.audioNode.muted
            island.holdPresenter()
        }
        Accessible.role: Accessible.CheckBox
        Accessible.name: I18n.tr("Mute")
        Accessible.checked: island.muted
        Accessible.onPressAction: clicked(null)
    }
    // thin capsule level bar, draggable to set the level directly
    Item {
        id: segBar
        anchors.left: pIcon.right; anchors.leftMargin: Theme.spacingM
        anchors.right: pVal.left; anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        height: 4
        visible: !presenterPane.isSplash
        readonly property bool adjustable: island.presenterKind === "volume" || island.presenterKind === "brightness"
        // Scale against the same denominator the system VolumeOSD uses
        // (island.presenterMax == AudioService.sinkMaxVolume for volume, else 100)
        // so this bar and the OSD bar fill identically for the same level.
        readonly property real frac: Math.max(0, Math.min(1, island.presenterValue / island.presenterMax))
        Rectangle {  // track
            anchors.fill: parent; radius: height / 2
            color: Theme.surfaceVariant
        }
        Rectangle {  // fill
            width: parent.width * segBar.frac
            height: parent.height; radius: height / 2
            color: island.accent
            Behavior on width { NumberAnimation { duration: 80 } }
        }
        MouseArea {
            anchors.fill: parent; anchors.topMargin: -13; anchors.bottomMargin: -13
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
            Accessible.role: Accessible.Slider
            Accessible.name: island.presenterKind === "brightness" ? I18n.tr("Brightness") : I18n.tr("Volume")
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
        id: pSplashLbl
        anchors.left: pIcon.right; anchors.leftMargin: Theme.spacingM
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: presenterPane.isSplash
        text: island.splashLabel
        elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
        color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
        // the label glides out of the glyph on every new splash — the text
        // change itself is the trigger, so queued activities each get the slide
        transform: Translate { id: splashSlide }
        SequentialAnimation {
            id: splashIn
            PropertyAction { target: splashSlide; property: "x"; value: 16 }
            NumberAnimation { target: splashSlide; property: "x"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        }
        onTextChanged: if (presenterPane.visible && !island.reduceMotion) splashIn.restart()
        onVisibleChanged: if (visible && !island.reduceMotion) splashIn.restart()
    }
}
