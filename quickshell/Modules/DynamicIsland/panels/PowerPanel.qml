import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Session / power detail view (drill-down, island-styled). Reads/writes island
// state via `island`. Each action runs against the same DMS services the native
// power menu uses, then collapses the island.
Column {
    id: powerCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "power" ? 1 : 0
    visible: opacity > 0
    onVisibleChanged: if (!visible) { armedKey = ""; disarmTimer.stop() }

    // destructive actions need a second click within 3 s (honours the same
    // SettingsData.powerActionConfirm the native power menu uses)
    property string armedKey: ""
    Timer { id: disarmTimer; interval: 3000; onTriggered: powerCol.armedKey = "" }
    transform: Translate { x: island.panelView === "power" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    // header: back + title
    DrillHeader { island: powerCol.island; title: I18n.tr("Power") }

    // two prominent tiles (Lock / Sleep) then a row of destructive actions
    Row {
        width: parent.width; spacing: Theme.spacingS
        readonly property real tileW: (width - spacing) / 2
        Repeater {
            model: [
                { key: "lock",    icon: "lock",        lbl: I18n.tr("Lock"),  danger: false },
                { key: "suspend", icon: "bedtime",     lbl: I18n.tr("Sleep"), danger: false }
            ]
            Rectangle {
                width: parent.tileW; height: 62; radius: 16
                color: tArea.containsMouse ? Theme.primaryHover : Theme.surfaceLight
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                scale: tArea.pressed ? 0.94 : 1.0
                Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
                Column {
                    anchors.centerIn: parent; spacing: 3
                    DankIcon { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.icon; size: 22; color: tArea.containsMouse ? island.accent : island.textColor }
                    StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.lbl; font.pixelSize: Theme.fontSizeSmall; font.bold: true; color: island.textColor }
                }
                MouseArea {
                    id: tArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: powerCol.run(modelData.key)
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.lbl
                    Accessible.onPressAction: clicked(null)
                }
            }
        }
    }

    // destructive / session actions as full-width rows
    Repeater {
        model: [
            { key: "logout",  icon: "logout",             lbl: I18n.tr("Log Out") },
            { key: "reboot",  icon: "restart_alt",        lbl: I18n.tr("Restart") },
            { key: "poweroff", icon: "power_settings_new", lbl: I18n.tr("Shut Down") }
        ]
        Rectangle {
            readonly property bool danger: modelData.key === "poweroff" || modelData.key === "reboot"
            readonly property bool armed: powerCol.armedKey === modelData.key
            width: parent.width; height: 44; radius: height / 2
            color: armed ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.16)
                 : rArea.containsMouse ? Theme.surfaceLight : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            scale: rArea.pressed ? 0.97 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            Rectangle {  // icon disc: destructive actions tinted error
                id: rIco
                width: 30; height: 30; radius: width / 2
                anchors.left: parent.left; anchors.leftMargin: 7; anchors.verticalCenter: parent.verticalCenter
                color: (danger || armed) ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, armed ? 0.20 : 0.16) : Theme.surfaceVariant
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                DankIcon {
                    anchors.centerIn: parent; name: modelData.icon; size: 17; filled: true
                    color: (danger || armed) ? Theme.error : island.textColor
                }
            }
            StyledText {
                anchors.left: rIco.right; anchors.leftMargin: Theme.spacingM; anchors.verticalCenter: parent.verticalCenter
                text: armed ? I18n.tr("Click again to confirm") : modelData.lbl
                font.pixelSize: Theme.fontSizeSmall; font.bold: true
                color: armed || (danger && rArea.containsMouse) ? Theme.error : island.textColor
            }
            MouseArea {
                id: rArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: powerCol.run(modelData.key)
                Accessible.role: Accessible.Button
                Accessible.name: modelData.lbl
                Accessible.onPressAction: clicked(null)
            }
        }
    }

    function run(key) {
        // destructive actions arm on first click, fire on the second (3 s window)
        const destructive = key === "logout" || key === "reboot" || key === "poweroff"
        if (destructive && SettingsData.powerActionConfirm && armedKey !== key) {
            armedKey = key
            disarmTimer.restart()
            return
        }
        armedKey = ""
        disarmTimer.stop()
        // collapse the island first so the menu doesn't linger over the action
        if (island) island.closeIsland()
        switch (key) {
        case "lock":     IdleService.lockRequested(); break
        case "suspend":  SessionService.suspend(); break
        case "logout":   SessionService.logout(); break
        case "reboot":   SessionService.reboot(); break
        case "poweroff": SessionService.poweroff(); break
        }
    }
}
