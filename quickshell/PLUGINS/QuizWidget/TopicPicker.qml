import QtQuick
import qs.Common
import qs.Widgets
import "Catalog.js" as Catalog

Column {
    id: root

    // Mode réglages (optionnel) : si une settingKey est définie, charge/persiste via le PluginSettings parent.
    property string settingKey: ""        // sujets catalogue (liste d'id)
    property string customSettingKey: ""  // sujets libres (liste de chaînes)
    // Source de vérité (en onboarding : lire directement + écouter les signaux).
    property var selectedIds: []
    property var customTopics: []
    property bool isLoading: false

    signal toggled(string id)
    signal changed(var ids)
    signal customChanged(var customs)

    width: parent ? parent.width : implicitWidth
    spacing: Theme.spacingM

    Component.onCompleted: if (root.settingKey !== "" || root.customSettingKey !== "") loadValue()

    function loadValue() {
        var settings = findSettings();
        if (settings) {
            isLoading = true;
            if (root.settingKey !== "")
                selectedIds = settings.loadValue(settingKey, []);
            if (root.customSettingKey !== "")
                customTopics = settings.loadValue(customSettingKey, []);
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

    function addCustomTopic(label) {
        var next = Catalog.addCustom(root.customTopics, label);
        if (next.length === (root.customTopics ? root.customTopics.length : 0))
            return; // rien ajouté (vide ou doublon)
        root.customTopics = next;
        root.customChanged(next);
        _persistCustom();
    }

    function removeCustomTopic(label) {
        var out = (root.customTopics || []).filter(function (x) { return x !== label; });
        root.customTopics = out;
        root.customChanged(out);
        _persistCustom();
    }

    function _persistCustom() {
        if (root.customSettingKey !== "" && !root.isLoading) {
            var settings = findSettings();
            if (settings)
                settings.saveValue(customSettingKey, root.customTopics);
        }
    }

    function _commitInput() {
        root.addCustomTopic(customInput.text);
        customInput.text = "";
    }

    // --- catalogue curaté ---
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

    // --- sujets libres ---
    Column {
        width: root.width
        spacing: Theme.spacingS

        StyledText {
            text: "Mes sujets"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        Row {
            width: root.width
            spacing: Theme.spacingS

            DankTextField {
                id: customInput
                width: Math.max(0, root.width - addBtn.width - Theme.spacingS)
                height: 44
                placeholderText: "Ajouter un sujet (ex. WebSockets, GraphQL…)"
                onAccepted: root._commitInput()
            }

            DankButton {
                id: addBtn
                text: "Ajouter"
                buttonHeight: 44
                onClicked: root._commitInput()
            }
        }

        Flow {
            width: root.width
            spacing: Theme.spacingS
            visible: (root.customTopics || []).length > 0

            Repeater {
                model: root.customTopics

                StyledRect {
                    id: cchip
                    property string clabel: modelData
                    implicitWidth: cchipRow.implicitWidth + Theme.spacingM * 2
                    implicitHeight: cchipRow.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: cchipArea.containsMouse ? Theme.surfaceContainerHighest : Theme.primary
                    border.width: 1
                    border.color: Theme.primary

                    Row {
                        id: cchipRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: cchip.clabel
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.primaryText
                        }

                        DankIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "close"
                            size: Theme.iconSizeSmall
                            color: Theme.primaryText
                        }
                    }

                    MouseArea {
                        id: cchipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeCustomTopic(cchip.clabel)
                    }
                }
            }
        }
    }
}
