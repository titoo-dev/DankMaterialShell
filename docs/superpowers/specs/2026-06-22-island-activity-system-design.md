# Generic live-activity system for the island — design

**Date:** 2026-06-22
**Status:** approved (design)
**Branch:** `feat/dynamic-island`

## Problem

The island has transient splashes (`pushActivity`) and a persistent satellite for a
few hard-coded ongoing states, but no **generic, scriptable, updatable** live
activity. The goal: an IPC-driven progress pill that lives while a long command
runs — `dms ipc call island activity start build1 "Build…"` → a pill showing the
label + progress, updatable (`… progress build1 60`), dismissed on completion
(`… done build1`). Reusable for builds, deploys, downloads, and as the **foundation**
for the timer/Pomodoro, calendar countdown, and screen-record-timer features.

## Decisions (from brainstorming)

- **Multiple concurrent activities, keyed by id.** The pill shows the primary
  (most recent running) + a "+N" badge; a drill panel lists all.
- **Progress is auto:** a given percentage → determinate bar; none → indeterminate
  animation.
- The activity rest mode **takes precedence over the media chip / compact** while any
  activity runs (iOS live-activity behaviour); reverts when none remain.
- Completion = visual flash (no sound in v1; the Pomodoro feature adds sound).
- Ephemeral (no persistence across shell restart); a safety auto-expiry prevents
  ghosts if a command crashes without calling `stop`.

## Components

### 1. `quickshell/Services/ActivityService.qml` (new singleton)

Single source of truth (global, shared across monitors).

State:
- `property var activities: []` — ordered (most-recent first), each:
  `{ id, label, icon, progress, state, _expireAt }` where `progress` is `-1`
  (indeterminate) or `0..100`, `state` ∈ `"running" | "done" | "failed"`.
- `readonly property int runningCount` — number of `running` activities.
- `readonly property var primary` — first `running` activity (or the most recent
  done/failed if none running), or `null`.

API (all no-ops on malformed input):
- `start(id, label, icon)` — add or update (idempotent on id); `icon` defaults to
  `"deployed_code"` when empty; `progress` starts at `-1`.
- `progress(id, pct)` — set `progress = clamp(0,100, pct)`.
- `update(id, label)` — change the label.
- `done(id, label)` — mark `done` (label optional), schedule removal in ~3s.
- `fail(id, label)` — mark `failed` likewise.
- `stop(id)` — remove immediately.
- internal: a 1s `Timer` prunes entries past `_expireAt` (done/failed after ~3s;
  running after a ~1h safety TTL refreshed on every update).

Signals: `activityFinished(string id, bool ok)` (for the island flash).

### 2. `quickshell/Modules/DynamicIsland/IslandHub.qml` — IPC

`function activity(action: string, id: string, arg: string): string` routing to
`ActivityService`:
- `start` → `ActivityService.start(id, arg, "")`
- `progress` → `ActivityService.progress(id, parseInt(arg))`
- `update` → `ActivityService.update(id, arg)`
- `done` → `ActivityService.done(id, arg)`
- `fail` → `ActivityService.fail(id, arg)`
- `stop` → `ActivityService.stop(id)`
- unknown action / empty id → `"ISLAND_ERROR:…"`.

Missing trailing args arrive as `""` (same as the existing `open`), so
`activity stop build1` works. Also add `"activities"` to the `views` list so
`dms ipc call island open activities` opens the panel.

### 3. `quickshell/Modules/DynamicIsland/DynamicIsland.qml`

- **Rest mode:** `restMode()` returns `"activity"` when `ActivityService.runningCount > 0`
  (or a finishing activity is showing), else the current chip/compact logic.
- **Geometry:** add `"activity"` cases to `pillW`/`pillH` (height ~34 like chip, width
  grown to fit `ActivityPane`'s content, clamped to screen).
- **Flash:** `Connections { target: ActivityService; onActivityFinished(id, ok) }` →
  `edgeGlow.flash(ok ? Theme.success : Theme.error)` + `bump()`.
- **Hold a ref** so the singleton + its prune timer live: reference `ActivityService`
  in the `restMode`/Connections (referencing it instantiates it).
- Tapping the activity pill / hovering → `openPanel("activities")`.

### 4. `quickshell/Modules/DynamicIsland/panes/ActivityPane.qml` (new)

Pill content for `mode === "activity"`: leading icon (the primary's icon, with a
slow spin while `running` & indeterminate), the primary label (elided), a compact
progress indicator (`M3WaveProgress` width-bound when `progress >= 0`, else a small
indeterminate pulse), and a "+N" badge when `runningCount > 1`. Done/failed primary
shows a ✓/✗ glyph briefly before the entry is pruned. Exposes a `contentWidth` the
pill geometry reads (same pattern as `CompactPane`/`MediaPane`).

### 5. `quickshell/Modules/DynamicIsland/panels/ActivityPanel.qml` (new)

Drill view `panelView === "activities"`: a list of all activities — icon, label,
state (running/done/failed), a determinate/indeterminate bar, and a dismiss (✕)
button per row calling `ActivityService.stop(id)`. Registered in
`ControlCenterPanel`'s `viewRegistry` as `"activities"`.

## Error handling & edge cases

- `progress`/`update`/`done`/`fail`/`stop` on an unknown id → ignored.
- `start` with an existing id → updates that entry (no duplicate).
- `progress` with a non-numeric / out-of-range arg → `parseInt` then clamp; `NaN` → ignored.
- A command that never calls `stop` → pruned by the ~1h safety TTL; also dismissable
  from the panel.
- Shell restart mid-activity → activities are lost (ephemeral); the command keeps
  running, the island simply forgets (acceptable).
- Multi-monitor → single shared singleton; every island renders the same; the flash
  uses each island's own `edgeGlow` gated to `isFocusedScreen` (existing pattern).

## Testing & verification

- **QML:** not unit-tested → manual, fully driveable via IPC (no second device needed):
  1. `dms ipc call island activity start t1 "Test…"` → island enters activity mode,
     pill shows "Test…" with an indeterminate animation.
  2. `… progress t1 50` → determinate bar at 50%.
  3. `… start t2 "Deploy…"` → pill shows primary + "+1" badge; `open activities`
     lists both.
  4. `… done t1 "Done"` → ✓ + green flash, entry auto-removes after ~3s.
  5. `… stop t2` → island returns to compact/chip.
  Screenshot each step (`dms screenshot full`).
- Verify via the live working-tree shell ([[verifying-qml-changes-no-qmllint]]).

## Out of scope (v1)

- Completion sound (added by the Pomodoro feature).
- Persistence across shell restarts.
- Click-to-cancel the underlying command (we only track display state; the panel's ✕
  dismisses the *display*, not the process).
- A `dms` CLI subcommand wrapper (use `dms ipc call island activity …` directly).
