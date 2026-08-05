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

    // SSID whose inline password prompt is open (one at a time); the island
    // grabs the keyboard only while a prompt is showing
    property string pwSsid: ""
    onPwSsidChanged: if (island) island.wifiNeedsKeyboard = (pwSsid !== "")
    // SSID of the most recent connect attempt, for inline error attribution
    property string lastTriedSsid: ""

    // ref-count the service while the view is open so the network list stays
    // fresh, and kick a scan on entry (covers the direct IPC `open wifi` path)
    readonly property bool wifiActive: island && island.mode === "expanded" && island.panelView === "wifi"
    onWifiActiveChanged: {
        if (wifiActive) {
            NetworkService.addRef()
            if (NetworkService.wifiEnabled) NetworkService.scanWifiNetworks()
        } else {
            NetworkService.removeRef()
            pwSsid = ""
            lastTriedSsid = ""
        }
    }
    Component.onDestruction: if (wifiActive) NetworkService.removeRef()

    // wrong password → the service asks for credentials again: reopen the
    // inline prompt instead of letting the global modal pop over the island
    Connections {
        target: NetworkService
        function onPasswordDialogShouldReopenChanged() {
            if (NetworkService.passwordDialogShouldReopen && wifiCol.wifiActive && wifiCol.lastTriedSsid.length > 0)
                wifiCol.pwSsid = wifiCol.lastTriedSsid
        }
    }

    // header: back · title · radio toggle
    DrillHeader {
        island: wifiCol.island; title: "Wi-Fi"
        Rectangle {  // refresh: rescan networks (icon spins while scanning)
            width: 30; height: 30; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            enabled: NetworkService.wifiEnabled
            opacity: enabled ? 1 : 0.4
            color: refreshArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: refreshArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon {
                id: wifiRefreshIcon
                anchors.centerIn: parent; name: "refresh"; size: 18; color: island.textColor
                RotationAnimation on rotation {
                    running: NetworkService.isScanning
                    from: 0; to: 360; duration: 900; loops: Animation.Infinite
                    onRunningChanged: if (!running) wifiRefreshIcon.rotation = 0
                }
            }
            MouseArea {
                id: refreshArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: if (NetworkService.wifiEnabled) NetworkService.scanWifiNetworks()
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("Scan for networks")
                Accessible.onPressAction: clicked(null)
            }
            DankTip {
                text: NetworkService.isScanning ? I18n.tr("Scanning…") : I18n.tr("Scan for networks")
                active: refreshArea.containsMouse && NetworkService.wifiEnabled
            }
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
            MouseArea {
                id: wifiRadioArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: NetworkService.toggleWifiRadio()
                Accessible.role: Accessible.CheckBox
                Accessible.name: "Wi-Fi"
                Accessible.checked: NetworkService.wifiEnabled
                Accessible.onPressAction: clicked(null)
            }
            DankTip {
                text: NetworkService.wifiEnabled ? I18n.tr("Turn off") : I18n.tr("Turn on")
                active: wifiRadioArea.containsMouse
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
                    readonly property bool isConnecting: NetworkService.isConnecting && NetworkService.connectingSSID === modelData.ssid
                    readonly property bool needsPw: modelData.secured && !modelData.saved && !isConnected
                    // 802.1X: the prompt also needs an identity (username) field
                    readonly property bool isEnterprise: modelData.enterprise === true
                    readonly property bool pwOpen: wifiCol.pwSsid === modelData.ssid
                    // show the last connection error inline, on the network that failed
                    readonly property bool showError: !isConnected && !isConnecting && wifiCol.lastTriedSsid === modelData.ssid && (NetworkService.lastConnectionError || "").length > 0
                    width: netCol.width
                    height: pwOpen ? (isEnterprise ? 122 : 84) : 46
                    radius: pwOpen ? 16 : 23
                    color: (rowArea.containsMouse || isConnected) ? Theme.surfaceLight : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    Behavior on height { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.emphasizedEasing } }
                    Behavior on radius { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.emphasizedEasing } }

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
                        StyledText {
                            width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: netRow.isConnecting ? I18n.tr("Connecting…")
                                : netRow.showError ? NetworkService.lastConnectionError
                                : netRow.isConnected ? I18n.tr("Connected")
                                : (modelData.secured ? I18n.tr("Secured") : I18n.tr("Open"))
                            color: netRow.showError ? Theme.error : (netRow.isConnecting ? island.accent : island.subText)
                            font.pixelSize: Theme.fontSizeSmall - 2
                        }
                    }
                    Row {
                        id: rowRight
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.top: parent.top; anchors.topMargin: 13; spacing: Theme.spacingXS
                        DankIcon { visible: modelData.secured && !netRow.isConnecting; name: "lock"; size: 14; color: island.subText; anchors.verticalCenter: parent.verticalCenter }
                        DankIcon { visible: netRow.isConnected && !netRow.isConnecting; name: "check_circle"; size: 16; color: island.accent; anchors.verticalCenter: parent.verticalCenter }
                        DankIcon {  // connection-in-progress spinner
                            visible: netRow.isConnecting; name: "sync"; size: 16; color: island.accent
                            anchors.verticalCenter: parent.verticalCenter
                            RotationAnimation on rotation { running: netRow.isConnecting; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                    }
                    MouseArea {
                        id: rowArea; anchors.fill: parent; anchors.bottomMargin: netRow.pwOpen ? (netRow.isEnterprise ? 78 : 40) : 0
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.ssid || I18n.tr("Unknown")
                        onClicked: {
                            if (netRow.isConnected || netRow.isConnecting) return
                            if (netRow.needsPw) {
                                wifiCol.pwSsid = netRow.pwOpen ? "" : modelData.ssid
                            } else {
                                wifiCol.lastTriedSsid = modelData.ssid
                                NetworkService.connectToWifi(modelData.ssid)
                            }
                        }
                        Accessible.onPressAction: clicked(null)
                    }
                    // inline credential entry for secured & unsaved networks —
                    // identity + password for 802.1X, password alone otherwise
                    Column {
                        visible: netRow.pwOpen
                        // focus the first field as soon as the prompt opens (the island's
                        // keyboard grab engages via island.wifiNeedsKeyboard)
                        onVisibleChanged: {
                            idField.text = ""; pwField.text = ""
                            if (visible) (netRow.isEnterprise ? idField : pwField).forceActiveFocus()
                        }
                        anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Theme.spacingM
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                        spacing: Theme.spacingXS
                        function submit() {
                            if (pwField.text.length === 0) return
                            if (netRow.isEnterprise && idField.text.length === 0) { idField.forceActiveFocus(); return }
                            wifiCol.lastTriedSsid = modelData.ssid
                            NetworkService.connectToWifi(modelData.ssid, pwField.text, netRow.isEnterprise ? idField.text : "")
                            idField.text = ""; pwField.text = ""
                            wifiCol.pwSsid = ""
                        }
                        DankTextField {
                            id: idField
                            visible: netRow.isEnterprise
                            width: parent.width; height: 30
                            placeholderText: I18n.tr("Identity (username)")
                            leftIconName: "person"
                            onAccepted: pwField.forceActiveFocus()
                        }
                        Row {
                            width: parent.width
                            spacing: Theme.spacingS
                            DankTextField {
                                id: pwField
                                width: parent.width - 80
                                height: 30
                                property bool reveal: false
                                echoMode: reveal ? TextInput.Normal : TextInput.Password
                                placeholderText: I18n.tr("Password")
                                leftIconName: "lock"
                                onAccepted: parent.parent.submit()
                                onVisibleChanged: if (!visible) reveal = false
                            }
                            Rectangle {  // reveal toggle
                                width: 32; height: 30; radius: height / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: pwField.reveal ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : (revealArea.containsMouse ? Theme.surfaceLight : Theme.surfaceVariant)
                                DankIcon { anchors.centerIn: parent; name: pwField.reveal ? "visibility_off" : "visibility"; size: 16; color: pwField.reveal ? Theme.primary : island.textColor }
                                MouseArea {
                                    id: revealArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.name: I18n.tr("Show password")
                                    Accessible.checked: pwField.reveal
                                    onClicked: pwField.reveal = !pwField.reveal
                                    Accessible.onPressAction: clicked(null)
                                }
                                DankTip {
                                    text: pwField.reveal ? I18n.tr("Hide password") : I18n.tr("Show password")
                                    active: revealArea.containsMouse
                                }
                            }
                            Rectangle {
                                width: 32; height: 30; radius: height / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: goArea.containsMouse ? Theme.primary : Theme.surfaceVariant
                                DankIcon { anchors.centerIn: parent; name: "arrow_forward"; size: 16; color: goArea.containsMouse ? Theme.primaryText : island.textColor }
                                MouseArea {
                                    id: goArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    Accessible.role: Accessible.Button
                                    Accessible.name: I18n.tr("Connect")
                                    onClicked: parent.parent.parent.submit()
                                    Accessible.onPressAction: clicked(null)
                                }
                                DankTip { text: I18n.tr("Connect"); active: goArea.containsMouse }
                            }
                        }
                    }
                }
            }
        }
    }
}
