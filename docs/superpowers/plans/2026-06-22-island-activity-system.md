# Generic Live-Activity System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An IPC-driven, multi-activity, updatable live-activity pill in the island (`dms ipc call island activity start id "Label"` → progress pill), the foundation for timer/calendar/screen-record activities.

**Architecture:** New `ActivityService` singleton holds the activity list + API; `IslandHub` exposes an `activity` IPC verb routing to it; `DynamicIsland` adds an `"activity"` rest mode (precedence over chip/compact), a new `ActivityPane` for the pill content, and an `ActivityPanel` drill view. Pure QML/shell — no Go.

**Tech Stack:** QML (Quickshell), `Quickshell.Io` IPC. Render with plain `Rectangle` progress bars (determinate + indeterminate), no media-specific widgets.

## Global Constraints

- **No `console.*` in QML** — use the `Log` service. (`Date.now()` IS allowed in QML runtime — `ShelfService` uses it.)
- **IPC missing trailing args arrive as `""`** (like `open`), so `activity stop id` works with a 3-arg `activity(action, id, arg)`.
- **No `qmllint`** → verify via the live working-tree shell journal + screenshots; this feature is fully driveable by IPC (no external device).
- **Singletons** in `qs.Services` auto-discovered by `pragma Singleton` + filename.
- Pane root mirrors `CompactPane`: a `Row` exposing `readonly property real contentWidth: implicitWidth`. Panel root mirrors `TailscalePanel`: a `Column` anchored top/left/right.
- Activity entry shape: `{ id, label, icon, progress, state, _expireAt }`, `progress` = `-1` (indeterminate) | `0..100`, `state` ∈ `"running"|"done"|"failed"`.

---

### Task 1: `ActivityService.qml`

**Files:**
- Create: `quickshell/Services/ActivityService.qml`

**Interfaces:**
- Produces: singleton `ActivityService` with `activities: var`, `runningCount: int`,
  `primary: var`, `start(id,label,icon)`, `progress(id,pct)`, `update(id,label)`,
  `done(id,label)`, `fail(id,label)`, `stop(id)`, signal `activityFinished(string id, bool ok)`.

- [ ] **Step 1: Create the service**

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

// Generic live-activity store: scriptable, multi-activity, updatable progress.
// Driven by IPC (see IslandHub.activity). Ephemeral — not persisted.
Singleton {
    id: root
    readonly property var log: Log.scoped("ActivityService")

    // each: { id, label, icon, progress (-1=indeterminate | 0..100), state, _expireAt }
    property var activities: []
    readonly property int runningCount: activities.filter(a => a.state === "running").length
    readonly property var primary: {
        const r = activities.filter(a => a.state === "running");
        if (r.length > 0)
            return r[0];
        return activities.length > 0 ? activities[0] : null;
    }
    signal activityFinished(string id, bool ok)

    function _find(id) {
        for (var i = 0; i < activities.length; i++)
            if (activities[i].id === id)
                return i;
        return -1;
    }

    function start(id, label, icon) {
        if (!id || id.length === 0)
            return;
        const arr = activities.slice();
        const i = _find(id);
        const entry = {
            id: id,
            label: (label && label.length > 0) ? label : id,
            icon: (icon && icon.length > 0) ? icon : "deployed_code",
            progress: i >= 0 ? arr[i].progress : -1,
            state: "running",
            _expireAt: Date.now() + 3600000
        };
        if (i >= 0)
            arr.splice(i, 1);
        arr.unshift(entry);
        activities = arr;
    }
    function progress(id, pct) {
        const i = _find(id);
        if (i < 0)
            return;
        const p = Math.round(pct);
        if (isNaN(p))
            return;
        const arr = activities.slice();
        arr[i] = Object.assign({}, arr[i], { progress: Math.max(0, Math.min(100, p)), _expireAt: Date.now() + 3600000 });
        activities = arr;
    }
    function update(id, label) {
        const i = _find(id);
        if (i < 0 || !label || label.length === 0)
            return;
        const arr = activities.slice();
        arr[i] = Object.assign({}, arr[i], { label: label, _expireAt: Date.now() + 3600000 });
        activities = arr;
    }
    function done(id, label) { _finish(id, label, "done", true); }
    function fail(id, label) { _finish(id, label, "failed", false); }
    function _finish(id, label, state, ok) {
        const i = _find(id);
        if (i < 0)
            return;
        const arr = activities.slice();
        const e = Object.assign({}, arr[i], { state: state, _expireAt: Date.now() + 3000 });
        if (label && label.length > 0)
            e.label = label;
        if (ok)
            e.progress = 100;
        arr[i] = e;
        activities = arr;
        activityFinished(id, ok);
    }
    function stop(id) {
        const i = _find(id);
        if (i < 0)
            return;
        const arr = activities.slice();
        arr.splice(i, 1);
        activities = arr;
    }

    // prune finished entries after their grace window, and running ghosts after the safety TTL
    Timer {
        interval: 1000
        repeat: true
        running: root.activities.length > 0
        onTriggered: {
            const now = Date.now();
            const arr = root.activities.filter(a => !(a._expireAt > 0 && now >= a._expireAt));
            if (arr.length !== root.activities.length)
                root.activities = arr;
        }
    }
}
```

- [ ] **Step 2: Verify journal clean (lazy — not instantiated yet)**

Run: `sleep 2 && journalctl --user -u dms.service --since "20 seconds ago" | grep -iE "ActivityService|\.qml:[0-9]|error:" | grep -v INFO | tail`
Expected: empty.

- [ ] **Step 3: Commit**

```bash
git add quickshell/Services/ActivityService.qml
git commit -m "feat(island): ActivityService — scriptable multi-activity store"
```

---

### Task 2: `IslandHub` — `activity` IPC + `activities` view

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/IslandHub.qml`

