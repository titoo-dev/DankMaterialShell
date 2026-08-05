import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// Notifications detail view (drill-down, island-styled). Reads/writes island
// state via `island`. Two tabs: Active (live notifications, with inline reply
// for chat apps that declare it) and History (the persisted list, survives
// dismissals and shell restarts).
Column {
    id: notifCol
    property var island: null
    // 0 = active, 1 = history
    property int tab: 0
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "notifications" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "notifications" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
    onVisibleChanged: if (!visible) { tab = 0; replyTarget = null }

    // the live notification currently showing its inline-reply field (null = none)
    property var replyTarget: null

    function fmtStamp(ts) {
        if (!ts) return ""
        const d = new Date(ts)
        const now = new Date()
        const hm = Qt.formatTime(d, SettingsData.use24HourClock ? "HH:mm" : "h:mm ap")
        if (d.toDateString() === now.toDateString()) return hm
        const yesterday = new Date(now.getTime() - 86400000)
        if (d.toDateString() === yesterday.toDateString()) return I18n.tr("Yesterday") + " " + hm
        return Qt.formatDate(d, "ddd d MMM") + " " + hm
    }

    // header: back · title · contextual clear
    DrillHeader {
        island: notifCol.island; title: I18n.tr("Notifications")
        Rectangle {  // clear all (active) / clear history
            width: clrLabel.implicitWidth + Theme.spacingM; height: 28; radius: 14
            visible: notifCol.tab === 0 ? (NotificationService.notifications || []).length > 0
                                        : (NotificationService.historyList || []).length > 0
            color: clrArea.containsMouse ? Theme.primary : Theme.surfaceLight
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            StyledText { id: clrLabel; anchors.centerIn: parent; text: I18n.tr("Clear all"); font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true; color: clrArea.containsMouse ? Theme.primaryText : island.subText }
            MouseArea {
                id: clrArea; anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: notifCol.tab === 0 ? NotificationService.clearAllNotifications() : NotificationService.clearHistory()
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("Clear all")
                Accessible.onPressAction: clicked(null)
            }
        }
    }

    // segmented control: Active / History
    Row {
        spacing: Theme.spacingXS
        Repeater {
            model: [I18n.tr("Active"), I18n.tr("History")]
            Rectangle {
                readonly property bool on: notifCol.tab === index
                width: segLbl.implicitWidth + Theme.spacingL; height: 26; radius: 13
                color: on ? Theme.primarySelected : (segArea.containsMouse ? Theme.surfaceLight : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                StyledText {
                    id: segLbl; anchors.centerIn: parent
                    text: modelData + (index === 0 && (NotificationService.notifications || []).length > 0 ? " " + NotificationService.notifications.length : "")
                    font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true
                    color: on ? island.accent : island.subText
                }
                MouseArea {
                    id: segArea; anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { notifCol.tab = index; notifCol.replyTarget = null }
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData
                    Accessible.checked: on
                    Accessible.onPressAction: clicked(null)
                }
            }
        }
    }

    // ---- ACTIVE: live notifications, virtualized ----
    ListView {
        id: nlist
        visible: notifCol.tab === 0
        width: parent.width
        height: !visible ? 0 : (count === 0 ? 56 : Math.min(contentHeight, 300))
        clip: true; spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        model: NotificationService.notifications
        StyledText {
            anchors.centerIn: parent
            visible: nlist.count === 0
            text: I18n.tr("No notifications"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
        }
        delegate: Rectangle {
                    id: nRow
                    readonly property bool canReply: modelData && modelData.notification && modelData.notification.hasInlineReply === true
                    readonly property bool replyOpen: notifCol.replyTarget === modelData
                    width: nlist.width; height: 66 + (replyOpen ? 42 : 0); radius: 14
                    Behavior on height { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } }
                    color: nRowArea.containsMouse || replyOpen ? Theme.surfaceLight : Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.4)
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                    ClippingRectangle {
                        id: nRowIco
                        // true rounded clip (bbox `clip` left the corners square)
                        width: 38; height: 38; radius: 11
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM
                        anchors.top: parent.top; anchors.topMargin: 14
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
                        anchors.top: parent.top; anchors.topMargin: 12; spacing: 1
                        Row {
                            width: parent.width; spacing: Theme.spacingXS
                            StyledText { text: (modelData.appName || ""); color: island.accent; font.pixelSize: Theme.fontSizeSmall - 2; font.bold: true; font.capitalization: Font.AllUppercase; elide: Text.ElideRight; width: Math.min(implicitWidth, parent.width - 60) }
                            StyledText { text: (modelData.timeStr || ""); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                        }
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (modelData.summary || modelData.appName || ""); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (modelData.plainBody || ""); visible: text.length > 0; color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1 }
                    }
                    Row {  // reply (chat apps) + dismiss, revealed on hover
                        id: nRowRight
                        spacing: 2
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingS
                        anchors.top: parent.top; anchors.topMargin: 20
                        opacity: nRowArea.containsMouse || nRow.replyOpen ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            visible: nRow.canReply
                            color: nReply.containsMouse || nRow.replyOpen ? Theme.primarySelected : "transparent"
                            DankIcon { anchors.centerIn: parent; name: "reply"; size: 15; color: nReply.containsMouse || nRow.replyOpen ? island.accent : island.subText }
                            MouseArea {
                                id: nReply; anchors.fill: parent; anchors.margins: -4
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: notifCol.replyTarget = nRow.replyOpen ? null : modelData
                                Accessible.role: Accessible.Button
                                Accessible.name: I18n.tr("Reply")
                                Accessible.onPressAction: clicked(null)
                            }
                            DankTip { text: I18n.tr("Reply"); active: nReply.containsMouse }
                        }
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: nClose.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : "transparent"
                            DankIcon { anchors.centerIn: parent; name: "close"; size: 15; color: nClose.containsMouse ? Theme.error : island.subText }
                            MouseArea {
                                id: nClose; anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (nRow.replyOpen) notifCol.replyTarget = null; NotificationService.dismissNotification(modelData) }
                                Accessible.role: Accessible.Button
                                Accessible.name: I18n.tr("Dismiss")
                                Accessible.onPressAction: clicked(null)
                            }
                            DankTip { text: I18n.tr("Dismiss"); active: nClose.containsMouse }
                        }
                    }
                    // inline reply field — straight to the app via the
                    // notification's inline-reply channel (chat 1:1)
                    Row {
                        visible: nRow.replyOpen
                        spacing: Theme.spacingS
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingM; anchors.rightMargin: Theme.spacingM
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                        onVisibleChanged: if (visible) { nReplyField.text = ""; nReplyField.forceActiveFocus() }
                        function send() {
                            const n = modelData
                            const text = nReplyField.text
                            if (!text || text.length === 0) return
                            notifCol.replyTarget = null
                            if (n && n.notification && n.notification.hasInlineReply) {
                                n.notification.sendInlineReply(text)
                                NotificationService.dismissNotification(n)
                            }
                        }
                        Item {
                            id: nReplyEsc
                            // same rule as everywhere else in the island: Escape
                            // closes it (the panel is unloaded, so the pending
                            // reply goes with it)
                            Keys.onEscapePressed: island.closeIsland()
                        }
                        DankTextField {
                            id: nReplyField
                            width: parent.width - 40
                            height: 32
                            leftIconName: "reply"
                            placeholderText: I18n.tr("Reply…")
                            keyForwardTargets: [nReplyEsc]
                            onAccepted: parent.send()
                        }
                        Rectangle {  // send
                            width: 32; height: 32; radius: 16
                            anchors.verticalCenter: parent.verticalCenter
                            color: nSend.containsMouse ? Theme.primary : Theme.surfaceVariant
                            DankIcon { anchors.centerIn: parent; name: "send"; size: 15; color: nSend.containsMouse ? Theme.primaryText : island.textColor }
                            MouseArea {
                                id: nSend; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: parent.parent.send()
                                Accessible.role: Accessible.Button
                                Accessible.name: I18n.tr("Send")
                                Accessible.onPressAction: clicked(null)
                            }
                            DankTip { text: I18n.tr("Send"); active: nSend.containsMouse }
                        }
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
                        Accessible.role: Accessible.Button
                        Accessible.name: I18n.tr("Open notification")
                        Accessible.onPressAction: clicked(null)
                    }
        }
    }

    // ---- HISTORY: persisted entries (survive dismissal + restart) ----
    ListView {
        id: hlist
        visible: notifCol.tab === 1
        width: parent.width
        height: !visible ? 0 : (count === 0 ? 56 : Math.min(contentHeight, 300))
        clip: true; spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        model: NotificationService.historyList
        StyledText {
            anchors.centerIn: parent
            visible: hlist.count === 0
            text: I18n.tr("No history"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
        }
        delegate: Rectangle {
            id: hRow
            width: hlist.width; height: 62; radius: 14
            color: hRowArea.containsMouse ? Theme.surfaceLight : Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.4)
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

            ClippingRectangle {
                id: hRowIco
                width: 36; height: 36; radius: 11
                anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                color: Theme.primaryBackground
                Image {
                    id: hRowImg
                    anchors.fill: parent; anchors.margins: 5
                    source: {
                        if (modelData.image) return modelData.image
                        const icon = modelData.appIcon || ""
                        if (!icon) return ""
                        if (icon.startsWith("file://") || icon.startsWith("http://") || icon.startsWith("https://") || icon.includes("/"))
                            return icon
                        return Quickshell.iconPath(icon, true)
                    }
                    sourceSize.width: 72; sourceSize.height: 72
                    fillMode: Image.PreserveAspectFit; cache: false; asynchronous: true
                    visible: status === Image.Ready
                }
                DankIcon { anchors.centerIn: parent; name: "history"; size: 17; color: island.subText; visible: hRowImg.status !== Image.Ready }
            }
            Column {
                anchors.left: hRowIco.right; anchors.leftMargin: Theme.spacingM
                anchors.right: hRowDel.left; anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter; spacing: 1
                Row {
                    width: parent.width; spacing: Theme.spacingXS
                    StyledText { text: (modelData.appName || ""); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2; font.bold: true; font.capitalization: Font.AllUppercase; elide: Text.ElideRight; width: Math.min(implicitWidth, parent.width - 90) }
                    StyledText { text: notifCol.fmtStamp(modelData.timestamp); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                }
                StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (modelData.summary || modelData.appName || ""); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (modelData.body || ""); visible: text.length > 0; color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1 }
            }
            Rectangle {  // per-entry delete
                id: hRowDel
                width: 26; height: 26; radius: 13
                anchors.right: parent.right; anchors.rightMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                color: hDel.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : "transparent"
                opacity: hRowArea.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                DankIcon { anchors.centerIn: parent; name: "delete"; size: 15; color: hDel.containsMouse ? Theme.error : island.subText }
                MouseArea {
                    id: hDel; anchors.fill: parent; anchors.margins: -6
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.removeFromHistory(modelData.id)
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("Delete")
                    Accessible.onPressAction: clicked(null)
                }
                DankTip { text: I18n.tr("Delete"); active: hDel.containsMouse }
            }
            MouseArea { id: hRowArea; anchors.fill: parent; hoverEnabled: true; z: -1 }
        }
    }
}
