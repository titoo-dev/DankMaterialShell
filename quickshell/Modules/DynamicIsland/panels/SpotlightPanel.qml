import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Spotlight app launcher (drill-down, island-native). Search field + results with
// full keyboard navigation: type to filter, ↑/↓ to move, Enter to launch, Esc to
// go back. Needs the window in an Exclusive keyboard grab (the controller flips it
// on for this view).
Column {
    id: appCol
    property var island: null
    readonly property int rowH: 48
    readonly property int rowGap: 2

    // computed imperatively (NOT a binding): searchApplications() mutates the
    // service's own caches, which a reactive binding would treat as a loop.
    property var results: []
    property int selIndex: 0

    // subsequence ("fzf-style") fuzzy score: >0 only if every query char appears in
    // order in the text; rewards consecutive runs and word-start hits, prefers short
    // names and early first-match. Complements the service's Levenshtein/typo fuzzy.
    function fuzzy(text, q) {
        if (!text) return 0
        text = text.toLowerCase()
        let ti = 0, qi = 0, score = 0, streak = 0, first = -1
        while (ti < text.length && qi < q.length) {
            if (text.charAt(ti) === q.charAt(qi)) {
                if (first < 0) first = ti
                streak += 1
                score += 1 + streak
                if (ti === 0 || text.charAt(ti - 1) === " ") score += 5
                qi += 1
            } else {
                streak = 0
            }
            ti += 1
        }
        if (qi < q.length) return 0   // not all query chars matched in order
        return score + Math.max(0, 10 - first) - text.length * 0.05
    }

    function refresh() {
        const q = searchField.text.trim()
        const primary = AppSearchService.searchApplications(q)
        if (q.length === 0) {
            results = primary
        } else {
            // append subsequence-fuzzy matches the service missed
            // (e.g. "vsc" -> Visual Studio Code, "frfx" -> Firefox)
            const ql = q.toLowerCase()
            const seen = ({})
            for (var i = 0; i < primary.length; i++) {
                if (primary[i].id) seen[primary[i].id] = true
            }
            const extra = []
            const apps = AppSearchService.getVisibleApplications()
            for (var j = 0; j < apps.length; j++) {
                const app = apps[j]
                if (app.id && seen[app.id]) continue
                const sc = Math.max(fuzzy(app.name, ql), fuzzy(app.id || "", ql) * 0.7, fuzzy(app.genericName || "", ql) * 0.6)
                if (sc > 0) extra.push({ app: app, sc: sc })
            }
            extra.sort((a, b) => b.sc - a.sc)
            results = primary.concat(extra.map(e => e.app))
        }
        selIndex = 0
        appFlick.contentY = 0
    }
    function move(delta) {
        if (results.length === 0) return
        selIndex = Math.max(0, Math.min(results.length - 1, selIndex + delta))
        ensureVisible()
    }
    function ensureVisible() {
        const step = rowH + rowGap
        const y = selIndex * step
        if (y < appFlick.contentY)
            appFlick.contentY = y
        else if (y + rowH > appFlick.contentY + appFlick.height)
            appFlick.contentY = y + rowH - appFlick.height
    }
    function launchSel() { launch(results.length > selIndex ? results[selIndex] : null) }
    function launch(app) {
        if (!app) return
        SessionService.launchDesktopEntry(app)
        island.panelView = "controls"
        island.pinned = false
        island.settle()
    }

    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "apps" ? 1 : 0
    visible: opacity > 0
    onVisibleChanged: if (visible) { searchField.text = ""; refresh(); searchField.forceActiveFocus() }
    transform: Translate { x: island.panelView === "apps" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    // receives forwarded ↑/↓/Esc from the search field (no focus needed for forwardTo)
    Item {
        id: navHandler
        Keys.onUpPressed: appCol.move(-1)
        Keys.onDownPressed: appCol.move(1)
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
            ignoreUpDownKeys: true            // let ↑/↓ drive list navigation instead of the caret
            keyForwardTargets: [navHandler]
            onTextEdited: appCol.refresh()
            onAccepted: appCol.launchSel()
        }
    }

    // results list — adaptive height, capped
    Flickable {
        id: appFlick
        width: parent.width; height: Math.min(appList.height, 296); clip: true
        contentHeight: appList.height; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: appList
            width: parent.width; spacing: appCol.rowGap
            StyledText {
                width: parent.width; height: 44
                visible: appCol.results.length === 0
                text: I18n.tr("No apps found"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: appCol.results.slice(0, 24)
                Rectangle {
                    width: appList.width; height: appCol.rowH; radius: 12
                    readonly property bool selected: index === appCol.selIndex
                    color: selected ? Theme.primarySelected : (appRowArea.containsMouse ? Theme.surfaceLight : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    AppIconRenderer {
                        id: appIco
                        width: 34; height: 34
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        iconValue: (modelData.icon && modelData.icon !== "") ? modelData.icon : ""
                        iconSize: 34
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
                        onPositionChanged: appCol.selIndex = index
                        onClicked: appCol.launch(modelData)
                    }
                }
            }
        }
    }
}
