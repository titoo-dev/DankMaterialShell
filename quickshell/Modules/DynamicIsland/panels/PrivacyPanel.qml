import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Common
import qs.Services
import qs.Widgets

// Privacy detail view (drill-down): WHO is capturing the mic / camera / screen
// right now — the satellite bubble's per-activity expanded layout. Live list
// straight from the Pipewire graph, mic streams get an inline mute kill-switch.
// Reads/writes island state via `island`.
Column {
    id: privCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "privacy" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "privacy" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    // hold the stream nodes' properties live while the view is open (muted
    // state, app names); gated so the tracker idles when the island rests
    PwObjectTracker { objects: privCol.visible && Pipewire.nodes?.values ? Pipewire.nodes.values.filter(n => n && n.isStream) : [] }

    // active capture streams, same heuristics as PrivacyService's booleans but
    // kept per-node so each capture shows as its own row
    readonly property var captures: {
        if (!visible || !Pipewire.ready || !Pipewire.nodes?.values) return []
        const out = []
        for (const node of Pipewire.nodes.values) {
            if (!node) continue
            const props = node.properties || {}
            const app = props["application.name"] || props["media.name"] || node.name || I18n.tr("Unknown app")
            if ((node.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream
                    && !PrivacyService.looksLikeSystemVirtualMic(node)) {
                out.push({ kind: "mic", icon: "mic", tint: Theme.warning, app: app, what: I18n.tr("Microphone"), node: node })
            } else if (props["media.class"] === "Stream/Input/Video" && props["stream.is-live"] === "true") {
                if (PrivacyService.looksLikeScreencast(node))
                    out.push({ kind: "screenshare", icon: "screen_share", tint: Theme.warning, app: app, what: I18n.tr("Screen sharing"), node: node })
                else
                    out.push({ kind: "cam", icon: "videocam", tint: Theme.success, app: app, what: I18n.tr("Camera"), node: node })
            } else if (((node.type & PwNodeType.VideoSource) === PwNodeType.VideoSource
                        || props["media.class"] === "Stream/Output/Video")
                       && PrivacyService.looksLikeScreencast(node)) {
                out.push({ kind: "screenshare", icon: "screen_share", tint: Theme.warning, app: app, what: I18n.tr("Screen sharing"), node: node })
            }
        }
        return out
    }

    // header: back · title
    DrillHeader {
        island: privCol.island; title: I18n.tr("Privacy")
        // live status chip mirroring the satellite's pulse
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: privCol.captures.length > 0
            width: pvLive.implicitWidth + Theme.spacingM; height: 24; radius: 12
            color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.15)
            StyledText {
                id: pvLive
                anchors.centerIn: parent
                text: I18n.tr("%1 active").arg(privCol.captures.length)
                color: Theme.warning; font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true
            }
        }
    }

    // empty state: nothing is capturing (the capture ended while drilling in)
    StyledText {
        width: parent.width; height: 52
        visible: privCol.captures.length === 0
        text: I18n.tr("Nothing is using your microphone, camera or screen")
        color: island.subText; font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: privCol.captures
        Rectangle {
            required property var modelData
            readonly property var pwNode: modelData.node
            readonly property bool canMute: modelData.kind === "mic" && pwNode && pwNode.audio
            readonly property bool isMuted: canMute ? pwNode.audio.muted : false
            width: privCol.width; height: 56; radius: 14
            color: Theme.surfaceLight
            Rectangle {  // kind orb, pulsing like the satellite
                id: pvOrb
                width: 36; height: 36; radius: 18
                anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(modelData.tint.r, modelData.tint.g, modelData.tint.b, 0.16)
                DankIcon {
                    anchors.centerIn: parent
                    name: modelData.icon; size: 18; color: modelData.tint; filled: true
                    SequentialAnimation on scale {
                        running: privCol.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.15; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
            }
            Column {
                anchors.left: pvOrb.right; anchors.leftMargin: Theme.spacingM
                anchors.right: pvMute.visible ? pvMute.left : parent.right; anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                StyledText {
                    width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                    text: modelData.app; color: island.textColor
                    font.pixelSize: Theme.fontSizeSmall; font.bold: true
                }
                StyledText {
                    width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                    text: modelData.what; color: modelData.tint
                    font.pixelSize: Theme.fontSizeSmall - 2; font.bold: true
                    font.capitalization: Font.AllUppercase
                }
            }
            Rectangle {  // mic kill-switch: mutes the capture stream itself
                id: pvMute
                visible: parent.canMute
                width: pvMuteLbl.implicitWidth + Theme.spacingL; height: 28; radius: 14
                anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                color: parent.isMuted ? Theme.error : (pvMuteArea.containsMouse ? Theme.primaryHover : Theme.surfaceVariant)
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                scale: pvMuteArea.pressed ? 0.92 : 1.0
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                StyledText {
                    id: pvMuteLbl
                    anchors.centerIn: parent
                    text: parent.parent.isMuted ? I18n.tr("Unmute") : I18n.tr("Mute")
                    color: parent.parent.isMuted ? Theme.primaryText : island.textColor
                    font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true
                }
                MouseArea {
                    id: pvMuteArea
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { if (parent.parent.pwNode && parent.parent.pwNode.audio) parent.parent.pwNode.audio.muted = !parent.parent.pwNode.audio.muted }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: I18n.tr("Mute")
                    Accessible.checked: parent.parent.isMuted
                    Accessible.onPressAction: clicked(null)
                }
            }
        }
    }

    // footnote: muting a mic stream silences what the app hears, it does not
    // stop the app from holding the device
    StyledText {
        width: parent.width
        visible: privCol.captures.some(c => c.kind === "mic")
        text: I18n.tr("Muting silences the stream without closing the app's capture")
        color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
}
