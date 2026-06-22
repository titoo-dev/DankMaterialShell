pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Countdown timer / Pomodoro. Drives the generic ActivityService entry "timer";
// the completion flash comes free via ActivityService.activityFinished, the sound
// is played here.
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
