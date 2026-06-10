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

            // materialize as a JS array: ScriptModel.values is a QVariantList and
            // can't take a QQmlListReference; the wrapper objects keep their
            // identity so the model still diffs instead of rebuilding
            readonly property var items: {
                if (!island.isFocusedScreen) return []
                const src = island.popups, out = []
                for (var i = 0; i < src.length; i++) out.push(src[i])
                return out
            }
            readonly property int n: items.length
            // expanded follows hover; a tap on the collapsed deck pins it open
            // (a separate flag — assigning to `expanded` would destroy the binding)
            property bool pinnedOpen: false
            readonly property bool expanded: areaHover.hovered || pinnedOpen
            onNChanged: if (n === 0) pinnedOpen = false
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
            // and critical notifications are persistent and never restarted)
            HoverHandler {
                id: areaHover
                onHoveredChanged: {
                    for (var i = 0; i < bannerArea.items.length; i++) {
                        const w = bannerArea.items[i]
                        if (!w || !w.timer) continue
                        if (hovered) w.timer.stop()
                        else if (w.popup && w.timer.interval > 0 && !w.timer.running) w.timer.restart()
                    }
                }
            }

            Repeater {
                // ScriptModel diffs by object identity, so existing delegates are
                // KEPT when a popup is added/removed (no animation restarts, no
                // handlers firing on dead modelData)
                model: ScriptModel { values: bannerArea.items }
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
                    // indices shift when a middle card is dismissed — re-publish
                    // this card's height under its new rank
                    readonly property int idx: index
                    onIdxChanged: bannerArea.setH(idx, height)

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
                                        source: (modelData.cleanImage || modelData.appIcon || "")
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
                                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                                        text: (modelData.body || ""); visible: text.length > 0; color: island.subText
                                        font.pixelSize: Theme.fontSizeSmall; lineHeight: 1.15
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
                                    MouseArea { id: bCloseA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (modelData) modelData.popup = false }
                                }
                            }

                            Row {  // action chips
                                width: parent.width; spacing: Theme.spacingS
                                visible: bActions.count > 0
                                Repeater {
                                    id: bActions
                                    model: {
                                        var out = []
                                        if (modelData && modelData.actions) {
                                            for (var i = 0; i < modelData.actions.length && out.length < 3; i++) {
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
                        }

                        // auto-dismiss is owned by the SERVICE timer (started in
                        // NotificationService, honours notificationTimeout* settings,
                        // interval 0 / critical = persistent); hover-pause above.
                        // tap = default action; swipe right = dismiss (only the active/top card)
                        MouseArea {
                            id: bArea
                            anchors.fill: parent
                            anchors.rightMargin: 30
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
                                    if (bannerArea.collapsed) { bannerArea.pinnedOpen = true }
                                    else {
                                        var def = null
                                        if (modelData && modelData.actions) for (var i = 0; i < modelData.actions.length; i++) { if (modelData.actions[i] && modelData.actions[i].identifier === "default") { def = modelData.actions[i]; break } }
                                        if (def && def.invoke) { def.invoke(); if (modelData) modelData.popup = false }
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
