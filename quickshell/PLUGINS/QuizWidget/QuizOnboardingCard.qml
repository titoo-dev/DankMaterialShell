import QtQuick
import qs.Common
import qs.Widgets

StyledRect {
    id: cardRoot
    signal start(var ids, var customs)

    readonly property color insetBorder: Qt.rgba(1, 1, 1, 0.14)

    // hauteur max de la liste de sujets (au-delà → scroll)
    property real maxPickerHeight: 360

    implicitWidth: 460
    implicitHeight: col.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: cardRoot.insetBorder

    ElevationShadow {
        anchors.fill: parent
        z: -1
        level: Theme.elevationLevel3
        targetRadius: cardRoot.radius
        targetColor: cardRoot.color
        borderColor: cardRoot.border.color
        borderWidth: cardRoot.border.width
        shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled
    }

    Column {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        StyledText {
            width: parent.width
            text: "Bienvenue 👋 Choisis tes sujets"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Sélectionne les technos, concepts et méthodologies dev/IT que tu veux réviser. Claude te posera des questions dessus."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        DankFlickable {
            id: pickerFlick
            width: parent.width
            height: Math.min(picker.implicitHeight, cardRoot.maxPickerHeight)
            contentHeight: picker.implicitHeight
            clip: true

            TopicPicker {
                id: picker
                width: pickerFlick.width - Theme.spacingS
            }
        }

        Item {
            width: parent.width
            height: startBtn.implicitHeight

            StyledRect {
                id: startBtn
                anchors.right: parent.right
                enabled: picker.selectedIds.length > 0 || picker.customTopics.length > 0
                implicitWidth: startText.implicitWidth + Theme.spacingL * 2
                implicitHeight: startText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: startBtn.enabled ? Theme.primary : Theme.surfaceContainer
                border.width: 1
                border.color: startBtn.enabled ? Qt.rgba(1, 1, 1, 0.22) : cardRoot.insetBorder

                StyledText {
                    id: startText
                    anchors.centerIn: parent
                    text: "Commencer"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: startBtn.enabled ? Theme.primaryText : Theme.surfaceVariantText
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: startBtn.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cardRoot.start(picker.selectedIds, picker.customTopics)
                }
            }
        }
    }
}
