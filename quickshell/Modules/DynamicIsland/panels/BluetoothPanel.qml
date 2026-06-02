import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Bluetooth detail view (drill-down, island-styled). Reads/writes island state via `island`.
Column {
    id: btCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "bluetooth" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "bluetooth" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    Item {
        width: parent.width; height: 34
        Rectangle {
            id: btBack
            width: 30; height: 30; radius: 9
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: btBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: btBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: btBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { island.panelView = "controls"; if (BluetoothService.adapter) BluetoothService.adapter.discovering = false } }
        }
        StyledText { anchors.left: btBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter; text: "Bluetooth"; color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true }
        Rectangle {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: 44; height: 24; radius: 12
            color: BluetoothService.enabled ? Theme.primary : Theme.surfaceLight
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            Rectangle {
                width: 18; height: 18; radius: 9; color: BluetoothService.enabled ? Theme.primaryText : island.subText
                anchors.verticalCenter: parent.verticalCenter
                x: BluetoothService.enabled ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.emphasizedEasing } }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (BluetoothService.adapter) BluetoothService.adapter.enabled = !BluetoothService.enabled } }
        }
    }

    Flickable {
        width: parent.width; height: Math.min(btList.height, 240); clip: true
        contentHeight: btList.height; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: btList
            width: parent.width; spacing: 4
            StyledText {
                width: parent.width; height: 40
                visible: !BluetoothService.enabled || (BluetoothService.pairedDevices || []).length === 0
                text: !BluetoothService.enabled ? I18n.tr("Bluetooth is off") : I18n.tr("No devices")
                color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: BluetoothService.enabled ? (BluetoothService.pairedDevices || []) : []
                Rectangle {
                    readonly property bool isConn: modelData.connected
                    width: btList.width; height: 46; radius: 12
                    color: (btRowA.containsMouse || isConn) ? Theme.surfaceLight : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    DankIcon {
                        id: btIco
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        name: BluetoothService.getDeviceIcon(modelData); size: 20; color: parent.isConn ? island.accent : island.textColor
                    }
                    Column {
                        anchors.left: btIco.right; anchors.leftMargin: Theme.spacingM
                        anchors.right: btSpin.left; anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter; spacing: 0
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: modelData.name || modelData.deviceName || I18n.tr("Unknown Device"); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: parent.parent.isConn }
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: (parent.parent.isConn ? I18n.tr("Connected") : I18n.tr("Disconnected")) + ((modelData.batteryAvailable && modelData.battery > 0) ? ("  •  " + Math.round(modelData.battery * 100) + "%") : ""); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                    }
                    DankIcon { id: btSpin; anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter; name: parent.isConn ? "check_circle" : "add_circle"; size: 16; color: parent.isConn ? island.accent : island.subText }
                    MouseArea {
                        id: btRowA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (modelData.connected) modelData.disconnect(); else BluetoothService.connectDeviceWithTrust(modelData) }
                    }
                }
            }
        }
    }
}
