import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Spotlight launcher (drill-down, island-native), multi-provider like macOS:
// apps, app actions (desktop-entry actions), clipboard entries and an inline
// calculator share one keyboard-navigable result list. Type to filter, ↑/↓ to
// move, Enter to launch/copy, Esc to go back. Needs the window in an Exclusive
// keyboard grab (the controller flips it on for this view).
Column {
    id: appCol
    property var island: null
    readonly property int rowH: 48
    readonly property int rowGap: 2
    readonly property int maxRows: 24

    // rows: { kind: "calc"|"app"|"action"|"clip", ... } — computed imperatively
    // (NOT a binding): searchApplications() mutates the service's own caches,
    // which a reactive binding would treat as a loop.
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

    // inline calculator: digits/operators only, evaluated in a strict sandboxed
    // expression (no identifiers can survive the whitelist regex). "= 2*3" or
    // a bare "23*48+2" both work; a lone number is NOT a calculation.
    function tryCalc(q) {
        if (!q || q.length < 3) return null
        let expr = q.startsWith("=") ? q.substring(1) : q
        expr = expr.trim()
        if (!/[0-9]/.test(expr) || !/[+\-*/%^]/.test(expr)) return null
        if (!/^[0-9+\-*/%^().,\s]+$/.test(expr)) return null
        expr = expr.replace(/\^/g, "**").replace(/,/g, ".")
        try {
            const v = Function('"use strict"; return (' + expr + ')')()
            if (typeof v !== "number" || !isFinite(v)) return null
            return Math.abs(v - Math.round(v)) < 1e-10 ? String(Math.round(v)) : String(Math.round(v * 1e6) / 1e6)
        } catch (e) {
            return null
        }
    }

    function refresh() {
        const q = searchField.text.trim()
        var rows = []

        // calculator first (macOS shows the math hit on top)
        const calc = tryCalc(q)
        if (calc !== null) rows.push({ kind: "calc", display: calc, expr: q })

        // applications: frecency/prefix results from the service, then append
        // subsequence-fuzzy matches it missed (e.g. "vsc" -> Visual Studio Code)
        const primary = AppSearchService.searchApplications(q)
        var apps
        if (q.length === 0) {
            apps = primary
        } else {
            const ql = q.toLowerCase()
            const seen = ({})
            for (var i = 0; i < primary.length; i++) {
                if (primary[i].id) seen[primary[i].id] = true
            }
            const extra = []
            const all = AppSearchService.getVisibleApplications()
            for (var j = 0; j < all.length; j++) {
                const app = all[j]
                if (app.id && seen[app.id]) continue
                const sc = Math.max(fuzzy(app.name, ql), fuzzy(app.id || "", ql) * 0.7, fuzzy(app.genericName || "", ql) * 0.6)
                if (sc > 0) extra.push({ app: app, sc: sc })
            }
            extra.sort((a, b) => b.sc - a.sc)
            apps = primary.concat(extra.map(e => e.app))
        }
        const appCap = q.length === 0 ? maxRows : 12
        for (var k = 0; k < apps.length && k < appCap; k++) rows.push({ kind: "app", app: apps[k] })

        if (q.length >= 2) {
            // desktop-entry actions ("New private window", "Mute", ...)
            const ql2 = q.toLowerCase()
            const acts = AppSearchService.searchAppActions(ql2, AppSearchService.getVisibleApplications())
            acts.sort((a, b) => b.score - a.score)
            for (var m = 0; m < acts.length && m < 3; m++) {
                const a = acts[m].app
                rows.push({ kind: "action", name: a.name, icon: a.icon || "", parentName: a.comment || "", parentApp: a.parentApp, actionData: a.actionData })
            }
            // clipboard history hits
            const clips = ClipboardService.getLauncherEntries(q, 4, 2)
            for (var c = 0; c < clips.length; c++) {
                const e = clips[c]
                rows.push({ kind: "clip", entry: e, preview: ClipboardService.getEntryPreview(e), isImage: e.isImage === true })
            }
        }

        results = rows
        selIndex = 0
        appFlick.contentY = 0
    }
    function move(delta) {
        // clamp to what is actually RENDERED, so the selection can never
        // scroll past the visible rows
        const visCount = Math.min(results.length, maxRows)
        if (visCount === 0) return
        selIndex = Math.max(0, Math.min(visCount - 1, selIndex + delta))
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
    function launchSel() { activate(results.length > selIndex ? results[selIndex] : null) }
    function activate(row) {
        if (!row) return
        if (row.kind === "app") {
            SessionService.launchDesktopEntry(row.app)
        } else if (row.kind === "action") {
            SessionService.launchDesktopAction(row.parentApp, row.actionData)
        } else if (row.kind === "clip") {
            ClipboardService.copyEntry(row.entry)
            if (typeof ToastService !== "undefined") ToastService.showInfo(I18n.tr("Copied"))
        } else if (row.kind === "calc") {
            Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "island-calc", row.display])
            if (typeof ToastService !== "undefined") ToastService.showInfo("= " + row.display + " — " + I18n.tr("copied"))
        }
        island.panelView = "controls"
        island.pinned = false
        island.settle()
    }

    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "apps" ? 1 : 0
    visible: opacity > 0
    onVisibleChanged: if (visible) { searchField.text = ""; refresh(); searchField.forceActiveFocus() }
    // lazily loaded: the panel is born visible, so onVisibleChanged never fires
    Component.onCompleted: if (visible) { refresh(); searchField.forceActiveFocus() }
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
            width: 30; height: 30; radius: width / 2
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: aBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: aBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea {
                // -4 not -7: the search field sits Theme.spacingXS away on the right
                id: aBackArea; anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: island.panelView = "controls"
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("Back")
                Accessible.onPressAction: clicked(null)
            }
        }
        DankTextField {
            id: searchField
            anchors.left: aBack.right; anchors.leftMargin: Theme.spacingXS
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            height: 36
            cornerRadius: height / 2
            backgroundColor: Theme.surfaceLight
            leftIconName: "search"
            placeholderText: I18n.tr("Apps, actions, clipboard, =math…")
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
                text: I18n.tr("No results"); color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: appCol.results.slice(0, appCol.maxRows)
                Rectangle {
                    width: appList.width; height: appCol.rowH; radius: height / 2
                    readonly property bool selected: index === appCol.selIndex
                    readonly property string kind: modelData.kind
                    color: selected ? Theme.primarySelected : (appRowArea.containsMouse ? Theme.surfaceLight : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                    // leading: app icon, or a glyph for calc/clipboard rows
                    AppIconRenderer {
                        id: appIco
                        visible: kind === "app" || kind === "action"
                        width: 34; height: 34
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        iconValue: {
                            if (kind === "app") return (modelData.app.icon && modelData.app.icon !== "") ? modelData.app.icon : ""
                            if (kind === "action") return modelData.icon || ""
                            return ""
                        }
                        iconSize: 34
                        fallbackText: {
                            const n = kind === "app" ? (modelData.app.name || "") : (modelData.name || "")
                            return n.length > 0 ? n.charAt(0).toUpperCase() : "A"
                        }
                    }
                    Rectangle {
                        visible: kind === "calc" || kind === "clip"
                        width: 34; height: 34; radius: width / 2
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        color: Theme.primaryBackground
                        DankIcon {
                            anchors.centerIn: parent; size: 18; color: island.accent
                            name: kind === "calc" ? "calculate" : (modelData.isImage ? "image" : "content_paste")
                        }
                    }

                    Column {
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM + 34 + Theme.spacingM
                        anchors.right: kindBadge.visible ? kindBadge.left : parent.right; anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter; spacing: 0
                        StyledText {
                            width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: {
                                if (kind === "app") return modelData.app.name || I18n.tr("Unknown")
                                if (kind === "action") return modelData.name || ""
                                if (kind === "clip") return modelData.isImage ? I18n.tr("Image") : (modelData.preview || "")
                                return "= " + modelData.display
                            }
                            color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                        }
                        StyledText {
                            width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: {
                                if (kind === "app") return modelData.app.genericName || modelData.app.comment || ""
                                if (kind === "action") return modelData.parentName || ""
                                if (kind === "clip") return I18n.tr("Clipboard")
                                return modelData.expr
                            }
                            visible: text.length > 0
                            color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2
                        }
                    }

                    // trailing kind badge for non-app rows
                    Rectangle {
                        id: kindBadge
                        visible: kind !== "app"
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        width: kindLbl.implicitWidth + 12; height: 18; radius: 9
                        color: Theme.primarySelected
                        StyledText {
                            id: kindLbl
                            anchors.centerIn: parent
                            text: kind === "action" ? I18n.tr("Action") : kind === "clip" ? I18n.tr("Clipboard") : I18n.tr("Copy")
                            color: island.accent; font.pixelSize: Theme.fontSizeSmall - 3; font.bold: true
                        }
                    }

                    MouseArea {
                        id: appRowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onPositionChanged: appCol.selIndex = index
                        onClicked: appCol.activate(modelData)
                        Accessible.role: Accessible.Button
                        Accessible.name: {
                            if (kind === "app") return modelData.app.name || I18n.tr("Unknown")
                            if (kind === "action") return modelData.name || ""
                            if (kind === "clip") return modelData.isImage ? I18n.tr("Image") : (modelData.preview || I18n.tr("Clipboard"))
                            return "= " + modelData.display
                        }
                        Accessible.onPressAction: clicked(null)
                    }
                }
            }
        }
    }
}
