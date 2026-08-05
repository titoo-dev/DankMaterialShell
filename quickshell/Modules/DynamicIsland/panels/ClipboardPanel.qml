import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Clipboard history (drill-down, island-native). Search field + entry list;
// click copies, ✕ deletes. Needs the window in keyboardFocus OnDemand (the
// controller flips it on for this view).
Column {
    id: clipCol
    property var island: null
    // hold the service watch while the view exists — with refCount at 0 the
    // daemon connection is gated off and the list goes stale
    readonly property QtObject _clipRef: Ref { service: ClipboardService }
    readonly property var entries: {
        const all = ClipboardService.clipboardEntries || []
        const q = clipSearch.text.toLowerCase().trim()
        return q.length === 0 ? all : all.filter(e => (e.preview || "").toLowerCase().includes(q))
    }

    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "clipboard" ? 1 : 0
    visible: opacity > 0
    onVisibleChanged: if (visible) { clipSearch.text = ""; ClipboardService.refresh(); clipSearch.forceActiveFocus() }
    // lazily loaded: the panel is born visible, so onVisibleChanged never fires
    Component.onCompleted: if (visible) { ClipboardService.refresh(); clipSearch.forceActiveFocus() }
    transform: Translate { x: island.panelView === "clipboard" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    function copy(entry) {
        if (!entry) return
        ClipboardService.copyEntry(entry)
        island.panelView = "controls"
        island.pinned = false
        island.settle()
    }

    // ---- keyboard navigation (the view holds an Exclusive grab — it must be
    // fully drivable from the keyboard, like Spotlight) ----
    property int selIndex: 0
    onEntriesChanged: { selIndex = 0; clipFlick.positionViewAtBeginning() }
    function move(delta) {
        const visCount = Math.min(entries.length, 50)
        if (visCount === 0) return
        selIndex = Math.max(0, Math.min(visCount - 1, selIndex + delta))
        clipFlick.positionViewAtIndex(selIndex, ListView.Contain)
    }
    function copySel() { if (entries.length > selIndex) copy(entries[selIndex]) }

    Item {
        id: escHandler
        Keys.onUpPressed: clipCol.move(-1)
        Keys.onDownPressed: clipCol.move(1)
        Keys.onEscapePressed: island.closeIsland()
    }

    // header: back · search field · clear-all
    Item {
        width: parent.width; height: 40
        Rectangle {
            id: clBack
            width: 30; height: 30; radius: width / 2
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: clBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: clBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea {
                // -4 not -7: the search field sits Theme.spacingXS away on the right
                id: clBackArea; anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: island.panelView = "controls"
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("Back")
                Accessible.onPressAction: clicked(null)
            }
        }
        DankTextField {
            id: clipSearch
            anchors.left: clBack.right; anchors.leftMargin: Theme.spacingXS
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            height: 36
            cornerRadius: height / 2
            backgroundColor: Theme.surfaceLight
            leftIconName: "content_paste"
            placeholderText: I18n.tr("Search clipboard")
            ignoreUpDownKeys: true   // ↑/↓ drive the list selection, not the caret
            keyForwardTargets: [escHandler]
            onAccepted: clipCol.copySel()
        }
    }

    // entries list — adaptive height, capped, virtualized (only the visible
    // rows exist; the 50-entry cap stays as the keyboard-nav bound)
    ListView {
        id: clipFlick
        width: parent.width
        height: count === 0 ? 48 : Math.min(contentHeight, 296)
        clip: true; spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        model: clipCol.entries.slice(0, 50)
        StyledText {
            anchors.centerIn: parent
            visible: clipFlick.count === 0
            text: I18n.tr("No clipboard history"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
        }
        delegate: Rectangle {
                    id: clipRow
                    readonly property bool sel: index === clipCol.selIndex
                    width: clipFlick.width; height: 52; radius: 14
                    color: (sel || clipRowArea.containsMouse) ? Theme.surfaceLight : Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.4)
                    border.width: sel ? 1 : 0
                    border.color: Qt.rgba(island.accent.r, island.accent.g, island.accent.b, 0.5)
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                    Rectangle {
                        id: clipIco
                        width: 34; height: 34; radius: 10
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        color: Theme.primaryBackground
                        DankIcon { anchors.centerIn: parent; name: modelData.isImage ? "image" : "content_paste"; size: 17; color: island.accent }
                    }
                    StyledText {
                        anchors.left: clipIco.right; anchors.leftMargin: Theme.spacingM
                        anchors.right: clipDel.left; anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap
                        text: modelData.isImage ? I18n.tr("Image") : (modelData.preview || "")
                        color: island.textColor; font.pixelSize: Theme.fontSizeSmall
                    }
                    Rectangle {  // delete
                        id: clipDel
                        width: 26; height: 26; radius: 13
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                        color: clipDelArea.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : "transparent"
                        opacity: clipRowArea.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                        DankIcon { anchors.centerIn: parent; name: "close"; size: 15; color: clipDelArea.containsMouse ? Theme.error : island.subText }
                        MouseArea {
                            id: clipDelArea; anchors.fill: parent; anchors.margins: -6
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: ClipboardService.deleteEntry(modelData)
                            Accessible.role: Accessible.Button
                            Accessible.name: I18n.tr("Delete")
                            Accessible.onPressAction: clicked(null)
                        }
                    }
                    MouseArea {
                        id: clipRowArea; anchors.fill: parent; hoverEnabled: true; z: -1; cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (containsMouse) clipCol.selIndex = index
                        onClicked: clipCol.copy(modelData)
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.isImage ? I18n.tr("Image") : (modelData.preview || I18n.tr("Clipboard entry"))
                        Accessible.onPressAction: clicked(null)
                    }
        }
    }
}
