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
    // mode apprentissage
    property string mode: "quiz" // "quiz" | "learning"
    property string learningSubject: ""
    property var learningHistory: []
    property string learningHistorySubject: ""
    property string currentNotion: "" // leçon en cours non validée → à ré-expliquer tant que pas "Suivant"

    // état runtime
    property var pendingQuestion: null
    property var pendingLesson: null
    property bool lessonValidated: false
    property var sessionSeen: ({})
    property string nudgeText: "Quiz dispo"
    property string nudgeEmoji: "🦉"
    property int animIndex: 0
    // Q&A leçon
    property string lessonAnswer: ""
    property bool lessonAnswering: false

    QuizProvider {
        id: provider
    }

    QuizOverlay {
        id: overlay
        question: root.pendingQuestion
        lesson: root.pendingLesson
        nudge: root.nudgeText
        emoji: root.nudgeEmoji
        animIndex: root.animIndex
        lessonAnswer: root.lessonAnswer
        lessonAnswering: root.lessonAnswering
        onAskQuestion: (q) => root.answerQuestion(q)
        onDismissed: {
            // Leçon : "Suivant" (validée) → on avance ; fermeture/report (non validée) → on retient
            // la notion pour la ré-expliquer au prochain cycle (ne PAS passer au suivant).
            if (root.pendingLesson) {
                if (root.lessonValidated)
                    root.setPendingNotion("");
                else
                    root.setPendingNotion(QuizEngine.summarizeStep(root.pendingLesson));
            }
            root.lessonValidated = false;
            root.pendingQuestion = null;
            root.pendingLesson = null;
            root.lessonAnswer = "";
            root.lessonAnswering = false;
        }
        onLessonDone: {
            root.lessonValidated = true;
            if (root.pendingLesson)
                root.recordHistory(QuizEngine.summarizeStep(root.pendingLesson));
        }
        // Un quiz d'apprentissage ne compte que s'il est RÉPONDU (validé), pas à la simple fermeture.
        onQuizAnswered: {
            if (root.mode === "learning" && root.pendingQuestion && root.pendingQuestion.summary)
                root.recordHistory(QuizEngine.summarizeStep(root.pendingQuestion));
        }
        onSnoozeRequested: (ms) => root.snooze(ms)
        onOnboardingComplete: (ids, customs) => root.completeOnboarding(ids, customs)
    }

    // Accroche de la pastille via `claude -p` qui renvoie un JSON {message, emoji, animation}
    // — claude choisit l'animation qui matche l'expression. On applique le résultat (ou un repli
    // local si claude échoue) PUIS on appelle onReady() : la pastille n'apparaît qu'une fois prête,
    // sans bascule d'animation. onReady est optionnel (re-nudge : rafraîchit la pastille déjà visible).
    function fetchNudge(onReady, context) {
        var fbText = QuizEngine.randomNudge();
        var fbEmoji = QuizEngine.randomEmoji();
        var fbAnim = Math.floor(Math.random() * Math.max(1, overlay.animCount));
        Proc.runCommand("quizWidget.nudge", [QuizEngine.claudeBinary(Quickshell.env("HOME")), "-p", QuizEngine.buildNudgePrompt(undefined, context)], function (stdout, exitCode) {
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
        onTriggered: root.requestNext()
    }

    Timer {
        id: snoozeTimer
        repeat: false
        onTriggered: {
            root.snoozing = false;
            root.requestNext();
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
        onTriggered: root.requestNext()
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
            overlay.contentType = "quiz";
            root.fetchNudge(function () {
                overlay.showPending();
            }); // n'affiche la pastille qu'une fois le nudge (message+emoji+animation) prêt
        });
    }

    // Dispatcher appelé par les timers : quiz ou apprentissage selon le mode.
    function requestNext() {
        if (root.mode === "learning")
            root.requestLearningStep();
        else
            root.requestQuiz();
    }

    // Mode apprentissage : l'IA enseigne la prochaine étape (leçon ou quiz) selon l'historique.
    function requestLearningStep() {
        if (root.pendingQuestion || root.pendingLesson)
            return;
        root.loadSettings();
        var subject = (root.learningSubject || "").trim();
        if (!subject)
            return;
        if (root.learningHistorySubject !== subject) {
            // sujet changé → réinitialiser la progression et la notion en cours
            root.learningHistory = [];
            root.learningHistorySubject = subject;
            root.setPendingNotion("");
            if (typeof pluginService !== "undefined" && pluginService) {
                pluginService.savePluginData("quizWidget", "learningHistory", []);
                pluginService.savePluginData("quizWidget", "learningHistorySubject", subject);
            }
        }
        var hist = root.learningHistory || [];
        var recent = hist.slice(Math.max(0, hist.length - 40));
        var notion = (root.currentNotion || "").trim();
        provider.fetchLearningStep(subject, recent, function (step) {
            if (!step) {
                console.warn("QuizDaemon: pas de leçon pour", subject);
                return;
            }
            step.topicLabel = subject;
            step.topicCategory = "Apprentissage";
            if (step.type === "lesson") {
                root.pendingLesson = step;
                overlay.contentType = "lesson";
            } else {
                root.pendingQuestion = step;
                overlay.contentType = "quiz";
            }
            root.fetchNudge(function () {
                overlay.showPending();
            }, "une nouvelle leçon de " + subject);
        }, notion ? notion : undefined);
    }

    function recordHistory(summary) {
        if (!summary)
            return;
        var h = (root.learningHistory || []).slice();
        h.push(summary);
        if (h.length > 60)
            h = h.slice(h.length - 60);
        root.learningHistory = h;
        if (typeof pluginService !== "undefined" && pluginService)
            pluginService.savePluginData("quizWidget", "learningHistory", h);
    }

    // Q&A : répond à une question libre de l'apprenant sur le sujet (réponse brève via claude -p).
    function answerQuestion(q) {
        var subject = (root.learningSubject || "").trim();
        if (!subject || !q || q.trim() === "")
            return;
        root.lessonAnswer = "";
        root.lessonAnswering = true;
        provider.fetchAnswer(subject, q, function (ans) {
            root.lessonAnswering = false;
            root.lessonAnswer = (ans && ans !== "") ? ans : "Désolé, je n'ai pas pu répondre. Réessaie ?";
        });
    }

    // Notion en cours non validée (persistée) : tant qu'elle est définie, on la ré-explique.
    function setPendingNotion(notion) {
        root.currentNotion = notion || "";
        if (typeof pluginService !== "undefined" && pluginService)
            pluginService.savePluginData("quizWidget", "learningPendingNotion", root.currentNotion);
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
        root.mode = pluginService.loadPluginData("quizWidget", "mode", "quiz");
        root.learningSubject = pluginService.loadPluginData("quizWidget", "learningSubject", "");
        root.learningHistory = pluginService.loadPluginData("quizWidget", "learningHistory", []);
        root.learningHistorySubject = pluginService.loadPluginData("quizWidget", "learningHistorySubject", "");
        root.currentNotion = pluginService.loadPluginData("quizWidget", "learningPendingNotion", "");
    }

    Component.onCompleted: {
        Qt.callLater(function () {
            root.loadSettings();
            if (root.mode === "learning") {
                if ((root.learningSubject || "").trim() !== "" && !root.paused)
                    firstQuizTimer.restart();
                console.info("QuizDaemon: started, mode learning, sujet", JSON.stringify(root.learningSubject), (root.learningHistory ? root.learningHistory.length : 0), "notions");
            } else {
                var nCat = root.selectedTopics ? root.selectedTopics.length : 0;
                var nCustom = root.customTopics ? root.customTopics.length : 0;
                if (nCat === 0 && nCustom === 0)
                    overlay.showOnboarding();
                else if (!root.paused)
                    firstQuizTimer.restart();
                console.info("QuizDaemon: started, mode quiz,", nCat, "catalogue +", nCustom, "libres");
            }
        });
    }
    Component.onDestruction: console.info("QuizDaemon: stopped")
}
