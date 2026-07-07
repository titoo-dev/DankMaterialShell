import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// System tray detail view (drill-down, island-styled): the SNI items as
// proper rows instead of a cramped icon strip in the idle pane. A row click
// activates the app — or opens its menu when the item is menu-only (the
// silent-click bug the strip had); the kebab always opens the menu.
Column {
    id: trayCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "tray" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "tray" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    // same icon-name → file URL rewriting as the idle pane / bar tray
    function iconSourceFor(trayItem) {
        let icon = trayItem && trayItem.icon
        if (!icon) return ""
        if (typeof icon === "string" && icon.includes("?path=")) {
            const chunks = icon.split("?path=")
            const name = chunks[0].split("/").pop()
            return "file://" + chunks[1] + "/" + name
        }
        return icon
    }

    DrillHeader { island: trayCol.island; title: I18n.tr("Tray") }

    ListView {
        id: tlist
        width: parent.width
        height: count === 0 ? 56 : Math.min(contentHeight, 300)
        clip: true; spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: trayCol.island ? trayCol.island.trayItems : []
        StyledText {
            anchors.centerIn: parent
            visible: tlist.count === 0
            text: I18n.tr("No tray applications"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
        }
        delegate: Rectangle {
            id: tRow
            width: tlist.width; height: 52; radius: 14
            color: tRowArea.containsMouse ? Theme.surfaceLight : Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.4)
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            function openMenu(anchorItem) {
                if (!modelData.hasMenu || !modelData.menu) return
                const p = anchorItem.mapToItem(null, 0, 0)
                trayCol.island.openTrayMenu(modelData.menu, Qt.rect(p.x, p.y + anchorItem.height, anchorItem.width, anchorItem.height))
            }

            Image {
                id: tIco
                width: 24; height: 24
                anchors.left: parent.left; anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                source: trayCol.iconSourceFor(modelData)
                sourceSize.width: 48; sourceSize.height: 48
                fillMode: Image.PreserveAspectFit; asynchronous: true
            }
            DankIcon {
                anchors.centerIn: tIco; name: "widgets"; size: 18; color: island.subText
                visible: tIco.status !== Image.Ready
            }
            Column {
                anchors.left: tIco.right; anchors.leftMargin: Theme.spacingM
                anchors.right: tKebab.left; anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter; spacing: 0
                StyledText {
                    width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                    text: modelData.title || modelData.tooltipTitle || modelData.id || I18n.tr("Application")
                    color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                }
                StyledText {
                    width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                    text: modelData.onlyMenu ? I18n.tr("Menu") : (modelData.tooltipTitle && modelData.tooltipTitle !== modelData.title ? modelData.tooltipTitle : I18n.tr("Open"))
                    color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2
                }
            }
            Rectangle {  // kebab: always reaches the SNI menu
                id: tKebab
                width: 28; height: 28; radius: 14
                anchors.right: parent.right; anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: modelData.hasMenu === true
                color: tKebabArea.containsMouse ? Theme.primarySelected : "transparent"
                DankIcon { anchors.centerIn: parent; name: "more_vert"; size: 16; color: tKebabArea.containsMouse ? island.accent : island.subText }
                MouseArea {
                    id: tKebabArea; anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: tRow.openMenu(tKebab)
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("Menu")
                    Accessible.onPressAction: clicked(null)
                }
            }
            MouseArea {
                id: tRowArea; anchors.fill: parent; hoverEnabled: true; z: -1
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) { modelData.secondaryActivate(); return }
                    // menu-only items (many SNI apps) have no activate: clicking
                    // used to do nothing — open their menu instead
                    if (modelData.onlyMenu) tRow.openMenu(tRow)
                    else modelData.activate()
                }
                Accessible.role: Accessible.Button
                Accessible.name: modelData.title || I18n.tr("Tray item")
                Accessible.onPressAction: clicked(null)
            }
        }
    }
}
