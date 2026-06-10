import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import "EmojiData.js" as EmojiData

// Emoji picker (drill-down, island-native). Search + category tabs + colour grid
// (Noto Color Emoji) + persisted recents + keyboard navigation. Click or Enter
// copies the emoji to the clipboard (via `dms cl copy`, so it also lands in the
// island Clipboard view). Needs the Exclusive keyboard grab (controller flips it
// on for this view).
Column {
    id: emojiCol
    property var island: null
    readonly property int cell: 42

    property string activeCat: "smileys"
    property var recents: []
    property int selIndex: 0
    // emoji whose skin-tone variants are showing in the strip ("" = closed)
    property string toneBase: ""
    readonly property int columns: Math.max(1, Math.floor(gridFlick.width / cell))

    // active model: search results, recents, or the active category
    readonly property var items: {
        const q = searchField.text
        if (q && q.trim().length > 0) return EmojiData.search(q)
        if (activeCat === "recent") return recents
        return EmojiData.byCategory(activeCat)
    }
    onItemsChanged: { selIndex = 0; gridFlick.contentY = 0; toneBase = "" }

    function emojiOf(it) { return (typeof it === "string") ? it : (it ? it.e : "") }
    // type the emoji straight into the focused input (Windows-emoji-picker style)
    // instead of copying it — no clipboard pollution. The controller closes the
    // island, re-focuses the previously-active window, then wtypes into it.
    function pick(it) {
        const e = emojiOf(it)
        if (!e) return
        addRecent(e)
        ToastService.showInfo(e)
        island.insertText(e)
    }
    function addRecent(e) {
        var out = [e]
        for (var i = 0; i < recents.length && out.length < 36; i++)
            if (recents[i] !== e) out.push(recents[i])
        recents = out
        recentsFile.setText(JSON.stringify(recents))
    }
    function move(dx, dy) {
        if (items.length === 0) return
        var n = selIndex + dx + dy * columns
        if (n < 0) n = 0
        if (n > items.length - 1) n = items.length - 1
        selIndex = n
        const row = Math.floor(selIndex / columns)
        const y = row * cell
        if (y < gridFlick.contentY) gridFlick.contentY = y
        else if (y + cell > gridFlick.contentY + gridFlick.height) gridFlick.contentY = y + cell - gridFlick.height
    }

    FileView {
        id: recentsFile
        path: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/DankMaterialShell/island-emoji-recents.json"
        blockLoading: true
        atomicWrites: true
        onLoaded: { try { emojiCol.recents = JSON.parse(recentsFile.text()) || [] } catch (e) { emojiCol.recents = [] } }
        onLoadFailed: emojiCol.recents = []
    }

    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "emoji" ? 1 : 0
    visible: opacity > 0
    onVisibleChanged: if (visible) {
        searchField.text = ""
        activeCat = recents.length > 0 ? "recent" : "smileys"
        searchField.forceActiveFocus()
    }
    // lazily loaded: the panel is born visible, so onVisibleChanged never fires
    Component.onCompleted: if (visible) {
        activeCat = recents.length > 0 ? "recent" : "smileys"
        searchField.forceActiveFocus()
    }
    transform: Translate { x: island.panelView === "emoji" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    Item {
        id: navHandler
        Keys.onLeftPressed: emojiCol.move(-1, 0)
        Keys.onRightPressed: emojiCol.move(1, 0)
        Keys.onUpPressed: emojiCol.move(0, -1)
        Keys.onDownPressed: emojiCol.move(0, 1)
        Keys.onEscapePressed: {
            if (emojiCol.toneBase !== "") emojiCol.toneBase = ""
            else island.panelView = "controls"
        }
    }

    // header: back · search field
    Item {
        width: parent.width; height: 40
        Rectangle {
            id: emBack
            width: 30; height: 30; radius: 9
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: emBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: emBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: emBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
        }
        DankTextField {
            id: searchField
            anchors.left: emBack.right; anchors.leftMargin: Theme.spacingXS
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            height: 36
            leftIconName: "search"
            placeholderText: I18n.tr("Search emoji")
            ignoreUpDownKeys: true
            ignoreLeftRightKeys: true
            keyForwardTargets: [navHandler]
            onAccepted: emojiCol.pick(emojiCol.items.length > emojiCol.selIndex ? emojiCol.items[emojiCol.selIndex] : null)
        }
    }

    // category tabs (hidden while searching)
    Row {
        width: parent.width
        visible: searchField.text.trim().length === 0
        Repeater {
            model: EmojiData.CATEGORIES
            Item {
                visible: modelData.key !== "recent" || emojiCol.recents.length > 0
                width: visible ? parent.width / emojiCol._visibleCats : 0
                height: 30
                Rectangle {
                    anchors.centerIn: parent; width: 28; height: 26; radius: 8
                    readonly property bool on: emojiCol.activeCat === modelData.key
                    color: on ? Theme.primarySelected : (catArea.containsMouse ? Theme.surfaceLight : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    StyledText { anchors.centerIn: parent; text: modelData.icon; font.pixelSize: Theme.fontSizeMedium }
                    MouseArea {
                        id: catArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { searchField.text = ""; emojiCol.activeCat = modelData.key }
                    }
                }
            }
        }
    }
    // count of currently-visible category tabs (recent only when non-empty)
    readonly property int _visibleCats: EmojiData.CATEGORIES.length - (recents.length > 0 ? 0 : 1)

    // skin-tone variant strip (right-click / long-press a hand emoji to open)
    Rectangle {
        width: parent.width; height: visible ? 46 : 0; radius: 12
        visible: emojiCol.toneBase !== ""
        color: Theme.surfaceLight
        Row {
            anchors.centerIn: parent; spacing: Theme.spacingXS
            Repeater {
                model: emojiCol.toneBase !== "" ? EmojiData.TONES : []
                Rectangle {
                    width: 40; height: 40; radius: 10
                    color: toneArea.containsMouse ? Theme.primarySelected : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    StyledText {
                        anchors.centerIn: parent
                        text: EmojiData.withTone(emojiCol.toneBase, modelData)
                        font.pixelSize: 22
                    }
                    MouseArea {
                        id: toneArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const v = EmojiData.withTone(emojiCol.toneBase, modelData)
                            emojiCol.toneBase = ""
                            emojiCol.pick(v)
                        }
                    }
                }
            }
        }
    }

    // emoji grid
    Flickable {
        id: gridFlick
        width: parent.width; height: 232; clip: true
        contentHeight: grid.height; boundsBehavior: Flickable.StopAtBounds
        StyledText {
            anchors.centerIn: parent
            visible: emojiCol.items.length === 0
            text: searchField.text.trim().length > 0 ? I18n.tr("No emoji found") : I18n.tr("No recent emoji")
            color: island.subText; font.pixelSize: Theme.fontSizeSmall
        }
        Grid {
            id: grid
            width: parent.width
            columns: emojiCol.columns
            Repeater {
                model: emojiCol.items
                Rectangle {
                    width: emojiCol.cell; height: emojiCol.cell; radius: 10
                    readonly property bool selected: index === emojiCol.selIndex
                    color: selected ? Theme.primarySelected : (cellArea.containsMouse ? Theme.surfaceLight : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    StyledText {
                        anchors.centerIn: parent
                        text: emojiCol.emojiOf(modelData)
                        font.pixelSize: 22
                    }
                    MouseArea {
                        id: cellArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onPositionChanged: emojiCol.selIndex = index
                        onClicked: mouse => {
                            const e = emojiCol.emojiOf(modelData)
                            if (mouse.button === Qt.RightButton && EmojiData.toneable(e)) {
                                emojiCol.toneBase = e   // right-click = skin-tone variants
                                return
                            }
                            emojiCol.pick(modelData)
                        }
                        // long-press = skin tones too (touch has no right-click)
                        onPressAndHold: {
                            const e = emojiCol.emojiOf(modelData)
                            if (EmojiData.toneable(e)) emojiCol.toneBase = e
                        }
                    }
                }
            }
        }
    }
}
