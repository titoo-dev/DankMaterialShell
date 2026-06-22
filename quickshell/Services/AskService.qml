pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Ask-the-island: runs `claude -p <question>` and holds the answer.
Singleton {
    id: root
    readonly property var log: Log.scoped("AskService")
    property string question: ""
    property string answer: ""
    property bool loading: false
    property string error: ""

    function _run(command, label) {
        root.question = label;
        root.answer = "";
        root.error = "";
        root.loading = true;
        askProc.command = command;
        askProc._out = "";
        askProc.running = true;
    }

    function ask(q) {
        const t = (q || "").trim();
        if (t.length === 0)
            return;
        _run(["sh", "-c", 'bin="$HOME/.local/bin/claude"; [ -x "$bin" ] || bin=claude; exec "$bin" -p "$1"', "_", t], t);
    }

    // run a claude action over the CURRENT clipboard content (wl-paste); nothing is
    // read or sent until this is called (user-initiated).
    function askClipboard(promptPrefix) {
        const p = (promptPrefix || "").trim();
        if (p.length === 0)
            return;
        _run(["sh", "-c",
            'p="$1"; c=$(wl-paste 2>/dev/null); [ -n "$c" ] || exit 9; bin="$HOME/.local/bin/claude"; [ -x "$bin" ] || bin=claude; exec "$bin" -p "$p: $c"',
            "_", p], p + " (presse-papier)");
    }

    function clear() {
        root.question = "";
        root.answer = "";
        root.error = "";
    }

    Process {
        id: askProc
        running: false
        property string _out: ""
        stdout: StdioCollector {
            onStreamFinished: askProc._out = text
        }
        onExited: exitCode => {
            root.loading = false;
            const out = (askProc._out || "").trim();
            if (exitCode === 9)
                root.error = I18n.tr("Clipboard is empty");
            else if (exitCode === 0 && out.length > 0)
                root.answer = out;
            else
                root.error = out.length > 0 ? out : I18n.tr("No response from claude");
        }
    }
}
