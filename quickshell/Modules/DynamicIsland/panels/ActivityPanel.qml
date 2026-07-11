import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Activities drill view: lists every live activity with progress + a dismiss button.
Column {
    id: actCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "activities" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "activities" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    DrillHeader { island: actCol.island; title: I18n.tr("Activities") }
    StyledText {
        width: parent.width
        visible: ActivityService.activities.length === 0 && ActivityService.recents.length === 0
        horizontalAlignment: Text.AlignHCenter
        topPadding: Theme.spacingM; bottomPadding: Theme.spacingM
        text: I18n.tr("No activities")
        font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText
    }
    Repeater {
        model: ActivityService.activities
        delegate: Rectangle {
            required property var modelData
            width: parent.width
            height: aRow.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHighest
            RowLayout {
                id: aRow
                anchors.fill: parent; anchors.margins: Theme.spacingS; spacing: Theme.spacingS
                DankIcon {
                    name: modelData.state === "done" ? "check_circle" : modelData.state === "failed" ? "error" : modelData.state === "waiting" ? "front_hand" : modelData.icon
                    size: 18
                    color: modelData.state === "done" || modelData.state === "idle" ? Theme.success : modelData.state === "failed" ? Theme.error : modelData.state === "waiting" ? Theme.warning : Theme.primary
                    Layout.alignment: Qt.AlignVCenter
                }
                Column {
                    Layout.fillWidth: true; spacing: 2
                    StyledText {
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold
                        color: Theme.surfaceText; width: parent.width; elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Rectangle {
                        visible: modelData.state === "running" && modelData.progress >= 0
                        width: parent.width; height: 4; radius: 2
                        color: Qt.rgba(Theme.surfaceVariantText.r, Theme.surfaceVariantText.g, Theme.surfaceVariantText.b, 0.3)
                        Rectangle { height: parent.height; radius: 2; width: parent.width * (modelData.progress / 100); color: Theme.primary }
                    }
                    StyledText {
                        visible: modelData.state === "running" && modelData.progress < 0
                        text: I18n.tr("running…")
                        font.pixelSize: 10; color: Theme.surfaceVariantText
                    }
                }
                DankActionButton {
                    iconName: "close"; buttonSize: 20; iconSize: 12
                    radius: buttonSize / 2
                    iconColor: Theme.surfaceVariantText
                    onClicked: ActivityService.dismiss(modelData.id)
                }
            }
        }
    }

    // ---- Recents: the last glanceable pops (splashes are fire-and-forget) ----
    StyledText {
        visible: ActivityService.recents.length > 0
        topPadding: Theme.spacingS
        text: I18n.tr("Recent")
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall - 2; font.bold: true
        font.capitalization: Font.AllUppercase
    }
    Repeater {
        model: ActivityService.recents.slice(0, 8)
        delegate: RowLayout {
            required property var modelData
            width: parent.width
            spacing: Theme.spacingS
            DankIcon {
                name: modelData.icon; size: 16
                color: Theme.surfaceVariantText
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                text: modelData.label
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            StyledText {
                text: Qt.formatTime(new Date(modelData.ts), "HH:mm")
                font.pixelSize: Theme.fontSizeSmall - 2
                color: Theme.surfaceVariantText
            }
        }
    }
}
