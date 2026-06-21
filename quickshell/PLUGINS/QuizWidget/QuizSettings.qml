import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: settingsRoot
    pluginId: "quizWidget"

    property string currentMode: "quiz"
    property int learnedCount: 0
    function refreshState() {
        currentMode = loadValue("mode", "quiz");
        var h = loadValue("learningHistory", []);
        learnedCount = Array.isArray(h) ? h.length : 0;
    }
    Component.onCompleted: refreshState()
    onSettingChanged: refreshState()

    StyledText {
        width: parent.width
        text: "Quiz Widget"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    SelectionSetting {
        settingKey: "mode"
        label: "Mode"
        description: "Quiz ponctuels, ou parcours d'apprentissage guidé sur un sujet"
        options: [
            { label: "Quiz", value: "quiz" },
            { label: "Apprentissage", value: "learning" }
        ]
        defaultValue: "quiz"
    }

    ToggleSetting {
        settingKey: "paused"
        label: "Pause"
        description: "Suspendre temporairement"
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "workMinutes"
        label: "Intervalle"
        description: "Temps entre chaque quiz / leçon"
        options: [
            { label: "15 minutes", value: "15" },
            { label: "25 minutes", value: "25" },
            { label: "45 minutes", value: "45" },
            { label: "60 minutes", value: "60" }
        ]
        defaultValue: "25"
    }

    // --- section Quiz ---
    Column {
        width: parent.width
        spacing: Theme.spacingM
        visible: settingsRoot.currentMode === "quiz"

        StyledText {
            width: parent.width
            text: "Sujets (dev & IT)"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }
        StyledText {
            width: parent.width
            text: "Choisis les technos, concepts et méthodologies à réviser. Questions générées par Claude."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
        TopicPicker {
            settingKey: "selectedTopics"
            customSettingKey: "customTopics"
        }
    }

    // --- section Apprentissage ---
    Column {
        width: parent.width
        spacing: Theme.spacingM
        visible: settingsRoot.currentMode === "learning"

        StyledText {
            width: parent.width
            text: "Sujet à apprendre"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }
        StyledText {
            width: parent.width
            text: "Un seul sujet. L'IA joue un prof cool : surtout des leçons, parfois un quiz, et garde le fil de ta progression."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
        StringSetting {
            settingKey: "learningSubject"
            label: "Sujet"
            description: "Ex. Vim, Rust, théorie musicale…"
            placeholder: "Vim"
            defaultValue: ""
        }
        StyledText {
            width: parent.width
            text: "📚 " + settingsRoot.learnedCount + " notion(s) apprise(s)"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
        }
        StyledRect {
            implicitWidth: resetText.implicitWidth + Theme.spacingL * 2
            implicitHeight: resetText.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: resetArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
            StyledText {
                id: resetText
                anchors.centerIn: parent
                text: "Réinitialiser la progression"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
            MouseArea {
                id: resetArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    settingsRoot.saveValue("learningHistory", []);
                    settingsRoot.saveValue("learningHistorySubject", settingsRoot.loadValue("learningSubject", ""));
                    settingsRoot.refreshState();
                }
            }
        }
    }
}
