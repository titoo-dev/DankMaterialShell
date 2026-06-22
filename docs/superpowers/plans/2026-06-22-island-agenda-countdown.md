# Calendar Countdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Checkbox steps.

**Goal:** Auto-show the next calendar event as an intensifying countdown in the island, via `ActivityService`.

**Architecture:** `CalendarCountdownService` polls `CalendarService.eventsByDate`, drives activity id `"agenda"`. Setting-gated. No IPC.

## Global Constraints
- No `console.*` (use `Log`). `Date.now()`/`new Date()` allowed in QML runtime.
- Reuse `ActivityService.start/update/progress/done/stop`.
- Event object: `{ title, start: Date, allDay }`; `eventsByDate` keyed `Qt.formatDate(d,"yyyy-MM-dd")`.

---

### Task 1: settings flag
**Files:** Modify `quickshell/Common/SettingsData.qml`, `quickshell/Common/settings/SettingsSpec.js`

- [ ] **Step 1:** In SettingsData after `taildropDefaultPeer`: `property bool islandAgendaCountdown: true`
- [ ] **Step 2:** In SettingsSpec after `taildropDefaultPeer`: `islandAgendaCountdown: { def: true },`
- [ ] **Step 3:** commit `feat(island): islandAgendaCountdown setting`

### Task 2: `CalendarCountdownService.qml`
**Files:** Create `quickshell/Services/CalendarCountdownService.qml`

- [ ] **Step 1: Create**

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Drives the "agenda" ActivityService entry: an intensifying countdown to the
// next calendar event within `windowMin`. Data from CalendarService (khal).
Singleton {
    id: root
    readonly property var log: Log.scoped("CalendarCountdownService")
    readonly property int windowMin: 15
    readonly property bool enabled: SettingsData.islandAgendaCountdown && CalendarService.khalAvailable

    function _nextEvent() {
        const now = new Date();
        const key = Qt.formatDate(now, "yyyy-MM-dd");
        const evts = CalendarService.eventsByDate[key] || [];
        let best = null;
        for (var i = 0; i < evts.length; i++) {
            const e = evts[i];
            if (e.allDay || !e.start)
                continue;
            const s = e.start instanceof Date ? e.start : new Date(e.start);
            const diff = s.getTime() - now.getTime();
            if (diff < -60000)               // already started >1min ago → skip
                continue;
            if (diff > root.windowMin * 60000)
                continue;
            if (!best || s.getTime() < best.start.getTime())
                best = { title: e.title || "Event", start: s };
        }
        return best;
    }

    function _refresh() {
        if (!enabled) {
            ActivityService.stop("agenda");
            return;
        }
        const e = _nextEvent();
        if (!e) {
            ActivityService.stop("agenda");
            return;
        }
        const mins = (e.start.getTime() - Date.now()) / 60000;
        ActivityService.start("agenda", e.title, "event");
        if (mins <= 0) {
            ActivityService.done("agenda", "📅 " + e.title);
        } else {
            ActivityService.update("agenda", "📅 " + e.title + " · " + I18n.tr("in %1 min").arg(Math.ceil(mins)));
            ActivityService.progress("agenda", Math.max(0, Math.min(100, Math.round((root.windowMin - mins) / root.windowMin * 100))));
        }
    }

    Component.onCompleted: if (enabled) CalendarService.loadCurrentMonth()
    onEnabledChanged: {
        if (enabled)
            CalendarService.loadCurrentMonth();
        else
            ActivityService.stop("agenda");
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.enabled
        triggeredOnStart: true
        onTriggered: root._refresh()
    }
}
```

- [ ] **Step 2:** journal-clean check; commit `feat(island): CalendarCountdownService — next-event countdown`

### Task 3: Verify
- [ ] **Step 1:** No QML errors (journal). With no events, silent.
- [ ] **Step 2:** Force-render: temporarily make `_nextEvent` return a fake `{title:"Réunion", start: new Date(Date.now()+600000)}`, screenshot the "📅 Réunion · in 10 min" pill, revert.
- [ ] **Step 3:** tree clean.

## Self-Review
- Setting → Task 1; service (poll, next-event, drive agenda activity) → Task 2; verify → Task 3.
- Edges: khal absent/no events → stop (silent); allDay skipped; started>1min → skip; soonest wins. Placeholders none. `islandAgendaCountdown` consistent T1↔T2; activity id `"agenda"`.
