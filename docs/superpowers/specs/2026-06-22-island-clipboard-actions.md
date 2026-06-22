# Smart clipboard actions (#6) — design + plan

**Date:** 2026-06-22 · **Status:** approved · **Branch:** `feat/dynamic-island`
**Builds on:** #5 AskService (claude -p), the Ask panel.

## Scope decision
The idea: "when you copy text, the island proposes claude actions (summarize/translate/
explain)." Two concerns make an **auto-pop on every copy** the wrong default:
- **Privacy:** auto-sending clipboard to a cloud LLM is sensitive.
- **Noise + detection:** ClipboardService has no clean "new external copy" signal;
  popping on every copy is intrusive.

So v1 surfaces the same value **user-initiated**: action chips in the Ask panel that run
claude on the **current clipboard** (`wl-paste`). Nothing is sent until the user taps a
chip. The auto-pop-on-copy is a documented follow-up (would need a clipboard watch + an
opt-in setting + content guards).

## Components
### `AskService.qml` (extend)
- Refactor `ask(q)` to share a private `_run(command, label)` that sets
  `loading/question`, runs `askProc`, and reports the answer/error.
- Add `function askClipboard(promptPrefix)`: runs
  `sh -c 'p="$1"; c=$(wl-paste 2>/dev/null); [ -n "$c" ] || { exit 9; }; bin="$HOME/.local/bin/claude"; [ -x "$bin" ] || bin=claude; exec "$bin" -p "$p: $c"'  _  <promptPrefix>`
  via `_run`; on exit code 9 → `error = I18n.tr("Clipboard is empty")`.

### `AskPanel.qml` (extend)
- Below the input field, a `Row` of three chips (`DankButton`): "Résumer", "Traduire",
  "Expliquer" → `AskService.askClipboard(prompt)` with prompts:
  - Résumer → "Résume ce texte en quelques points"
  - Traduire → "Traduis ce texte en anglais"
  - Expliquer → "Explique simplement ce texte"
- The existing answer area renders the result.

## Implementation
- [ ] AskService: extract `_run`, add `askClipboard`, handle empty-clipboard (exit 9).
- [ ] AskPanel: add the 3 clipboard-action chips calling `askClipboard`.
- [ ] Verify: copy some text, open Ask (SUPER+ALT+G), tap "Résumer" → "💭" then a summary.
  Confirm empty-clipboard shows the message. Journal clean. Screenshot.
- [ ] commit `feat(island): clipboard claude actions in the Ask panel (#6)`

## Edge cases
- Empty clipboard → "Clipboard is empty" (exit 9). `wl-paste` missing → error from claude
  step / no output → error. Image clipboard → `wl-paste` yields nothing useful → empty/err.

## Out of scope (documented follow-up)
- Auto-pop on copy (privacy + noise + clipboard-watch); would be opt-in with content
  guards (skip passwords/large blobs).
- Per-action custom prompts UI.
