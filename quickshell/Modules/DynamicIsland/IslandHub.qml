pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Single shared controller for all per-monitor DynamicIsland instances.
// Exposes an IPC target so a compositor keybind can toggle the island:
//   dms ipc call island toggle
// Hyprland bind example (add to hyprland.conf):
//   bind = SUPER, I, exec, dms ipc call island toggle
Singleton {
    id: hub

    signal toggleRequested
    signal expandRequested

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
    }
}
