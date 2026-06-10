import QtQuick
import qs.Common
import qs.Widgets

// Single-line auto-scrolling text (iOS ticker): centered while it fits,
// shuttles smoothly when it overflows instead of eliding to "…".
// Animates only while visible; exposes `textWidth` for layout maths.
Item {
    id: root
    property string text: ""
    property color color: "white"
    property int pixelSize: Theme.fontSizeMedium
    property bool bold: false
    property real speed: 30   // px/s while shuttling toward the tail
    readonly property real textWidth: label.implicitWidth
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    property real scrollX: 0
    implicitHeight: label.implicitHeight
    clip: true

    onTextChanged: { scrollX = 0; if (shuttle.running) shuttle.restart() }

    StyledText {
        id: label
        x: root.overflow > 1 ? -root.scrollX : (root.width - implicitWidth) / 2
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: root.color
        font.pixelSize: root.pixelSize
        font.bold: root.bold
        maximumLineCount: 1
        wrapMode: Text.NoWrap
    }

    SequentialAnimation {
        id: shuttle
        running: root.visible && root.overflow > 1
        loops: Animation.Infinite
        onStopped: root.scrollX = 0
        PauseAnimation { duration: 1800 }
        NumberAnimation { target: root; property: "scrollX"; from: 0; to: root.overflow; duration: Math.max(600, root.overflow / root.speed * 1000) }
        PauseAnimation { duration: 1400 }
        NumberAnimation { target: root; property: "scrollX"; to: 0; duration: 500; easing.type: Easing.InOutQuad }
    }
}