**Interfaces:**
- Consumes: `ActivityService` (Task 1).
- Produces: `dms ipc call island activity <action> <id> <arg>`; `"activities"` view.

- [ ] **Step 1: Add `"activities"` to the views list**

```qml
    readonly property var views: ["controls", "wifi", "bluetooth", "audio", "input", "notifications", "calendar", "monitor", "wallpaper", "apps", "clipboard", "emoji", "power", "mixer", "privacy", "shelf", "tailscale", "activities"]
```

- [ ] **Step 2: Add the `activity` IPC function**

Inside the `IpcHandler { target: "island" … }`, after the `shelf(...)` function, add:

```qml
        // generic live-activity control (see ActivityService):
        //   dms ipc call island activity start  <id> "<label>"
        //   dms ipc call island activity progress <id> <0-100>
        //   dms ipc call island activity update <id> "<label>"
        //   dms ipc call island activity done  <id> "<label?>"
        //   dms ipc call island activity fail  <id> "<label?>"
        //   dms ipc call island activity stop  <id>
        function activity(action: string, id: string, arg: string): string {
            if (!id || id.length === 0)
                return "ISLAND_ERROR:activity-needs-id";
            switch (action) {
            case "start":    ActivityService.start(id, arg, ""); break;
            case "progress": ActivityService.progress(id, parseInt(arg, 10)); break;
            case "update":   ActivityService.update(id, arg); break;
            case "done":     ActivityService.done(id, arg); break;
            case "fail":     ActivityService.fail(id, arg); break;
            case "stop":     ActivityService.stop(id); break;
            default:         return "ISLAND_ERROR:unknown-action:" + action + " (start|progress|update|done|fail|stop)";
            }
            return "ISLAND_ACTIVITY:" + action + ":" + id;
        }
```

Add `import qs.Services` at the top if not present (IslandHub already imports it).

- [ ] **Step 3: Verify + commit**

Run: `sleep 2 && journalctl --user -u dms.service --since "15 seconds ago" | grep -iE "IslandHub|\.qml:[0-9]|error:" | grep -v INFO | tail`
Expected: empty. Then `dms ipc call island activity start probe "x"` → returns `ISLAND_ACTIVITY:start:probe`; `dms ipc call island activity stop probe` → `ISLAND_ACTIVITY:stop:probe`.

```bash
git add quickshell/Modules/DynamicIsland/IslandHub.qml
git commit -m "feat(island): activity IPC verb + activities view"
```

---

### Task 3: `DynamicIsland` integration (rest mode, geometry, flash, click, pane host)

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/DynamicIsland.qml`

**Interfaces:**
- Consumes: `ActivityService` (Task 1), `ActivityPane` (Task 4).
- Produces: `"activity"` mode wired into geometry + rest logic.

- [ ] **Step 1: Activity-aware rest mode + re-settle on change**

Replace `function restMode() { return playing ? "chip" : "compact" }` with:

```qml
    function restMode() {
        if (ActivityService.activities.length > 0)
            return "activity"
        return playing ? "chip" : "compact"
    }
