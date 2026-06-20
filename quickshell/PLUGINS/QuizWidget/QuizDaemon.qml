import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root
    property var popoutService: null

    // réglages (chargés en onCompleted, défauts ci-dessous)
    // Note: l'activation/désactivation du plugin (flag "enabled" géré par PluginService)
    // gouverne déjà le chargement du daemon — pas de toggle "enabled" propre ici.
    property bool paused: false
    property int workMinutes: 25
    property var subjects: []
    property bool aiEnabled: false
    property string apiKey: ""

    // état runtime
    property var pendingQuestion: null
    property var sessionSeen: ({})

    QuizProvider {
        id: provider
        aiEnabled: root.aiEnabled
        apiKey: root.apiKey
    }

    QuizOverlay {
        id: overlay
        question: root.pendingQuestion
        onClosed: root.pendingQuestion = null
    }

    Timer {
        id: workTimer
        interval: Math.max(1, root.workMinutes) * 60 * 1000
        repeat: true
        running: !root.paused
        onTriggered: root.requestQuiz()
    }

    function seenFor(subject) {
        return root.sessionSeen[subject] ? root.sessionSeen[subject] : [];
    }

    function requestQuiz() {
        if (root.pendingQuestion)
            return; // une seule en attente
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
            overlay.showPending();
        });
    }

    Component.onCompleted: {
        if (typeof pluginService !== "undefined" && pluginService) {
            root.paused = pluginService.loadPluginData("quizWidget", "paused", false);
            root.workMinutes = parseInt(pluginService.loadPluginData("quizWidget", "workMinutes", "25")) || 25;
            root.subjects = pluginService.loadPluginData("quizWidget", "subjects", []);
            root.aiEnabled = pluginService.loadPluginData("quizWidget", "aiEnabled", false);
            root.apiKey = pluginService.loadPluginData("quizWidget", "apiKey", "");
        }
        console.info("QuizDaemon: started, work", root.workMinutes, "min, subjects", JSON.stringify(root.subjects));
    }
    Component.onDestruction: console.info("QuizDaemon: stopped")
}
