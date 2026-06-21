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

        // contenu (markdown → RichText : gras, code stylé, listes…)
        StyledText {
            width: parent.width
            text: QuizEngine.mdToHtml(card.lesson ? (card.lesson.content || "") : "", card.codeColor, card.codeBg)
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
        }

        // action : Suivant
        Row {
            anchors.right: parent.right
            spacing: Theme.spacingS
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
    }
}
