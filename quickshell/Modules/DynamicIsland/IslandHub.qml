pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Single shared controller for all per-monitor DynamicIsland instances.
// Exposes an IPC target so a compositor keybind can drive the island:
//   dms ipc call island toggle            # expand/collapse the control center
//   dms ipc call island expand            # open (idempotent)
//   dms ipc call island close             # collapse no matter the current state
//   dms ipc call island back              # drill out one level (view -> hub -> closed)
//   dms ipc call island open apps         # open straight to a drill view (toggles)
// Hyprland bind examples (add to hyprland.conf / hyprland.lua):
//   bind = SUPER, I,         exec, dms ipc call island toggle
//   bind = SUPER SHIFT, I,   exec, dms ipc call island close
//   bind = SUPER ALT, Space, exec, dms ipc call island open apps
//   bind = SUPER ALT, V,     exec, dms ipc call island open clipboard
//   bind = SUPER ALT, M,     exec, dms ipc call island open monitor
Singleton {
    id: hub

    signal toggleRequested
    signal expandRequested
    signal closeRequested
    signal backRequested
    signal openViewRequested(string view)

    IpcHandler {
        target: "island"
        function toggle(): string {
            hub.toggleRequested();
            return "ISLAND_TOGGLE";
        }
        function expand(): string {
            hub.expandRequested();
            return "ISLAND_EXPAND";
        }
        // collapse the island regardless of which view it is showing
        function close(): string {
            hub.closeRequested();
            return "ISLAND_CLOSE";
        }
        // step back one level: a drill view returns to the hub, the hub closes
        function back(): string {
            hub.backRequested();
            return "ISLAND_BACK";
        }
        // open the expanded panel straight to a drill view (toggles it shut if
        // already showing): controls | wifi | bluetooth | audio | notifications |
        // calendar | monitor | wallpaper | apps | clipboard | power
        function open(view: string): string {
            hub.openViewRequested(view && view.length > 0 ? view : "controls");
            return "ISLAND_OPEN:" + view;
        }
    }
}
