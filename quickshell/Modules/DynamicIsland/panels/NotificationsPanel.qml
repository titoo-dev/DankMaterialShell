import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// Notifications detail view (drill-down, island-styled). Reads/writes island state via `island`.
Column {
    id: notifCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "notifications" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "notifications" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    // header: back · title · clear-all
    Item {
        width: parent.width; height: 34
        Rectangle {
            id: nBack
            width: 30; height: 30; radius: width / 2
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: nBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: nBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: nBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
        }
        StyledText {
            anchors.left: nBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Notifications"); color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
        }
        Rectangle {  // clear all
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: clrLabel.implicitWidth + Theme.spacingM; height: 28; radius: 14
            visible: (NotificationService.notifications || []).length > 0
            color: clrArea.containsMouse ? Theme.primary : Theme.surfaceLight
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            StyledText { id: clrLabel; anchors.centerIn: parent; text: I18n.tr("Clear all"); font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true; color: clrArea.containsMouse ? Theme.primaryText : island.subText }
            MouseArea { id: clrArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: NotificationService.clearAllNotifications() }
        }
    }

    // scrollable notification list — adaptive height, capped
    Flickable {
        width: parent.width; height: Math.min(nlist.height, 300); clip: true
        contentHeight: nlist.height
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: nlist
            width: parent.width; spacing: 4
            StyledText {
                width: parent.width; height: 56
                visible: (NotificationService.notifications || []).length === 0
                text: I18n.tr("No notifications"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: NotificationService.notifications
                Rectangle {
                    id: nRow
                    width: nlist.width; height: 66; radius: 14
                    color: nRowArea.containsMouse ? Theme.surfaceLight : Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.4)
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                    ClippingRectangle {
                        id: nRowIco
                        // true rounded clip (bbox `clip` left the corners square)
                        width: 38; height: 38; radius: 11
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        color: Theme.primaryBackground
                        Image {
                            id: nRowImg
                            anchors.fill: parent; anchors.margins: 5
                            // appIcon is often a THEME ICON NAME, not a URL — resolve it,
                            // and never hand a bare name to Image (silent failure)
                            source: {
                                if (modelData.cleanImage) return modelData.cleanImage
                                const icon = modelData.appIcon || ""
                                if (!icon) return ""
                                if (icon.startsWith("file://") || icon.startsWith("http://") || icon.startsWith("https://") || icon.includes("/"))
                                    return icon
                                return Quickshell.iconPath(icon, true)
                            }
                            sourceSize.width: 76; sourceSize.height: 76   // decode at 2× box, not full size
                            fillMode: Image.PreserveAspectFit; cache: false; asynchronous: true
                            visible: status === Image.Ready
                        }
                        DankIcon { anchors.centerIn: parent; name: "notifications"; size: 18; color: island.accent; visible: nRowImg.status !== Image.Ready }
                    }
                    Column {
                        anchors.left: nRowIco.right; anchors.leftMargin: Theme.spacingM
                        anchors.right: nRowRight.left; anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter; spacing: 1
                        Row {
                            width: parent.width; spacing: Theme.spacingXS
                            StyledText { text: (modelData.appName || ""); color: island.accent; font.pixelSize: Theme.fontSizeSmall - 2; font.bold: true; font.capitalization: Font.AllUppercase; elide: Text.ElideRight; width: Math.min(implicitWidth, parent.width - 60) }
                            StyledText { text: (modelData.timeStr || ""); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                        }
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (modelData.summary || modelData.appName || ""); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (modelData.plainBody || ""); visible: text.length > 0; color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1 }
                    }
                    Rectangle {  // per-row dismiss
                        id: nRowRight
                        width: 26; height: 26; radius: 13
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                        color: nClose.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : "transparent"
                        opacity: nRowArea.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                        DankIcon { anchors.centerIn: parent; name: "close"; size: 15; color: nClose.containsMouse ? Theme.error : island.subText }
                        MouseArea { id: nClose; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: NotificationService.dismissNotification(modelData) }
                    }
                    MouseArea {
                        id: nRowArea; anchors.fill: parent; hoverEnabled: true; z: -1
                        onClicked: {
                            // invoke the notification's DEFAULT action (body click), never
                            // an arbitrary actions[0] which may be "Delete"/"Archive"
                            var def = null
                            if (modelData.actions) {
                                for (var i = 0; i < modelData.actions.length; i++) {
                                    const a = modelData.actions[i]
                                    if (a && a.identifier === "default") { def = a; break }
                                }
                            }
                            if (def && def.invoke) { def.invoke(); NotificationService.dismissNotification(modelData) }
                        }
                    }
                }
            }
        }
    }
}
