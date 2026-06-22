# Taildrop in the Dynamic Island — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Taildrop to the island — drop a file onto a Tailscale peer card to send it, and auto-receive incoming files into a folder with a live-activity pop — by shelling out to `tailscale file`.

**Architecture:** A new `TaildropService` singleton wraps `tailscale file cp` (send) and a polling `tailscale file get` (receive). The Tailscale drill panel's peer cards become drop targets; the island controller turns the service's signals into splashes. No Go changes.

**Tech Stack:** QML (Quickshell), `Quickshell.Io` `Process`/`SplitParser`, `QtCore` `StandardPaths`. Backend = the `tailscale` CLI.

## Global Constraints

- **No `console.*` in QML** — pre-commit hook rejects it; use the `Log` service (`root.log.debug(...)`).
- **Operator prerequisite:** `tailscale file cp/get` need operator rights. The user must run `sudo tailscale set --operator=$USER` once. The service detects the access-denied error (`needsOperatorSetup`) and degrades gracefully — it must never crash or spam.
- **Settings live in three synced places:** the property in `quickshell/Common/SettingsData.qml`, the spec in `quickshell/Common/settings/SettingsSpec.js`, the UI in `quickshell/Modules/Settings/DankBarTab.qml`. Write with `SettingsData.set("key", value)`.
- **Quickshell singletons** in `qs.Services` are auto-discovered by `pragma Singleton` + filename — no qmldir registration.
- **Process API:** `onExited: exitCode => {…}`; `stderr: SplitParser { splitMarker: "\n"; onRead: data => {…} }`; bind `running` to a condition or set it `true` to launch.
- **No `qmllint`** on this host → verify via the live working-tree shell's journal (`journalctl --user -u dms.service`) + screenshots. Working-tree override must be active (already enabled this session).
- **Send targets** are restricted to `TailscaleService.myOnlinePeers` (Taildrop only reaches your own online devices); peer addressed by `peer.tailscaleIp`.

---

### Task 0: Operator prerequisite (verification gate)

Not a code change. Taildrop cannot work until the operator is set.

- [ ] **Step 1: User sets operator (one-time)**

The user runs (in their session, `!`-prefixed): `sudo tailscale set --operator=$USER`

- [ ] **Step 2: Verify file ops no longer need root**

Run: `tailscale file get /tmp 2>&1 | head -1`
Expected: NOT "Access denied: file access denied". (Empty inbox prints a "WaitingFiles"/no-files line or nothing — both fine.) If still access-denied, the operator step didn't take; stop and re-run Step 1.

---

### Task 1: `TaildropService.qml`

**Files:**
- Create: `quickshell/Services/TaildropService.qml`

**Interfaces:**
- Consumes: `SettingsData.taildropReceive`, `SettingsData.taildropReceiveDir` (Task 2), `TailscaleService.connected`, `Paths.strip`, `StandardPaths`.
- Produces: singleton `TaildropService` with `function send(paths, peer)`, properties `needsOperatorSetup: bool`, `sending: bool`, `receiveDir: string`, signals `sendStarted(string label, string peerHost)`, `sendFinished(string label, string peerHost, bool ok, string error)`, `received(string name)`. Consumed by Tasks 3 and 4.

- [ ] **Step 1: Create the service**

Create `quickshell/Services/TaildropService.qml`:

