# Calendar countdown in the island (#3) — design

**Date:** 2026-06-22 · **Status:** approved (design) · **Branch:** `feat/dynamic-island`
**Builds on:** the generic live-activity system (`ActivityService`) and `CalendarService` (khal).

## Problem
Show the next calendar event as an intensifying countdown in the island — "📅 Meeting · in 10 min" — so an upcoming meeting is glanceable.

## Approach
A `CalendarCountdownService` singleton polls `CalendarService` for the soonest future
event today; when it's within a window (15 min) it drives an `ActivityService` entry
(id `"agenda"`) whose progress intensifies as the start approaches. No new rendering;
no IPC (automatic, data-driven).

## Components
### 1. `quickshell/Services/CalendarCountdownService.qml` (new singleton)
- `readonly property int windowMin: 15`.
- on `Component.onCompleted` and a 30s `Timer` (running when `SettingsData.islandAgendaCountdown && CalendarService.khalAvailable`):
  - if events not loaded recently, `CalendarService.loadCurrentMonth()`.
  - compute `next` = the event in `CalendarService.eventsByDate` for today with the
    soonest `start` Date strictly in the future and `start - now <= windowMin*60000`
    (skip `allDay`).
  - if `next`: `ActivityService.start("agenda", title, "event")`,
    `ActivityService.update("agenda", "📅 " + title + " · " + relLabel(mins))`,
    `ActivityService.progress("agenda", round((windowMin - mins)/windowMin*100))`.
  - when `start <= now` (event started, within a 1-min grace): `ActivityService.done("agenda", "📅 " + title)`.
  - if no `next` within window but an `"agenda"` entry exists: `ActivityService.stop("agenda")`.
- `relLabel(mins)` → `"dans <m> min"` / `"maintenant"`.

### 2. Settings
- `SettingsData.islandAgendaCountdown: bool` (default `true`); `SettingsSpec.js` entry.

## Error handling & edge cases
- khal absent / no events → silent (timer guarded by `khalAvailable`).
- all-day events → skipped (no start time).
- Re-poll throttled to 30s; progress updates each poll (fine for a 15-min window).
- Multiple events within the window → the soonest wins (single `"agenda"` entry).
- Shell restart → recomputed on next poll (ephemeral, consistent with #1).

## Testing & verification
- khal present but no events here → the feature stays silent. Verify: the service
  loads with no QML errors; force a fake `next` (temporary edit) to confirm the
  "agenda" activity + pill render via screenshot, then revert. Real e2e needs a
  calendar event within 15 min (user-side).
- Verify via the live shell ([[verifying-qml-changes-no-qmllint]]).

## Out of scope (v1)
- Multiple simultaneous event countdowns.
- Click-to-open the calendar from the countdown (the calendar drill already exists).
- Configurable window UI (15-min constant; the toggle enables/disables).
