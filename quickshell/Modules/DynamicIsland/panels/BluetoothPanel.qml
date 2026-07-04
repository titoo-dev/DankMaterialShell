import QtQuick
import Quickshell
import Quickshell.Bluetooth
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

    // addresses currently being paired (optimistic per-row spinner). Reassigned
    // wholesale so QML re-evaluates the bindings that read it.
    property var pairingAddrs: ({})

    // discovered, not-yet-paired devices (same filter the native DMS UI uses).
    // Once discovery stops the RSSI is no longer refreshed, so long-gone devices
    // would linger forever — show the list only while actually discovering.
    readonly property var availableDevices: {
        if (!BluetoothService.enabled || !BluetoothService.devices || !BluetoothService.discovering)
            return []
        const list = BluetoothService.devices.values.filter(d => d && !d.paired && !d.pairing && !d.blocked && (d.signalStrength === undefined || d.signalStrength > 0))
        return BluetoothService.sortDevices(list)
    }

    // discover nearby devices only while this view is the active one and BT is on,
    // so the "Available" list populates automatically (and scanning stops when we
    // leave). Bound to a plain boolean (not `visible`, which lags behind the fade).
    readonly property bool btActive: island && island.mode === "expanded" && island.panelView === "bluetooth"
    function ensureDiscovery() {
        if (BluetoothService.adapter && BluetoothService.enabled)
            BluetoothService.adapter.discovering = btCol.btActive
    }
    onBtActiveChanged: ensureDiscovery()
    Connections { target: BluetoothService; function onEnabledChanged() { btCol.ensureDiscovery() } }
    // lazily loaded: stop the discovery we started if the view is torn down
    // before the btActive binding had a chance to flip
    Component.onDestruction: if (BluetoothService.adapter && BluetoothService.adapter.discovering) BluetoothService.adapter.discovering = false

    function pairNew(device) {
        if (!device)
            return
        let m = btCol.pairingAddrs; m[device.address] = true; btCol.pairingAddrs = m
        BluetoothService.pairDevice(device, function (resp) {
            let mm = btCol.pairingAddrs; delete mm[device.address]; btCol.pairingAddrs = mm
            if (resp && resp.error) { ToastService.showError(I18n.tr("Pairing failed"), resp.error); return }
            if (!BluetoothService.enhancedPairingAvailable) ToastService.showSuccess(I18n.tr("Device paired"))
        })
    }

    Item {
        width: parent.width; height: 34
        Rectangle {
            id: btBack
            width: 30; height: 30; radius: width / 2
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: btBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: btBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: btBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { island.panelView = "controls"; if (BluetoothService.adapter) BluetoothService.adapter.discovering = false } }
        }
        StyledText { anchors.left: btBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter; text: "Bluetooth"; color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true }

        // restart discovery to refresh the device list (icon spins while scanning)
        Timer { id: btRescanTimer; interval: 250; onTriggered: if (BluetoothService.adapter && BluetoothService.enabled) BluetoothService.adapter.discovering = true }

        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacingXS
            Rectangle {  // refresh: re-scan for devices
                width: 30; height: 30; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                enabled: BluetoothService.enabled
                opacity: enabled ? 1 : 0.4
                color: btRefreshArea.containsMouse ? Theme.primaryHover : "transparent"
                scale: btRefreshArea.pressed ? 0.9 : 1.0
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                DankIcon {
                    id: btRefreshIcon
                    anchors.centerIn: parent; name: "refresh"; size: 18; color: island.textColor
                    RotationAnimation on rotation {
                        running: BluetoothService.discovering
                        from: 0; to: 360; duration: 900; loops: Animation.Infinite
                        onRunningChanged: if (!running) btRefreshIcon.rotation = 0
                    }
                }
                MouseArea {
                    id: btRefreshArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!BluetoothService.adapter || !BluetoothService.enabled) return
                        BluetoothService.adapter.discovering = false   // restart for a fresh sweep
                        btRescanTimer.restart()
                    }
                }
            }
            Rectangle {  // radio on/off pill switch
                anchors.verticalCenter: parent.verticalCenter
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
    }

    Flickable {
        width: parent.width; height: Math.min(btList.height, 240); clip: true
        contentHeight: btList.height; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: btList
            width: parent.width; spacing: 4
            StyledText {
                width: parent.width; height: 40
                visible: !BluetoothService.enabled
                text: I18n.tr("Bluetooth is off")
                color: island.subText; font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                // keyed by address: device property changes (RSSI, battery) update
                // delegates IN PLACE instead of destroying/recreating the whole list
                model: ScriptModel { values: BluetoothService.enabled ? (BluetoothService.pairedDevices || []) : []; objectProp: "address" }
                Rectangle {
                    readonly property bool isConn: modelData.connected
                    readonly property bool isBusy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                    width: btList.width; height: 46; radius: height / 2
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
                        StyledText {
                            width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
                            text: {
                                if (modelData.state === BluetoothDeviceState.Connecting) return I18n.tr("Connecting…")
                                if (modelData.state === BluetoothDeviceState.Disconnecting) return I18n.tr("Disconnecting…")
                                return (parent.parent.isConn ? I18n.tr("Connected") : I18n.tr("Disconnected")) + ((modelData.batteryAvailable && modelData.battery > 0) ? ("  •  " + Math.round(modelData.battery * 100) + "%") : "")
                            }
                            color: parent.parent.isBusy ? island.accent : island.subText
                            font.pixelSize: Theme.fontSizeSmall - 2
                        }
                    }
                    DankIcon {
                        id: btSpin
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        name: parent.isBusy ? "sync" : (parent.isConn ? "check_circle" : "add_circle"); size: 16
                        color: parent.isBusy || parent.isConn ? island.accent : island.subText
                        RotationAnimation on rotation { running: btSpin.parent.isBusy; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onRunningChanged: if (!running) btSpin.rotation = 0 }
                    }
                    MouseArea {
                        id: btRowA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        enabled: !parent.isBusy   // no double-fire while a transition is in flight
                        onClicked: { if (modelData.connected) modelData.disconnect(); else BluetoothService.connectDeviceWithTrust(modelData) }
                    }
                }
            }

            // ---- Available (discovered, not-yet-paired) devices ----
            StyledText {
                width: parent.width; topPadding: Theme.spacingXS
                visible: BluetoothService.enabled && btCol.availableDevices.length > 0
                text: I18n.tr("Available")
                color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2; font.bold: true
            }
            StyledText {
                width: parent.width; height: 36
                visible: BluetoothService.enabled && btCol.availableDevices.length === 0
                text: BluetoothService.discovering ? I18n.tr("Searching for devices…") : I18n.tr("Tap refresh to scan for devices")
                color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                // keyed model: the available list re-sorts on every RSSI tick during
                // discovery — without identity-diffing every delegate would churn
                model: ScriptModel { values: BluetoothService.enabled ? btCol.availableDevices : []; objectProp: "address" }
                Rectangle {
                    readonly property bool isPairing: modelData.pairing || (btCol.pairingAddrs[modelData.address] === true)
                    width: btList.width; height: 46; radius: height / 2
                    color: avRowA.containsMouse ? Theme.surfaceLight : "transparent"
                    opacity: isPairing ? 0.7 : 1
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    DankIcon {
                        id: avIco
                        anchors.left: parent.left; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        name: BluetoothService.getDeviceIcon(modelData); size: 20; color: island.textColor
                    }
                    Column {
                        anchors.left: avIco.right; anchors.leftMargin: Theme.spacingM
                        anchors.right: avAdd.left; anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter; spacing: 0
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: modelData.name || modelData.deviceName || I18n.tr("Unknown Device"); color: island.textColor; font.pixelSize: Theme.fontSizeSmall }
                        StyledText { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap; text: parent.parent.isPairing ? I18n.tr("Pairing…") : (modelData.signalStrength > 0 ? (I18n.tr("Click to pair") + "  •  " + modelData.signalStrength + "%") : I18n.tr("Click to pair")); color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2 }
                    }
                    // add / spinner affordance
                    DankIcon {
                        id: avAdd
                        anchors.right: parent.right; anchors.rightMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                        name: parent.isPairing ? "bluetooth_searching" : "add_circle"; size: 16; color: parent.isPairing ? island.accent : island.subText
                        RotationAnimation on rotation {
                            running: avAdd.parent.isPairing
                            from: 0; to: 360; duration: 1100; loops: Animation.Infinite
                            onRunningChanged: if (!running) avAdd.rotation = 0
                        }
                    }
                    MouseArea {
                        id: avRowA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        enabled: !parent.isPairing
                        onClicked: btCol.pairNew(modelData)
                    }
                }
            }
        }
    }
}