```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

// Taildrop over Tailscale: send files to a peer (`tailscale file cp`) and
// auto-receive incoming files (`tailscale file get`, polled into a dedicated
// folder). Shell-out only; no Go backend changes. Requires the user to have run
// `sudo tailscale set --operator=$USER` once (else file ops are root-only).
Singleton {
    id: root
    readonly property var log: Log.scoped("TaildropService")

    // dedicated receive folder (avoids mistaking unrelated downloads for receipts)
    readonly property string receiveDir: {
        const cfg = SettingsData.taildropReceiveDir
        if (cfg && cfg.length > 0)
            return cfg
        return Paths.strip(StandardPaths.writableLocation(StandardPaths.DownloadLocation)) + "/Taildrop"
    }

    property bool needsOperatorSetup: false
    property bool sending: false

    signal sendStarted(string label, string peerHost)
    signal sendFinished(string label, string peerHost, bool ok, string error)
    signal received(string name)

    function _basename(p) {
        const s = String(p)
        return s.substring(s.lastIndexOf("/") + 1) || s
    }

    // ---- SEND: tailscale file cp <paths...> <ip>: ----
    function send(paths, peer) {
        if (!paths || paths.length === 0 || !peer)
            return
        const ip = peer.tailscaleIp || ""
        if (ip.length === 0)
            return
        const host = peer.hostname || ip
        const label = paths.length === 1 ? _basename(paths[0]) : (paths.length + " " + I18n.tr("files"))
        sendProc._label = label
        sendProc._host = host
        sendProc._err = ""
        sendProc.command = ["tailscale", "file", "cp"].concat(paths).concat([ip + ":"])
        root.sending = true
        root.sendStarted(label, host)
        sendProc.running = true
    }

    Process {
        id: sendProc
        property string _label: ""
        property string _host: ""
        property string _err: ""
        running: false
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => { if (data && data.length > 0) sendProc._err = data }
        }
        onExited: exitCode => {
            root.sending = false
            const ok = exitCode === 0
            if (!ok && /access denied|--operator/i.test(sendProc._err))
                root.needsOperatorSetup = true
            root.sendFinished(sendProc._label, sendProc._host, ok, sendProc._err)
        }
    }

    // ---- RECEIVE: poll `tailscale file get` into receiveDir, diff for new files ----
    property var _seen: ({})
    property bool _seeded: false

    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: SettingsData.taildropReceive && TailscaleService.connected && !root.needsOperatorSetup
        onRunningChanged: if (!running) root._seeded = false   // re-seed next time we start
        onTriggered: if (!getProc.running) getProc.running = true
    }

    Process {
        id: getProc
        running: false
        property var _lines: []
        command: ["sh", "-c",
            'd="$1"; mkdir -p "$d"; out=$(tailscale file get --conflict=rename "$d" 2>&1); echo "GET:$?:$out"; ls -1 "$d"',
            "_", root.receiveDir]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => getProc._lines.push(data)
        }
        onExited: exitCode => {
            const lines = getProc._lines
            getProc._lines = []
            if (lines.length === 0)
                return
            const head = lines[0] || ""
            if (/access denied|--operator/i.test(head)) {
                root.needsOperatorSetup = true
                return
            }
            const listing = lines.slice(1).filter(s => s && s.length > 0)
            if (!root._seeded) {
                const seed = {}
                for (const f of listing)
                    seed[f] = true
                root._seen = seed
                root._seeded = true
                return
            }
            const next = {}
            const fresh = []
            for (const f of listing) {
                next[f] = true
                if (!root._seen[f])
                    fresh.push(f)
            }
            root._seen = next
            for (const f of fresh)
                root.received(f)
        }
    }
}
```

- [ ] **Step 2: Verify it loads (journal clean)**

