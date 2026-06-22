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
