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
        Repeater {
            model: island.wsList
            Rectangle {
                readonly property bool active: modelData.focused
                width: 30; height: 30; radius: 10
                color: active ? Theme.primarySelected : (wsArea.containsMouse ? Theme.surfaceHover : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                scale: wsArea.pressed ? 0.86 : 1.0
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                StyledText {
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
        StyledText {
            anchors.fill: parent
            visible: island.focusedTitle.length > 0
            text: island.focusedTitle
            elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
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
        StyledText {  // keyboard layout (niri/dwl)
            text: island.kbLayout.substring(0, 2).toUpperCase()
            visible: island.kbLayout.length > 0
            color: island.subText; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
        Row {
            spacing: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: island.trayItems
                Item {
                    width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                    scale: trayArea.pressed ? 0.82 : (trayArea.containsMouse ? 1.12 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                    Image {
                        anchors.centerIn: parent; width: 17; height: 17
                        source: modelData.icon ?? ""
                        sourceSize.width: 17; sourceSize.height: 17
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
