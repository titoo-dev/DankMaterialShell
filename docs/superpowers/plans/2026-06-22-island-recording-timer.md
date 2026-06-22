# Screen-capture Chrono Implementation Plan

> REQUIRED SUB-SKILL: superpowers:executing-plans. Checkbox steps.

**Goal:** A count-up chrono in the island while the screen is captured, via `ActivityService`.
**Architecture:** `RecordingTimerService` watches `PrivacyService.screensharingActive`, drives activity id `"screenrec"`. Setting-gated, instantiated from DynamicIsland.

## Global Constraints
- No `console.*` (use `Log`). Reuse `ActivityService.start/update/stop`. No native recorder → chrono only.

### Task 1: setting
- [ ] SettingsData after `islandAgendaCountdown`: `property bool islandRecordingTimer: true`
- [ ] SettingsSpec after `islandAgendaCountdown`: `islandRecordingTimer: { def: true },`
- [ ] commit `feat(island): islandRecordingTimer setting`

### Task 2: `RecordingTimerService.qml`
- [ ] Create:

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Count-up chrono while the screen is being captured (PrivacyService). No native
// recorder exists, so this only times the capture; stopping belongs to the app.
Singleton {
    id: root
    readonly property var log: Log.scoped("RecordingTimerService")
    readonly property bool enabled: SettingsData.islandRecordingTimer
    property double startTime: 0

    function _fmt(ms) {
        const s = Math.max(0, Math.round(ms / 1000));
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
        const pad = n => (n < 10 ? "0" + n : "" + n);
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(sec)) : (m + ":" + pad(sec));
    }
    function _begin() {
        root.startTime = Date.now();
        ActivityService.start("screenrec", I18n.tr("Recording"), "screen_record");
    }
    function _end() {
        root.startTime = 0;
        ActivityService.stop("screenrec");
    }

    Connections {
        target: PrivacyService
        function onScreensharingActiveChanged() {
            if (PrivacyService.screensharingActive && root.enabled)
                root._begin();
            else
                root._end();
        }
    }
    onEnabledChanged: {
        if (!enabled)
            _end();
        else if (PrivacyService.screensharingActive)
            _begin();
    }
    Timer {
        interval: 1000
        repeat: true
        running: PrivacyService.screensharingActive && root.enabled
        triggeredOnStart: true
        onTriggered: ActivityService.update("screenrec", "🔴 " + I18n.tr("Capture") + " · " + root._fmt(Date.now() - root.startTime))
    }
}
```

- [ ] commit `feat(island): RecordingTimerService — screen-capture chrono (#4)`

### Task 3: instantiate from DynamicIsland
- [ ] After `_agendaCountdownAlive`: `readonly property bool _recTimerAlive: RecordingTimerService.enabled`
- [ ] commit (with Task 2)

### Task 4: verify
- [ ] No QML errors (journal). Trigger a screen-share → chrono; stop → gone. Force-render otherwise.

## Self-Review
- Setting → T1; service (watch privacy, count-up, gated) → T2; instantiate → T3; verify → T4.
- Edges: any screencast triggers it (setting disables); ephemeral; stop on capture end. Placeholders none. `islandRecordingTimer` consistent; activity id `"screenrec"`.
