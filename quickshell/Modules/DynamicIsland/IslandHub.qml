pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

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

    // single source of truth for the drill views reachable over IPC
    readonly property var views: ["controls", "wifi", "bluetooth", "audio", "input", "notifications", "calendar", "monitor", "wallpaper", "apps", "clipboard", "emoji", "power", "mixer", "privacy", "shelf", "tailscale"]

    signal toggleRequested
    signal expandRequested
    signal closeRequested
    signal backRequested
    signal openViewRequested(string view)
    signal typeRequested(string text)

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
        // already showing); unknown views are rejected instead of opening an
        // empty island
        function open(view: string): string {
            const v = (view && view.length > 0) ? view : "controls";
            if (hub.views.indexOf(v) === -1)
                return "ISLAND_ERROR:unknown-view:" + v + " (valid: " + hub.views.join("|") + ")";
            hub.openViewRequested(v);
            return "ISLAND_OPEN:" + v;
        }
        // inject text into the focused app through the same path the emoji
        // picker uses (wtype / clipboard) — also handy for scripting
        function type(text: string): string {
            if (!text || text.length === 0)
                return "ISLAND_ERROR:empty-text";
            hub.typeRequested(text);
            return "ISLAND_TYPE:" + text;
        }
        // park a file/dir on the Shelf from the CLI / a file-manager action:
        //   dms ipc call island shelf /path/to/file
        function shelf(path: string): string {
            if (!path || !path.startsWith("/"))
                return "ISLAND_ERROR:absolute-path-required";
            ShelfService.addPath(path);
            return "ISLAND_SHELF:" + path;
        }
    }
}
