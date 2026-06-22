# Quiz Widget — Mouse-Free Keyboard Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Operate the Quiz widget entirely from the keyboard — global hotkeys to open/snooze/dismiss the pending pill, and in-card keys to select/validate/advance/ask/close.

**Architecture:** A global `IpcHandler { target: "quiz" }` in the daemon exposes `open`/`snooze`/`dismiss`, bound to `Super+L`/`+Shift`/`+Alt` in `hyprland.lua`. In-card navigation is handled at the overlay level: a pure resolver `QuizEngine.keyAction(token, mode, contentType, inputActive)` maps a key to an action token, and `QuizOverlay`'s `Keys.onPressed` dispatches it against the existing state machine. Cards stay declarative views.

**Tech Stack:** QML (Quickshell), `Quickshell.Io` `IpcHandler`, plain JS (`QuizEngine.js`) with `node:test` unit tests, Hyprland Lua config.

## Global Constraints

- Do NOT regress the focus-steal fix: the pill (`overlay.mode === "pending"`) keeps `keyboardFocus: None`. Active focus is forced only for opened cards (`open`/`feedback`).
- Keyboard snooze duration = 5 minutes = `300000` ms.
- IPC target name = `"quiz"`; IPC functions return `string` (island idiom).
- Global chords use the free letter `L`: `Super+L`, `Super+Shift+L`, `Super+Alt+L`.
- No qmllint on this machine: verify QML at runtime — scan `journalctl --user -u dms.service` for `.qml:` errors, drive via `dms ipc call …`, behavioral key tests via `wtype` into a sink terminal.
- The plugin runs live from the working tree via the symlink `~/.config/DankMaterialShell/plugins/QuizWidget`; restart with `systemctl --user restart dms.service` to reload edits.
- Plugin id is `quizWidget`; daemon file is `quickshell/PLUGINS/QuizWidget/QuizDaemon.qml`.

---

### Task 1: Global IPC handler (open / snooze / dismiss)

De-risks the core assumption first: that an `IpcHandler` declared inside a dynamically-loaded plugin is reachable via `dms ipc call quiz …`.

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizDaemon.qml` (add `import Quickshell.Io`; add `IpcHandler` block near the other top-level objects, e.g. after the `QuizOverlay { id: overlay … }` block)

**Interfaces:**
- Consumes: existing `overlay` (id) with `mode`, `showPending()`, `reset()`, signal `snoozeRequested(int)`; existing daemon signal wiring `onSnoozeRequested: (ms) => root.snooze(ms)`.
- Produces: IPC target `quiz` with `open(): string`, `snooze(): string`, `dismiss(): string`.

- [ ] **Step 1: Add the import**

At the top of `QuizDaemon.qml`, add after `import Quickshell`:

```qml
import Quickshell.Io
```

- [ ] **Step 2: Add the IpcHandler**

Insert as a child of the root `PluginComponent` (place it right after the `QuizOverlay { … }` block):

```qml
// Contrôle clavier global (depuis n'importe quelle appli) via `dms ipc call quiz <fn>`.
// No-op explicite si aucune pastille n'est en attente.
IpcHandler {
    target: "quiz"

    // Ouvre la pastille en attente (équivaut au clic sur la pastille).
    function open(): string {
        if (overlay.mode !== "pending")
            return "quiz: rien en attente";
        overlay.mode = "open";
        return "quiz: ouvert";
    }

    // Reporte la pastille en attente de 5 min sans l'ouvrir (réutilise le chemin du bouton snooze).
    function snooze(): string {
        if (overlay.mode !== "pending")
            return "quiz: rien en attente";
        overlay.snoozeRequested(300000);
        overlay.reset();
        return "quiz: reporté 5 min";
    }

    // Ignore la pastille en attente sans l'ouvrir (réutilise le chemin de fermeture : onDismissed
    // conserve la notion d'une leçon non validée pour la ré-expliquer plus tard).
    function dismiss(): string {
        if (overlay.mode !== "pending")
            return "quiz: rien en attente";
        overlay.reset();
        return "quiz: ignoré";
    }
}
```

- [ ] **Step 3: Reload and verify the IPC is reachable (the de-risk)**

Run:
```bash
systemctl --user restart dms.service
sleep 6
dms ipc call quiz open
```
Expected: prints `quiz: rien en attente` (no pill pending right after restart). This proves `dms ipc call quiz …` reaches the plugin's IpcHandler. If it instead prints an "unknown target/function" error, STOP — the plugin-IPC assumption is wrong; revisit before continuing.

- [ ] **Step 4: Verify no QML errors**

Run:
```bash
journalctl --user -u dms.service --since "20 sec ago" --no-pager | grep -iE '\.qml:[0-9]|component error|IpcHandler|TypeError' || echo "clean"
```
Expected: `clean` (and earlier `Daemon plugin loaded: quizWidget`).

- [ ] **Step 5: Verify the effect on a real pending pill**

Force a pill, then drive it:
```bash
# force a pending pill via the running daemon's learning timer is slow; instead use a temp check:
dms ipc call quiz dismiss   # still "rien en attente" until a pill exists
```
Then wait for the natural pill (learning mode generates one) OR temporarily lower `firstQuizTimer` during dev. Once `hyprctl layers | grep dms:quiz` shows the pill:
```bash
dms ipc call quiz open      # expect "quiz: ouvert"; hyprctl layers still shows dms:quiz, card now open
```
Expected: `open` returns `quiz: ouvert` and the card opens (overlay grows; `hyprctl layers` width increases).

- [ ] **Step 6: Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizDaemon.qml
git commit -m "feat(quiz-widget): global IPC (quiz open/snooze/dismiss)"
```

