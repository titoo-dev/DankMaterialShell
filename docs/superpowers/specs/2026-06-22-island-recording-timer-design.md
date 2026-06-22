# Screen-capture chrono in the island (#4) — design

**Date:** 2026-06-22 · **Status:** approved (design) · **Branch:** `feat/dynamic-island`
**Builds on:** the generic live-activity system (`ActivityService`), `PrivacyService`.

## Problem
While the screen is being captured/recorded, show a running chrono in the island.

## Key constraint
DMS has **no native screen recorder** — only `PrivacyService.screensharingActive`
(portal/screencast detection). So a universal "stop recording" button is impossible
(stopping belongs to whatever app captures: OBS, portal, wf-recorder…). v1 therefore
provides the chrono (the solid, universal part) and routes a tap to the privacy panel.

## Approach
A `RecordingTimerService` singleton watches `PrivacyService.screensharingActive` and
drives an `ActivityService` entry (id `"screenrec"`) that counts **up** (elapsed),
gated by a setting. No new rendering.

## Components
### 1. `quickshell/Services/RecordingTimerService.qml` (new singleton)
- `property double startTime: 0`; `readonly property bool enabled: SettingsData.islandRecordingTimer`.
- `Connections { target: PrivacyService; onScreensharingActiveChanged }`:
  - active && enabled → `startTime = Date.now()`; `ActivityService.start("screenrec", I18n.tr("Recording"), "screen_record")`.
  - inactive → `ActivityService.stop("screenrec")`; `startTime = 0`.
- 1s `Timer` (running while `PrivacyService.screensharingActive && enabled`):
  `ActivityService.update("screenrec", "🔴 " + I18n.tr("Capture") + " · " + fmt(Date.now()-startTime))`
  (progress stays `-1` → indeterminate). `fmt` → `M:SS`/`H:MM:SS`.
- `onEnabledChanged` false → stop the entry.

### 2. Tap → privacy panel
The activity pill already opens the activities panel on click; the screen-capture
entry needs no special routing in v1 (the privacy satellite/panel remain the place to
manage captures). No extra wiring.

### 3. Settings
- `SettingsData.islandRecordingTimer: bool` (default `true`); `SettingsSpec.js` entry.

### 4. Instantiation
Referenced from `DynamicIsland` (a read-only prop) so the lazy singleton lives, same
as `CalendarCountdownService`.

## Error handling & edge cases
- Fires for any screencast (incl. video-call screen-share) — can't distinguish from
  recording; the setting lets the user disable it.
- Shell restart mid-capture → chrono restarts from 0 on next detection (ephemeral).
- Capture ends → entry stopped immediately.

## Testing & verification
- Trigger a screen-share/recording → "🔴 Capture · 0:NN" chrono in the pill; stop →
  it disappears. With nothing capturing, force-render to confirm layout. Verify no QML
  errors. ([[verifying-qml-changes-no-qmllint]])

## Out of scope (v1)
- A real stop-recording button (no native recorder).
- Distinguishing recording from screen-sharing.
- Bundling a recorder.
