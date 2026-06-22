import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Ask-the-island drill view: a Spotlight-style field that sends to claude -p and
// shows the answer (plain text v1).
Column {
    id: askCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "ask" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "ask" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    readonly property bool askActive: island && island.mode === "expanded" && island.panelView === "ask"
    onAskActiveChanged: if (askActive) askField.forceActiveFocus()

    RowLayout {
        width: parent.width
        spacing: Theme.spacingS
        DankIcon { name: "auto_awesome"; size: 18; color: Theme.primary; Layout.alignment: Qt.AlignVCenter }
        DankTextField {
            id: askField
            Layout.fillWidth: true
            placeholderText: I18n.tr("Ask anything…")
            onAccepted: AskService.ask(text)
        }
    }
    // clipboard claude actions (operate on the current clipboard, user-initiated)
    Row {
        width: parent.width
        spacing: Theme.spacingXS
        DankButton {
            text: I18n.tr("Summarize")
            buttonHeight: 26
            backgroundColor: Theme.surfaceContainerHigh
            onClicked: AskService.askClipboard(I18n.tr("Summarize this text in a few bullet points"))
        }
        DankButton {
            text: I18n.tr("Translate")
            buttonHeight: 26
            backgroundColor: Theme.surfaceContainerHigh
            onClicked: AskService.askClipboard(I18n.tr("Translate this text to English"))
        }
        DankButton {
            text: I18n.tr("Explain")
            buttonHeight: 26
            backgroundColor: Theme.surfaceContainerHigh
            onClicked: AskService.askClipboard(I18n.tr("Explain this text simply"))
        }
    }
    DankFlickable {
        width: parent.width
        height: Math.min(contentHeight, 300)
        contentHeight: ansCol.implicitHeight
        clip: true
        visible: AskService.loading || AskService.answer.length > 0 || AskService.error.length > 0
        Column {
            id: ansCol
            width: parent.width
            StyledText {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                color: AskService.error.length > 0 ? Theme.error : Theme.surfaceText
                text: AskService.loading ? "💭 " + I18n.tr("Thinking…")
                    : (AskService.error.length > 0 ? AskService.error : AskService.answer)
            }
        }
    }
}
