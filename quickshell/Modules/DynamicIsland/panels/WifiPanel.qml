import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Wi-Fi detail view (drill-down, island-styled). Reads/writes island state via `island`.
Column {
    id: wifiCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "wifi" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "wifi" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    // header: back · title · radio toggle
    Item {
        width: parent.width; height: 34
        Rectangle {
            id: backBtn
            width: 30; height: 30; radius: 9
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: backArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: backArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
        }
        StyledText {
            anchors.left: backBtn.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
            text: "Wi-Fi"; color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacingXS
            StyledText {
                visible: NetworkService.isScanning; text: I18n.tr("Scanning…")
                color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1; anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {  // radio on/off pill switch
                width: 44; height: 24; radius: 12
                anchors.verticalCenter: parent.verticalCenter
                color: NetworkService.wifiEnabled ? Theme.primary : Theme.surfaceLight
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                Rectangle {
                    width: 18; height: 18; radius: 9; color: NetworkService.wifiEnabled ? Theme.primaryText : island.subText
                    anchors.verticalCenter: parent.verticalCenter
                    x: NetworkService.wifiEnabled ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.emphasizedEasing } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NetworkService.toggleWifiRadio() }
            }
        }
    }

    // scrollable network list — height adapts to content, capped
    Flickable {
        width: parent.width; height: Math.min(netCol.height, 232); clip: true
        contentHeight: netCol.height
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: netCol
            width: parent.width; spacing: 4
            StyledText {
                width: parent.width; height: 40
                visible: !NetworkService.wifiEnabled || (NetworkService.wifiNetworks || []).length === 0
                text: !NetworkService.wifiEnabled ? I18n.tr("Wi-Fi is off") : (NetworkService.isScanning ? I18n.tr("Scanning…") : I18n.tr("No networks found"))
                color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                model: NetworkService.wifiEnabled ? (NetworkService.wifiNetworks || []) : []
                Rectangle {
                    id: netRow
                    readonly property bool isConnected: modelData.ssid === NetworkService.currentWifiSSID
                    readonly property bool needsPw: modelData.secured && !modelData.saved && !isConnected
                    property bool pwOpen: false
                    width: netCol.width
                    height: pwOpen ? 84 : 46
                    radius: 12
                    color: (rowArea.containsMouse || isConnected) ? Theme.surfaceLight : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    Behavior on height { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.emphasizedEasing } }

                    DankIcon {
                        id: sigIcon
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.top: parent.top; anchors.topMargin: 13
                        name: (modelData.signal >= 66 ? "network_wifi" : modelData.signal >= 33 ? "network_wifi_3_bar" : "network_wifi_1_bar")
                        size: 20; color: netRow.isConnected ? island.accent : island.textColor
                    }
                    Column {
                        anchors.left: sigIcon.right; anchors.leftMargin: Theme.spacingM
                        anchors.right: rowRight.left; anchors.rightMargin: Theme.spacingS
                        anchors.top: parent.top; anchors.topMargin: 6; spacing: 0
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: modelData.ssid || I18n.tr("Unknown"); color: island.textColor; font.pixelSize: Theme.fontSizeSmall; font.bold: netRow.isConnected }
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: netRow.isConnected ? I18n.tr("Connected") : (modelData.secured ? I18n.tr("Secured") : I18n.tr("Open")); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                    }
                    Row {
                        id: rowRight
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.top: parent.top; anchors.topMargin: 13; spacing: Theme.spacingXS
                        DankIcon { visible: modelData.secured; name: "lock"; size: 14; color: island.subText; anchors.verticalCenter: parent.verticalCenter }
                        DankIcon { visible: netRow.isConnected; name: "check_circle"; size: 16; color: island.accent; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        id: rowArea; anchors.fill: parent; anchors.bottomMargin: netRow.pwOpen ? 40 : 0
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (netRow.isConnected) return
                            if (netRow.needsPw) netRow.pwOpen = !netRow.pwOpen
                            else NetworkService.connectToWifi(modelData.ssid)
                        }
                    }
                    // inline password entry for secured & unsaved networks
                    Row {
                        visible: netRow.pwOpen
                        anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Theme.spacingM
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                        spacing: Theme.spacingS
                        DankTextField {
                            id: pwField
                            width: parent.width - 40
                            height: 30
                            echoMode: TextInput.Password
                            placeholderText: I18n.tr("Password")
                            leftIconName: "lock"
                        }
                        Rectangle {
                            width: 32; height: 30; radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            color: goArea.containsMouse ? Theme.primary : Theme.surfaceVariant
                            DankIcon { anchors.centerIn: parent; name: "arrow_forward"; size: 16; color: goArea.containsMouse ? Theme.primaryText : island.textColor }
                            MouseArea {
                                id: goArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { NetworkService.connectToWifi(modelData.ssid, pwField.text); netRow.pwOpen = false }
                            }
                        }
                    }
                }
            }
        }
    }
}