Run: `sleep 2 && journalctl --user -u dms.service --since "20 seconds ago" | grep -iE "TaildropService|\.qml:[0-9]|error:|is not defined" | tail`
Expected: empty (the singleton is lazy; it won't fully run until referenced in Task 3, but it must parse).

- [ ] **Step 3: Commit**

```bash
git add quickshell/Services/TaildropService.qml
git commit -m "feat(taildrop): TaildropService — send via file cp, receive via polled file get"
```

---

### Task 2: Settings (`SettingsData.qml`, `SettingsSpec.js`, `DankBarTab.qml`)

**Files:**
- Modify: `quickshell/Common/SettingsData.qml` (after `dynamicIslandTailscale`)
- Modify: `quickshell/Common/settings/SettingsSpec.js` (after `dynamicIslandTailscale`)
- Modify: `quickshell/Modules/Settings/DankBarTab.qml` (after the "Tailscale status" toggle)

**Interfaces:**
- Produces: `SettingsData.taildropReceive: bool` (default `true`), `SettingsData.taildropReceiveDir: string` (default `""`).

- [ ] **Step 1: Add properties in SettingsData.qml**

After `property bool dynamicIslandTailscale: true`, add:

```qml
    property bool taildropReceive: true
    property string taildropReceiveDir: ""
```

- [ ] **Step 2: Add spec entries in SettingsSpec.js**

After `dynamicIslandTailscale: { def: true },`, add:

```js
    taildropReceive: { def: true },
    taildropReceiveDir: { def: "" },
```

- [ ] **Step 3: Add settings UI in DankBarTab.qml**

After the "Tailscale status" `DankToggle { ... }` block, add (DankToggle + a dir field):

```qml
                DankToggle {
                    width: parent.width
                    text: I18n.tr("Taildrop: receive files")
                    description: I18n.tr("Automatically receive files sent to this machine over Tailscale into the folder below, with a pop in the island. Requires running `sudo tailscale set --operator=$USER` once.")
                    enabled: SettingsData.dynamicIslandEnabled
                    checked: SettingsData.taildropReceive
                    onToggled: SettingsData.set("taildropReceive", checked)
                }

                DankTextField {
                    width: parent.width
                    enabled: SettingsData.dynamicIslandEnabled && SettingsData.taildropReceive
                    placeholderText: "~/Downloads/Taildrop"
                    text: SettingsData.taildropReceiveDir
                    onEditingFinished: SettingsData.set("taildropReceiveDir", text)
                }
```

- [ ] **Step 4: Verify journal clean + commit**

Run: `sleep 2 && journalctl --user -u dms.service --since "20 seconds ago" | grep -iE "DankBarTab|\.qml:[0-9]|error:|DankTextField" | tail`
Expected: empty.

```bash
git add quickshell/Common/SettingsData.qml quickshell/Common/settings/SettingsSpec.js quickshell/Modules/Settings/DankBarTab.qml
git commit -m "feat(taildrop): settings — receive toggle + receive dir"
```

---

### Task 3: Island reference + splashes (`DynamicIsland.qml`)

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/DynamicIsland.qml` (add `Connections` near the existing Tailscale `Connections`, ~after the peer-online block)

**Interfaces:**
- Consumes: `TaildropService` signals (Task 1), existing `pushActivity(icon, label, opts)`.
- Produces: splash side effects; referencing `TaildropService` instantiates the singleton so its receive timer runs.

- [ ] **Step 1: Add the Connections block**

After the Tailscale peer-online `Connections` block (the one with `onMyOnlinePeersChanged`), add:

```qml
    // Live Activity: Taildrop send/receive feedback. Referencing TaildropService
    // here also instantiates the singleton, so its receive poller runs.
    Connections {
        target: TaildropService
        function onSendStarted(label, peerHost) {
            root.pushActivity("cloud_upload", I18n.tr("Sending") + " " + label + " → " + peerHost)
        }
        function onSendFinished(label, peerHost, ok, error) {
            if (ok) {
                root.pushActivity("cloud_done", I18n.tr("Sent") + " ✓ → " + peerHost)
            } else if (TaildropService.needsOperatorSetup) {
                root.pushActivity("warning", I18n.tr("Taildrop: run sudo tailscale set --operator=$USER"), { priority: 2, duration: 5000 })
            } else {
                root.pushActivity("error", I18n.tr("Send failed") + ": " + (error || peerHost), { priority: 2 })
            }
        }
        function onReceived(name) {
            root.pushActivity("cloud_download", "📥 " + name)
        }
    }
```

- [ ] **Step 2: Verify journal clean + commit**

Run: `sleep 2 && journalctl --user -u dms.service --since "20 seconds ago" | grep -iE "DynamicIsland|\.qml:[0-9]|error:|TaildropService" | tail`
Expected: empty (and the receive poller is now active when connected — you may see `tailscale file get` running every 5s; that's expected).

```bash
git add quickshell/Modules/DynamicIsland/DynamicIsland.qml
git commit -m "feat(taildrop): island splashes for send/receive + instantiate service"
```

---

### Task 4: Drop-onto-peer in `TailscalePanel.qml`

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml` (the peer-card delegate)

**Interfaces:**
- Consumes: `TaildropService.send(paths, peer)` (Task 1), the delegate's `modelData` (a peer).
- Produces: a per-card `DropArea` + hover affordance.

- [ ] **Step 1: Add a DropArea + affordance to the peer card delegate**

In the peer-card `delegate: Rectangle { ... }`, add — as children of that Rectangle, after the existing `RowLayout { id: peerRow ... }`:

```qml
                    // Taildrop: drop files here to send to this device (online, owned only)
                    readonly property bool canReceiveDrop: modelData.online && TailscaleService.isMine(modelData) && (modelData.tailscaleIp || "").length > 0
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        visible: tsDrop.containsDrag && parent.canReceiveDrop
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                        border.width: 1
                        border.color: Theme.primary
                        StyledText {
                            anchors.centerIn: parent
                            text: I18n.tr("Drop to send")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                        }
                    }
                    DropArea {
                        id: tsDrop
                        anchors.fill: parent
                        onEntered: drag => {
                            if (!parent.canReceiveDrop || !drag.hasUrls) {
                                drag.accepted = false
                                return
                            }
                        }
                        onDropped: drop => {
                            if (!parent.canReceiveDrop || !drop.hasUrls)
                                return
                            const paths = []
                            for (var i = 0; i < drop.urls.length; i++) {
                                const u = String(drop.urls[i])
                                if (u.startsWith("file://"))
                                    paths.push(decodeURIComponent(u.substring(7)))
                            }
                            if (paths.length > 0) {
                                TaildropService.send(paths, modelData)
                                drop.accept(Qt.CopyAction)
                            }
                        }
                    }
```

- [ ] **Step 2: Verify the panel still instantiates (open it) + journal clean**

Run: `dms ipc call island close; sleep 1; dms ipc call island open tailscale; sleep 2; journalctl --user -u dms.service --since "15 seconds ago" | grep -iE "TailscalePanel|\.qml:[0-9]|error:|is not a function" | tail`
Expected: `ISLAND_OPEN:tailscale` printed, journal grep empty.

- [ ] **Step 3: Commit**

```bash
git add quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml
git commit -m "feat(taildrop): drop files onto a peer card to send via Taildrop"
```

---

### Task 5: Runtime verification

Prerequisite: Task 0 done (operator set). Working tree live.

- [ ] **Step 1: Receive folder + poller**

Run: `journalctl --user -u dms.service --since "1 minute ago" | grep -i "file get" | tail` (optional) and `ls -la ~/Downloads/Taildrop`
Expected: the `~/Downloads/Taildrop` folder exists (the poller `mkdir -p`s it once running while Tailscale is connected).

- [ ] **Step 2: Receive a file (needs a second device)**

From the phone (pixel-4a) or another device, Taildrop a file to `thorfinn`.
Expected within ~5s: the file appears in `~/Downloads/Taildrop` and a "📥 \<name\>" pop shows in the island.

- [ ] **Step 3: Send via drop**

Open the Tailscale panel (SUPER+ALT+T), drag a file from a file manager over an **online** peer card → it highlights "Drop to send"; release → a "Sending … → \<host\>" pop, then "Sent ✓" or "Send failed" (failure is expected if no online peer accepts — it still verifies the path). Offline peer cards must NOT highlight.

- [ ] **Step 4: Operator-missing path (only if not yet set)**

If `needsOperatorSetup` triggers, a single "run sudo tailscale set --operator=$USER" pop appears and the receive poller stops — no spam.

- [ ] **Step 5: Toggle**

Settings → DankBar/Island → "Taildrop: receive files" off → poller stops (no more `tailscale file get`); on → resumes.

- [ ] **Step 6: Final**

Run: `git status` → only the unrelated `QuizDaemon.qml` change should remain unstaged; all Taildrop work committed.

---

## Self-Review

**Spec coverage:**
- Prerequisite/operator detection → Task 0 + `needsOperatorSetup` in Tasks 1/3 ✅
- TaildropService send → Task 1 ✅; receive (polled, dedicated dir, dir-diff, seed) → Task 1 ✅
- Peer-card drop targets (online+owned only) → Task 4 ✅
- Island splashes (send started/finished, received) + singleton instantiation → Task 3 ✅
- Settings (taildropReceive + taildropReceiveDir, dedicated `~/Downloads/Taildrop` default) → Task 2 ✅
- Error/edge cases: offline/non-owned blocked (Task 4 `canReceiveDrop`); cp failure splash (Task 3); operator hint once (`needsOperatorSetup` gates Timer + send); conflict=rename (Task 1); non-file drop ignored (Task 4 filters `file://`); multi-file one cp (Task 1 concat) ✅
- Testing → Task 5 ✅

**Placeholder scan:** none — every code step is complete.

**Type consistency:** `send(paths, peer)`, `needsOperatorSetup`, `sending`, `receiveDir`, signals `sendStarted(label, peerHost)`/`sendFinished(label, peerHost, ok, error)`/`received(name)` defined in Task 1 and used verbatim in Tasks 3-4. `TailscaleService.isMine(modelData)` is an existing method (TailscaleService.qml). Settings keys `taildropReceive`/`taildropReceiveDir` consistent across Tasks 1-2.
