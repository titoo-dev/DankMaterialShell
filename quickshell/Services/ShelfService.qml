pragma Singleton

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

// Island Shelf (macOS Yoink-style): a temporary parking spot for files, links
// and text snippets dragged onto the Dynamic Island. Items persist across
// shell restarts; dead file entries are pruned on load and after every add.
Singleton {
    id: root

    readonly property var log: Log.scoped("ShelfService")
    readonly property int maxItems: 50

    // [{kind: "file"|"link"|"text", url, path, name, isDir, isImage, text, addedAt}]
    property var items: []
    readonly property int count: items.length

    // emitted for every batch that actually lands (drop, IPC, …) so the
    // island can give feedback (bump / Live Activity)
    signal added(int n)

    property bool _loading: true

    function addUrls(urls) {
        let arr = items.slice()
        let n = 0
        const statPaths = []
        for (var i = 0; i < (urls ? urls.length : 0); i++) {
            const it = _itemFromUrl(String(urls[i]))
            if (!it) continue
            if (arr.some(x => x.kind !== "text" && x.url === it.url)) continue
            arr.unshift(it)
            n++
            if (it.kind === "file") statPaths.push(it.path)
        }
        if (n === 0) return
        _commit(arr)
        added(n)
        if (statPaths.length > 0) _stat(statPaths)
    }

    // raw text/uri-list payload (newline-separated, "#" comments)
    function addUriList(raw) {
        if (!raw) return
        addUrls(raw.split(/\r?\n/).map(s => s.trim()).filter(s => s.length > 0 && !s.startsWith("#")))
    }

    function addText(text) {
        const t = (text || "").trim()
        if (t.length === 0) return
        if (items.some(x => x.kind === "text" && x.text === t)) return
        let arr = items.slice()
        arr.unshift({ kind: "text", url: "", path: "", name: t.split("\n")[0].substring(0, 80), isDir: false, isImage: false, text: t, addedAt: Date.now() })
        _commit(arr)
        added(1)
    }

    // plain filesystem path (IPC / scripting entry point)
    function addPath(path) {
        if (!path || !path.startsWith("/")) return
        addUrls(["file://" + encodeURI(path).replace(/#/g, "%23")])
    }

    function _itemFromUrl(u) {
        if (!u || u.length === 0) return null
        if (u.startsWith("file://")) {
            let path = decodeURIComponent(u.substring(7))
            if (path.length > 1 && path.endsWith("/")) path = path.substring(0, path.length - 1)
            const name = path.substring(path.lastIndexOf("/") + 1) || path
            return { kind: "file", url: "file://" + encodeURI(path).replace(/#/g, "%23"), path: path, name: name,
                     isDir: false, isImage: /\.(png|jpe?g|gif|webp|bmp|svg|avif|jxl)$/i.test(name), text: "", addedAt: Date.now() }
        }
        if (/^[a-z][a-z0-9+.-]*:/i.test(u))
            return { kind: "link", url: u, path: "", name: u.replace(/^[a-z]+:\/\//i, ""), isDir: false, isImage: false, text: "", addedAt: Date.now() }
        return null
    }

    function remove(index) {
        if (index < 0 || index >= items.length) return
        let arr = items.slice()
        arr.splice(index, 1)
        _commit(arr)
    }

    function clear() { _commit([]) }

    function openItem(item) {
        if (!item || item.kind === "text") return
        Quickshell.execDetached(["xdg-open", item.kind === "file" ? item.path : item.url])
    }

    // copy as text/uri-list for files (pasteable in file managers), plain text otherwise
    function copyItem(item) {
        if (!item) return
        if (item.kind === "file")
            Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy -t text/uri-list", "_", item.url])
        else
            Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "_", item.kind === "link" ? item.url : item.text])
    }

    function mimeDataFor(item) {
        if (!item) return ({})
        if (item.kind === "file") return ({ "text/uri-list": item.url + "\r\n", "text/plain": item.path })
        if (item.kind === "link") return ({ "text/uri-list": item.url + "\r\n", "text/plain": item.url })
        return ({ "text/plain": item.text })
    }

    function _commit(arr) {
        if (arr.length > maxItems) arr = arr.slice(0, maxItems)
        items = arr
        _save()
    }

    // ---- file reality check: mark directories, drop entries whose file vanished ----
    function _stat(paths) {
        if (paths.length === 0) return
        statProc.command = ["sh", "-c",
            "for p in \"$@\"; do if [ -d \"$p\" ]; then printf 'd\\t%s\\n' \"$p\"; elif [ -e \"$p\" ]; then printf 'f\\t%s\\n' \"$p\"; else printf 'x\\t%s\\n' \"$p\"; fi; done",
            "_"].concat(paths)
        statProc.running = true
    }
    Process {
        id: statProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const flags = {}
                for (const line of (text || "").split("\n")) {
                    const tab = line.indexOf("\t")
                    if (tab > 0) flags[line.substring(tab + 1)] = line.substring(0, tab)
                }
                let arr = root.items.filter(it => it.kind !== "file" || flags[it.path] !== "x")
                let dirty = arr.length !== root.items.length
                arr = arr.map(it => {
                    if (it.kind === "file" && flags[it.path] === "d" && !it.isDir) {
                        dirty = true
                        return Object.assign({}, it, { isDir: true })
                    }
                    return it
                })
                if (dirty) root._commit(arr)
            }
        }
    }

    // ---- persistence (same pattern as SessionData: GenericState/DankMaterialShell) ----
    function _save() {
        if (_loading) return
        shelfFile.setText(JSON.stringify(items))
    }
    FileView {
        id: shelfFile
        path: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/DankMaterialShell/island_shelf.json"
        blockLoading: true
        atomicWrites: true
        watchChanges: false
        onLoaded: {
            try {
                const arr = JSON.parse(shelfFile.text())
                if (Array.isArray(arr)) root.items = arr
            } catch (e) {
                root.log.warn("Corrupt shelf state, starting fresh:", e)
            }
            root._loading = false
            root._stat(root.items.filter(it => it.kind === "file").map(it => it.path))
        }
        onLoadFailed: error => { root._loading = false }
    }
}
