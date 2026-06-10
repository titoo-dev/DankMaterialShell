import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import qs.Widgets

// macOS-style notification banners — collapsible deck (top-right).
// Independent surface; reads island state via the `island` property.
        Item {
            id: bannerArea
            property var island: null
            width: 392
            anchors.top: parent.top; anchors.right: parent.right
            anchors.topMargin: island.notchMode ? 8 : 14
            anchors.rightMargin: 16
            visible: island.isFocusedScreen && n > 0

            // GROUPED by app (macOS): one card per group, newest notification on
            // top of each group, count badge when the group has several
            readonly property var items: island.isFocusedScreen ? (NotificationService.groupedPopups || []) : []
            readonly property int n: items.length
            // group key with an open inline-reply field ("" = none). While a reply
            // is being typed the banner window holds the keyboard (see needsKeyboard)
            property string replyKey: ""
            readonly property bool needsKeyboard: replyKey !== ""
            onItemsChanged: if (replyKey !== "" && !items.some(g => g && g.key === replyKey)) replyKey = ""
            // expanded follows hover; a tap on the collapsed deck pins it open
            // (a separate flag — assigning to `expanded` would destroy the binding);
            // an open reply field also holds the deck open while typing
            property bool pinnedOpen: false
            readonly property bool expanded: areaHover.hovered || pinnedOpen || replyKey !== ""
            onNChanged: if (n === 0) pinnedOpen = false
            // when the reply closes with the pointer already outside, resume the
            // auto-dismiss timers (no hover transition will fire to do it)
            onReplyKeyChanged: if (replyKey === "" && !areaHover.hovered) syncTimers(false)
            function syncTimers(stop) {
                for (var i = 0; i < items.length; i++) {
                    const g = items[i]
                    const arr = (g && g.notifications) ? g.notifications : []
                    for (var j = 0; j < arr.length; j++) {
                        const w = arr[j]
                        if (!w || !w.timer) continue
                        if (stop) w.timer.stop()
                        else if (replyKey === "" && w.popup && w.timer.interval > 0 && !w.timer.running) w.timer.restart()
                    }
                }
            }
            readonly property bool collapsed: n > 1 && !expanded
            readonly property real gap: 10
            readonly property real peek: 9   // visible sliver per stacked card when collapsed

            // measured card heights (index -> px), to lay the spread out without a flow layout
            property var hmap: ({})
            function setH(i, h) { var m = hmap; m[i] = h; hmap = m }
            function cardH(i) { return (hmap[i] !== undefined && hmap[i] > 0) ? hmap[i] : 104 }

            readonly property real expandedH: { var s = 0; for (var i = 0; i < n; i++) s += cardH(i); return s + Math.max(0, n - 1) * gap }
            readonly property real collapsedH: cardH(n - 1) + Math.min(n - 1, 2) * peek
            height: n === 0 ? 0 : ((expanded || n === 1) ? expandedH : collapsedH)
            Behavior on height { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }

            // pause every popup's SERVICE timer while the deck is hovered (the
            // timers honour the user's notificationTimeout* settings; interval 0
            // and critical notifications are persistent and never restarted).
            // While an inline reply is being typed, nothing restarts.
            HoverHandler {
                id: areaHover
                onHoveredChanged: bannerArea.syncTimers(hovered)
            }

            Repeater {
                // keyed by group key, so existing delegates are KEPT when a group's
                // content changes (no animation restarts, no dead-modelData handlers)
                model: ScriptModel { values: bannerArea.items; objectProp: "key" }
                delegate: Item {
                    id: bWrap
                    width: bannerArea.width
                    height: bCard.height
                    // the group's freshest notification drives the card content
                    readonly property var topNotif: modelData ? modelData.latestNotification : null
                    readonly property int gCount: modelData ? (modelData.count || 0) : 0
                    function dismissGroup() {
                        if (!modelData) return
                        const arr = modelData.notifications || []
                        for (var i = 0; i < arr.length; i++) if (arr[i]) arr[i].popup = false
                    }
                    // groupedPopups is sorted NEWEST FIRST -> rank == index
                    readonly property int r: index
                    z: 100 - r
                    transformOrigin: Item.Top

                    onHeightChanged: bannerArea.setH(index, height)
                    Component.onCompleted: bannerArea.setH(index, height)
                    // indices shift when a middle card is dismissed — re-publish
                    // this card's height under its new rank
                    readonly property int idx: index
                    onIdxChanged: bannerArea.setH(idx, height)

                    // ---- placement: spread vs collapsed deck ----
                    readonly property real spreadY: {
                        var y = 0
                        for (var rr = 0; rr < r; rr++) y += bannerArea.cardH(rr) + bannerArea.gap
                        return y
                    }
                    readonly property bool active: bannerArea.expanded || bannerArea.n === 1 || r === 0
                    y: (bannerArea.expanded || bannerArea.n === 1) ? spreadY : (Math.min(r, 2) * bannerArea.peek)
                    Behavior on y { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }
                    scale: (bannerArea.expanded || bannerArea.n === 1) ? 1 : (1 - Math.min(r, 2) * 0.05)
                    Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }
                    opacity: (bannerArea.expanded || bannerArea.n === 1 || r < 3) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                    Rectangle {
                        id: bCard
                        width: parent.width
                        height: bCol.implicitHeight + 32   // generous vertical padding (16 top/bottom)
                        x: bCard.swipe
                        radius: 24
                        antialiasing: true
                        readonly property bool crit: bWrap.topNotif ? (bWrap.topNotif.urgency === NotificationUrgency.Critical) : false
                        // inline reply, straight from the banner (the notification
                        // declares hasInlineReply, e.g. chat apps)
                        readonly property bool canReply: bWrap.topNotif && bWrap.topNotif.notification && bWrap.topNotif.notification.hasInlineReply === true
                        readonly property bool replyOpen: modelData && bannerArea.replyKey === modelData.key
                        function openReply() {
                            if (!modelData) return
                            bannerArea.replyKey = modelData.key
                            // typing must not race the auto-dismiss
                            const arr = modelData.notifications || []
                            for (var i = 0; i < arr.length; i++) if (arr[i] && arr[i].timer) arr[i].timer.stop()
                        }
                        function closeReply() { if (bCard.replyOpen) bannerArea.replyKey = "" }
                        function sendReply(text) {
                            if (!text || text.length === 0) return
                            const n = bWrap.topNotif
                            bannerArea.replyKey = ""
                            if (n && n.notification && n.notification.hasInlineReply) {
                                n.notification.sendInlineReply(text)
                                n.popup = false
                            }
                        }
                        property real swipe: 0
                        Behavior on swipe { enabled: !bArea.dragging; NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                        color: island.islandColor
                        border.width: crit ? 1.5 : 1
                        border.color: crit ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.7) : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: bCard.crit ? Theme.error : "#000000"
                            shadowBlur: bCard.crit ? 1.0 : 0.7
                            shadowVerticalOffset: 3
                            shadowOpacity: bCard.crit ? 0.5 : 0.32
                        }
                        Rectangle {  // glass material
                            anchors.fill: parent; radius: parent.radius; color: "transparent"
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                                GradientStop { position: 0.14; color: Qt.rgba(1, 1, 1, 0.0) }
                                GradientStop { position: 0.85; color: Qt.rgba(0, 0, 0, 0.0) }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.08) }
                            }
                        }

                        Column {
                            id: bCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.topMargin: 16
                            spacing: 10

                            Item {  // header: icon · (app + title + body) · dismiss
                                width: parent.width
                                height: Math.max(46, bText.implicitHeight)
                                Rectangle {
                                    id: bIco
                                    width: 46; height: 46; radius: 14; clip: true
                                    anchors.left: parent.left; anchors.top: parent.top
                                    color: Theme.primaryBackground
                                    Image {
                                        id: bImg
                                        anchors.fill: parent; anchors.margins: 6
                                        // resolve theme-name appIcons; never hand a bare name to Image
                                        source: {
                                            const n = bWrap.topNotif
                                            if (!n) return ""
                                            if (n.cleanImage) return n.cleanImage
                                            const icon = n.appIcon || ""
                                            if (!icon) return ""
                                            if (icon.startsWith("file://") || icon.startsWith("http://") || icon.startsWith("https://") || icon.includes("/"))
                                                return icon
                                            return Quickshell.iconPath(icon, true)
                                        }
                                        sourceSize.width: 92; sourceSize.height: 92
                                        fillMode: Image.PreserveAspectFit; cache: false; asynchronous: true
                                        visible: status === Image.Ready
                                    }
                                    DankIcon { anchors.centerIn: parent; name: "notifications"; size: 22; color: bCard.crit ? Theme.error : island.accent; visible: bImg.status !== Image.Ready }
                                }
                                Column {
                                    id: bText
                                    anchors.left: bIco.right; anchors.leftMargin: 12
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 2
                                    Item {  // eyebrow line: app + group count (left) · time (right)
                                        width: parent.width; height: bApp.implicitHeight
                                        StyledText {
                                            id: bApp
                                            anchors.left: parent.left; anchors.right: bCnt.visible ? bCnt.left : bTime.left; anchors.rightMargin: Theme.spacingS
                                            text: (modelData ? (modelData.appName || "") : ""); color: bCard.crit ? Theme.error : island.accent
                                            font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true; font.capitalization: Font.AllUppercase
                                            elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                                        }
                                        Rectangle {  // group count badge (e.g. Messages ×3)
                                            id: bCnt
                                            visible: bWrap.gCount > 1
                                            anchors.right: bTime.left; anchors.rightMargin: Theme.spacingS
                                            anchors.verticalCenter: bApp.verticalCenter
                                            width: bCntLbl.implicitWidth + 10; height: 16; radius: 8
                                            color: bCard.crit ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.2) : Theme.primarySelected
                                            StyledText { id: bCntLbl; anchors.centerIn: parent; text: "×" + bWrap.gCount; color: bCard.crit ? Theme.error : island.accent; font.pixelSize: Theme.fontSizeSmall - 3; font.bold: true }
                                        }
                                        StyledText {
                                            id: bTime
                                            anchors.right: parent.right; anchors.baseline: bApp.baseline
                                            text: (bWrap.topNotif ? (bWrap.topNotif.timeStr || "") : ""); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1
                                        }
                                    }
                                    StyledText {
                                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                                        text: bWrap.topNotif ? (bWrap.topNotif.summary || bWrap.topNotif.appName || "") : ""
                                        color: island.textColor
                                        font.pixelSize: Theme.fontSizeMedium; font.bold: true
                                    }
                                    StyledText {
                                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                                        text: bWrap.topNotif ? (bWrap.topNotif.plainBody || "") : ""
                                        visible: text.length > 0; color: island.subText
                                        font.pixelSize: Theme.fontSizeSmall; lineHeight: 1.15
                                    }
                                }
                                Rectangle {  // dismiss ✕ — clears the whole group (revealed on hover)
                                    id: bClose
                                    width: 26; height: 26; radius: 13
                                    anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: -2
                                    color: bCloseA.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.55)
                                    opacity: (areaHover.hovered && bWrap.active) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                                    DankIcon { anchors.centerIn: parent; name: "close"; size: 15; color: bCloseA.containsMouse ? Theme.error : island.subText }
                                    MouseArea { id: bCloseA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bWrap.dismissGroup() }
                                }
                            }

                            Row {  // action chips (+ inline Reply when supported)
                                width: parent.width; spacing: Theme.spacingS
                                visible: (bActions.count > 0 || bCard.canReply) && !bCard.replyOpen
                                Rectangle {  // Reply — opens the inline reply field
                                    visible: bCard.canReply
                                    height: 32; radius: 16
                                    width: bReplyLbl.implicitWidth + Theme.spacingL * 2
                                    color: bReplyA.containsMouse ? Theme.primary : Theme.primarySelected
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    scale: bReplyA.pressed ? 0.93 : 1.0
                                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                    Row {
                                        anchors.centerIn: parent; spacing: 4
                                        DankIcon { name: "reply"; size: 14; color: bReplyA.containsMouse ? Theme.primaryText : island.accent; anchors.verticalCenter: parent.verticalCenter }
                                        StyledText { id: bReplyLbl; text: I18n.tr("Reply"); color: bReplyA.containsMouse ? Theme.primaryText : island.accent; font.pixelSize: Theme.fontSizeSmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    MouseArea { id: bReplyA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bCard.openReply() }
                                }
                                Repeater {
                                    id: bActions
                                    model: {
                                        var out = []
                                        const n = bWrap.topNotif
                                        if (n && n.actions) {
                                            for (var i = 0; i < n.actions.length && out.length < 3; i++) {
                                                var a = n.actions[i]
                                                if (a && a.identifier !== "default" && (a.text || "").length > 0) out.push(a)
                                            }
                                        }
                                        return out
                                    }
                                    Rectangle {
                                        height: 32; radius: 16
                                        width: Math.min(bActLbl.implicitWidth + Theme.spacingL * 2, 160)
                                        color: bActA.containsMouse ? Theme.primary : Theme.primarySelected
                                        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                        scale: bActA.pressed ? 0.93 : 1.0
                                        Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                        StyledText { id: bActLbl; anchors.centerIn: parent; width: Math.min(implicitWidth, 160 - Theme.spacingL * 2); text: modelData.text || I18n.tr("Open"); elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; color: bActA.containsMouse ? Theme.primaryText : island.accent; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                                        MouseArea { id: bActA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (modelData && modelData.invoke) modelData.invoke(); if (bWrap.topNotif) bWrap.topNotif.popup = false } }
                                    }
                                }
                            }

                            // inline reply field (sent straight to the app via the
                            // notification's inline-reply channel)
                            Row {
                                width: parent.width; spacing: Theme.spacingS
                                visible: bCard.replyOpen
                                onVisibleChanged: if (visible) { bReplyField.text = ""; bReplyField.forceActiveFocus() }
                                Item {
                                    id: bReplyEsc
                                    Keys.onEscapePressed: bCard.closeReply()
                                }
                                DankTextField {
                                    id: bReplyField
                                    width: parent.width - 40
                                    height: 34
                                    leftIconName: "reply"
                                    placeholderText: I18n.tr("Reply…")
                                    keyForwardTargets: [bReplyEsc]
                                    onAccepted: bCard.sendReply(text)
                                }
                                Rectangle {  // send
                                    width: 32; height: 34; radius: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: bSendA.containsMouse ? Theme.primary : Theme.surfaceVariant
                                    DankIcon { anchors.centerIn: parent; name: "send"; size: 16; color: bSendA.containsMouse ? Theme.primaryText : island.textColor }
                                    MouseArea { id: bSendA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bCard.sendReply(bReplyField.text) }
                                }
                            }
                        }

                        // auto-dismiss is owned by the SERVICE timer (started in
                        // NotificationService, honours notificationTimeout* settings,
                        // interval 0 / critical = persistent); hover-pause above.
                        // tap = default action; swipe right = dismiss (only the active/top card)
                        MouseArea {
                            id: bArea
                            anchors.fill: parent
                            anchors.rightMargin: 30
                            // below the content column: interactive children (action
                            // chips, reply field, send) get their clicks first, the
                            // plain text/body falls through to tap/swipe here
                            z: -1
                            enabled: bWrap.active
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            property real pressX: 0
                            property bool dragging: false
                            onPressed: mouse => { pressX = mouse.x; dragging = true }
                            onPositionChanged: mouse => { if (dragging) bCard.swipe = Math.max(0, mouse.x - pressX) }
                            onReleased: mouse => {
                                dragging = false
                                if (bCard.swipe > 90) { bWrap.dismissGroup() }
                                else if (bCard.swipe < 6 && !bCard.replyOpen) {
                                    if (bannerArea.collapsed) { bannerArea.pinnedOpen = true }
                                    else {
                                        var def = null
                                        const n = bWrap.topNotif
                                        if (n && n.actions) for (var i = 0; i < n.actions.length; i++) { if (n.actions[i] && n.actions[i].identifier === "default") { def = n.actions[i]; break } }
                                        if (def && def.invoke) { def.invoke(); if (n) n.popup = false }
                                    }
                                }
                                bCard.swipe = 0
                            }
                            onCanceled: { bArea.dragging = false; bCard.swipe = 0 }
                        }
                    }
                }
            }

            // count chip when collapsed (e.g. "+2") — bottom-right of the deck
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 6
                y: bannerArea.collapsedH - 6
                width: cntLbl.implicitWidth + Theme.spacingM; height: 22; radius: 11
                visible: bannerArea.collapsed && bannerArea.n > 1
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                color: Theme.primary
                z: 200
                StyledText { id: cntLbl; anchors.centerIn: parent; text: "+" + (bannerArea.n - 1); color: Theme.primaryText; font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true }
            }
        }
