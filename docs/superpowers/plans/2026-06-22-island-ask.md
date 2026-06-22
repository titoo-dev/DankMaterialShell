# "Ask the island" Implementation Plan

> REQUIRED SUB-SKILL: superpowers:executing-plans. Checkbox steps.

**Goal:** A Spotlight-style island panel that sends a question to `claude -p` and shows the answer.
**Architecture:** `AskService` runs claude via its own `Process`; `AskPanel` drill view provides input + answer (plain text v1). Keyboard-focused drill view. No Proc/plugin import (robustness).

## Global Constraints
- No `console.*` (use `Log`). Render answer as plain wrapped text in v1 (no markdown dep).
- claude resolved via `sh -c` (`$HOME/.local/bin/claude` → fallback `claude`).
- Keyboard drill views must be in `DynamicIsland._kbViews`.

### Task 1: `AskService.qml`
- [ ] Create `quickshell/Services/AskService.qml`:

```qml
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
        stdout: StdioCollector { onStreamFinished: askProc._out = text }
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
```
- [ ] commit `feat(island): AskService — claude -p question/answer`

### Task 2: `AskPanel.qml`
- [ ] Create `quickshell/Modules/DynamicIsland/panels/AskPanel.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: askCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "ask" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "ask" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    readonly property bool askActive: island && island.mode === "expanded" && island.panelView === "ask"
    onAskActiveChanged: if (askActive) askField.forceActiveFocus()

    RowLayout {
        width: parent.width; spacing: Theme.spacingS
        DankIcon { name: "auto_awesome"; size: 18; color: Theme.primary; Layout.alignment: Qt.AlignVCenter }
        DankTextField {
            id: askField
            Layout.fillWidth: true
            placeholderText: I18n.tr("Ask anything…")
            onAccepted: AskService.ask(text)
        }
    }
    DankFlickable {
        width: parent.width
        height: Math.min(contentHeight, 300)
        contentHeight: ansCol.implicitHeight
        clip: true
        Column {
            id: ansCol
            width: parent.width
            StyledText {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                color: AskService.error.length > 0 ? Theme.error : Theme.surfaceText
                text: AskService.loading ? "💭 " + I18n.tr("Thinking…")
                    : (AskService.error.length > 0 ? AskService.error : AskService.answer)
            }
        }
    }
}
```
- [ ] commit `feat(island): AskPanel — claude question/answer drill view`

### Task 3: wiring (kb-view, registry, IPC, keybind)
- [ ] DynamicIsland `_kbViews`: add `"ask"` → `["apps", "clipboard", "emoji", "wallpaper", "ask"]`
- [ ] ControlCenterPanel registry: `"ask": askComp` + `Component { id: askComp; AskPanel { island: ccPanel.island } }`
- [ ] IslandHub `views`: add `"ask"`
- [ ] hyprland.lua: `hl.bind(mainMod .. " + ALT + G", hl.dsp.exec_cmd("dms ipc call island open ask"))` + reload
- [ ] commit `feat(island): wire Ask panel (kb-view, registry, IPC, keybind)`

### Task 4: verify
- [ ] `dms ipc call island open ask`; type a question; "💭 Thinking…" then answer. Screenshot. No QML errors. Keyboard focus works.

## Self-Review
- AskService (own Process, claude resolve, answer/error/loading) → T1; AskPanel (field+answer, autofocus) → T2; wiring (kb-view crucial for typing, registry, IPC, keybind) → T3; verify → T4.
- Edges: empty ignored; claude missing/non-zero → error; new ask supersedes (same proc). Placeholders none. `"ask"` consistent across _kbViews/registry/views. `ask()`/`answer`/`loading`/`error` consistent T1↔T2.
