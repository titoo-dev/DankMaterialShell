import QtQuick
import qs.Common
import qs.Widgets
import "Catalog.js" as Catalog

Column {
    id: root

    // Mode réglages (optionnel) : si settingKey est défini, charge/persiste via le PluginSettings parent.
    property string settingKey: ""
    // Source de vérité de la sélection (liste d'id). En onboarding, lire selectedIds + écouter changed.
    property var selectedIds: []
    property bool isLoading: false

    signal toggled(string id)
    signal changed(var ids)

    width: parent ? parent.width : implicitWidth
    spacing: Theme.spacingM

    Component.onCompleted: if (root.settingKey !== "") loadValue()

    function loadValue() {
        var settings = findSettings();
        if (settings) {
            isLoading = true;
            selectedIds = settings.loadValue(settingKey, []);
            isLoading = false;
        }
    }

    function findSettings() {
        var item = parent;
        while (item) {
            if (item.saveValue !== undefined && item.loadValue !== undefined)
                return item;
            item = item.parent;
        }
        return null;
    }

    function isSelected(id) {
        return (root.selectedIds || []).indexOf(id) !== -1;
    }

    function toggle(id) {
        var ids = (root.selectedIds || []).slice();
        var i = ids.indexOf(id);
        if (i === -1)
            ids.push(id);
        else
            ids.splice(i, 1);
        root.selectedIds = ids;
        root.toggled(id);
        root.changed(ids);
        if (root.settingKey !== "" && !root.isLoading) {
            var settings = findSettings();
            if (settings)
                settings.saveValue(settingKey, ids);
        }
    }

    Repeater {
        model: Catalog.categoriesWithTopics()

        Column {
            id: catBlock
            property var cat: modelData
            width: root.width
            spacing: Theme.spacingS

            StyledText {
                text: catBlock.cat.category
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            Flow {
                width: root.width
                spacing: Theme.spacingS

                Repeater {
                    model: catBlock.cat.topics

                    StyledRect {
                        id: chip
                        property var topic: modelData
                        readonly property bool sel: (root.selectedIds || []).indexOf(chip.topic.id) !== -1
                        implicitWidth: chipText.implicitWidth + Theme.spacingM * 2
                        implicitHeight: chipText.implicitHeight + Theme.spacingS * 2
                        radius: Theme.cornerRadius
                        color: chip.sel ? Theme.primary : (chipArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer)
                        border.width: 1
                        border.color: chip.sel ? Theme.primary : Qt.rgba(1, 1, 1, 0.14)

                        StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.topic.label
                            font.pixelSize: Theme.fontSizeSmall
                            color: chip.sel ? Theme.primaryText : Theme.surfaceText
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggle(chip.topic.id)
                        }
                    }
                }
            }
        }
    }
}
