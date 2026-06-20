import QtQuick
import Quickshell.Io
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
        _loadBank(subject, function (bank) {
            var res = QuizEngine.pickQuestion(bank, seen);
            if (res)
                callback(res.question, res.seen);
            else
                callback(null, seen || []);
        });
    }

    // Lecture asynchrone de banks/<subject>.json via FileView (pattern prouvé du repo).
    function _loadBank(subject, cb) {
        var url = Qt.resolvedUrl("banks/" + subject + ".json").toString();
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
