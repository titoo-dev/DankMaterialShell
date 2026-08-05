pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Shared hover-intent state behind DankTip / DankTooltipMorph.
//
// The pointer can only be over ONE button, so a single state bus is enough —
// and it is what buys the macOS feel: instead of every button owning a popup
// that fades out and back in, one capsule MORPHS from button to button.
// The timing lives here too, so the dwell is a property of the RUN rather than
// of each button: the first tooltip waits, its neighbours appear instantly.
Singleton {
    id: manager

    // the button the visible capsule describes (null while nothing shows)
    property Item anchorItem: null
    property string text: ""
    // preferred placement; the view flips it when the surface runs out
    property string side: "bottom"
    property bool shown: false

    // hover intent before the FIRST tooltip of a run appears
    property int dwell: 420
    // once a run ends, re-entering any button this soon reopens instantly
    property int warmWindow: 800
    // a gap this short between two buttons reads as a morph, not a close
    property int handover: 120

    property Item _pending: null
    property string _pendingText: ""
    property string _pendingSide: "bottom"
    property bool _warm: false

    function request(item, tipText, tipSide) {
        if (!item || !tipText || tipText.length === 0) {
            dismiss(item);
            return;
        }
        _pending = item;
        _pendingText = tipText;
        _pendingSide = (tipSide && tipSide.length > 0) ? tipSide : "bottom";
        // the pointer landed somewhere new before the close could commit:
        // that is a handover, so keep the capsule alive and let it glide
        handoverTimer.stop();
        if (shown || _warm) {
            _commit();
            return;
        }
        dwellTimer.restart();
    }

    function dismiss(item) {
        // a stale exit from a button that no longer owns the tooltip is a no-op
        if (!item || (_pending !== item && anchorItem !== item))
            return;
        dwellTimer.stop();
        _pending = null;
        if (!shown)
            return;
        handoverTimer.restart();
    }

    // hard close (island collapsed, drill view swapped): no warm window, so the
    // next tooltip has to earn its dwell again instead of flashing on entry
    function reset() {
        dwellTimer.stop();
        handoverTimer.stop();
        coolTimer.stop();
        _pending = null;
        _warm = false;
        shown = false;
        anchorItem = null;
    }

    function _commit() {
        dwellTimer.stop();
        handoverTimer.stop();
        coolTimer.stop();
        anchorItem = _pending;
        text = _pendingText;
        side = _pendingSide;
        shown = true;
        _warm = true;
    }

    Timer {
        id: dwellTimer
        interval: manager.dwell
        onTriggered: if (manager._pending) manager._commit()
    }
    // grace so leaving A and entering B reads as one continuous tooltip
    Timer {
        id: handoverTimer
        interval: manager.handover
        onTriggered: {
            manager.shown = false;
            coolTimer.restart();
        }
    }
    // the capsule has faded out — drop the anchor reference and go cold
    Timer {
        id: coolTimer
        interval: manager.warmWindow
        onTriggered: {
            manager._warm = false;
            manager.anchorItem = null;
        }
    }
}