```

After the existing `onPlayingChanged: …` line, add a Connections so the island enters/leaves activity mode as the list changes, and flashes on completion:

```qml
    Connections {
        target: ActivityService
        function onActivitiesChanged() {
            if (!root.hovered && !root.pinned && root.mode !== "presenter" && root.mode !== "expanded")
                root.mode = root.restMode()
        }
        function onActivityFinished(id, ok) {
            if (root.ready && root.isFocusedScreen)
                edgeGlow.flash(ok ? Theme.success : Theme.error)
            root.bump()
        }
    }
```

- [ ] **Step 2: Geometry for `"activity"`**

In `pillW`'s switch, add before `default:`:

```qml
        case "activity":  return Math.max(220, Math.min(activityPane.contentWidth + Theme.spacingL * 2, screenW - 40))
```

In `pillH`'s switch, add before `default:`:

```qml
        case "activity":  return 40
```

In `pillRadius`, treat activity like chip (rounded): change to

```qml
    readonly property real pillRadius: (mode === "compact" || mode === "chip" || mode === "activity") ? 12 : 22
```

- [ ] **Step 3: Instantiate `ActivityPane` in the pill**

After the `MediaPane { id: mediaPane; island: root }` line, add:

```qml
            ActivityPane  { id: activityPane;   island: root }
```

- [ ] **Step 4: Click the activity pill → activities panel**

In the `bgClick` MouseArea `onClicked`, change the non-expanded branch so activity opens its panel. Replace:

```qml
                    if (root.mode === "expanded") {
                        root.pinned = false
                        root.settle()
                    } else {
                        root.mode = "expanded"
                    }
```
with:
```qml
                    if (root.mode === "expanded") {
                        root.pinned = false
                        root.settle()
                    } else if (root.mode === "activity") {
                        root.openPanel("activities")
                    } else {
                        root.mode = "expanded"
                    }
