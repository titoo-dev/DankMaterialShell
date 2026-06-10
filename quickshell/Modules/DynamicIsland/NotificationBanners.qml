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

            readonly property var items: island.isFocusedScreen ? island.popups : []
            readonly property int n: items.length
            // hover spreads the deck; tap (touch, no hover) pins it open
            property bool touchExpanded: false
            // any open inline-reply pins the deck and pauses auto-dismiss
            property int replyOpenCount: 0
            readonly property bool replyOpen: replyOpenCount > 0
            readonly property bool expanded: areaHover.hovered || touchExpanded || replyOpen
            readonly property bool collapsed: n > 1 && !expanded
            readonly property real gap: 10
            readonly property real peek: 9   // visible sliver per stacked card when collapsed

            onNChanged: if (n <= 1) touchExpanded = false
            onReplyOpenChanged: {
                if (island) island.bannerReplyActive = replyOpen
                _syncTimers()
            }
            Component.onDestruction: if (island) island.bannerReplyActive = false

            // Auto-dismiss runs on the service wrapper timers (per-urgency
            // timeouts from Settings; critical = 0 = persistent). Pause them
            // while the deck is hovered or a reply is being typed.
            function _syncTimers() {
                for (var i = 0; i < items.length; i++) {
                    const w = items[i]
                    if (!w || !w.timer) continue
                    if (areaHover.hovered || replyOpen) w.timer.stop()
                    else if (w.popup && w.timer.interval > 0) w.timer.restart()
                }
            }
            onItemsChanged: _syncTimers()

            // measured card heights (index -> px), to lay the spread out without a flow layout
            property var hmap: ({})
            function setH(i, h) { var m = hmap; m[i] = h; hmap = m }
            function cardH(i) { return (hmap[i] !== undefined && hmap[i] > 0) ? hmap[i] : 104 }

            readonly property real expandedH: { var s = 0; for (var i = 0; i < n; i++) s += cardH(i); return s + Math.max(0, n - 1) * gap }
            readonly property real collapsedH: cardH(n - 1) + Math.min(n - 1, 2) * peek
            height: n === 0 ? 0 : ((expanded || n === 1) ? expandedH : collapsedH)
            Behavior on height { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }

            HoverHandler { id: areaHover; onHoveredChanged: bannerArea._syncTimers() }

            Repeater {
                model: bannerArea.items
                delegate: Item {
                    id: bWrap
                    width: bannerArea.width
                    height: bCard.height
                    property var parentPopup: modelData
                    // rank from the newest popup (0 = newest, shown on top of the deck)
                    readonly property int r: bannerArea.n - 1 - index
                    z: 100 - r
                    transformOrigin: Item.Top

                    onHeightChanged: bannerArea.setH(index, height)
                    Component.onCompleted: bannerArea.setH(index, height)

                    // ---- placement: spread vs collapsed deck ----
                    readonly property real spreadY: {
                        var y = 0
                        for (var rr = 0; rr < r; rr++) y += bannerArea.cardH(bannerArea.n - 1 - rr) + bannerArea.gap
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
                        readonly property bool crit: modelData && modelData.urgency === NotificationUrgency.Critical
                        property bool replying: false
                        onReplyingChanged: bannerArea.replyOpenCount += replying ? 1 : -1
                        Component.onDestruction: if (replying) bannerArea.replyOpenCount -= 1
                        readonly property bool canReply: modelData && modelData.notification && modelData.notification.hasInlineReply === true
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

                        // tap = default action; swipe right = dismiss; link clicks open the
                        // link. Declared BELOW the content so action chips / close / reply
                        // field receive their own clicks instead of being swallowed here.
                        MouseArea {
                            id: bArea
                            anchors.fill: parent
                            enabled: bWrap.active
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            property real pressX: 0
                            property bool dragging: false
                            onPressed: mouse => { pressX = mouse.x; dragging = true }
                            onPositionChanged: mouse => { if (dragging) bCard.swipe = Math.max(0, mouse.x - pressX) }
                            onReleased: mouse => {
                                dragging = false
                                if (bCard.swipe > 90) { if (modelData) modelData.popup = false }
                                else if (bCard.swipe < 6) {
                                    if (bannerArea.collapsed) { bannerArea.touchExpanded = true }
                                    else {
                                        // body link under the cursor wins over the card action
                                        const lp = bArea.mapToItem(bBody, mouse.x, mouse.y)
                                        const link = (bBody.visible && bBody.linkAt) ? bBody.linkAt(lp.x, lp.y) : ""
                                        if (link) { Qt.openUrlExternally(link) }
                                        else {
                                            var act = null
                                            const acts = (modelData && modelData.actions) ? modelData.actions : []
                                            for (var i = 0; i < acts.length; i++) { if (acts[i] && acts[i].identifier === "default") { act = acts[i]; break } }
                                            if (!act && acts.length > 0) act = acts[0]
                                            if (act && act.invoke) { act.invoke(); if (modelData) modelData.popup = false }
                                            else if (modelData) { modelData.popup = false }
                                        }
                                    }
                                }
                                bCard.swipe = 0
                            }
                            onCanceled: { bArea.dragging = false; bCard.swipe = 0 }
                        }

                        Column {
                            id: bCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.topMargin: 16
                            spacing: 10

                            Item {  // header: icon · (app + title + body) · dismiss
                                width: parent.width
                                height: Math.max(46, bText.implicitHeight)
                                DankCircularImage {
                                    id: bIco
                                    width: 46; height: 46
                                    anchors.left: parent.left; anchors.top: parent.top

                                    readonly property string rawImage: modelData?.image || ""
                                    readonly property string iconFromImage: rawImage.startsWith("image://icon/") ? rawImage.substring(13) : ""
                                    readonly property bool imageHasSpecialPrefix: {
                                        const icon = iconFromImage
                                        return icon.startsWith("material:") || icon.startsWith("svg:") || icon.startsWith("unicode:") || icon.startsWith("image:")
                                    }
                                    readonly property bool hasNotificationImage: rawImage !== "" && !rawImage.startsWith("image://icon/")
                                    readonly property bool needsImagePersist: hasNotificationImage && rawImage.startsWith("image://qsimage/") && modelData && !modelData.persistedImagePath

                                    imageSource: {
                                        if (!modelData) return ""
                                        if (hasNotificationImage) return modelData.cleanImage || ""
                                        if (imageHasSpecialPrefix) return ""
                                        const appIcon = modelData.appIcon
                                        if (!appIcon) return ""
                                        if (appIcon.startsWith("file://") || appIcon.startsWith("http://") || appIcon.startsWith("https://") || appIcon.includes("/")) return appIcon
                                        return ""
                                    }
                                    hasImage: hasNotificationImage
                                    fallbackIcon: imageHasSpecialPrefix ? iconFromImage : (modelData?.appIcon || iconFromImage || "")
                                    fallbackText: (modelData?.appName || "?").charAt(0).toUpperCase()

                                    // persist sender avatars so history keeps them (in island
                                    // mode no popup window exists to do it)
                                    onImageStatusChanged: {
                                        if (imageStatus === Image.Ready && needsImagePersist)
                                            saveImageToFile(NotificationService.getImageCachePath(modelData))
                                    }
                                    onImageSaved: filePath => {
                                        if (!modelData) return
                                        modelData.persistedImagePath = filePath
                                        const wrapperId = modelData.notification?.id?.toString() || ""
                                        if (wrapperId) NotificationService.updateHistoryImage(wrapperId, filePath)
                                    }
                                }
                                Column {
                                    id: bText
                                    anchors.left: bIco.right; anchors.leftMargin: 12
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 2
                                    Item {  // eyebrow line: app (left) · time (right)
                                        width: parent.width; height: bApp.implicitHeight
                                        StyledText {
                                            id: bApp
                                            anchors.left: parent.left; anchors.right: bTime.left; anchors.rightMargin: Theme.spacingS
                                            text: (modelData.appName || ""); color: bCard.crit ? Theme.error : island.accent
                                            font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true; font.capitalization: Font.AllUppercase
                                            elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                                        }
                                        StyledText {
                                            id: bTime
                                            anchors.right: parent.right; anchors.baseline: bApp.baseline
                                            text: (modelData.timeStr || ""); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1
                                        }
                                    }
                                    StyledText {
                                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                                        text: (modelData.summary || modelData.appName || ""); color: island.textColor
                                        font.pixelSize: Theme.fontSizeMedium; font.bold: true
                                    }
                                    StyledText {
                                        id: bBody
                                        width: parent.width; elide: Text.ElideRight
                                        // hover/expand reveals more of long messages (macOS)
                                        maximumLineCount: bannerArea.expanded ? 6 : 2
                                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                        // sanitized markup — safe for StyledText, never raw HTML
                                        text: SettingsData.notificationPopupPrivacyMode ? "" : (modelData.htmlBody || "")
                                        textFormat: Text.StyledText
                                        linkColor: bCard.crit ? Theme.error : island.accent
                                        visible: text.length > 0; color: island.subText
                                        font.pixelSize: Theme.fontSizeSmall; lineHeight: 1.15
                                    }
                                    StyledText {  // privacy-mode placeholder
                                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 1
                                        visible: SettingsData.notificationPopupPrivacyMode && (modelData.plainBody || "").length > 0
                                        text: I18n.tr("Message Content", "notification privacy mode placeholder")
                                        color: island.subText; font.pixelSize: Theme.fontSizeSmall; font.italic: true
                                    }
                                }
                                Rectangle {  // dismiss ✕ (revealed on hover)
                                    id: bClose
                                    width: 26; height: 26; radius: 13
                                    anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: -2
                                    color: bCloseA.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.55)
                                    opacity: (areaHover.hovered && bWrap.active) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                                    DankIcon { anchors.centerIn: parent; name: "close"; size: 15; color: bCloseA.containsMouse ? Theme.error : island.subText }
                                    MouseArea { id: bCloseA; anchors.fill: parent; enabled: bClose.opacity > 0; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (modelData) modelData.popup = false }
                                }
                            }

                            Row {  // action chips (+ inline-reply toggle when the sender supports it)
                                width: parent.width; spacing: Theme.spacingS
                                visible: bActions.count > 0 || bCard.canReply
                                Rectangle {  // "Reply" chip — macOS quick reply
                                    visible: bCard.canReply
                                    height: 32; radius: 16
                                    width: Math.min(bReplyLbl.implicitWidth + Theme.spacingL * 2, 160)
                                    color: bReplyA.containsMouse || bCard.replying ? Theme.primary : Theme.primarySelected
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    scale: bReplyA.pressed ? 0.93 : 1.0
                                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                                    StyledText { id: bReplyLbl; anchors.centerIn: parent; text: I18n.tr("Reply"); color: bReplyA.containsMouse || bCard.replying ? Theme.primaryText : island.accent; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                                    MouseArea {
                                        id: bReplyA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            bCard.replying = !bCard.replying
                                            if (bCard.replying) Qt.callLater(() => bReplyField.forceActiveFocus())
                                        }
                                    }
                                }
                                Repeater {
                                    id: bActions
                                    model: {
                                        var out = []
                                        if (modelData && modelData.actions) {
                                            const cap = bCard.canReply ? 2 : 3
                                            for (var i = 0; i < modelData.actions.length && out.length < cap; i++) {
                                                var a = modelData.actions[i]
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
                                        MouseArea { id: bActA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (modelData && modelData.invoke) modelData.invoke(); if (bWrap.parentPopup) bWrap.parentPopup.popup = false } }
                                    }
                                }
                            }

                            Row {  // inline-reply field (quick reply, macOS-style)
                                width: parent.width; spacing: Theme.spacingS
                                visible: bCard.replying
                                DankTextField {
                                    id: bReplyField
                                    width: parent.width - bSend.width - Theme.spacingS
                                    height: 36
                                    cornerRadius: 18
                                    placeholderText: (modelData && modelData.notification && modelData.notification.inlineReplyPlaceholder) ? modelData.notification.inlineReplyPlaceholder : I18n.tr("Type a reply…")
                                    font.pixelSize: Theme.fontSizeSmall
                                    onAccepted: bSend.send()
                                    Keys.onEscapePressed: { bCard.replying = false; bReplyField.clear() }
                                }
                                Rectangle {  // send ➤
                                    id: bSend
                                    width: 36; height: 36; radius: 18
                                    readonly property bool canSend: bReplyField.text.trim().length > 0
                                    color: canSend ? Theme.primary : Theme.surfaceLight
                                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                                    function send() {
                                        if (!canSend || !modelData || !modelData.notification) return
                                        modelData.notification.sendInlineReply(bReplyField.text.trim())
                                        bReplyField.clear()
                                        bCard.replying = false
                                        if (modelData) modelData.popup = false
                                    }
                                    DankIcon { anchors.centerIn: parent; name: "send"; size: 17; color: bSend.canSend ? Theme.primaryText : island.subText }
                                    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: bSend.canSend ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: bSend.send() }
                                }
                            }
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
