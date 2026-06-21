import QtQuick
import qs.Common
import qs.Widgets
import "Catalog.js" as Catalog
import "QuizEngine.js" as QuizEngine

StyledRect {
    id: card

    function hex6(c) {
        function p(x) { var v = Math.round(x * 255).toString(16); return v.length < 2 ? "0" + v : v; }
        return "#" + p(c.r) + p(c.g) + p(c.b);
    }
    readonly property string codeColor: hex6(Theme.primary)
    readonly property string codeBg: hex6(Theme.surfaceContainerHighest)

    // hauteur max de la zone question/choix/feedback (au-delà → scroll)
    property real maxBodyHeight: 360
    property var question: null
    property string mode: "open"   // "open" | "feedback"
    property int selected: -1
    signal select(int index)
    signal submit()
    signal close()
    signal snooze(int ms)

    readonly property bool correct: question && selected === question.answer

    // bordures blanches subtiles en inset (accent bento) — le reste suit le thème dynamique DMS
    readonly property color insetBorder: Qt.rgba(1, 1, 1, 0.14)
    readonly property color insetBorderSoft: Qt.rgba(1, 1, 1, 0.08)

    // pastilles A/B/C/D — quartet coloré « jeu télé » pour le fun
    readonly property var choiceColors: ["#4F86F7", "#33B679", "#F5A623", "#A368E8"]
    readonly property var choiceLetters: ["A", "B", "C", "D"]

    implicitWidth: 380
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

    // Bouton fermer (×) — disponible à tout moment, en haut-droite
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

        // Badge de sujet — emoji de catégorie + label, pilule colorée
        StyledRect {
            visible: card.question && card.question.topicLabel
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
                    text: card.question ? Catalog.categoryEmoji(card.question.topicCategory) : ""
                    font.pixelSize: Theme.fontSizeSmall
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.question ? (card.question.topicLabel || "") : ""
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.primary
                }
            }
        }

        // Question + choix + feedback : hauteur plafonnée + scrollable
        DankFlickable {
            id: bodyFlick
            width: parent.width
            height: Math.min(bodyCol.implicitHeight, card.maxBodyHeight)
            contentHeight: bodyCol.implicitHeight
            clip: true

            Column {
                id: bodyCol
                width: bodyFlick.width - Theme.spacingS
                spacing: Theme.spacingM

        // Question (largeur réduite pour ne pas passer sous le bouton ×) — markdown + emoji
        StyledText {
            width: parent.width - Theme.iconSize
            text: QuizEngine.mdToHtml(card.question ? card.question.question : "", card.codeColor, card.codeBg)
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
            color: Theme.surfaceText
        }

        // Choix — tuiles bento recessed
        Column {
            width: parent.width
            spacing: Theme.spacingS
            visible: card.mode === "open"

            Repeater {
                model: card.question ? card.question.choices : []

                StyledRect {
                    id: choiceTile
                    width: parent.width
                    implicitHeight: Math.max(choiceText.implicitHeight, 24) + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: index === card.selected
                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                           : (choiceArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer)
                    border.width: index === card.selected ? 2 : 1
                    border.color: index === card.selected ? Theme.primary : card.insetBorder

                    // pastille A/B/C/D colorée (accent « jeu télé »)
                    Rectangle {
                        id: marker
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        width: 24
                        height: 24
                        radius: width / 2
                        color: card.choiceColors[index % 4]

                        StyledText {
                            anchors.centerIn: parent
                            text: card.choiceLetters[index % 4]
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: "white"
                        }
                    }

                    StyledText {
                        id: choiceText
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: marker.right
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        text: QuizEngine.mdToHtml(modelData, card.codeColor, card.codeBg)
                        textFormat: Text.RichText
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }

                    MouseArea {
                        id: choiceArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.select(index)
                    }
                }
            }
        }

        // Feedback — tuile bento teintée
        StyledRect {
            width: parent.width
            visible: card.mode === "feedback"
            implicitHeight: feedbackText.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: card.correct
                   ? Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.20)
                   : Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.20)
            border.width: 1
            border.color: card.insetBorder

            StyledText {
                id: feedbackText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                wrapMode: Text.WordWrap
                textFormat: Text.RichText
                elide: Text.ElideNone
                font.pixelSize: Theme.fontSizeMedium
                text: QuizEngine.mdToHtml(card.question
                      ? ((card.correct
                          ? "🎉 **Bravo, c'est ça !**"
                          : "😅 **Raté !** La bonne réponse : " + card.question.choices[card.question.answer])
                         + "\n\n" + card.question.explanation)
                      : "", card.codeColor, card.codeBg)
                color: Theme.surfaceText
            }
        }
            } // bodyCol
        } // bodyFlick

        // Actions — tuiles bento
        Row {
            anchors.right: parent.right
            spacing: Theme.spacingS

            StyledRect {
                visible: card.mode === "open"
                implicitWidth: validateText.implicitWidth + Theme.spacingL * 2
                implicitHeight: validateText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: card.selected >= 0 ? Theme.primary : Theme.surfaceContainer
                border.width: 1
                border.color: card.selected >= 0 ? Qt.rgba(1, 1, 1, 0.22) : card.insetBorderSoft

                StyledText {
                    id: validateText
                    anchors.centerIn: parent
                    text: "Valider"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: card.selected >= 0 ? Theme.primaryText : Theme.surfaceVariantText
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: card.selected >= 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.submit()
                }
            }

            StyledRect {
                visible: card.mode === "feedback"
                implicitWidth: closeText.implicitWidth + Theme.spacingL * 2
                implicitHeight: closeText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainer
                border.width: 1
                border.color: card.insetBorder

                StyledText {
                    id: closeText
                    anchors.centerIn: parent
                    text: "Fermer"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.close()
                }
            }
        }

        // Reporter (snooze) — décale la prochaine quiz de X s/min/h
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
    }
}
