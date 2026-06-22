import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// IDLE (hover): workspaces + focused-window title + clock/weather/vpn/kb/tray/battery.
// Reads island state via `island`; exposes `wsWidth`/`clusterWidth` for pill geometry.
Item {
    id: idlePane
    property var island: null
    readonly property real wsWidth: wsRow.implicitWidth
    readonly property real clusterWidth: rightCluster.implicitWidth

    // SNI icons of Electron apps (Spotify, Discord, …) arrive as "name?path=/dir"
    // and need rewriting to a file URL (same logic as the DankBar tray widget)
    function trayIconSourceFor(trayItem) {
        let icon = trayItem && trayItem.icon
        if (typeof icon === 'string' || icon instanceof String) {
            if (icon === "") return ""
            if (icon.includes("?path=")) {
                const split = icon.split("?path=")
                if (split.length !== 2) return icon
                const name = split[0], path = split[1]
                let fileName = name.substring(name.lastIndexOf("/") + 1)
                if (fileName.startsWith("dropboxstatus"))
                    fileName = `hicolor/16x16/status/${fileName}`
                return `file://${path}/${fileName}`
            }
            if (icon.startsWith("/") && !icon.startsWith("file://"))
                return `file://${icon}`
            return icon
        }
        return ""
    }
    anchors.fill: parent
    anchors.leftMargin: Theme.spacingL; anchors.rightMargin: Theme.spacingL
    opacity: island.mode === "idle" ? 1 : 0
    visible: opacity > 0
    scale: island.mode === "idle" ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
    Behavior on scale { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }

    Row {
        id: wsRow
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS
        // directional entrance: the leading cluster slides in from the left
        // while the trailing one comes from the right (iOS unfold feel)
        transform: Translate {
            x: island.mode === "idle" ? 0 : -16
            Behavior on x { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }
        }
        Repeater {
            // gated by visibility: wsList rebuilds on every compositor event, and
            // an ungated Repeater would churn delegates even while the pane rests
            model: idlePane.visible ? island.wsList : []
            Rectangle {
                readonly property bool active: modelData.focused
                // circle for digits, capsule for named workspaces
                width: Math.max(30, wsLabel.implicitWidth + 16); height: 30; radius: height / 2
                color: active ? Theme.primarySelected : (wsArea.containsMouse ? Theme.surfaceHover : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                scale: wsArea.pressed ? 0.86 : 1.0
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                StyledText {
                    id: wsLabel
                    anchors.centerIn: parent; text: modelData.label
                    color: active ? island.accent : island.subText
                    font.pixelSize: Theme.fontSizeSmall; font.bold: active
                }
                MouseArea {
                    id: wsArea; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: island.wsActivate(modelData.key)
                }
            }
        }
    }
    // focused window — fills the gap BETWEEN the side clusters and
    // truncates to whatever width is actually available (no overlap)
    Item {
        id: centerSlot
        anchors.left: wsRow.right; anchors.leftMargin: Theme.spacingM
        anchors.right: rightCluster.left; anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        // width comes purely from the anchors -> never collapses
        MarqueeText {
            anchors.fill: parent
            visible: island.focusedTitle.length > 0
            text: island.focusedTitle
            color: island.textColor; pixelSize: Theme.fontSizeMedium; bold: true
        }
        StyledText {
            anchors.fill: parent
            visible: island.focusedTitle.length === 0
            text: island.clockLong
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: island.textColor; font.pixelSize: Theme.fontSizeLarge; font.bold: true
        }
    }
    Row {
        id: rightCluster
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS
        transform: Translate {
            x: island.mode === "idle" ? 0 : 16
            Behavior on x { NumberAnimation { duration: Theme.mediumDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial } }
        }
        StyledText {
            text: island.clockShort
            color: clockArea.containsMouse ? island.accent : island.textColor
            font.pixelSize: Theme.fontSizeSmall; font.bold: true
            anchors.verticalCenter: parent.verticalCenter
            // menu-bar-clock affordance: click straight into the calendar drill
            MouseArea {
                id: clockArea
                anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: island.openPanel("calendar")
            }
        }
        Row {  // weather
            spacing: 3; visible: island.weatherReady; anchors.verticalCenter: parent.verticalCenter
            DankIcon { name: island.weatherIcon; size: Theme.iconSize - 7; color: island.subText; anchors.verticalCenter: parent.verticalCenter }
            StyledText { text: island.weatherTemp; color: island.textColor; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
        }
        DankIcon {  // VPN
            name: "vpn_lock"; size: Theme.iconSize - 6; color: island.accent
            visible: island.vpnOn; anchors.verticalCenter: parent.verticalCenter
        }
        Item {  // Tailscale: peer count, exit-node glyph, click → panel
            visible: island.tsAvailable
            width: tsChip.implicitWidth; height: 22
            anchors.verticalCenter: parent.verticalCenter
            scale: tsArea.pressed ? 0.86 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            Row {
                id: tsChip
                spacing: 3
                anchors.verticalCenter: parent.verticalCenter
                DankIcon {
                    name: "device_hub"
                    size: Theme.iconSize - 6
                    color: island.tsNeedsAttention ? Theme.warning
                        : (island.tsConnected ? island.accent : island.subText)
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    visible: island.tsConnected
                    text: island.tsPeerCount
                    color: island.tsNeedsAttention ? Theme.warning : island.textColor
                    font.pixelSize: Theme.fontSizeSmall; font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                DankIcon {
                    visible: island.tsUsingExitNode
                    name: "public"
                    size: Theme.iconSize - 8
                    color: island.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: tsArea
                anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: island.openPanel("tailscale")
            }
        }
        Row {  // Bluetooth device battery (lowest connected device with battery)
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            readonly property var lowest: {
                const ds = BluetoothService.allDevicesWithBattery
                let best = null
                for (var i = 0; i < ds.length; i++)
                    if (!best || ds[i].battery < best.battery) best = ds[i]
                return best
            }
            visible: lowest !== null
            DankIcon {
                name: "bluetooth"
                size: Theme.iconSize - 7
                color: parent.lowest && parent.lowest.battery <= 0.2 ? Theme.error : island.subText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: parent.lowest ? Math.round(parent.lowest.battery * 100) + "%" : ""
                color: island.textColor; font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Item {  // Shelf: parked items, click drills into the shelf view
            visible: ShelfService.count > 0
            width: shelfChip.implicitWidth; height: 22
            anchors.verticalCenter: parent.verticalCenter
            scale: shelfArea.pressed ? 0.86 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            Row {
                id: shelfChip
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter
                DankIcon {
                    name: "place_item"; size: Theme.iconSize - 7
                    color: shelfArea.containsMouse ? island.accent : island.subText
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: ShelfService.count
                    color: shelfArea.containsMouse ? island.accent : island.textColor
                    font.pixelSize: Theme.fontSizeSmall; font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: shelfArea
                anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: island.openPanel("shelf")
            }
        }
        StyledText {  // keyboard layout (niri/dwl)
            text: island.kbLayout.substring(0, 2).toUpperCase()
            visible: island.kbLayout.length > 0
            color: island.subText; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
        Row {
            spacing: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
            Repeater {
                // gated like the workspaces; tray models churn on every SNI update
                model: idlePane.visible ? island.trayItems : []
                Item {
                    width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                    scale: trayArea.pressed ? 0.82 : (trayArea.containsMouse ? 1.12 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                    Image {
                        id: trayImg
                        anchors.centerIn: parent; width: 17; height: 17
                        source: idlePane.trayIconSourceFor(modelData)
                        sourceSize.width: 17; sourceSize.height: 17
                        asynchronous: true
                    }
                    DankIcon {  // fallback when the SNI icon fails to resolve
                        anchors.centerIn: parent; name: "widgets"; size: 15; color: island.subText
                        visible: trayImg.status !== Image.Ready
                    }
                    MouseArea {
                        id: trayArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.MiddleButton) {
                                modelData.secondaryActivate()
                            } else if (mouse.button === Qt.RightButton && modelData.hasMenu && modelData.menu) {
                                const p = trayArea.mapToItem(null, 0, 0)
                                island.openTrayMenu(modelData.menu, Qt.rect(p.x, p.y + trayArea.height, trayArea.width, trayArea.height))
                            } else {
                                modelData.activate()
                            }
                        }
                    }
                }
            }
        }
        Row {
            spacing: 4; visible: island.batAvailable; anchors.verticalCenter: parent.verticalCenter
            DankIcon {
                name: island.charging ? "battery_charging_full" : "battery_full"
                size: Theme.iconSize - 5
                color: island.charging ? Theme.primary : island.subText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: island.batPct + "%"; color: island.textColor; font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
