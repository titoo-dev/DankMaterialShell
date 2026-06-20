import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "quizWidget"

    StyledText {
        width: parent.width
        text: "Quiz Widget"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "paused"
        label: "Pause"
        description: "Suspendre temporairement les quiz"
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "workMinutes"
        label: "Durée de travail"
        description: "Intervalle avant chaque quiz"
        options: [
            { label: "15 minutes", value: "15" },
            { label: "25 minutes", value: "25" },
            { label: "45 minutes", value: "45" },
            { label: "60 minutes", value: "60" }
        ]
        defaultValue: "25"
    }

    StyledText {
        width: parent.width
        text: "Sujets (dev & IT)"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Choisis les technos, concepts et méthodologies à réviser. Les questions sont générées par Claude (claude -p) sur ces sujets."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    TopicPicker {
        settingKey: "selectedTopics"
    }
}
