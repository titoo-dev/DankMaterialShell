# "Ask the island" (#5) — design

**Date:** 2026-06-22 · **Status:** approved (design) · **Branch:** `feat/dynamic-island`
**Builds on:** the island panel/drill system, the QuizWidget `claude -p` pattern (`Proc.runCommand`, `QuizEngine.claudeBinary`, `QuizEngine.mdToHtml`).

## Problem
A Spotlight-like input in the island that sends a question to `claude -p` and shows the
answer — a mini-AI always at hand.

## Approach
An `AskService` singleton runs `claude -p` via `Proc.runCommand` and holds
question/answer/loading/error; an `AskPanel` drill view provides the input + rendered
answer. Reuses the existing panel system and markdown renderer.

## Components
### 1. `quickshell/Services/AskService.qml` (new singleton)
- `property string question`, `property string answer`, `property bool loading`, `property string error`.
- `function ask(q)`: trim; ignore empty; set `question=q`, `answer=""`, `error=""`, `loading=true`;
  `Proc.runCommand("island.ask", [QuizEngine.claudeBinary(Quickshell.env("HOME")), "-p", q], cb, 0, 60000)`
  where `cb(stdout, exitCode)` sets `loading=false` and either `answer=stdout.trim()` (exit 0,
  non-empty) or `error = I18n.tr("No response") / stderr`.
- `function clear()`: reset all.
- imports `qs.Common` (Proc) and the QuizWidget engine (`import "../PLUGINS/QuizWidget/QuizEngine.js" as QuizEngine`) — or duplicate the tiny `claudeBinary` helper to avoid cross-importing a plugin. **Decision:** inline a local `_claudeBin()` (HOME/.local/bin/claude → fallback `claude`) to avoid depending on a plugin path; render markdown in the panel via the same engine import there.

### 2. `quickshell/Modules/DynamicIsland/panels/AskPanel.qml` (new drill view `"ask"`)
- header (back + "Ask") + a `DankTextField` (autofocus; `onAccepted` → `AskService.ask(text)`).
- a `DankFlickable` rendering `AskService.answer` via `QuizEngine.mdToHtml(answer, codeColor, codeBg)`
  as `StyledText { textFormat: Text.RichText }`; shows "💭 …" while `AskService.loading`,
  the error in `Theme.error` if `AskService.error`.
- imports the QuizWidget engine for `mdToHtml` (`import "../../../PLUGINS/QuizWidget/QuizEngine.js" as QuizEngine`).

### 3. Wiring
- `DynamicIsland.qml`: add `"ask"` to `_kbViews` so the panel receives keyboard focus to type.
- `ControlCenterPanel.qml`: register `"ask": askComp` + `Component { id: askComp; AskPanel { island: ccPanel.island } }`.
- `IslandHub.qml`: add `"ask"` to `views`.
- keybind (`hyprland.lua`): `SUPER + ALT + G` → `dms ipc call island open ask`.

## Error handling & edge cases
- Empty question → ignored. `claude` missing / non-zero exit → `error` shown.
- New `ask` while one is loading → the `Proc.runCommand` id is shared (`"island.ask"`), so a
  new call supersedes; UI reflects the latest.
- 60s timeout (claude can be slow) → `cb` with non-zero/empty → error.
- Closing the panel keeps the last answer (re-opening shows it); `clear()` available.

## Testing & verification
- `dms ipc call island open ask` → type a question → "💭" then a rendered markdown answer.
  Directly testable (claude present at `~/.local/bin/claude`). Verify keyboard focus works
  (typing appears). Screenshot. ([[verifying-qml-changes-no-qmllint]])

## Out of scope (v1)
- Conversation history / multi-turn (single Q→A).
- Streaming the answer (waits for full output).
- Tool use / context injection beyond the raw question.
