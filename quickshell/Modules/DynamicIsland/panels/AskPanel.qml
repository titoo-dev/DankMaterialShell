import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import "../../../Common/Markdown.js" as Markdown

// Ask-the-island: a Spotlight-style prompt that sends to claude -p and renders the
// answer as themed rich text (headings, lists, inline + fenced code panels).
Column {
    id: askCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingM
    opacity: island.panelView === "ask" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "ask" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    function hex6(c) {
        function p(x) { var v = Math.round(x * 255).toString(16); return v.length < 2 ? "0" + v : v; }
        return "#" + p(c.r) + p(c.g) + p(c.b);
    }
    readonly property var mdOpts: ({
        codeColor: hex6(Theme.primary),
        codeBg: hex6(Theme.surfaceContainerHighest),
        mono: Theme.monoFontFamily,
        linkColor: hex6(Theme.primary)
    })
    readonly property bool hasOutput: AskService.loading || AskService.answer.length > 0 || AskService.error.length > 0

    readonly property bool askActive: island && island.mode === "expanded" && island.panelView === "ask"
    onAskActiveChanged: if (askActive) askField.forceActiveFocus()

    // ---- hero: the prompt field (Spotlight-style) ----
    Rectangle {
        width: parent.width
        height: 48
        radius: height / 2
        color: Theme.surfaceLight
        border.width: 1
        border.color: askField.activeFocus ? Theme.primary : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)
        Behavior on border.color { ColorAnimation { duration: Theme.shortDuration } }

        DankIcon {
            id: spark
            anchors.left: parent.left; anchors.leftMargin: Theme.spacingL
            anchors.verticalCenter: parent.verticalCenter
            name: "auto_awesome"; size: 20
            color: askField.activeFocus ? Theme.primary : Theme.surfaceVariantText
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
        }
        DankTextField {
            id: askField
            anchors.left: spark.right; anchors.leftMargin: Theme.spacingM
            anchors.right: askSend.left; anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            backgroundColor: "transparent"
            normalBorderColor: "transparent"
            focusedBorderColor: "transparent"
            font.pixelSize: Theme.fontSizeLarge
            placeholderText: I18n.tr("Ask anything…")
            onAccepted: AskService.ask(text)
        }
        Rectangle {  // the view's one accent-filled primary action: send
            id: askSend
            width: 32; height: 32; radius: width / 2
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.primary
            opacity: askField.text.length > 0 ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
            scale: askSendArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "arrow_upward"; size: 18; color: Theme.primaryText }
            MouseArea { id: askSendArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: AskService.ask(askField.text) }
            DankTip { text: I18n.tr("Send"); active: askSendArea.containsMouse }
        }
    }

    // ---- clipboard quick actions ----
    Row {
        width: parent.width
        spacing: Theme.spacingS
        Repeater {
            model: [
                { lbl: I18n.tr("Summarize"), icon: "summarize",  prompt: I18n.tr("Summarize this text in a few bullet points") },
                { lbl: I18n.tr("Translate"), icon: "translate",  prompt: I18n.tr("Translate this text to English") },
                { lbl: I18n.tr("Explain"),   icon: "lightbulb",  prompt: I18n.tr("Explain this text simply") }
            ]
            delegate: DankButton {
                text: modelData.lbl
                iconName: modelData.icon
                iconSize: 14
                buttonHeight: 30
                radius: buttonHeight / 2
                backgroundColor: hovered ? Theme.primaryHover : Theme.surfaceLight
                textColor: hovered ? Theme.primary : Theme.surfaceText
                onClicked: AskService.askClipboard(modelData.prompt)
            }
        }
    }

    // ---- hairline separator (only with output) ----
    Rectangle {
        width: parent.width; height: 1
        visible: askCol.hasOutput
        color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)
    }

    // ---- thinking state ----
    Row {
        spacing: Theme.spacingS
        visible: AskService.loading
        DankIcon {
            name: "auto_awesome"; size: 18; color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
            SequentialAnimation on opacity {
                running: AskService.loading; loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutSine }
            }
        }
        StyledText {
            text: I18n.tr("Thinking…")
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ---- error ----
    StyledText {
        width: parent.width
        visible: !AskService.loading && AskService.error.length > 0
        text: AskService.error
        color: Theme.error
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.WordWrap
    }

    // ---- answer (rich markdown) ----
    DankFlickable {
        width: parent.width
        height: Math.min(answerText.implicitHeight, 340)
        contentHeight: answerText.implicitHeight
        clip: true
        visible: !AskService.loading && AskService.answer.length > 0
        StyledText {
            id: answerText
            width: parent.width - Theme.spacingS
            text: Markdown.toRichText(AskService.answer, askCol.mdOpts)
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            onLinkActivated: link => Quickshell.execDetached(["xdg-open", link])
        }
    }

    // ---- empty hint ----
    StyledText {
        width: parent.width
        visible: !askCol.hasOutput
        text: I18n.tr("Ask a question, or run an action on your clipboard.")
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.WordWrap
    }
}
