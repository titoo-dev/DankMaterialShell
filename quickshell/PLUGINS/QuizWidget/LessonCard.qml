import QtQuick
import qs.Common
import qs.Widgets
import "Catalog.js" as Catalog
import "QuizEngine.js" as QuizEngine

StyledRect {
    id: card
    property var lesson: null
    signal next()
    signal close()
    signal snooze(int ms)

    readonly property color insetBorder: Qt.rgba(1, 1, 1, 0.14)
    readonly property color insetBorderSoft: Qt.rgba(1, 1, 1, 0.08)

    // couleurs du code (markdown → RichText), dérivées du thème
    function hex6(c) {
        function p(x) { var v = Math.round(x * 255).toString(16); return v.length < 2 ? "0" + v : v; }
        return "#" + p(c.r) + p(c.g) + p(c.b);
    }
    readonly property string codeColor: hex6(Theme.primary)
    readonly property string codeBg: hex6(Theme.surfaceContainerHighest)

    // hauteur max de la zone de contenu (au-delà → scroll)
    property real maxContentHeight: 380

    // Q&A : poser une question libre sur le sujet
    property bool askMode: false
    property string answer: ""
    property bool answering: false
    property real maxAnswerHeight: 200
    signal ask(string question)
    onLessonChanged: card.askMode = false
    function _submitAsk() {
        var q = askInput.text.trim();
        if (q === "")
            return;
        card.ask(q);
        askInput.text = "";
    }

    // Vrai quand le champ de question a le focus clavier → l'overlay suspend ses keymaps.
    property bool inputActive: askInput.activeFocus

    function openAsk() {
        card.askMode = true;
        askInput.forceActiveFocus();
    }
    function closeAsk() {
        card.askMode = false;
        askInput.text = "";
    }

    implicitWidth: 400
    implicitHeight: col.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: card.insetBorder

    ElevationShadow {
        anchors.fill: parent
        z: -1
        level: Theme.elevationLevel3
        targetRadius: card.radius
        targetColor: card.color
        borderColor: card.border.color
        borderWidth: card.border.width
        shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled
    }

    StyledRect {
        id: closeButton
        z: 1
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        width: 28
        height: 28
        radius: width / 2
        color: closeBtnArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"
        DankIcon {
            anchors.centerIn: parent
            name: "close"
            size: Theme.iconSizeSmall
            color: Theme.surfaceText
        }
        MouseArea {
            id: closeBtnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.close()
        }
    }

    Column {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        // badge sujet
        StyledRect {
            visible: card.lesson && card.lesson.topicLabel
            implicitWidth: badgeRow.implicitWidth + Theme.spacingM * 2
            implicitHeight: badgeRow.implicitHeight + Theme.spacingXS * 2
            radius: height / 2
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
            border.width: 1
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
            Row {
                id: badgeRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.lesson ? Catalog.categoryEmoji(card.lesson.topicCategory) : ""
                    font.pixelSize: Theme.fontSizeSmall
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.lesson ? (card.lesson.topicLabel || "") : ""
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.primary
                }
            }
        }

        // titre (markdown → RichText + emoji)
        StyledText {
            width: parent.width - Theme.iconSize
            text: QuizEngine.mdToHtml(card.lesson ? (card.lesson.title || "") : "", card.codeColor, card.codeBg)
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        // contenu (markdown → RichText) — hauteur plafonnée + scrollable
        DankFlickable {
            id: contentFlick
            width: parent.width
            height: Math.min(contentText.implicitHeight, card.maxContentHeight)
            contentHeight: contentText.implicitHeight
            clip: true

            StyledText {
                id: contentText
                width: contentFlick.width - Theme.spacingS
                text: QuizEngine.mdToHtml(card.lesson ? (card.lesson.content || "") : "", card.codeColor, card.codeBg)
                textFormat: Text.RichText
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
            }
        }

        // actions : Des questions ? + Suivant
        Row {
            anchors.right: parent.right
            spacing: Theme.spacingS

            StyledRect {
                implicitWidth: askText.implicitWidth + Theme.spacingL * 2
                implicitHeight: askText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: card.askMode
                       ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                       : (askBtnArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer)
                border.width: 1
                border.color: card.askMode ? Theme.primary : card.insetBorderSoft
                StyledText {
                    id: askText
                    anchors.centerIn: parent
                    text: card.askMode ? "Fermer ✕" : "Des questions ?"
                    font.pixelSize: Theme.fontSizeMedium
                    color: card.askMode ? Theme.primary : Theme.surfaceText
                }
                MouseArea {
                    id: askBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        card.askMode = !card.askMode;
                        if (card.askMode)
                            askInput.forceActiveFocus();
                        else
                            askInput.text = "";
                    }
                }
            }

            StyledRect {
                implicitWidth: nextText.implicitWidth + Theme.spacingL * 2
                implicitHeight: nextText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: Theme.primary
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.22)
                StyledText {
                    id: nextText
                    anchors.centerIn: parent
                    text: "Compris 👍 Suivant"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.primaryText
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.next()
                }
            }
        }

        // reporter (snooze)
        Row {
            spacing: Theme.spacingXS
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Reporter :"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
            Repeater {
                model: [
                    { label: "30 s", ms: 30000 },
                    { label: "5 min", ms: 300000 },
                    { label: "15 min", ms: 900000 },
                    { label: "1 h", ms: 3600000 }
                ]
                StyledRect {
                    radius: Theme.cornerRadius
                    color: snoozeArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                    border.width: 1
                    border.color: card.insetBorderSoft
                    implicitWidth: snoozeLabel.implicitWidth + Theme.spacingM * 2
                    implicitHeight: snoozeLabel.implicitHeight + Theme.spacingXS * 2
                    StyledText {
                        id: snoozeLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }
                    MouseArea {
                        id: snoozeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.snooze(modelData.ms)
                    }
                }
            }
        }

        // --- Q&A : panneau réponse (au-dessus) + champ de saisie (en bas) ---
        StyledRect {
            visible: card.askMode && (card.answering || card.answer !== "")
            width: parent.width
            implicitHeight: ansFlick.height + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainer
            border.width: 1
            border.color: card.insetBorderSoft

            DankFlickable {
                id: ansFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                height: Math.min(ansText.implicitHeight, card.maxAnswerHeight)
                contentHeight: ansText.implicitHeight
                clip: true

                StyledText {
                    id: ansText
                    width: ansFlick.width - Theme.spacingS
                    text: card.answering ? "💭 Je réfléchis…" : QuizEngine.mdToHtml(card.answer, card.codeColor, card.codeBg)
                    textFormat: card.answering ? Text.PlainText : Text.RichText
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }
            }
        }

        Row {
            visible: card.askMode
            width: parent.width
            spacing: Theme.spacingS

            DankTextField {
                id: askInput
                width: Math.max(0, parent.width - askSend.width - Theme.spacingS)
                placeholderText: "Pose ta question sur " + (card.lesson ? (card.lesson.topicLabel || "le sujet") : "le sujet") + "…"
                onAccepted: card._submitAsk()
            }

            DankButton {
                id: askSend
                text: "Demander"
                buttonHeight: 44
                onClicked: card._submitAsk()
            }
        }
    }
}
