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

    function ask(q) {
        const t = (q || "").trim();
        if (t.length === 0)
            return;
        root.question = t;
        root.answer = "";
        root.error = "";
        root.loading = true;
        askProc.command = ["sh", "-c", 'bin="$HOME/.local/bin/claude"; [ -x "$bin" ] || bin=claude; exec "$bin" -p "$1"', "_", t];
        askProc._out = "";
        askProc.running = true;
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
            if (exitCode === 0 && out.length > 0)
                root.answer = out;
            else
                root.error = out.length > 0 ? out : I18n.tr("No response from claude");
        }
    }
}
