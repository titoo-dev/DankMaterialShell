pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Single shared controller for all per-monitor DynamicIsland instances.
// Exposes an IPC target so a compositor keybind can drive the island:
//   dms ipc call island toggle            # expand/collapse the control center
//   dms ipc call island open apps         # open straight to a drill view (toggles)
// Hyprland bind examples (add to hyprland.conf):
//   bind = SUPER, I,     exec, dms ipc call island toggle
//   bind = SUPER, Space, exec, dms ipc call island open apps
//   bind = SUPER, V,     exec, dms ipc call island open clipboard
Singleton {
    id: hub

    signal toggleRequested
    signal expandRequested
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
        // open the expanded panel straight to a drill view (toggles it shut if
        // already showing): controls | wifi | bluetooth | audio | notifications |
        // calendar | apps | clipboard
        function open(view: string): string {
            hub.openViewRequested(view && view.length > 0 ? view : "controls");
            return "ISLAND_OPEN:" + view;
        }
    }
}
