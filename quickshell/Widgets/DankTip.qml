import QtQuick
import qs.Common

// Attaches a morphing tooltip to a button. Drop it inside the button and bind
// `active` to that button's hover state:
//
//     DankTip { text: I18n.tr("Copy"); active: copyArea.containsMouse }
//
// Non-visual, so it never joins a Row / Column / Layout it is declared in.
// The capsule itself is drawn once per window by DankTooltipMorph — this only
// publishes "the pointer is on ME, and here is my label".
Item {
    id: tip

    property string text: ""
    property bool active: false
    // "bottom" | "top" | "left" | "right"; flipped by the view when it doesn't fit
    property string side: "bottom"
    // what the capsule points at — the button this tip lives in by default
    property Item target: parent

    visible: false

    // a button that scrolled out, got hidden by its row's hover fade or lost its
    // label must drop the tooltip even though the pointer never left it
    readonly property bool _live: active && enabled && text.length > 0 && !!target && target.visible

    on_LiveChanged: _sync()
    onTextChanged: if (_live) _sync()
    onSideChanged: if (_live) _sync()
    Component.onDestruction: if (target) TooltipManager.dismiss(target)

    function _sync() {
        if (_live)
            TooltipManager.request(target, text, side);
        else if (target)
            TooltipManager.dismiss(target);
    }
}
