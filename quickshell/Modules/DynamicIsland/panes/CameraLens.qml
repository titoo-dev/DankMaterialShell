import QtQuick

// The "camera" anchoring the notch's central gap (MacBook skeuomorphism):
// a dark lens with a faint ring and a cool glint. Purely decorative.
Item {
    id: lens
    property real gap: 52   // total reserved width around the lens
    width: gap; height: 12

    Rectangle {
        anchors.centerIn: parent
        width: 9; height: 9; radius: 4.5
        color: "#0b0e14"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07)
        Rectangle {   // lens glint
            x: 2.5; y: 2.5; width: 2.5; height: 2.5; radius: 1.25
            color: Qt.rgba(0.45, 0.55, 0.75, 0.55)
        }
    }
}
