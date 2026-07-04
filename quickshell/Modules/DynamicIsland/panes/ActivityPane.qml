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
        anchors.verticalCenter: parent.verticalCenter
        name: activityRow.act ? activityRow.act.icon : "deployed_code"
        size: 16
        color: {
            if (!activityRow.act) return island.subText
            if (activityRow.act.state === "done") return Theme.success
            if (activityRow.act.state === "failed") return Theme.error
            return island.accent
        }
        RotationAnimation on rotation {
            running: activityRow.act && activityRow.act.state === "running" && activityRow.act.progress < 0
            from: 0; to: 360; duration: 1400; loops: Animation.Infinite
        }
    }
    StyledText {
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
        width: Math.min(implicitWidth, 200)
    }
    Item {  // progress: determinate fill OR indeterminate slider
        width: 48; height: 4
        anchors.verticalCenter: parent.verticalCenter
        visible: activityRow.act && activityRow.act.state === "running"
        Rectangle {
            anchors.fill: parent; radius: height / 2
            color: Theme.surfaceVariant
        }
        Rectangle {
            visible: activityRow.act && activityRow.act.progress >= 0
            height: parent.height; radius: height / 2
            width: parent.width * ((activityRow.act ? Math.max(0, activityRow.act.progress) : 0) / 100)
            color: island.accent
            Behavior on width { NumberAnimation { duration: Theme.shortDuration } }
        }
        Rectangle {
            id: indeterminate
            visible: activityRow.act && activityRow.act.progress < 0
            height: parent.height; radius: height / 2; width: parent.width * 0.4
            color: island.accent
            SequentialAnimation on x {
                running: indeterminate.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: 28; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 28; to: 0; duration: 900; easing.type: Easing.InOutQuad }
            }
        }
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        visible: activityRow.act && activityRow.act.state === "running" && activityRow.act.progress >= 0
        text: (activityRow.act ? activityRow.act.progress : 0) + "%"
        color: island.subText
        font.pixelSize: Theme.fontSizeSmall
    }
    Rectangle {  // +N badge
        anchors.verticalCenter: parent.verticalCenter
        visible: ActivityService.runningCount > 1
        width: badgeText.implicitWidth + 10; height: 16; radius: 8
        color: Qt.rgba(island.accent.r, island.accent.g, island.accent.b, 0.2)
        StyledText {
            id: badgeText; anchors.centerIn: parent
            text: "+" + (ActivityService.runningCount - 1)
            color: island.accent; font.pixelSize: 10; font.bold: true
        }
    }
}
