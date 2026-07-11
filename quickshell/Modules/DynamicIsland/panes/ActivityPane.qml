import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// ACTIVITY (rest): the primary running activity — icon + label + progress + "+N".
Row {
    id: activityRow
    property var island: null
    readonly property var act: ActivityService.primary
    readonly property real contentWidth: implicitWidth
    anchors.centerIn: parent
    spacing: Theme.spacingS
    opacity: island.mode === "activity" ? 1 : 0
    visible: opacity > 0
    scale: island.mode === "activity" ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
    Behavior on scale { NumberAnimation { duration: Theme.mediumDuration } }

    DankIcon {
        id: actIcon
        anchors.verticalCenter: parent.verticalCenter
        name: activityRow.act ? activityRow.act.icon : "deployed_code"
        size: 16
        color: {
            if (!activityRow.act) return island.subText
            if (activityRow.act.state === "done" || activityRow.act.state === "idle") return Theme.success
            if (activityRow.act.state === "failed") return Theme.error
            if (activityRow.act.state === "waiting") return Theme.warning
            return island.accent
        }
        // (color transitions come from DankIcon's own internal Behavior)
        // micro-life, all finite: a pop when the icon swaps (state change), a
        // 3-beat pulse when something starts waiting, and a tick per tool call
        onNameChanged: if (visible && !island.reduceMotion) iconPop.restart()
        SequentialAnimation {
            id: iconPop
            NumberAnimation { target: actIcon; property: "scale"; to: 1.35; duration: Theme.shortDuration; easing.type: Easing.OutQuad }
            NumberAnimation { target: actIcon; property: "scale"; to: 1.0; duration: Theme.mediumDuration; easing.type: Easing.OutBack }
        }
        readonly property bool isWaiting: activityRow.act !== null && activityRow.act.state === "waiting"
        onIsWaitingChanged: {
            if (isWaiting && visible && !island.reduceMotion) {
                waitPulse.restart()
            } else {
                waitPulse.stop()
                opacity = 1
            }
        }
        SequentialAnimation {
            id: waitPulse
            loops: 3
            NumberAnimation { target: actIcon; property: "opacity"; to: 0.35; duration: 350; easing.type: Easing.InOutSine }
            NumberAnimation { target: actIcon; property: "opacity"; to: 1.0; duration: 350; easing.type: Easing.InOutSine }
        }
        Connections {
            target: AgentService
            enabled: activityRow.visible && !island.reduceMotion
            function onSessionActivity(sid) {
                // only tick for the session the pill is showing
                if (activityRow.act && activityRow.act.id === "agent-" + sid && !iconPop.running && !waitPulse.running)
                    iconTick.restart()
            }
        }
        SequentialAnimation {
            id: iconTick
            NumberAnimation { target: actIcon; property: "scale"; to: 1.12; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: actIcon; property: "scale"; to: 1.0; duration: 160; easing.type: Easing.InOutQuad }
        }
    }
    StyledText {
        id: actLabel
        anchors.verticalCenter: parent.verticalCenter
        text: {
            if (!activityRow.act) return ""
            if (activityRow.act.state === "done") return "✓ " + activityRow.act.label
            if (activityRow.act.state === "failed") return "✗ " + activityRow.act.label
            return activityRow.act.label
        }
        color: island.textColor
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
        elide: Text.ElideRight
        maximumLineCount: 1  // StyledText defaults to WordWrap — long agent titles must elide, not stack
        width: Math.min(implicitWidth, 200)
        // soft settle when the label content changes (new task, state prefix)
        onTextChanged: if (visible && !island.reduceMotion) labelIn.restart()
        NumberAnimation { id: labelIn; target: actLabel; property: "opacity"; from: 0.35; to: 1.0; duration: Theme.mediumDuration }
    }
    Item {  // progress bar: determinate only — indeterminate shows the static ellipsis below
        width: 48; height: 4
        anchors.verticalCenter: parent.verticalCenter
        visible: activityRow.act && activityRow.act.state === "running" && activityRow.act.progress >= 0
        Rectangle {
            anchors.fill: parent; radius: height / 2
            color: Theme.surfaceVariant
        }
        Rectangle {
            height: parent.height; radius: height / 2
            width: parent.width * ((activityRow.act ? Math.max(0, activityRow.act.progress) : 0) / 100)
            color: island.accent
            Behavior on width { NumberAnimation { duration: Theme.shortDuration } }
        }
    }
    StyledText {  // indeterminate "working" hint — static, no loop
        anchors.verticalCenter: parent.verticalCenter
        visible: activityRow.act && activityRow.act.state === "running" && activityRow.act.progress < 0
        text: "•••"
        color: island.subText
        font.pixelSize: Theme.fontSizeSmall
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        visible: activityRow.act && activityRow.act.state === "running" && activityRow.act.progress >= 0
        text: (activityRow.act ? activityRow.act.progress : 0) + "%"
        color: island.subText
        font.pixelSize: Theme.fontSizeSmall
    }
    Rectangle {  // +N badge — amber when someone besides the primary needs the user
        id: badge
        anchors.verticalCenter: parent.verticalCenter
        visible: ActivityService.runningCount > 1
        readonly property bool hotBehind: ActivityService.activities.some(a => a.state === "waiting" && (!activityRow.act || a.id !== activityRow.act.id))
        readonly property color tone: hotBehind ? Theme.warning : island.accent
        width: badgeText.implicitWidth + 10; height: 16; radius: 8
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.2)
        Behavior on color { ColorAnimation { duration: Theme.mediumDuration } }
        onVisibleChanged: if (visible && !island.reduceMotion) badgePop.restart()
        SequentialAnimation {
            id: badgePop
            NumberAnimation { target: badge; property: "scale"; from: 0.4; to: 1.15; duration: Theme.shortDuration; easing.type: Easing.OutQuad }
            NumberAnimation { target: badge; property: "scale"; to: 1.0; duration: Theme.shortDuration; easing.type: Easing.OutBack }
        }
        StyledText {
            id: badgeText; anchors.centerIn: parent
            text: "+" + (ActivityService.runningCount - 1)
            color: parent.tone; font.pixelSize: 10; font.bold: true
        }
    }
}
