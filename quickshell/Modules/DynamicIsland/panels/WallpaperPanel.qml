import Qt.labs.folderlistmodel
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.Widgets

// Wallpaper picker (drill-down, island-native). A thumbnail grid of the current
// wallpaper folder (DMS SessionData / CacheData brain), click to apply live.
// Folder browse, cycling toggle and manual prev/next reuse the same native
// services the DankDash WallpaperTab drives. Reads/writes island state via
// `island`; exposes `implicitHeight` (read by the controller's pillH).
// Per-monitor aware: when SessionData.perMonitorWallpaper is on, it targets
// THIS island's monitor (island.monitorName).
Column {
    id: wpCol
    property var island: null

    // ----- brain: current folder + selected wallpaper (mirrors WallpaperTab) -----
    property string targetScreenName: (SessionData.perMonitorWallpaper && island && island.monitorName) ? island.monitorName : ""
    property string wallpaperDir: ""

    // ----- keyboard navigation (3-col grid; Enter applies, Esc backs out) -----
    property int selIndex: 0
    readonly property int columns: Math.max(1, Math.round(wpGrid.width / wpGrid.cellWidth))
    function move(dx, dy) {
        const n = wpModel.count
        if (n === 0) return
        var i = selIndex + dx + dy * columns
        if (i < 0) i = 0
        if (i > n - 1) i = n - 1
        selIndex = i
    }
    function pathAt(i) {
        if (i < 0 || i >= wpModel.count) return ""
        const fp = wpModel.get(i, "filePath")
        return fp ? fp.toString().replace(/^file:\/\//, '') : ""
    }
    function applySel() {
        const p = pathAt(selIndex)
        if (p) setCurrentWallpaper(p)
    }
    // place the cursor on the currently-applied wallpaper when the view opens
    function syncSelToCurrent() {
        const cur = getCurrentWallpaper()
        for (var i = 0; i < wpModel.count; i++) {
            if (pathAt(i) === cur) { selIndex = i; return }
        }
        selIndex = 0
    }
    Connections {
        target: wpModel
        function onStatusChanged() { if (wpModel.status === FolderListModel.Ready) wpCol.syncSelToCurrent() }
        function onCountChanged() { if (wpCol.selIndex > Math.max(0, wpModel.count - 1)) wpCol.selIndex = Math.max(0, wpModel.count - 1) }
    }

    function getCurrentWallpaper() {
        if (SessionData.perMonitorWallpaper && targetScreenName)
            return SessionData.getMonitorWallpaper(targetScreenName)
        return SessionData.wallpaperPath
    }
    function setCurrentWallpaper(path) {
        if (SessionData.perMonitorWallpaper && targetScreenName)
            SessionData.setMonitorWallpaper(targetScreenName, path)
        else
            SessionData.setWallpaper(path)
    }
    function loadWallpaperDirectory() {
        const cur = getCurrentWallpaper()
        if (!cur || cur.startsWith("#")) {
            wallpaperDir = (CacheData.wallpaperLastPath && CacheData.wallpaperLastPath !== "") ? CacheData.wallpaperLastPath : ""
            return
        }
        wallpaperDir = cur.substring(0, cur.lastIndexOf('/'))
    }
    function fileNameOf(path) {
        const p = (path || "").toString().replace(/^file:\/\//, '')
        return p.substring(p.lastIndexOf('/') + 1)
    }

    // lazily loaded: created on first open (no longer enumerating the wallpaper
    // dir at shell boot for every monitor), and born visible — onVisibleChanged
    // won't fire for the initial state, so activate here too
    Component.onCompleted: {
        loadWallpaperDirectory()
        if (visible) { syncSelToCurrent(); wpGrid.forceActiveFocus() }
    }
    onVisibleChanged: if (visible) {
        loadWallpaperDirectory()
        syncSelToCurrent()
        wpGrid.forceActiveFocus()
    }
    Connections {
        target: SessionData
        function onWallpaperPathChanged() { wpCol.loadWallpaperDirectory() }
        function onMonitorWallpapersChanged() { wpCol.loadWallpaperDirectory() }
        function onPerMonitorWallpaperChanged() { wpCol.loadWallpaperDirectory() }
    }

    FolderListModel {
        id: wpModel
        showDirs: false; showFiles: true; showDotAndDotDot: false; showHidden: false
        caseSensitive: false; sortField: FolderListModel.Name
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.jxl", "*.avif", "*.heif", "*.exr"]
        folder: wpCol.wallpaperDir ? "file://" + wpCol.wallpaperDir.split('/').map(s => encodeURIComponent(s)).join('/') : ""
    }

    // folder picker — same native modal the DankDash wallpaper tab uses
    FileBrowserSurfaceModal {
        id: wpBrowser
        browserTitle: I18n.tr("Select Wallpaper Directory", "wallpaper directory file browser title")
        browserIcon: "folder_open"
        browserType: "wallpaper"
        showHiddenFiles: false
        fileExtensions: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.jxl", "*.avif", "*.heif", "*.exr"]
        onFileSelected: path => {
            const clean = path.replace(/^file:\/\//, '')
            wpCol.setCurrentWallpaper(clean)
            const dir = clean.substring(0, clean.lastIndexOf('/'))
            if (dir) {
                wpCol.wallpaperDir = dir
                CacheData.wallpaperLastPath = dir
                CacheData.saveCache()
            }
            close()
        }
    }

    // ----- drill-view shell (matches the other panels) -----
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "wallpaper" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "wallpaper" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    // header: back + title + folder browse
    Item {
        width: parent.width; height: 34
        Rectangle {
            id: wpBack
            width: 30; height: 30; radius: 9
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: wpBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: wpBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: wpBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
        }
        StyledText { anchors.left: wpBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Wallpaper"); color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true }
        Rectangle {
            id: wpFolder
            width: 30; height: 30; radius: 9
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            color: wpFolderArea.containsMouse ? Theme.primaryHover : Theme.surfaceLight
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            scale: wpFolderArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "folder_open"; size: 17; color: wpFolderArea.containsMouse ? island.accent : island.textColor }
            ToolTip.visible: wpFolderArea.containsMouse; ToolTip.text: I18n.tr("Browse folder"); ToolTip.delay: 400
            MouseArea { id: wpFolderArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wpBrowser.open() }
        }
    }

    // thumbnail grid (GridView recycles delegates → large folders stay cheap)
    Item {
        width: parent.width; height: 232
        GridView {
            id: wpGrid
            anchors.fill: parent
            clip: true
            cellWidth: width / 3
            cellHeight: cellWidth * 0.62
            boundsBehavior: Flickable.StopAtBounds
            model: wpModel
            cacheBuffer: cellHeight * 4

            // keyboard cursor: drive currentIndex + keep it scrolled into view.
            // built-in key nav is off so our handlers own arrows/hjkl/Enter/Esc.
            keyNavigationEnabled: false
            currentIndex: wpCol.selIndex
            highlightFollowsCurrentItem: true
            highlightMoveDuration: Theme.shortDuration
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
            Keys.onLeftPressed: wpCol.move(-1, 0)
            Keys.onRightPressed: wpCol.move(1, 0)
            Keys.onUpPressed: wpCol.move(0, -1)
            Keys.onDownPressed: wpCol.move(0, 1)
            Keys.onReturnPressed: wpCol.applySel()
            Keys.onEnterPressed: wpCol.applySel()
            Keys.onEscapePressed: island.panelView = "controls"
            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_H: wpCol.move(-1, 0); event.accepted = true; break
                case Qt.Key_L: wpCol.move(1, 0);  event.accepted = true; break
                case Qt.Key_K: wpCol.move(0, -1); event.accepted = true; break
                case Qt.Key_J: wpCol.move(0, 1);  event.accepted = true; break
                case Qt.Key_Backspace: island.panelView = "controls"; event.accepted = true; break
                }
            }
            highlight: Item {
                z: 2
                Rectangle {
                    anchors.fill: parent; anchors.margins: Theme.spacingXS
                    color: "transparent"; radius: Theme.cornerRadius
                    border.width: 3; border.color: wpCol.island.accent
                }
            }

            delegate: Item {
                width: wpGrid.cellWidth; height: wpGrid.cellHeight
                readonly property string path: model.filePath ? model.filePath.toString().replace(/^file:\/\//, '') : ""
                readonly property bool selected: wpCol.getCurrentWallpaper() === path

                Rectangle {
                    id: card
                    anchors.fill: parent; anchors.margins: Theme.spacingXS
                    radius: Theme.cornerRadius
                    color: Theme.surfaceLight
                    clip: true
                    // applied wallpaper = check badge (below); the accent ring is the
                    // keyboard cursor (GridView highlight), so cards stay ring-free
                    // except a faint hover hint.
                    border.width: cardArea.containsMouse && !selected ? 1 : 0
                    border.color: Qt.rgba(island.accent.r, island.accent.g, island.accent.b, 0.5)
                    scale: cardArea.pressed ? 0.95 : 1.0
                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }

                    Rectangle {
                        id: thumbMask
                        anchors.fill: parent; radius: Theme.cornerRadius; visible: false; layer.enabled: true
                    }
                    CachingImage {
                        id: thumb
                        anchors.fill: parent
                        imagePath: path; maxCacheSize: 256
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0; maskSource: thumbMask }
                    }
                    // dim the non-applied thumbnails slightly so the active one pops
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius
                        color: "black"; opacity: selected ? 0 : (cardArea.containsMouse ? 0 : 0.18)
                        Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
                    }
                    // applied check badge
                    Rectangle {
                        visible: selected
                        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 5
                        width: 20; height: 20; radius: 10; color: island.accent
                        DankIcon { anchors.centerIn: parent; name: "check"; size: 13; color: Theme.primaryText }
                    }
                    MouseArea {
                        id: cardArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { wpCol.selIndex = index; if (path) wpCol.setCurrentWallpaper(path) }
                    }
                }
            }
        }

        // empty state
        Column {
            anchors.centerIn: parent; spacing: Theme.spacingXS
            visible: wpModel.count === 0
            DankIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "wallpaper"; size: 30; color: island.subText }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("No wallpapers — browse a folder")
                color: island.subText; font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    // footer: cycling toggle + manual prev/next + current filename
    Item {
        width: parent.width; height: 38
        Row {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS
            // auto-cycle toggle
            Rectangle {
                width: 32; height: 32; radius: 10
                readonly property bool on: SessionData.wallpaperCyclingEnabled
                color: on ? island.accent : (cycArea.containsMouse ? Theme.primaryHover : Theme.surfaceLight)
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                scale: cycArea.pressed ? 0.9 : 1.0
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                DankIcon { anchors.centerIn: parent; name: "shuffle"; size: 17; color: parent.on ? Theme.primaryText : island.textColor }
                ToolTip.visible: cycArea.containsMouse; ToolTip.text: I18n.tr("Auto-cycle wallpaper"); ToolTip.delay: 400
                MouseArea { id: cycArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: SessionData.setWallpaperCyclingEnabled(!SessionData.wallpaperCyclingEnabled) }
            }
            // manual prev / next
            Rectangle {
                width: 32; height: 32; radius: 10
                color: prevArea.containsMouse ? Theme.primaryHover : Theme.surfaceLight
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                scale: prevArea.pressed ? 0.9 : 1.0
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                DankIcon { anchors.centerIn: parent; name: "skip_previous"; size: 18; color: prevArea.containsMouse ? island.accent : island.textColor }
                MouseArea { id: prevArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: WallpaperCyclingService.cyclePrevManually() }
            }
            Rectangle {
                width: 32; height: 32; radius: 10
                color: nextArea.containsMouse ? Theme.primaryHover : Theme.surfaceLight
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                scale: nextArea.pressed ? 0.9 : 1.0
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                DankIcon { anchors.centerIn: parent; name: "skip_next"; size: 18; color: nextArea.containsMouse ? island.accent : island.textColor }
                MouseArea { id: nextArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: WallpaperCyclingService.cycleNextManually() }
            }
        }
        StyledText {
            anchors.right: parent.right; anchors.left: parent.left; anchors.leftMargin: 120
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: wpCol.fileNameOf(wpCol.getCurrentWallpaper())
            color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1
            elide: Text.ElideMiddle; maximumLineCount: 1; wrapMode: Text.NoWrap
        }
    }
}
