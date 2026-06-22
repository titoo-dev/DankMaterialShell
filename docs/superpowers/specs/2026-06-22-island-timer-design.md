# Timer / Pomodoro in the island (#2) — design

**Date:** 2026-06-22
**Status:** approved (design)
**Branch:** `feat/dynamic-island`
**Builds on:** the generic live-activity system (`ActivityService`).

## Problem

A countdown timer / Pomodoro shown in the island: start it (keybind or IPC), watch
it count down in the activity pill, and get a flash + sound when it ends.

## Approach

A thin `TimerService` singleton that drives a single `ActivityService` entry
(id `"timer"`). It reuses the #1 foundation for all rendering (pill, progress,
completion flash); it only adds the countdown tick and the end-of-timer sound. No
new rendering.

## Components

### 1. `quickshell/Services/TimerService.qml` (new singleton)

- `property double endTime: 0`, `property double totalMs: 0`, `property string label: ""`.
- `readonly property bool active: endTime > 0`.
- `function start(minutes, label)` — `m = parseFloat(minutes)`; ignore if `NaN`/`<= 0`.
  Sets `totalMs = m*60000`, `endTime = Date.now() + totalMs`, `this.label =`
  (label or `"Minuteur"`); `ActivityService.start("timer", this.label, "timer")`;
  starts the tick.
- `function cancel()` — `endTime = 0`; `ActivityService.stop("timer")`.
- A 1s `Timer` (running while `active`): `remain = endTime - Date.now()`. If
  `remain <= 0` → `_finish()`. Else
  `ActivityService.update("timer", label + "  " + fmt(remain))` and
  `ActivityService.progress("timer", round((totalMs - remain) / totalMs * 100))`.
- `function _finish()` — `endTime = 0`; `ActivityService.done("timer", "⏰ " + label + " terminé")`
  (this triggers the green flash via `activityFinished`); play the end sound
  (`AudioService.criticalNotificationSound` → `stop()` then `play()`).
- `fmt(ms)` → `"M:SS"` (or `"H:MM:SS"` past an hour).

Note: the generic "done" entry auto-removes after ~3s. For a timer that is
acceptable (the flash + sound are the alert); v1 does not add a persistent
"acknowledge" state — keep it simple.

### 2. `quickshell/Modules/DynamicIsland/IslandHub.qml` — IPC

- `function timerStart(minutes: string, label: string): string` → `TimerService.start(minutes, label)`; returns `"ISLAND_TIMER:start:" + minutes`.
- `function timerCancel(): string` → `TimerService.cancel()`; returns `"ISLAND_TIMER:cancel"`.

### 3. Keybind — `~/.config/hypr/hyprland.lua`

Add `SUPER + ALT + O` ("pOmodoro") → `dms ipc call island timerStart 25 "Pomodoro"`
(O is free in the SUPER+ALT family), next to the other island binds; `hyprctl reload`.

## Error handling & edge cases

- `minutes` non-numeric / `<= 0` → ignored (no timer started).
- A second `start` replaces the current timer (same `"timer"` id; `endTime` reset).
- `cancel` with no active timer → `ActivityService.stop` is a no-op.
- The end sound respects the system; if the sound player is unavailable, the flash
  still fires (sound is best-effort, guarded by a null check).
- Shell restart mid-timer → the timer is lost (ephemeral), consistent with #1.

## Testing & verification

- 100% IPC-driveable: `dms ipc call island timerStart 1 "Test"` → pill counts down
  ("Test 0:59…"), determinate bar fills; at 0 → green flash + sound +
  "⏰ Test terminé"; `dms ipc call island timerCancel` removes it. Screenshot the
  countdown. Verify the keybind after `hyprctl reload`.
- Verify via the live working-tree shell ([[verifying-qml-changes-no-qmllint]]).

## Out of scope (v1)

- Full Pomodoro cycle (auto work→break→repeat).
- Pause/resume.
- A persistent "time's up, acknowledge" state (the flash + sound + 3s done entry suffice).
- Configurable presets UI (durations come from the IPC arg / keybind).
