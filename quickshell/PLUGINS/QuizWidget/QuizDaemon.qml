import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import "QuizEngine.js" as QuizEngine

PluginComponent {
    id: root
    property var popoutService: null

    // réglages (chargés en onCompleted, défauts ci-dessous)
    // Note: l'activation/désactivation du plugin (flag "enabled" géré par PluginService)
    // gouverne déjà le chargement du daemon — pas de toggle "enabled" propre ici.
    property bool paused: false
    property bool snoozing: false
    property int workMinutes: 25
    property var subjects: []
    property bool aiEnabled: false
    property string apiKey: ""

    // état runtime
    property var pendingQuestion: null
    property var sessionSeen: ({})
    property string nudgeText: "Quiz dispo"

    QuizProvider {
        id: provider
        aiEnabled: root.aiEnabled
        apiKey: root.apiKey
    }

    QuizOverlay {
        id: overlay
        question: root.pendingQuestion
        nudge: root.nudgeText
        onDismissed: root.pendingQuestion = null
        onSnoozeRequested: (ms) => root.snooze(ms)
    }

    // Accroche affichée sur la pastille : preset local immédiat, puis enrichie via `claude -p`.
    function fetchNudge() {
        root.nudgeText = QuizEngine.randomNudge();
        Proc.runCommand("quizWidget.nudge", ["claude", "-p", QuizEngine.nudgePrompt()], function (stdout, exitCode) {
            if (exitCode === 0) {
                var n = QuizEngine.cleanNudge(stdout);
                if (n)
                    root.nudgeText = n;
            }
        }, 0);
    }

    Timer {
        id: workTimer
        interval: Math.max(1, root.workMinutes) * 60 * 1000
        repeat: true
        running: !root.paused && !root.snoozing
        onTriggered: root.requestQuiz()
    }

    // Report (snooze) : pause la cadence pomodoro pendant `ms`, puis montre une quiz et reprend.
    Timer {
        id: snoozeTimer
        repeat: false
        onTriggered: {
            root.snoozing = false; // réactive workTimer (binding running)
            root.requestQuiz();
        }
    }

    function snooze(ms) {
        root.pendingQuestion = null;
        snoozeTimer.interval = Math.max(1, ms);
        root.snoozing = true; // stoppe workTimer
        snoozeTimer.restart();
        console.info("QuizDaemon: snooze", ms, "ms");
    }

    function seenFor(subject) {
        return root.sessionSeen[subject] ? root.sessionSeen[subject] : [];
    }

    function requestQuiz() {
        if (root.pendingQuestion)
            return; // une seule en attente
        root.loadSettings(); // re-lecture fraîche (robuste à la course de chargement + réglages à chaud)
        if (!root.subjects || root.subjects.length === 0)
            return;
        var raw = root.subjects[Math.floor(Math.random() * root.subjects.length)];
        var subject = (raw && typeof raw === "object") ? (raw.name || "") : raw;
        if (!subject)
            return;
        provider.fetchQuestion(subject, root.seenFor(subject), function (q, newSeen) {
            if (!q) {
                console.warn("QuizDaemon: pas de question pour", subject);
                return;
            }
            var s = root.sessionSeen;
            s[subject] = newSeen;
            root.sessionSeen = s;
            root.pendingQuestion = q;
            root.fetchNudge();
            overlay.showPending();
        });
    }

    function loadSettings() {
        if (typeof pluginService === "undefined" || !pluginService)
            return;
        root.paused = pluginService.loadPluginData("quizWidget", "paused", false);
        root.workMinutes = parseInt(pluginService.loadPluginData("quizWidget", "workMinutes", "25")) || 25;
        root.subjects = pluginService.loadPluginData("quizWidget", "subjects", []);
        root.aiEnabled = pluginService.loadPluginData("quizWidget", "aiEnabled", false);
        root.apiKey = pluginService.loadPluginData("quizWidget", "apiKey", "");
    }

    Component.onCompleted: {
        Qt.callLater(loadSettings);
        console.info("QuizDaemon: started, work", root.workMinutes, "min");
    }
    Component.onDestruction: console.info("QuizDaemon: stopped")
}
