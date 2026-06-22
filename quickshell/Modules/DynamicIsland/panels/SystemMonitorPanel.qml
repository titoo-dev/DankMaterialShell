import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Services
import qs.Widgets

// System monitor detail view (drill-down, island-styled). Live CPU / RAM ring
// gauges + network throughput, all from the native DMS DgopService backend.
// Reads/writes island state via `island`; exposes `implicitHeight` (read by the
// controller's `pillH`). The DgopService module refs are held by the controller
// only while this view is open, so polling stays idle the rest of the time.
Column {
    id: monCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "monitor" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "monitor" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    // threshold -> accent / warning / error (shared by both ring gauges)
    function loadColor(v) {
        if (v > 90) return Theme.error
        if (v > 70) return Theme.warning
        return island.accent
    }
    function fmtRate(bytesPerSec) {
        const r = bytesPerSec || 0
        if (r < 1024) return r.toFixed(0) + " B/s"
        if (r < 1024 * 1024) return (r / 1024).toFixed(0) + " KB/s"
        if (r < 1024 * 1024 * 1024) return (r / (1024 * 1024)).toFixed(1) + " MB/s"
        return (r / (1024 * 1024 * 1024)).toFixed(1) + " GB/s"
    }

    // header: back + title, with live uptime on the right
    Item {
        width: parent.width; height: 34
        Rectangle {
            id: monBack
            width: 30; height: 30; radius: 9
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            color: monBackArea.containsMouse ? Theme.primaryHover : "transparent"
            scale: monBackArea.pressed ? 0.9 : 1.0
            Behavior on scale { SpringAnimation { spring: 7; damping: 0.3 } }
            DankIcon { anchors.centerIn: parent; name: "chevron_left"; size: 20; color: island.textColor }
            MouseArea { id: monBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: island.panelView = "controls" }
        }
        StyledText { anchors.left: monBack.right; anchors.leftMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("System"); color: island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true }
        StyledText {
            anchors.right: parent.right; anchors.rightMargin: Theme.spacingXS; anchors.verticalCenter: parent.verticalCenter
            text: DgopService.shortUptime ? ("↑ " + DgopService.shortUptime) : ""
            color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1
        }
    }

    // two big ring gauges: CPU% and RAM%
    Row {
        width: parent.width; spacing: Theme.spacingS
        readonly property real cellW: (width - spacing) / 2
        Repeater {
            model: [
                { kind: "cpu", icon: "memory",          lbl: "CPU" },
                { kind: "ram", icon: "developer_board", lbl: "RAM" }
            ]
            Rectangle {
                readonly property real val: modelData.kind === "cpu" ? DgopService.cpuUsage : DgopService.memoryUsage
                readonly property color ringColor: monCol.loadColor(val)
                width: parent.cellW; height: 132; radius: 16
                color: Theme.surfaceLight

                Column {
                    anchors.centerIn: parent; spacing: Theme.spacingXS
                    // ring gauge
                    Item {
                        width: 78; height: 78
                        anchors.horizontalCenter: parent.horizontalCenter
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            asynchronous: false
                            // track
                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)
                                strokeWidth: 7
                                capStyle: ShapePath.RoundCap
                                PathAngleArc { centerX: 39; centerY: 39; radiusX: 33; radiusY: 33; startAngle: 0; sweepAngle: 360 }
                            }
                            // progress
                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: ringColor
                                strokeWidth: 7
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: 39; centerY: 39; radiusX: 33; radiusY: 33
                                    startAngle: -90
                                    sweepAngle: 3.6 * Math.max(0, Math.min(100, val))
                                    Behavior on sweepAngle { NumberAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing } }
                                }
                            }
                        }
                        Column {
                            anchors.centerIn: parent; spacing: -2
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(val) + "%"
                                color: island.textColor; font.pixelSize: Theme.fontSizeLarge; font.bold: true
                            }
                            DankIcon { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.icon; size: 14; color: ringColor }
                        }
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.lbl; color: island.subText; font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true
                    }
                    // memory subtitle (used / total) only under the RAM gauge
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: modelData.kind === "ram"
                        text: DgopService.totalMemoryKB > 0 ? (DgopService.formatSystemMemory(DgopService.usedMemoryKB) + " / " + DgopService.formatSystemMemory(DgopService.totalMemoryKB)) : ""
                        color: island.subText; font.pixelSize: Theme.fontSizeSmall - 2
                    }
                    // CPU temperature subtitle under the CPU gauge
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: modelData.kind === "cpu" && DgopService.cpuTemperature > 0
                        text: DgopService.cpuTemperature + "°C"
                        color: DgopService.cpuTemperature >= 85 ? Theme.error : island.subText
                        font.pixelSize: Theme.fontSizeSmall - 2
                    }
                }
            }
        }
    }

    // network throughput: download / upload rates + a live mini sparkline each
    Row {
        width: parent.width; spacing: Theme.spacingS
        readonly property real cellW: (width - spacing) / 2
        Repeater {
            model: [
                { dir: "rx", icon: "south", lbl: I18n.tr("Download"), col: Theme.info },
                { dir: "tx", icon: "north", lbl: I18n.tr("Upload"),   col: Theme.error }
            ]
            Rectangle {
                id: netCell
                readonly property color dirColor: modelData.col
                readonly property real rate: modelData.dir === "rx" ? DgopService.networkRxRate : DgopService.networkTxRate
                readonly property var hist: {
                    const h = DgopService.networkHistory
                    return (h && h[modelData.dir]) ? h[modelData.dir] : []
                }
                width: parent.cellW; height: 64; radius: 16
                color: Theme.surfaceLight

                Row {
                    anchors.left: parent.left; anchors.leftMargin: Theme.spacingM
                    anchors.top: parent.top; anchors.topMargin: Theme.spacingS
                    spacing: Theme.spacingXS
                    DankIcon { name: modelData.icon; size: 14; color: netCell.dirColor; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { text: modelData.lbl; color: monCol.island.subText; font.pixelSize: Theme.fontSizeSmall - 1; anchors.verticalCenter: parent.verticalCenter }
                }
                StyledText {
                    anchors.left: parent.left; anchors.leftMargin: Theme.spacingM
                    anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.spacingS
                    text: monCol.fmtRate(netCell.rate)
                    color: monCol.island.textColor; font.pixelSize: Theme.fontSizeMedium; font.bold: true
                }
                // live sparkline (last samples normalised to the window max)
                Row {
                    id: spark
                    anchors.right: parent.right; anchors.rightMargin: Theme.spacingM
                    anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.spacingS
                    height: 26; spacing: 2
                    readonly property var samples: netCell.hist.slice(-16)
                    readonly property real peak: {
                        var m = 1
                        for (var i = 0; i < samples.length; i++) m = Math.max(m, samples[i] || 0)
                        return m
                    }
                    Repeater {
                        model: spark.samples
                        Rectangle {
                            width: 3; radius: 1.5
                            anchors.bottom: parent.bottom
                            height: Math.max(2, 26 * Math.min(1, (modelData || 0) / spark.peak))
                            color: Qt.rgba(netCell.dirColor.r, netCell.dirColor.g, netCell.dirColor.b, 0.8)
                        }
                    }
                }
            }
        }
    }
}
