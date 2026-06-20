import QtQuick
import qs.Common
import qs.Widgets

StyledRect {
    id: card
    property var question: null
    property string mode: "open"   // "open" | "feedback"
    property int selected: -1
    signal select(int index)
    signal submit()
    signal close()

    readonly property bool correct: question && selected === question.answer

    // bordures blanches subtiles en inset (accent bento) — le reste suit le thème dynamique DMS
    readonly property color insetBorder: Qt.rgba(1, 1, 1, 0.14)
    readonly property color insetBorderSoft: Qt.rgba(1, 1, 1, 0.08)

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

        // Question (largeur réduite pour ne pas passer sous le bouton ×)
        StyledText {
            width: parent.width - Theme.iconSize
            text: card.question ? card.question.question : ""
            wrapMode: Text.WordWrap
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
                    implicitHeight: choiceText.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: index === card.selected
                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                           : (choiceArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer)
                    border.width: 1
                    border.color: index === card.selected ? Theme.primary : card.insetBorder

                    StyledText {
                        id: choiceText
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        text: modelData
                        wrapMode: Text.WordWrap
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
                font.pixelSize: Theme.fontSizeMedium
                text: card.question
                      ? ((card.correct ? "✓ Correct" : "✗ Incorrect — réponse : " + card.question.choices[card.question.answer])
                         + "\n" + card.question.explanation)
                      : ""
                color: Theme.surfaceText
            }
        }

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
    }
}
