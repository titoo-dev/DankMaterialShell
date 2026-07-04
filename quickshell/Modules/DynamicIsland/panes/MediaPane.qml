import QtQuick
import QtQuick.Controls
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// MEDIA (hover + playing): art | title/artist + inline progress | transport.
// Everything vertically balanced for the floating capsule (side margins clear
// the corner curves). Reads island state via `island`; exposes
// `titleW`/`controlsWidth` for pill geometry.
Item {
    id: mediaPane
    property var island: null
    readonly property real titleW: Math.min(Math.max(mTitle.textWidth, mArtist.implicitWidth), 360)
    readonly property real controlsWidth: controls.implicitWidth
    anchors.fill: parent
    anchors.leftMargin: 22; anchors.rightMargin: 16
    opacity: island.mode === "media" ? 1 : 0
    visible: opacity > 0
    onVisibleChanged: if (!visible) island.seekHover = false
    scale: island.mode === "media" ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
    Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

    ClippingRectangle {
        id: art
        // true rounded clip: bbox `clip` let the square art cover the radius
        width: 50; height: 50; radius: 14
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        color: Theme.primaryBackground
        scale: artArea.pressed ? 0.92 : (artArea.containsMouse ? 1.06 : 1.0)
        Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
        Image {
            id: mArtImg
            anchors.fill: parent
            source: island.player ? (island.player.trackArtUrl ?? "") : ""
            fillMode: Image.PreserveAspectCrop
            cache: false; asynchronous: true
            visible: status === Image.Ready
        }
        DankIcon {
            anchors.centerIn: parent; name: "music_note"
            size: 22; color: island.accent
            // fall back on the REAL load status (art URLs are often transient
            // tmp files that vanish) — never leave an empty box
            visible: mArtImg.status !== Image.Ready
        }
        // click the art = jump to the player app (macOS Now Playing behaviour)
        MouseArea {
            id: artArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: island.player && island.player.canRaise ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (island.player && island.player.canRaise) {
                    island.player.raise()
                    island.closeIsland()
                }
            }
        }
    }
    Column {
        anchors.left: art.right; anchors.leftMargin: Theme.spacingM
        anchors.right: controls.left; anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        // shift up to make room for the progress line at the bottom of the pill
        anchors.verticalCenterOffset: island.mediaLen > 0 ? -8 : 0
        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: Theme.shortDuration } }
        spacing: 2
        MarqueeText {   // long track titles shuttle instead of eliding (iOS ticker)
            id: mTitle
            width: parent.width
            centered: false
            text: island.player ? (island.player.trackTitle || I18n.tr("Unknown")) : ""
            color: island.textColor; pixelSize: Theme.fontSizeMedium; bold: true
        }
        // artist line, swapped for elapsed/remaining while hovering the scrubber
        Item {
            width: parent.width; height: mArtist.implicitHeight
            StyledText {
                id: mArtist
                width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                text: island.player ? (island.player.trackArtist || island.player.identity || "") : ""
                color: island.subText; font.pixelSize: Theme.fontSizeSmall
                opacity: trackBar.timesShown ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
            }
            StyledText {
                anchors.left: parent.left
                text: { island.mediaTick; return island.fmtTime(trackBar.seeking ? trackBar.seekFrac * island.mediaLen : (island.player ? island.player.position : 0)) }
                color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true
                opacity: trackBar.timesShown ? 0.9 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
            }
            StyledText {
                anchors.right: parent.right
                text: { island.mediaTick; return "-" + island.fmtTime(Math.max(0, island.mediaLen - (trackBar.seeking ? trackBar.seekFrac * island.mediaLen : (island.player ? island.player.position : 0)))) }
                color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true
                opacity: trackBar.timesShown ? 0.9 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
            }
        }
    }
    Row {
        id: controls
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Repeater {
            // STATIC model: the buttons live across play/pause/track changes (a
            // computed array model would destroy+recreate them on every change)
            model: ["prev", "play", "next"]
            Rectangle {
                readonly property bool big: modelData === "play"
                readonly property bool en: modelData === "play" ? !!island.player
                                         : modelData === "prev" ? !!(island.player && island.player.canGoPrevious)
                                         : !!(island.player && island.player.canGoNext)
                readonly property string glyph: modelData === "play" ? (island.playing ? "pause" : "play_arrow")
                                              : modelData === "prev" ? "skip_previous" : "skip_next"
                readonly property string label: modelData === "play" ? (island.playing ? I18n.tr("Pause") : I18n.tr("Play"))
                                              : modelData === "prev" ? I18n.tr("Previous") : I18n.tr("Next")
                function act() {
                    if (!island.player) return
                    if (modelData === "play") island.player.togglePlaying()
                    else if (modelData === "prev") island.player.previous()
                    else island.player.next()
                }
                width: big ? 38 : 32; height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                // hierarchy: accent-filled play disc, quiet ghost side buttons
                color: big ? island.accent : (cArea.containsMouse && en ? Theme.primaryHover : "transparent")
                opacity: en ? 1 : 0.35
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                scale: cArea.pressed && en ? 0.86 : (big && cArea.containsMouse ? 1.06 : 1.0)
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                DankIcon { anchors.centerIn: parent; name: parent.glyph; size: parent.big ? 22 : 18; color: parent.big ? Theme.primaryText : island.textColor; filled: true }
                ToolTip.visible: cArea.containsMouse && en
                ToolTip.text: label
                ToolTip.delay: 400
                MouseArea {
                    id: cArea; anchors.fill: parent; hoverEnabled: true
                    enabled: parent.en; cursorShape: Qt.PointingHandCursor
                    onClicked: parent.act()
                }
            }
        }
    }
    Rectangle {
        id: trackBar
        // scoped to the text column — never runs under the transport buttons
        // or into the capsule's corner curve
        anchors.left: art.right; anchors.leftMargin: Theme.spacingM
        anchors.right: controls.left; anchors.rightMargin: Theme.spacingM
        anchors.bottom: parent.bottom; anchors.bottomMargin: 15
        height: 3; radius: 1.5
        color: Theme.surfaceVariant
        // streams without a duration (radio, some browsers) get no scrubber (macOS)
        visible: island.mediaLen > 0
        property int tick: 0
        property bool seeking: false
        property real seekFrac: 0
        readonly property real frac: {
            trackBar.tick
            const len = MprisController.activePlayerStableLength
            return (island.player && len > 0) ? Math.min(1, island.player.position / len) : 0
        }
        readonly property real shownFrac: seeking ? seekFrac : frac
        Timer { interval: 1000; repeat: true; running: island.mode === "media" && island.playing && !trackBar.seeking; onTriggered: trackBar.tick++ }
        Rectangle {
            width: parent.width * trackBar.shownFrac; height: parent.height; radius: parent.radius
            color: island.accent
            Behavior on width { enabled: !trackBar.seeking; NumberAnimation { duration: 240 } }
        }
        // grab handle (visible while dragging)
        Rectangle {
            width: 10; height: 10; radius: 5; color: island.accent
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * trackBar.shownFrac - width / 2
            opacity: (seekArea.containsMouse || trackBar.seeking) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
        }
        MouseArea {
            id: seekArea
            anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !!(island.player && island.player.canSeek)
            preventStealing: true
            // tell the pill's volume WheelHandler to stand down over the scrubber
            onContainsMouseChanged: island.seekHover = containsMouse
            function fracAt(mx) { return Math.max(0, Math.min(1, mx / width)) }
            onPressed: mouse => { trackBar.seeking = true; trackBar.seekFrac = fracAt(mouse.x) }
            onPositionChanged: mouse => { if (trackBar.seeking) trackBar.seekFrac = fracAt(mouse.x) }
            onReleased: mouse => {
                const len = MprisController.activePlayerStableLength
                if (island.player && len > 0)
                    island.player.position = trackBar.seekFrac * len
                trackBar.seeking = false
            }
            onCanceled: trackBar.seeking = false
            // wheel on the scrubber = relative seek (macOS: ±5 s)
            onWheel: wheel => {
                const len = MprisController.activePlayerStableLength
                if (!island.player || len <= 0) return
                const next = Math.max(0, Math.min(len, island.player.position + (wheel.angleDelta.y > 0 ? 5 : -5)))
                island.player.position = next
            }
        }
        // elapsed / remaining revealed in the artist line while scrubbing/hovering
        property bool timesShown: (seekArea.containsMouse || trackBar.seeking) && island.mediaLen > 0
    }
}
