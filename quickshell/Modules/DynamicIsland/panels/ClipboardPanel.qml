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
    transform: Translate { x: island.panelView === "clipboard" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    function copy(entry) {
        if (!entry) return
        ClipboardService.copyEntry(entry)
        island.panelView = "controls"
        island.pinned = false
        island.settle()
    }

    Item {
        id: escHandler
        Keys.onEscapePressed: island.panelView = "controls"
    }

    // header: back · search field · clear-all
    Item {
        width: parent.width; height: 40
        Rectangle {
            id: clBack
            width: 30; height: 30; radius: 9
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: clBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: clBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: clBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
        }
        DankTextField {
            id: clipSearch
            anchors.left: clBack.right; anchors.leftMargin: Theme.spacingXS
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            height: 36
            leftIconName: "content_paste"
            placeholderText: I18n.tr("Search clipboard")
            keyForwardTargets: [escHandler]
        }
    }

    // entries list — adaptive height, capped
    Flickable {
        width: parent.width; height: Math.min(clipList.height, 296); clip: true
        contentHeight: clipList.height; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: clipList
            width: parent.width; spacing: 3
            StyledText {
                width: parent.width; height: 48
                visible: clipCol.entries.length === 0
                text: I18n.tr("No clipboard history"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: clipCol.entries.slice(0, 50)
                Rectangle {
                    id: clipRow
                    width: clipList.width; height: 52; radius: 12
                    color: clipRowArea.containsMouse ? Theme.surfaceLight : Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.4)
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
                        MouseArea { id: clipDelArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ClipboardService.deleteEntry(modelData) }
                    }
                    MouseArea {
                        id: clipRowArea; anchors.fill: parent; hoverEnabled: true; z: -1; cursorShape: Qt.PointingHandCursor
                        onClicked: clipCol.copy(modelData)
                    }
                }
            }
        }
    }
}
