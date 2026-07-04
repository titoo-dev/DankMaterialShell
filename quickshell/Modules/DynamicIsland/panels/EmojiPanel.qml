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
    readonly property int columns: Math.max(1, Math.floor(grid.width / cell))

    // search input debounced so the dataset isn't re-scanned on every keystroke
    property string query: ""
    Timer { id: searchDebounce; interval: 120; onTriggered: emojiCol.query = searchField.text }
    // active model: search results, recents, or the active category
    readonly property var items: {
        if (query && query.trim().length > 0) return EmojiData.search(query)
        if (activeCat === "recent") return recents
        return EmojiData.byCategory(activeCat)
    }
    onItemsChanged: { selIndex = 0; grid.positionViewAtBeginning(); toneBase = "" }

    function emojiOf(it) { return (typeof it === "string") ? it : (it ? it.e : "") }
    // type the emoji straight into the focused input (Windows-emoji-picker style)
    // instead of copying it — no clipboard pollution, hence no toast either
    // (the emoji lands in the field; on XWayland it's on the clipboard, Ctrl+V).
    // The controller closes the island, re-focuses the previously-active window,
    // then wtypes into it.
    function pick(it) {
        const e = emojiOf(it)
        if (!e) return
        addRecent(e)
        island.insertText(e)
    }
    // Enter: insert the selected tone variant if the strip is open, else the
    // selected grid emoji
    function confirm() {
        if (toneBase !== "") {
            const v = EmojiData.withTone(toneBase, EmojiData.TONES[toneSel])
            toneBase = ""
            pick(v)
            return
        }
        pick(items.length > selIndex ? items[selIndex] : null)
    }
    // cycle the category tabs with the keyboard (Tab / Shift+Tab, Ctrl+←/→);
    // skips "recent" when it's empty, leaves search mode first
    function cycleCat(dir) {
        if (searchField.text.trim().length > 0) searchField.text = ""
        const cats = EmojiData.CATEGORIES
        var idx = -1
        for (var i = 0; i < cats.length; i++) if (cats[i].key === activeCat) { idx = i; break }
        for (var step = 0; step < cats.length; step++) {
            idx = (idx + dir + cats.length) % cats.length
            if (cats[idx].key === "recent" && recents.length === 0) continue
            activeCat = cats[idx].key
            return
        }
    }
    // keyboard control of the skin-tone strip
    property int toneSel: 0
    onToneBaseChanged: toneSel = 0
    function toneMove(dir) { toneSel = Math.max(0, Math.min(EmojiData.TONES.length - 1, toneSel + dir)) }
    function openTonesForSelection() {
        const e = emojiOf(items.length > selIndex ? items[selIndex] : null)
        const base = EmojiData.datasetBase(e)
        if (base && EmojiData.toneable(base)) toneBase = base
    }
    function addRecent(e) {
        var out = [e]
        for (var i = 0; i < recents.length && out.length < 36; i++)
            if (recents[i] !== e) out.push(recents[i])
        recents = out
        recentsFile.setText(JSON.stringify(recents))
    }
    function move(dx, dy) {
        if (toneBase !== "") toneBase = ""   // grid navigation closes the strip
        if (items.length === 0) return
        var n = selIndex + dx + dy * columns
        if (n < 0) n = 0
        if (n > items.length - 1) n = items.length - 1
        selIndex = n
        grid.positionViewAtIndex(selIndex, GridView.Contain)
    }

    FileView {
        id: recentsFile
        path: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/DankMaterialShell/island-emoji-recents.json"
        // async: no blocking IO at panel creation; the recents land a few ms
        // later and flip the initial tab if the user hasn't interacted yet
        atomicWrites: true
        onLoaded: {
            try { emojiCol.recents = JSON.parse(recentsFile.text()) || [] } catch (e) { emojiCol.recents = [] }
            if (emojiCol.visible && searchField.text === "" && emojiCol.activeCat === "smileys" && emojiCol.recents.length > 0 && emojiCol.selIndex === 0)
                emojiCol.activeCat = "recent"
        }
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
        // ←/→ navigate the grid, or the tone strip while it is open;
        // Ctrl+←/→ jump categories (backup for Tab inside the text field)
        Keys.onLeftPressed: event => {
            if (event.modifiers & Qt.ControlModifier) emojiCol.cycleCat(-1)
            else if (emojiCol.toneBase !== "") emojiCol.toneMove(-1)
            else emojiCol.move(-1, 0)
        }
        Keys.onRightPressed: event => {
            if (event.modifiers & Qt.ControlModifier) emojiCol.cycleCat(1)
            else if (emojiCol.toneBase !== "") emojiCol.toneMove(1)
            else emojiCol.move(1, 0)
        }
        Keys.onUpPressed: emojiCol.move(0, -1)
        Keys.onDownPressed: emojiCol.move(0, 1)
        // Tab / Shift+Tab cycle the category tabs (search must be empty —
        // the tabs are hidden while a query filters)
        Keys.onTabPressed: emojiCol.cycleCat(1)
        Keys.onBacktabPressed: emojiCol.cycleCat(-1)
        Keys.onEscapePressed: {
            if (emojiCol.toneBase !== "") emojiCol.toneBase = ""
            else island.panelView = "controls"
        }
        // Ctrl+T: skin tones for the selected emoji (keyboard parity with right-click)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_T && (event.modifiers & Qt.ControlModifier)) {
                emojiCol.openTonesForSelection()
                event.accepted = true
            }
        }
    }

    // header: back · search field
    Item {
        width: parent.width; height: 40
        Rectangle {
            id: emBack
            width: 30; height: 30; radius: width / 2
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: emBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: emBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea {
                // -4 not -7: the search field sits Theme.spacingXS away on the right
                id: emBackArea; anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: island.panelView = "controls"
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("Back")
                Accessible.onPressAction: clicked(null)
            }
        }
        DankTextField {
            id: searchField
            anchors.left: emBack.right; anchors.leftMargin: Theme.spacingXS
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            height: 36
            cornerRadius: height / 2
            backgroundColor: Theme.surfaceLight
            leftIconName: "search"
            placeholderText: I18n.tr("Search emoji")
            ignoreUpDownKeys: true
            ignoreLeftRightKeys: true
            ignoreTabKeys: true       // Tab cycles the category tabs (navHandler)
            keyForwardTargets: [navHandler]
            onAccepted: emojiCol.confirm()
            // clearing must apply instantly (tab switches clear the field);
            // only actual typing is debounced
            onTextChanged: {
                if (text.trim().length === 0) { searchDebounce.stop(); emojiCol.query = "" }
                else searchDebounce.restart()
            }
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
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name
                        Accessible.onPressAction: clicked(null)
                    }
                }
            }
        }
    }
    // count of currently-visible category tabs (recent only when non-empty)
    readonly property int _visibleCats: EmojiData.CATEGORIES.length - (recents.length > 0 ? 0 : 1)

    // skin-tone variant strip (right-click / long-press a hand emoji to open)
    Rectangle {
        width: parent.width; height: visible ? 46 : 0; radius: height / 2
        visible: emojiCol.toneBase !== ""
        color: Theme.surfaceLight
        Row {
            anchors.centerIn: parent; spacing: Theme.spacingXS
            Repeater {
                model: emojiCol.toneBase !== "" ? EmojiData.TONES : []
                Rectangle {
                    width: 40; height: 40; radius: 10
                    readonly property bool sel: index === emojiCol.toneSel
                    color: (sel || toneArea.containsMouse) ? Theme.primarySelected : "transparent"
                    border.width: sel ? 1 : 0
                    border.color: Qt.rgba(island.accent.r, island.accent.g, island.accent.b, 0.55)
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    StyledText {
                        anchors.centerIn: parent
                        text: EmojiData.withTone(emojiCol.toneBase, modelData)
                        font.pixelSize: 22
                    }
                    MouseArea {
                        id: toneArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (containsMouse) emojiCol.toneSel = index
                        onClicked: {
                            const v = EmojiData.withTone(emojiCol.toneBase, modelData)
                            emojiCol.toneBase = ""
                            emojiCol.pick(v)
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: EmojiData.nameOf(EmojiData.withTone(emojiCol.toneBase, modelData)) || I18n.tr("Skin tone")
                        Accessible.onPressAction: clicked(null)
                    }
                }
            }
        }
    }

    // emoji grid — virtualized: only the ~6 visible rows exist at a time
    GridView {
        id: grid
        width: parent.width; height: 232; clip: true
        cellWidth: emojiCol.cell; cellHeight: emojiCol.cell
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        model: emojiCol.items
        StyledText {
            anchors.centerIn: parent
            visible: emojiCol.items.length === 0
            text: searchField.text.trim().length > 0 ? I18n.tr("No emoji found") : I18n.tr("No recent emoji")
            color: island.subText; font.pixelSize: Theme.fontSizeSmall
        }
        delegate: Rectangle {
            width: emojiCol.cell; height: emojiCol.cell; radius: 10
            readonly property bool selected: index === emojiCol.selIndex
            color: selected ? Theme.primarySelected : (cellArea.containsMouse ? Theme.surfaceLight : "transparent")
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
                    // resolve toned recents back to their base (✌🏽 -> ✌️)
                    const base = EmojiData.datasetBase(emojiCol.emojiOf(modelData))
                    if (mouse.button === Qt.RightButton && EmojiData.toneable(base)) {
                        emojiCol.toneBase = base   // right-click = skin-tone variants
                        return
                    }
                    emojiCol.pick(modelData)
                }
                // long-press = skin tones too (touch has no right-click)
                onPressAndHold: {
                    const base = EmojiData.datasetBase(emojiCol.emojiOf(modelData))
                    if (EmojiData.toneable(base)) emojiCol.toneBase = base
                }
                Accessible.role: Accessible.Button
                Accessible.name: EmojiData.nameOf(emojiCol.emojiOf(modelData)) || emojiCol.emojiOf(modelData)
                Accessible.onPressAction: emojiCol.pick(modelData)
            }
        }
    }

    // ---- footer preview (macOS picker): selected emoji + its name, plus the
    // keyboard cheatsheet on the right ----
    Item {
        width: parent.width; height: 30
        visible: emojiCol.items.length > 0
        readonly property string previewChar: {
            if (emojiCol.toneBase !== "")
                return EmojiData.withTone(emojiCol.toneBase, EmojiData.TONES[emojiCol.toneSel])
            return emojiCol.emojiOf(emojiCol.items.length > emojiCol.selIndex ? emojiCol.items[emojiCol.selIndex] : null)
        }
        StyledText {
            id: pvChar
            anchors.left: parent.left; anchors.leftMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            text: parent.previewChar; font.pixelSize: 20
        }
        StyledText {
            anchors.left: pvChar.right; anchors.leftMargin: Theme.spacingS
            anchors.right: pvHint.left; anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: EmojiData.nameOf(parent.previewChar)
            elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
            color: island.textColor; font.pixelSize: Theme.fontSizeSmall
        }
        StyledText {
            id: pvHint
            anchors.right: parent.right; anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            text: emojiCol.toneBase !== "" ? I18n.tr("←/→ · Enter · Esc")
                : (EmojiData.toneable(parent.previewChar) ? I18n.tr("Tab tabs · Ctrl+T tones") : I18n.tr("Tab tabs · Enter insert"))
            color: island.subText; font.pixelSize: Theme.fontSizeSmall - 3
        }
    }
}