---

### Task 2: Hyprland global keybinds

**Files:**
- Modify: `~/personal/dotfiles/hypr/hyprland.lua` (add 3 binds in the keybind section, near the other `dms ipc call …` binds around the island binds)

**Interfaces:**
- Consumes: Task 1's `dms ipc call quiz open|snooze|dismiss`.
- Produces: `Super+L` / `Super+Shift+L` / `Super+Alt+L`.

- [ ] **Step 1: Add the binds**

Add next to the existing `dms ipc call island …` binds:

```lua
hl.bind(mainMod .. " + L",         hl.dsp.exec_cmd("dms ipc call quiz open"))    -- Quiz: ouvrir la pastille en attente
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("dms ipc call quiz snooze"))  -- Quiz: reporter 5 min
hl.bind(mainMod .. " + ALT + L",   hl.dsp.exec_cmd("dms ipc call quiz dismiss")) -- Quiz: ignorer
```

- [ ] **Step 2: Reload Hyprland config**

The lua config is applied via the normal reload mechanism (see how other binds are applied on this host; typically a Hyprland reload). After reload, confirm the binds exist:
```bash
hyprctl binds | grep -iA2 -B1 'quiz' || hyprctl binds | grep -i ' L$'
```
Expected: the three `L` binds appear.

- [ ] **Step 3: Verify end to end**

Press `Super+L` (no pill) → nothing visible (no-op). With a pill pending, `Super+L` opens it, `Super+Shift+L` snoozes it, `Super+Alt+L` dismisses it. Cross-check the no-pill case via:
```bash
dms ipc call quiz open   # "quiz: rien en attente"
```

- [ ] **Step 4: Commit (in ~/personal)**

```bash
cd ~/personal && git add dotfiles/hypr/hyprland.lua && git commit -m "feat(hypr): Super+L quiz keybinds (open/snooze/dismiss)"
```

---

