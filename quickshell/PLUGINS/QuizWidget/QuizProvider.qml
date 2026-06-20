import QtQuick
import qs.Common
import "QuizEngine.js" as QuizEngine

Item {
    id: provider
    property bool aiEnabled: false
    property string apiKey: ""

    // fetchQuestion(subject, seen, callback(question|null, newSeen))
    function fetchQuestion(subject, seen, callback) {
        if (provider.aiEnabled && provider.apiKey !== "") {
            _fetchAi(subject, function (q) {
                if (q) {
                    var ns = (seen || []).slice();
                    ns.push(q.id);
                    callback(q, ns);
                } else {
                    _fetchLocal(subject, seen, callback); // fallback
                }
            });
        } else {
            _fetchLocal(subject, seen, callback);
        }
    }

    function _fetchLocal(subject, seen, callback) {
        var bank = _loadBank(subject);
        var res = QuizEngine.pickQuestion(bank, seen);
        if (res)
            callback(res.question, res.seen);
        else
            callback(null, seen || []);
    }

    function _loadBank(subject) {
        var path = Qt.resolvedUrl("banks/" + subject + ".json");
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", path, false);
            xhr.send();
            if (xhr.status === 200 || xhr.status === 0)
                return JSON.parse(xhr.responseText);
        } catch (e) {
            console.warn("QuizProvider: cannot load bank", subject, e);
        }
        return [];
    }

    function _fetchAi(subject, callback) {
        var body = QuizEngine.buildAiRequestBody(subject);
        Proc.runCommand("quizWidget.gen", [
            "curl", "-s", "-X", "POST", "https://api.anthropic.com/v1/messages",
            "-H", "x-api-key: " + provider.apiKey,
            "-H", "anthropic-version: 2023-06-01",
            "-H", "content-type: application/json",
            "-d", body
        ], function (stdout, exitCode) {
            if (exitCode !== 0) {
                console.warn("QuizProvider: AI curl exit", exitCode);
                callback(null);
                return;
            }
            callback(QuizEngine.parseAiQuestion(stdout));
        }, 0);
    }
}
