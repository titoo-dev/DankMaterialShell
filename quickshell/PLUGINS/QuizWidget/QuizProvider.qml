import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import "QuizEngine.js" as QuizEngine

Item {
    id: provider

    // fetchQuestion(topicId, label, category, seen, callback(question|null, newSeen))
    function fetchQuestion(topicId, label, category, seen, callback) {
        _fetchAi(label, category, function (q) {
            if (q) {
                var ns = (seen || []).slice();
                ns.push(q.id);
                callback(q, ns);
            } else {
                _fetchLocal(topicId, seen, callback); // fallback banque locale si présente
            }
        });
    }

    // Apprentissage : une étape (leçon OU quiz) via `claude -p`, selon l'historique couvert.
    function fetchLearningStep(subject, history, callback, relearnNotion) {
        var prompt = (relearnNotion && relearnNotion !== "")
            ? QuizEngine.buildRelearnPrompt(subject, relearnNotion, history)
            : QuizEngine.buildLessonPrompt(subject, history);
        Proc.runCommand("quizWidget.learn", [
            QuizEngine.claudeBinary(Quickshell.env("HOME")), "-p", "--model", "claude-haiku-4-5", prompt
        ], function (stdout, exitCode) {
            if (exitCode !== 0) {
                console.warn("QuizProvider: learn claude -p exit", exitCode);
                callback(null);
                return;
            }
            callback(QuizEngine.parseLearningStep(stdout));
        }, 0, 60000);
    }

    // Réponse libre à une question de l'apprenant sur le sujet (texte markdown bref).
    function fetchAnswer(subject, question, history, currentTitle, callback) {
        var prompt = QuizEngine.buildAnswerPrompt(subject, question, history, currentTitle);
        Proc.runCommand("quizWidget.answer", [
            QuizEngine.claudeBinary(Quickshell.env("HOME")), "-p", "--model", "claude-haiku-4-5", prompt
        ], function (stdout, exitCode) {
            if (exitCode !== 0) {
                console.warn("QuizProvider: answer claude -p exit", exitCode);
                callback(null);
                return;
            }
            callback((stdout || "").trim());
        }, 0, 45000);
    }

    // Génération via `claude -p` (CLI Claude Code local — pas de clé API, comme le nudge).
    function _fetchAi(label, category, callback) {
        var prompt = QuizEngine.buildQuestionPrompt(label, category);
        var bin = QuizEngine.claudeBinary(Quickshell.env("HOME"));
        Proc.runCommand("quizWidget.gen", [
            bin, "-p", "--model", "claude-haiku-4-5", prompt
        ], function (stdout, exitCode) {
            if (exitCode !== 0) {
                console.warn("QuizProvider: claude -p exit", exitCode);
                callback(null);
                return;
            }
            callback(QuizEngine.extractQuestionJson(stdout));
        }, 0, 60000); // debounce 0, timeout 60 s (la génération claude -p dépasse le défaut de 10 s)
    }

    function _fetchLocal(topicId, seen, callback) {
        _loadBank(topicId, function (bank) {
            var res = QuizEngine.pickQuestion(bank, seen);
            if (res)
                callback(res.question, res.seen);
            else
                callback(null, seen || []);
        });
    }

    // Lecture asynchrone de banks/<topicId>.json via FileView (pattern prouvé du repo).
    function _loadBank(topicId, cb) {
        var url = Qt.resolvedUrl("banks/" + topicId + ".json").toString();
        var path = url.indexOf("file://") === 0 ? url.substring(7) : url;
        bankFvComp.createObject(provider, { "path": path, "cb": cb });
    }

    Component {
        id: bankFvComp
        FileView {
            property var cb: null
            onLoaded: {
                var bank = [];
                try {
                    bank = JSON.parse(text());
                } catch (e) {
                    console.warn("QuizProvider: parse bank failed", path, e);
                }
                if (cb)
                    cb(bank);
                destroy();
            }
            onLoadFailed: err => {
                console.warn("QuizProvider: bank load failed", path, err);
                if (cb)
                    cb([]);
                destroy();
            }
        }
    }
}
