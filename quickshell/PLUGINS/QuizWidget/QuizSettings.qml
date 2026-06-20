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
        color: Theme.onSurface
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

    ListSettingWithInput {
        settingKey: "subjects"
        label: "Sujets"
        description: "Sujets à réviser (doit correspondre à un fichier banks/<sujet>.json et/ou un prompt IA)"
        defaultValue: []
        fields: [
            { id: "name", label: "Sujet", placeholder: "algorithmes", width: 220, required: true }
        ]
    }

    ToggleSetting {
        settingKey: "aiEnabled"
        label: "Générer via IA"
        description: "Utilise Claude pour générer des questions (sinon banque locale uniquement)"
        defaultValue: false
    }

    StringSetting {
        settingKey: "apiKey"
        label: "Clé API Anthropic"
        description: "Requise si « Générer via IA » est activé"
        placeholder: "sk-ant-…"
        defaultValue: ""
    }
}
