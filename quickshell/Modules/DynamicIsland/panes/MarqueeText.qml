import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Widgets

// Single-line auto-scrolling text (iOS ticker): shuttles smoothly when it
// overflows instead of eliding to "…", with a soft fade at the clipped edges
// (no mid-glyph hard cut). Centered while it fits unless `centered: false`.
// Animates only while visible; exposes `textWidth` for layout maths.
Item {
    id: root
    property string text: ""
    property color color: "white"
    property int pixelSize: Theme.fontSizeMedium
    property bool bold: false
    property bool centered: true   // false = flush left while the text fits
    property real speed: 30   // px/s while shuttling toward the tail
    readonly property real textWidth: label.implicitWidth
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    property real scrollX: 0
    implicitHeight: label.implicitHeight
    clip: true

    onTextChanged: { scrollX = 0; if (shuttle.running) shuttle.restart() }

    // fade masks only exist while the text overflows; a fitting title renders
    // with zero effect cost
    layer.enabled: overflow > 1
    layer.effect: MultiEffect { maskEnabled: true; maskThresholdMin: 0; maskSpreadAtMin: 1; maskSource: fadeMask }
    Rectangle {
        id: fadeMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            // each edge fades only while glyphs are actually clipped there
            GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, root.scrollX > 1 ? 0 : 1) }
            GradientStop { position: 0.08; color: "white" }
            GradientStop { position: 0.92; color: "white" }
            GradientStop { position: 1.0;  color: Qt.rgba(1, 1, 1, (root.overflow - root.scrollX) > 1 ? 0 : 1) }
        }
    }

    StyledText {
        id: label
        x: root.overflow > 1 ? -root.scrollX : (root.centered ? (root.width - implicitWidth) / 2 : 0)
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
