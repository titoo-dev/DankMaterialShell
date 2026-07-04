import QtQuick
import QtQuick.Controls
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// Shelf (drill-down, island-native): a Yoink-style parking spot for files,
// links and text snippets. Items are dropped onto the island (the controller's
// DropArea routes here) and can be dragged back OUT into any other app as a
// real system drag (text/uri-list). Click opens, hover reveals copy / remove.
Column {
    id: shelfCol
    property var island: null

    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "shelf" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "shelf" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    readonly property var entries: ShelfService.items

    function iconFor(item) {
        if (item.kind === "link") return "link"
        if (item.kind === "text") return "notes"
        if (item.isDir) return "folder"
        if (item.isImage) return "image"
        if (/\.(mp4|mkv|webm|avi|mov)$/i.test(item.name)) return "movie"
        if (/\.(mp3|flac|ogg|opus|wav|m4a)$/i.test(item.name)) return "music_note"
        if (/\.(zip|tar|gz|xz|zst|7z|rar)$/i.test(item.name)) return "folder_zip"
        if (/\.pdf$/i.test(item.name)) return "picture_as_pdf"
        return "draft"
    }

    // header: back · title + count · clear-all
    Item {
        width: parent.width; height: 40
        Rectangle {
            id: shBack
            width: 30; height: 30; radius: width / 2
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: shBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: shBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea {
                id: shBackArea; anchors.fill: parent; anchors.margins: -6
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: island.panelView = "controls"
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("Back")
                Accessible.onPressAction: clicked(null)
            }
        }
        Column {
            anchors.left: shBack.right; anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter; spacing: 0
            StyledText { text: I18n.tr("Shelf"); color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true }
            StyledText {
                text: shelfCol.entries.length === 0 ? I18n.tr("Empty") : I18n.tr("%1 item(s)").arg(shelfCol.entries.length)
                color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1
            }
        }
        Rectangle {  // clear all
            width: 30; height: 30; radius: width / 2
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            visible: shelfCol.entries.length > 0
            color: shClearArea.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : "transparent"
            scale: shClearArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "delete_sweep"; size: 18; color: shClearArea.containsMouse ? Theme.error : island.subText }
            ToolTip.visible: shClearArea.containsMouse; ToolTip.text: I18n.tr("Clear shelf"); ToolTip.delay: 400
            MouseArea {
                id: shClearArea; anchors.fill: parent; anchors.margins: -6
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: ShelfService.clear()
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("Clear shelf")
                Accessible.onPressAction: clicked(null)
            }
        }
    }

    // drop target affordance — lights up while a drag hovers the island
    Rectangle {
        width: parent.width
        height: shelfCol.entries.length === 0 ? 96 : 44
        radius: 14
        color: island.shelfDropHover ? Qt.rgba(island.accent.r, island.accent.g, island.accent.b, 0.16)
                                     : Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.4)
        border.width: 1.5
        border.color: island.shelfDropHover ? island.accent : Qt.rgba(island.subText.r, island.subText.g, island.subText.b, 0.35)
        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
        Behavior on border.color { ColorAnimation { duration: Theme.shortDuration } }
        Behavior on height { NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing } }
        scale: island.shelfDropHover ? 1.02 : 1.0
        Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
        Row {
            anchors.centerIn: parent; spacing: Theme.spacingS
            DankIcon {
                name: "place_item"; size: 20
                color: island.shelfDropHover ? island.accent : island.subText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: island.shelfDropHover ? I18n.tr("Release to add") : I18n.tr("Drop files, links or text here")
                color: island.shelfDropHover ? island.accent : island.subText
                font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // items — adaptive height, capped; rows drag OUT into other apps
    Flickable {
        id: shelfFlick
        width: parent.width; height: Math.min(shelfList.height, 300); clip: true
        contentHeight: shelfList.height; boundsBehavior: Flickable.StopAtBounds
        visible: shelfCol.entries.length > 0
        Column {
            id: shelfList
            width: parent.width; spacing: 3
            Repeater {
                model: shelfCol.entries
                Rectangle {
                    id: shelfRow
                    width: shelfList.width; height: 52; radius: 14
                    color: shelfRowArea.containsMouse ? Theme.surfaceLight : Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.4)
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                    // real system drag (Wayland data source): other apps receive
                    // text/uri-list / text/plain. The drag starts only once the
                    // row grab image is ready so the cursor carries a preview.
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.mimeData: ShelfService.mimeDataFor(modelData)
                    Drag.onDragFinished: island.shelfDragActive = false
                    DragHandler {
                        id: rowDrag
                        target: null
                        onActiveChanged: {
                            if (active) {
                                // the scrim must unmap BEFORE the drag grabs the
                                // seat, or every drop outside the pill lands on it
                                island.shelfDragActive = true
                                shelfRow.grabToImage(result => {
                                    shelfRow.Drag.imageSource = result.url
                                    shelfRow.Drag.active = true
                                })
                            } else {
                                shelfRow.Drag.active = false
                                island.shelfDragActive = false
                            }
                        }
                    }

                    ClippingRectangle {
                        id: shelfIco
                        // true rounded clip (bbox `clip` left the corners square)
                        width: 36; height: 36; radius: 10
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                        color: Theme.primaryBackground
                        Image {
                            id: shelfThumb
                            anchors.fill: parent
                            source: modelData.isImage ? modelData.url : ""
                            sourceSize.width: 72; sourceSize.height: 72
                            fillMode: Image.PreserveAspectCrop
                            cache: false; asynchronous: true
                            visible: status === Image.Ready
                        }
                        DankIcon {
                            anchors.centerIn: parent
                            name: shelfCol.iconFor(modelData); size: 18; color: island.accent
                            visible: shelfThumb.status !== Image.Ready
                        }
                    }
                    Column {
                        anchors.left: shelfIco.right; anchors.leftMargin: Theme.spacingM
                        anchors.right: shelfActions.left; anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter; spacing: 0
                        StyledText {
                            width: parent.width; elide: Text.ElideMiddle; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: modelData.name
                            color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                        }
                        StyledText {
                            width: parent.width; elide: Text.ElideMiddle; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: modelData.kind === "file" ? modelData.path
                                : modelData.kind === "link" ? modelData.url
                                : modelData.text
                            color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1
                        }
                    }
                    Row {
                        id: shelfActions
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingS; anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        opacity: shelfRowArea.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                        Rectangle {  // copy
                            width: 26; height: 26; radius: 13
                            color: shCopyArea.containsMouse ? Theme.primaryHover : "transparent"
                            DankIcon { anchors.centerIn: parent; name: "content_copy"; size: 14; color: shCopyArea.containsMouse ? island.accent : island.subText }
                            ToolTip.visible: shCopyArea.containsMouse; ToolTip.text: I18n.tr("Copy"); ToolTip.delay: 400
                            MouseArea {
                                // vertical-only growth: the remove button is 2 px away horizontally
                                id: shCopyArea; anchors.fill: parent; anchors.topMargin: -6; anchors.bottomMargin: -6
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: ShelfService.copyItem(modelData)
                                Accessible.role: Accessible.Button
                                Accessible.name: I18n.tr("Copy")
                                Accessible.onPressAction: clicked(null)
                            }
                        }
                        Rectangle {  // remove
                            width: 26; height: 26; radius: 13
                            color: shDelArea.containsMouse ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.18) : "transparent"
                            DankIcon { anchors.centerIn: parent; name: "close"; size: 15; color: shDelArea.containsMouse ? Theme.error : island.subText }
                            ToolTip.visible: shDelArea.containsMouse; ToolTip.text: I18n.tr("Remove"); ToolTip.delay: 400
                            MouseArea {
                                // vertical-only growth: the copy button is 2 px away horizontally
                                id: shDelArea; anchors.fill: parent; anchors.topMargin: -6; anchors.bottomMargin: -6
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: ShelfService.remove(index)
                                Accessible.role: Accessible.Button
                                Accessible.name: I18n.tr("Remove")
                                Accessible.onPressAction: clicked(null)
                            }
                        }
                    }
                    MouseArea {
                        id: shelfRowArea; anchors.fill: parent; hoverEnabled: true; z: -1
                        cursorShape: Qt.OpenHandCursor
                        // click = open (file/link) or copy (text snippet)
                        onClicked: {
                            if (modelData.kind === "text") ShelfService.copyItem(modelData)
                            else ShelfService.openItem(modelData)
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.name || I18n.tr("Shelf item")
                        Accessible.onPressAction: clicked(null)
                    }
                }
            }
        }
    }

    // footer hint — the whole point is dragging things back out
    StyledText {
        width: parent.width
        visible: shelfCol.entries.length > 0
        text: I18n.tr("Drag an item into any app, click to open")
        color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1
        horizontalAlignment: Text.AlignHCenter
    }
}
