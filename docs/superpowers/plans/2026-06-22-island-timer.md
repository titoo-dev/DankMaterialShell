# Timer / Pomodoro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A countdown timer/Pomodoro in the island, driving an `ActivityService` entry, with a sound at zero.

**Architecture:** `TimerService` singleton drives activity id `"timer"` (label + progress each second); at zero it marks the activity done (green flash via the foundation) and plays a sound. IPC verbs + a keybind start/cancel it.

**Tech Stack:** QML (Quickshell), the #1 `ActivityService`, `AudioService.criticalNotificationSound` (MediaPlayer).

## Global Constraints

- No `console.*` in QML (use `Log`). `Date.now()` allowed in QML runtime.
- IPC requires all declared args → fixed-arity functions.
- No `qmllint` → verify via journal + screenshots; fully IPC-driveable.
- Reuse `ActivityService.start/update/progress/done/stop` (id `"timer"`).

---

### Task 1: `TimerService.qml`

**Files:** Create `quickshell/Services/TimerService.qml`

**Interfaces:** Produces singleton `TimerService` with `active: bool`, `start(minutes, label)`, `cancel()`.

- [ ] **Step 1: Create the service**

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Countdown timer / Pomodoro. Drives the generic ActivityService entry "timer";
// flash comes free via ActivityService.activityFinished, sound played here.
Singleton {
    id: root
    readonly property var log: Log.scoped("TimerService")

    property double endTime: 0
    property double totalMs: 0
    property string label: ""
    readonly property bool active: endTime > 0

    function _fmt(ms) {
        const s = Math.max(0, Math.round(ms / 1000));
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
        const pad = n => (n < 10 ? "0" + n : "" + n);
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(sec)) : (m + ":" + pad(sec));
    }

    function start(minutes, label) {
        const m = parseFloat(minutes);
        if (isNaN(m) || m <= 0)
            return;
        root.totalMs = m * 60000;
        root.endTime = Date.now() + root.totalMs;
        root.label = (label && label.length > 0) ? label : I18n.tr("Timer");
        ActivityService.start("timer", root.label + "  " + _fmt(root.totalMs), "timer");
        tick.restart();
    }
    function cancel() {
        root.endTime = 0;
        ActivityService.stop("timer");
    }
    function _finish() {
        root.endTime = 0;
        ActivityService.done("timer", "⏰ " + root.label);
        if (AudioService.criticalNotificationSound) {
            AudioService.criticalNotificationSound.stop();
            AudioService.criticalNotificationSound.play();
        }
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            if (!root.active)
                return;
            const remain = root.endTime - Date.now();
            if (remain <= 0) {
                root._finish();
                return;
            }
            ActivityService.update("timer", root.label + "  " + root._fmt(remain));
            ActivityService.progress("timer", Math.round((root.totalMs - remain) / root.totalMs * 100));
        }
    }
}
```

- [ ] **Step 2: Verify journal clean + commit**

Run: `sleep 2 && journalctl --user -u dms.service --since "15 seconds ago" | grep -iE "TimerService|\.qml:[0-9]|error:" | grep -v INFO | tail`
Expected: empty.

```bash
git add quickshell/Services/TimerService.qml
git commit -m "feat(island): TimerService — countdown driving the activity pill + end sound"
```

---

### Task 2: IPC verbs (`IslandHub.qml`)

**Files:** Modify `quickshell/Modules/DynamicIsland/IslandHub.qml`

- [ ] **Step 1: Add `timerStart`/`timerCancel` after the activity functions**

```qml
        function timerStart(minutes: string, label: string): string {
            TimerService.start(minutes, label);
            return "ISLAND_TIMER:start:" + minutes;
        }
        function timerCancel(): string {
            TimerService.cancel();
            return "ISLAND_TIMER:cancel";
        }
```

- [ ] **Step 2: Verify + commit**

Run: `sleep 2 && dms ipc call island timerStart 1 "Test"; sleep 1; journalctl --user -u dms.service --since "10 seconds ago" | grep -iE "IslandHub|TimerService|\.qml:[0-9]|error:" | grep -v INFO | tail`
Expected: `ISLAND_TIMER:start:1`, grep empty, pill counts down.

```bash
git add quickshell/Modules/DynamicIsland/IslandHub.qml
git commit -m "feat(island): timerStart/timerCancel IPC"
```

---

### Task 3: Keybind (`~/.config/hypr/hyprland.lua`)

- [ ] **Step 1: Add the Pomodoro bind near the island binds**

```lua
hl.bind(mainMod .. " + ALT + O",       hl.dsp.exec_cmd("dms ipc call island timerStart 25 \"Pomodoro\""))  -- 25-min Pomodoro timer
```

- [ ] **Step 2: Reload + verify registered**

Run: `hyprctl reload; hyprctl binds -j | jq -r '.[] | select(.key=="O") | "mod=\(.modmask) key=\(.key)"'`
Expected: `mod=72 key=O` (SUPER+ALT+O).

(No commit — the keybind is in the user's local config, not the repo.)

---

### Task 4: Verification

- [ ] **Step 1: Lifecycle**

```
dms ipc call island timerStart 1 "Test"   # pill: "Test 0:59…", bar fills
# wait ~60s → green flash + sound + "⏰ Test"
dms ipc call island timerStart 25 "Pomodoro"; dms ipc call island timerCancel   # starts then removes
```
Screenshot the countdown.

- [ ] **Step 2: Error paths**

`dms ipc call island timerStart abc "x"` → no timer (ignored). `dms ipc call island timerCancel` with none → no-op.

- [ ] **Step 3: No QML errors + clean tree**

`journalctl --user -u dms.service --since "3 min ago" | grep -iE "Timer|\.qml:[0-9]|TypeError" | grep -v INFO; git status --short`

---

## Self-Review

- TimerService (start/cancel/tick/finish, fmt, sound) → Task 1 ✅
- IPC → Task 2 ✅; keybind → Task 3 ✅; verify → Task 4 ✅
- Edges: NaN/≤0 ignored (Task 1 start), restart replaces (same id), cancel no-op, sound guarded ✅
- Placeholders: none. Types: `start(minutes,label)`/`cancel()`/`active` consistent across Tasks 1-2; activity id `"timer"` consistent.
