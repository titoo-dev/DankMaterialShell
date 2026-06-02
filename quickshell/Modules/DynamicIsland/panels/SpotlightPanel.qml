import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Spotlight app launcher (drill-down, island-native). Search field + results;
// Enter launches the top hit, Esc returns to the hub. Needs the window in
// keyboardFocus OnDemand (the controller flips it on for this view).
Column {
    id: appCol
    property var island: null
    // computed imperatively (NOT a binding): searchApplications() mutates the
    // service's own caches, which a reactive binding would treat as a loop.
    property var results: []
    function refresh() { results = AppSearchService.searchApplications(searchField.text) }

    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "apps" ? 1 : 0
    visible: opacity > 0
    onVisibleChanged: if (visible) { searchField.text = ""; refresh(); searchField.forceActiveFocus() }
    transform: Translate { x: island.panelView === "apps" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    function launch(app) {
        if (!app) return
        SessionService.launchDesktopEntry(app)
        island.panelView = "controls"
        island.pinned = false
        island.settle()
    }

    // receives forwarded Esc from the search field -> back to hub
    Item {
        id: escHandler
        Keys.onEscapePressed: island.panelView = "controls"
    }

    // header: back · search field
    Item {
        width: parent.width; height: 40
        Rectangle {
            id: aBack
            width: 30; height: 30; radius: 9
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: aBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: aBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: aBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
        }
        DankTextField {
            id: searchField
            anchors.left: aBack.right; anchors.leftMargin: Theme.spacingXS
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            height: 36
            leftIconName: "search"
            placeholderText: I18n.tr("Search apps")
            keyForwardTargets: [escHandler]
            onTextEdited: appCol.refresh()
            onAccepted: appCol.launch(appCol.results.length > 0 ? appCol.results[0] : null)
        }
    }

    // results list — adaptive height, capped
    Flickable {
        width: parent.width; height: Math.min(appList.height, 296); clip: true
        contentHeight: appList.height; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: appList
            width: parent.width; spacing: 2
            StyledText {
                width: parent.width; height: 44
                visible: appCol.results.length === 0
                text: I18n.tr("No apps found"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: appCol.results.slice(0, 24)
                Rectangle {
                    width: appList.width; height: 48; radius: 12
                    readonly property bool first: index === 0
                    color: appRowArea.containsMouse ? Theme.surfaceLight : (first ? Qt.rgba(Theme.surfaceLight.r, Theme.surfaceLight.g, Theme.surfaceLight.b, 0.4) : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    AppIconRenderer {
                        id: appIco
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        iconValue: (modelData.icon && modelData.icon !== "") ? modelData.icon : ""
                        iconSize: 32
                        fallbackText: (modelData.name && modelData.name.length > 0) ? modelData.name.charAt(0).toUpperCase() : "A"
                    }
                    Column {
                        anchors.left: appIco.right; anchors.leftMargin: Theme.spacingM
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter; spacing: 0
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: modelData.name || I18n.tr("Unknown"); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                        StyledText {
                            width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: modelData.genericName || modelData.comment || ""
                            visible: text.length > 0
                            color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2
                        }
                    }
                    MouseArea {
                        id: appRowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: appCol.launch(modelData)
                    }
                }
            }
        }
    }
}