```

- [ ] **Step 5: Verify + commit**

Run: `sleep 2 && dms ipc call island activity start t1 "Building…"; sleep 1; journalctl --user -u dms.service --since "12 seconds ago" | grep -iE "DynamicIsland|ActivityPane|\.qml:[0-9]|error:|is not defined" | grep -v INFO | tail; dms ipc call island activity stop t1`
Expected: grep empty; while `t1` ran the pill showed the activity (verified visually in Task 6).

```bash
git add quickshell/Modules/DynamicIsland/DynamicIsland.qml
git commit -m "feat(island): activity rest mode + geometry + completion flash"
```

---

### Task 4: `ActivityPane.qml` (pill content)

**Files:**
- Create: `quickshell/Modules/DynamicIsland/panes/ActivityPane.qml`

**Interfaces:**
- Consumes: `ActivityService.primary`, `runningCount`; `island.mode`/colors.
- Produces: `contentWidth` read by `pillW` (Task 3).

- [ ] **Step 1: Create the pane**

```qml
import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// ACTIVITY (rest): the primary running activity — icon + label + progress + "+N".
Row {
    id: activityRow
    property var island: null
    readonly property var act: ActivityService.primary
    readonly property real contentWidth: implicitWidth
    anchors.centerIn: parent
    spacing: Theme.spacingS
    opacity: island.mode === "activity" ? 1 : 0
    visible: opacity > 0
    scale: island.mode === "activity" ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
    Behavior on scale { NumberAnimation { duration: Theme.mediumDuration } }

    DankIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: activityRow.act ? activityRow.act.icon : "deployed_code"
        size: 16
        color: {
            if (!activityRow.act) return island.subText
            if (activityRow.act.state === "done") return Theme.success
            if (activityRow.act.state === "failed") return Theme.error
            return island.accent
        }
        RotationAnimation on rotation {
            running: activityRow.act && activityRow.act.state === "running" && activityRow.act.progress < 0
            from: 0; to: 360; duration: 1400; loops: Animation.Infinite
        }
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: {
            if (!activityRow.act) return ""
            if (activityRow.act.state === "done") return "✓ " + activityRow.act.label
            if (activityRow.act.state === "failed") return "✗ " + activityRow.act.label
            return activityRow.act.label
        }
        color: island.textColor
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 200)
    }
    Item {  // progress: determinate fill OR indeterminate slider
        width: 48; height: 6
        anchors.verticalCenter: parent.verticalCenter
        visible: activityRow.act && activityRow.act.state === "running"
        Rectangle {
            anchors.fill: parent; radius: 3
            color: Qt.rgba(island.subText.r, island.subText.g, island.subText.b, 0.3)
        }
        Rectangle {
            visible: activityRow.act && activityRow.act.progress >= 0
            height: parent.height; radius: 3
            width: parent.width * ((activityRow.act ? Math.max(0, activityRow.act.progress) : 0) / 100)
            color: island.accent
            Behavior on width { NumberAnimation { duration: Theme.shortDuration } }
        }
        Rectangle {
            id: indeterminate
            visible: activityRow.act && activityRow.act.progress < 0
            height: parent.height; radius: 3; width: parent.width * 0.4
            color: island.accent
            SequentialAnimation on x {
                running: indeterminate.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: 28; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 28; to: 0; duration: 900; easing.type: Easing.InOutQuad }
            }
        }
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        visible: activityRow.act && activityRow.act.state === "running" && activityRow.act.progress >= 0
        text: (activityRow.act ? activityRow.act.progress : 0) + "%"
        color: island.subText
        font.pixelSize: Theme.fontSizeSmall
    }
    Rectangle {  // +N badge
        anchors.verticalCenter: parent.verticalCenter
        visible: ActivityService.runningCount > 1
        width: badgeText.implicitWidth + 10; height: 16; radius: 8
        color: Qt.rgba(island.accent.r, island.accent.g, island.accent.b, 0.2)
        StyledText {
            id: badgeText; anchors.centerIn: parent
            text: "+" + (ActivityService.runningCount - 1)
            color: island.accent; font.pixelSize: 10; font.bold: true
        }
    }
}
```

- [ ] **Step 2: Verify + commit** (this + Task 3 together make the pill render)

Run: `sleep 2 && dms ipc call island activity start t1 "Building…"; sleep 1; journalctl --user -u dms.service --since "10 seconds ago" | grep -iE "ActivityPane|\.qml:[0-9]|error:" | grep -v INFO | tail; dms ipc call island activity stop t1`
Expected: empty.

```bash
git add quickshell/Modules/DynamicIsland/panes/ActivityPane.qml
git commit -m "feat(island): ActivityPane — activity pill content (label + progress + badge)"
```

---

### Task 5: `ActivityPanel.qml` (drill view) + registry

**Files:**
- Create: `quickshell/Modules/DynamicIsland/panels/ActivityPanel.qml`
- Modify: `quickshell/Modules/DynamicIsland/ControlCenterPanel.qml`

**Interfaces:**
- Consumes: `ActivityService.activities`, `stop(id)`.
- Produces: `panelView === "activities"` view; registry key `"activities"`.

- [ ] **Step 1: Create the panel**

```qml
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Activities drill view: lists every live activity with progress + a dismiss button.
Column {
    id: actCol
    property var island: null
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    spacing: Theme.spacingS
    opacity: island.panelView === "activities" ? 1 : 0
    visible: opacity > 0
    transform: Translate { x: island.panelView === "activities" ? 0 : 24; Behavior on x { NumberAnimation { duration: Theme.shortDuration; easing.type: Easing.OutQuad } } }
    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

    RowLayout {
        width: parent.width
        spacing: Theme.spacingS
        DankActionButton {
            iconName: "chevron_left"; buttonSize: 30; iconSize: 20
            iconColor: actCol.island.textColor
            onClicked: actCol.island.panelView = "controls"
        }
        StyledText {
            text: I18n.tr("Activities")
            font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Bold
            color: actCol.island.textColor; Layout.fillWidth: true
        }
    }
    StyledText {
        width: parent.width
        visible: ActivityService.activities.length === 0
        horizontalAlignment: Text.AlignHCenter
        topPadding: Theme.spacingM; bottomPadding: Theme.spacingM
        text: I18n.tr("No activities")
        font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText
    }
    Repeater {
        model: ActivityService.activities
        delegate: Rectangle {
            required property var modelData
            width: parent.width
            height: aRow.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHighest
            RowLayout {
                id: aRow
                anchors.fill: parent; anchors.margins: Theme.spacingS; spacing: Theme.spacingS
                DankIcon {
                    name: modelData.state === "done" ? "check_circle" : modelData.state === "failed" ? "error" : modelData.icon
                    size: 18
                    color: modelData.state === "done" ? Theme.success : modelData.state === "failed" ? Theme.error : Theme.primary
                    Layout.alignment: Qt.AlignVCenter
                }
                Column {
                    Layout.fillWidth: true; spacing: 2
                    StyledText {
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold
                        color: Theme.surfaceText; width: parent.width; elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: modelData.state === "running" && modelData.progress >= 0
                        width: parent.width; height: 4; radius: 2
                        color: Qt.rgba(Theme.surfaceVariantText.r, Theme.surfaceVariantText.g, Theme.surfaceVariantText.b, 0.3)
                        Rectangle { height: parent.height; radius: 2; width: parent.width * (modelData.progress / 100); color: Theme.primary }
                    }
                    StyledText {
                        visible: modelData.state === "running" && modelData.progress < 0
                        text: I18n.tr("running…")
                        font.pixelSize: 10; color: Theme.surfaceVariantText
                    }
                }
                DankActionButton {
                    iconName: "close"; buttonSize: 20; iconSize: 12
                    iconColor: Theme.surfaceVariantText
                    onClicked: ActivityService.stop(modelData.id)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Register in ControlCenterPanel.qml**

Add to `viewRegistry` and a Component:

```qml
                    "tailscale": tsComp, "dropchoose": dropChooseComp,
                    "activities": activitiesComp
                })
```
and:
```qml
                Component { id: activitiesComp; ActivityPanel { island: ccPanel.island } }
```

- [ ] **Step 3: Verify (open panel) + commit**

Run: `dms ipc call island activity start t1 "Build…"; sleep 1; dms ipc call island open activities; sleep 2; journalctl --user -u dms.service --since "10 seconds ago" | grep -iE "ActivityPanel|\.qml:[0-9]|error:|is not a function" | grep -v INFO | tail; dms ipc call island activity stop t1`
Expected: `ISLAND_OPEN:activities`; grep empty; the panel lists "Build…".

```bash
git add quickshell/Modules/DynamicIsland/panels/ActivityPanel.qml quickshell/Modules/DynamicIsland/ControlCenterPanel.qml
git commit -m "feat(island): ActivityPanel drill view + registry"
```

---

### Task 6: End-to-end verification

- [ ] **Step 1: Lifecycle via IPC + screenshots**

```
dms ipc call island activity start t1 "Building…"      # → pill: spinner + Building…
dms ipc call island activity progress t1 50            # → bar at 50% + "50%"
dms ipc call island activity start t2 "Deploy…"        # → "+1" badge
dms ipc call island open activities                    # → panel lists both
dms ipc call island activity done t1 "Built ✓"         # → ✓ + green flash, auto-removes ~3s
dms ipc call island activity stop t2                   # → island returns to compact/chip
```
Screenshot after the `progress` and `start t2` steps (`dms screenshot full`) to confirm the pill + badge render.

- [ ] **Step 2: Error paths**

`dms ipc call island activity progress ghost 10` → `ISLAND_ACTIVITY:progress:ghost` but no entry created (ignored). `dms ipc call island activity bogus t1 x` → `ISLAND_ERROR:unknown-action:bogus …`.

- [ ] **Step 3: No QML errors + clean tree**

Run: `journalctl --user -u dms.service --since "3 minutes ago" | grep -iE "Activity|\.qml:[0-9]|TypeError|is not a function|is not defined" | grep -v INFO | tail; git status --short`
Expected: grep empty; tree clean (all committed).

---

## Self-Review

**Spec coverage:**
- ActivityService (state, API, primary/runningCount, prune timer, finished signal) → Task 1 ✅
- IPC verb + `activities` view → Task 2 ✅
- Rest-mode precedence + geometry + flash + click → Task 3 ✅
- ActivityPane (icon/label/determinate+indeterminate progress/badge) → Task 4 ✅
- ActivityPanel + registry → Task 5 ✅
- Edge cases: unknown id ignored (Task 1 `_find` guards), start-existing updates (Task 1), clamp/NaN (Task 1 `progress`), safety TTL prune (Task 1 Timer), ephemeral (no persistence) ✅
- Testing → Task 6 ✅

**Placeholder scan:** none — all code complete.

**Type consistency:** `start/progress/update/done/fail/stop`, `activities/runningCount/primary`, signal `activityFinished(id, ok)` defined in Task 1, used verbatim in Tasks 2-5. `activityPane.contentWidth` (Task 4) read by `pillW` (Task 3). `"activities"` view consistent across Tasks 2 (IslandHub) + 5 (registry). `ActivityPane`/`ActivityPanel` component names match their files. Entry fields (`id/label/icon/progress/state`) consistent across Service/Pane/Panel.
