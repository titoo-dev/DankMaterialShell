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

    implicitWidth: 360
    implicitHeight: col.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainer
    border.width: 1
    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.08)

    Column {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        StyledText {
            width: parent.width
            text: card.question ? card.question.question : ""
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Medium
            color: Theme.onSurface
        }

        Column { // choix
            width: parent.width
            spacing: Theme.spacingXS
            visible: card.mode === "open"

            Repeater {
                model: card.question ? card.question.choices : []

                StyledRect {
                    width: parent.width
                    implicitHeight: choiceText.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: index === card.selected ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    border.width: index === card.selected ? 1 : 0
                    border.color: Theme.primary

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
                        color: Theme.onSurface
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.select(index)
                    }
                }
            }
        }

        StyledText { // feedback
            width: parent.width
            visible: card.mode === "feedback"
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeMedium
            text: card.question
                  ? ((card.correct ? "✓ Correct" : "✗ Incorrect — réponse : " + card.question.choices[card.question.answer])
                     + "\n" + card.question.explanation)
                  : ""
            color: card.correct ? Theme.success : Theme.error
        }

        Row { // actions
            anchors.right: parent.right
            spacing: Theme.spacingS

            StyledRect {
                visible: card.mode === "open"
                implicitWidth: validateText.implicitWidth + Theme.spacingM * 2
                implicitHeight: validateText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: card.selected >= 0 ? Theme.primary : Theme.surfaceContainerHigh

                StyledText {
                    id: validateText
                    anchors.centerIn: parent
                    text: "Valider"
                    font.pixelSize: Theme.fontSizeMedium
                    color: card.selected >= 0 ? Theme.onPrimary : Theme.onSurfaceVariant
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
                implicitWidth: closeText.implicitWidth + Theme.spacingM * 2
                implicitHeight: closeText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                StyledText {
                    id: closeText
                    anchors.centerIn: parent
                    text: "Fermer"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.onSurface
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
