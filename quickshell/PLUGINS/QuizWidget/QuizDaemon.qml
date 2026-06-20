import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import "QuizEngine.js" as QuizEngine
import "Catalog.js" as Catalog

PluginComponent {
    id: root
    property var popoutService: null

    // réglages (chargés via Qt.callLater, défauts ci-dessous)
    property bool paused: false
    property bool snoozing: false
    property int workMinutes: 25
    property var selectedTopics: []
    property var customTopics: []

    // état runtime
    property var pendingQuestion: null
    property var sessionSeen: ({})
    property string nudgeText: "Quiz dispo"
    property string nudgeEmoji: "🦉"
    property int animIndex: 0

    QuizProvider {
        id: provider
    }

    QuizOverlay {
        id: overlay
        question: root.pendingQuestion
        nudge: root.nudgeText
        emoji: root.nudgeEmoji
        animIndex: root.animIndex
        onDismissed: root.pendingQuestion = null
        onSnoozeRequested: (ms) => root.snooze(ms)
        onOnboardingComplete: (ids, customs) => root.completeOnboarding(ids, customs)
    }

    // Accroche de la pastille via `claude -p` qui renvoie un JSON {message, emoji, animation}
    // — claude choisit l'animation qui matche l'expression. On applique le résultat (ou un repli
    // local si claude échoue) PUIS on appelle onReady() : la pastille n'apparaît qu'une fois prête,
    // sans bascule d'animation. onReady est optionnel (re-nudge : rafraîchit la pastille déjà visible).
    function fetchNudge(onReady) {
        var fbText = QuizEngine.randomNudge();
        var fbEmoji = QuizEngine.randomEmoji();
        var fbAnim = Math.floor(Math.random() * Math.max(1, overlay.animCount));
        Proc.runCommand("quizWidget.nudge", [QuizEngine.claudeBinary(Quickshell.env("HOME")), "-p", QuizEngine.buildNudgePrompt()], function (stdout, exitCode) {
            var n = (exitCode === 0) ? QuizEngine.parseNudge(stdout) : null;
            if (n) {
                root.nudgeText = n.message;
                root.nudgeEmoji = n.emoji ? n.emoji : fbEmoji;
                root.animIndex = n.animIndex >= 0 ? n.animIndex : fbAnim; // animation choisie par claude
            } else {
                root.nudgeText = fbText;
                root.nudgeEmoji = fbEmoji;
                root.animIndex = fbAnim;
            }
            if (onReady)
                onReady();
        }, 0, 15000); // debounce 0, timeout 15 s (borne l'attente avant l'affichage de la pastille)
    }

    Timer {
        id: workTimer
        interval: Math.max(1, root.workMinutes) * 60 * 1000
        repeat: true
        running: !root.paused && !root.snoozing
        onTriggered: root.requestQuiz()
    }

    Timer {
        id: snoozeTimer
        repeat: false
        onTriggered: {
            root.snoozing = false;
            root.requestQuiz();
        }
    }

    Timer {
        id: renudgeTimer
        interval: 5 * 60 * 1000
        repeat: true
        running: overlay.mode === "pending"
        onTriggered: {
            root.fetchNudge();
            console.info("QuizDaemon: re-nudge (quiz ignorée)");
        }
    }

    // Première quiz peu après le démarrage (sujets déjà configurés) ou après l'onboarding,
    // pour une gratification immédiate ; ensuite la cadence pomodoro normale prend le relais.
    Timer {
        id: firstQuizTimer
        interval: 30 * 1000
        repeat: false
        onTriggered: root.requestQuiz()
    }

    function snooze(ms) {
        root.pendingQuestion = null;
        snoozeTimer.interval = Math.max(1, ms);
        root.snoozing = true;
        snoozeTimer.restart();
        console.info("QuizDaemon: snooze", ms, "ms");
    }

    function seenFor(topicId) {
        return root.sessionSeen[topicId] ? root.sessionSeen[topicId] : [];
    }

    function requestQuiz() {
        if (root.pendingQuestion)
            return; // une seule en attente
        root.loadSettings(); // re-lecture fraîche (robuste à la course de chargement + réglages à chaud)
        var pool = Catalog.buildTopicPool(root.selectedTopics, root.customTopics);
        if (pool.length === 0)
            return;
        var t = pool[Math.floor(Math.random() * pool.length)];
        var id = t.id;
        provider.fetchQuestion(id, t.label, t.category, root.seenFor(id), function (q, newSeen) {
            if (!q) {
                console.warn("QuizDaemon: pas de question pour", id);
                return;
            }
            q.topicLabel = t.label;       // pour le badge de la carte
            q.topicCategory = t.category;
            var s = root.sessionSeen;
            s[id] = newSeen;
            root.sessionSeen = s;
            root.pendingQuestion = q;
            root.fetchNudge(function () {
                overlay.showPending();
            }); // n'affiche la pastille qu'une fois le nudge (message+emoji+animation) prêt
        });
    }

    function completeOnboarding(ids, customs) {
        if (typeof pluginService !== "undefined" && pluginService) {
            pluginService.savePluginData("quizWidget", "selectedTopics", ids || []);
            pluginService.savePluginData("quizWidget", "customTopics", customs || []);
        }
        root.selectedTopics = ids || [];
        root.customTopics = customs || [];
        console.info("QuizDaemon: onboarding terminé,", (ids ? ids.length : 0), "catalogue +", (customs ? customs.length : 0), "libres");
        firstQuizTimer.restart();
    }

    function loadSettings() {
        if (typeof pluginService === "undefined" || !pluginService)
            return;
        root.paused = pluginService.loadPluginData("quizWidget", "paused", false);
        root.workMinutes = parseInt(pluginService.loadPluginData("quizWidget", "workMinutes", "25")) || 25;
        root.selectedTopics = pluginService.loadPluginData("quizWidget", "selectedTopics", []);
        root.customTopics = pluginService.loadPluginData("quizWidget", "customTopics", []);
    }

    Component.onCompleted: {
        Qt.callLater(function () {
            root.loadSettings();
            var nCat = root.selectedTopics ? root.selectedTopics.length : 0;
            var nCustom = root.customTopics ? root.customTopics.length : 0;
            if (nCat === 0 && nCustom === 0)
                overlay.showOnboarding();
            else if (!root.paused)
                firstQuizTimer.restart(); // sujets déjà configurés → 1re quiz peu après le démarrage (sinon attente = workMinutes)
            console.info("QuizDaemon: started, work", root.workMinutes, "min,", nCat, "catalogue +", nCustom, "libres");
        });
    }
    Component.onDestruction: console.info("QuizDaemon: stopped")
}