### Task 3: Pure keymap resolver `keyAction` + unit tests

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizEngine.js` (add exported `keyAction`)
- Test: `quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs` (add cases)

**Interfaces:**
- Produces: `keyAction(token, mode, contentType, inputActive) -> string` where `token` is a normalized key (`"A".."Z"`, `"1".."4"`, `"?"`, `"ENTER"`, `"ESC"`), and the return is one of `"select0".."select3"`, `"submit"`, `"next"`, `"ask"`, `"closeAsk"`, `"snooze"`, `"close"`, or `""` (no action).

- [ ] **Step 1: Write the failing tests**

Add to `tests/quizEngine.test.mjs` (it already imports the engine; match existing import style):

```js
test("keyAction — quiz open: A/B/C/D et 1-4 sélectionnent", () => {
  for (const [tok, exp] of [["A","select0"],["B","select1"],["C","select2"],["D","select3"],["1","select0"],["4","select3"]])
    assert.equal(QuizEngine.keyAction(tok, "open", "quiz", false), exp);
});
test("keyAction — quiz open: Entrée valide, S reporte, Échap ferme", () => {
  assert.equal(QuizEngine.keyAction("ENTER", "open", "quiz", false), "submit");
  assert.equal(QuizEngine.keyAction("S", "open", "quiz", false), "snooze");
  assert.equal(QuizEngine.keyAction("ESC", "open", "quiz", false), "close");
});
test("keyAction — quiz feedback: Entrée et Échap ferment", () => {
  assert.equal(QuizEngine.keyAction("ENTER", "feedback", "quiz", false), "close");
  assert.equal(QuizEngine.keyAction("ESC", "feedback", "quiz", false), "close");
});
test("keyAction — leçon: Entrée/N suivant, Q/? questions, Échap ferme", () => {
  assert.equal(QuizEngine.keyAction("ENTER", "open", "lesson", false), "next");
  assert.equal(QuizEngine.keyAction("N", "open", "lesson", false), "next");
  assert.equal(QuizEngine.keyAction("Q", "open", "lesson", false), "ask");
  assert.equal(QuizEngine.keyAction("?", "open", "lesson", false), "ask");
  assert.equal(QuizEngine.keyAction("ESC", "open", "lesson", false), "close");
});
test("keyAction — champ actif: lettres ignorées, Échap referme le champ", () => {
  assert.equal(QuizEngine.keyAction("A", "open", "lesson", true), "");
  assert.equal(QuizEngine.keyAction("N", "open", "lesson", true), "");
  assert.equal(QuizEngine.keyAction("ESC", "open", "lesson", true), "closeAsk");
});
test("keyAction — touche inconnue / mode pending => aucune action", () => {
  assert.equal(QuizEngine.keyAction("Z", "open", "quiz", false), "");
  assert.equal(QuizEngine.keyAction("A", "pending", "quiz", false), "");
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected: FAIL — `QuizEngine.keyAction is not a function`.

- [ ] **Step 3: Implement `keyAction`**

Add to `QuizEngine.js` (and ensure it is exported the same way the other functions are — match the file's existing export mechanism):

```js
function keyAction(token, mode, contentType, inputActive) {
    if (inputActive)
        return token === "ESC" ? "closeAsk" : "";
    if (contentType === "quiz") {
        if (mode === "open") {
            var sel = { "A": 0, "B": 1, "C": 2, "D": 3, "1": 0, "2": 1, "3": 2, "4": 3 };
            if (token in sel) return "select" + sel[token];
            if (token === "ENTER") return "submit";
            if (token === "S") return "snooze";
            if (token === "ESC") return "close";
        } else if (mode === "feedback") {
            if (token === "ENTER" || token === "ESC") return "close";
            if (token === "S") return "snooze";
        }
    } else if (contentType === "lesson" && mode === "open") {
        if (token === "ENTER" || token === "N") return "next";
        if (token === "Q" || token === "?") return "ask";
        if (token === "S") return "snooze";
        if (token === "ESC") return "close";
    }
    return "";
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected: PASS (all new cases green, plus the existing suite still green).

- [ ] **Step 5: Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizEngine.js quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs
git commit -m "feat(quiz-widget): keyAction keymap resolver + tests"
```

---

### Task 4: LessonCard — expose ask-field control

The overlay needs to open/close the question field and know when it is focused (to suspend keymaps).

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/LessonCard.qml`

**Interfaces:**
- Produces: on the `card` root — `property bool inputActive`, `function openAsk()`, `function closeAsk()`.

- [ ] **Step 1: Add the property and functions**

In `LessonCard.qml`, on the root `StyledRect { id: card … }`, add near the existing `askMode`/`_submitAsk` declarations:

```qml
// Vrai quand le champ de question a le focus clavier → l'overlay suspend ses keymaps.
property bool inputActive: askInput.activeFocus

function openAsk() {
    card.askMode = true;
    askInput.forceActiveFocus();
}
function closeAsk() {
    card.askMode = false;
    askInput.text = "";
}
```

(`askInput` is the existing `DankTextField { id: askInput }`. This mirrors the logic already inside the "Des questions ?" button's `onClicked`.)

- [ ] **Step 2: Reload and verify no QML errors**

Run:
```bash
systemctl --user restart dms.service && sleep 6
journalctl --user -u dms.service --since "15 sec ago" --no-pager | grep -iE 'LessonCard|\.qml:[0-9]|component error' || echo "clean"
```
Expected: `clean` and `Daemon plugin loaded: quizWidget`.

- [ ] **Step 3: Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/LessonCard.qml
git commit -m "feat(quiz-widget): LessonCard exposes openAsk/closeAsk/inputActive"
```

---

### Task 5: QuizOverlay — in-card key dispatch + focus

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizOverlay.qml` (the `Item { id: content … }` block, and `onModeChanged`)

**Interfaces:**
- Consumes: `QuizEngine.keyAction` (Task 3); `lessonCard.inputActive`/`openAsk()`/`closeAsk()` (Task 4); existing `card`/`lessonCard` ids, `overlay.selected`, `overlay.question`, signals `quizAnswered()`/`lessonDone()`/`snoozeRequested(int)`, and `reset()`.

- [ ] **Step 1: Make the content focusable and add the key handler**

On `Item { id: content … }` in `QuizOverlay.qml`, add `focus: true` and a `Keys.onPressed` handler. `QuizEngine` is already imported in the overlay (`import "QuizEngine.js" as QuizEngine`); if not, add it.

```qml
Item {
    id: content
    focus: true
    Keys.onPressed: (event) => {
        var token;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            token = "ENTER";
        else if (event.key === Qt.Key_Escape)
            token = "ESC";
        else if (event.text && event.text.length === 1)
            token = event.text.toUpperCase();
        else
            return;
        var act = QuizEngine.keyAction(token, overlay.mode, overlay.contentType, lessonCard.inputActive);
        if (act === "")
            return;
        event.accepted = true;
        if (act.indexOf("select") === 0) {
            var i = Number(act.charAt(6));
            if (overlay.question && overlay.question.choices && i < overlay.question.choices.length)
                overlay.selected = i;
        } else if (act === "submit") {
            if (overlay.selected >= 0) { overlay.mode = "feedback"; overlay.quizAnswered(); }
        } else if (act === "next") {
            overlay.lessonDone(); overlay.reset();
        } else if (act === "ask") {
            lessonCard.openAsk();
        } else if (act === "closeAsk") {
            lessonCard.closeAsk();
        } else if (act === "snooze") {
            overlay.snoozeRequested(300000); overlay.reset();
        } else if (act === "close") {
            overlay.reset();
        }
    }
    // … existing children (pill, card, lessonCard, onboardingCard) unchanged …
}
```

- [ ] **Step 2: Force focus when a card opens**

Extend the existing `onModeChanged` handler (currently `onModeChanged: if (overlay.mode === "pending") pill.resetPillTransforms()`) so it also grabs focus for opened cards:

```qml
onModeChanged: {
    if (overlay.mode === "pending")
        pill.resetPillTransforms();
    if (overlay.mode === "open" || overlay.mode === "feedback")
        content.forceActiveFocus();
}
```

- [ ] **Step 3: Reload and verify no QML errors**

Run:
```bash
systemctl --user restart dms.service && sleep 6
journalctl --user -u dms.service --since "15 sec ago" --no-pager | grep -iE '\.qml:[0-9]|component error|QuizOverlay' || echo "clean"
```
Expected: `clean`.

- [ ] **Step 4: Behavioral verification (keyboard drives the card)**

With a pill pending (or forced), open it (`dms ipc call quiz open`), then type and confirm via a sink terminal is not applicable here (the overlay is focused). Instead drive keys with `wtype` while the card is focused and observe state via screenshot:
```bash
dms ipc call quiz open
wtype "A"            # selects choice A
sleep 0.3; wtype -k Return   # validates -> feedback
SC=<scratchpad>; dms screenshot full -d "$SC" --filename quiz-kbd.png --no-clipboard --no-notify
```
Read the PNG: choice A highlighted then feedback shown. Then `wtype -k Escape` closes (overlay layer gone from `hyprctl layers`). For a lesson: `wtype "Q"` opens the question field (focus it), letters then type into the field (not navigation), `wtype -k Escape` closes the field.

- [ ] **Step 5: Verify the focus-steal fix is intact**

Confirm the pill still does not steal focus (regression guard): with the pill pending (not opened), a focused text field keeps focus. Reuse the existing behavioral focus test (sink terminal + `wtype`) — the pending pill must not capture keystrokes.

- [ ] **Step 6: Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizOverlay.qml
git commit -m "feat(quiz-widget): in-card keyboard navigation (select/validate/next/ask/close)"
```

---

## Self-Review

**Spec coverage:**
- Global open/snooze/dismiss → Task 1 (IPC) + Task 2 (binds). ✓
- In-card quiz keys (A-D/1-4, Enter, S, Esc) and lesson keys (Enter/N, Q/?, S, Esc) → Task 3 (resolver) + Task 5 (dispatch). ✓
- Suspend keymaps when question field focused → Task 3 (`inputActive` branch) + Task 4 (`inputActive`) + Task 5 (passes `lessonCard.inputActive`). ✓
- No-op when nothing pending → Task 1 (mode guards). ✓
- Don't regress focus-steal fix → Task 5 Step 5 regression guard; focus only forced on `open`/`feedback`. ✓
- Chords on `L`; snooze = 300000 ms; IPC target `quiz` → Global Constraints + Tasks 1/2/5. ✓

**Placeholder scan:** No TBD/TODO; all code blocks complete; verification commands concrete. ✓

**Type consistency:** `keyAction(token, mode, contentType, inputActive)` and its return tokens (`select0..3`, `submit`, `next`, `ask`, `closeAsk`, `snooze`, `close`, `""`) are used identically in Task 3 (def + tests) and Task 5 (dispatch). `lessonCard.inputActive`/`openAsk()`/`closeAsk()` defined in Task 4, consumed in Task 5. IPC `open/snooze/dismiss` defined in Task 1, bound in Task 2. ✓
