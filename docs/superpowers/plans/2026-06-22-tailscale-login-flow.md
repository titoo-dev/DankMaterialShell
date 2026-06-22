# Tailscale logged-out state + login flow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the island Tailscale panel is opened on a logged-out machine, show an actionable card ("Pas de compte actif" → Sign in → open browser / copy link) instead of an empty/broken view, by adding a `pkexec tailscale up` login flow to `TailscaleService`.

**Architecture:** `TailscaleService` gains a login API (`pkexec <tailscale> up`, auth-URL capture from output). `TailscalePanel` replaces its not-connected view with a state card driven by `statusKind` + the login state. No Go changes.

**Tech Stack:** QML (Quickshell), `Quickshell.Io` `Process`/`SplitParser`/`StdioCollector`, `pkexec` + DMS polkit agent.

## Global Constraints

- **No `console.*` in QML** — use the `Log` service.
- **`pkexec` sanitizes PATH** → resolve tailscale's absolute path before `pkexec <abs> up` (bare `pkexec tailscale up` fails on NixOS). Pattern: `["pkexec", _tsBin, "up"]`.
- **Process API:** `onExited: exitCode => {…}`; `stdout`/`stderr` take `SplitParser { splitMarker: "\n"; onRead }` or `StdioCollector { onStreamFinished }`.
- **No `qmllint`** → verify via the live working-tree shell journal + screenshots.
- **Widgets:** `DankButton { text; iconName; backgroundColor; textColor; clicked }`, `DankIcon`, `StyledText` (all `qs.Widgets`); spinner = `RotationAnimation on rotation { running; from:0; to:360; duration:1000; loops: Animation.Infinite }` on a `DankIcon`.
- This builds on the existing `TailscaleService.statusKind` (`"running" | "starting" | "stopped" | "needsLogin" | "needsAuth" | "error"`).

---

### Task 1: Login API on `TailscaleService.qml`

**Files:**
- Modify: `quickshell/Services/TailscaleService.qml` (add after the `needsAttention` derived prop / near the existing functions)

**Interfaces:**
- Consumes: existing `connected`, `statusKind`.
- Produces: `property string authUrl`, `property bool loginInProgress`, `property string loginError`, `function login()`, `function cancelLogin()`. Consumed by Task 2.

- [ ] **Step 1: Add login state + binary resolution + processes**

In `TailscaleService.qml`, after the `needsAttention` property block, add:

```qml
    // ---- login flow (pkexec tailscale up) ----
    property string authUrl: ""
    property bool loginInProgress: false
    property string loginError: ""
    property string _tsBin: "tailscale"   // pkexec sanitizes PATH → need an absolute path

    // resolve the tailscale binary's absolute path once
    Process {
        running: true
        command: ["sh", "-c", "command -v tailscale || echo tailscale"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = (text || "").trim()
                if (t.length > 0)
                    root._tsBin = t.split("\n")[0]
            }
        }
    }

    function login() {
        if (loginInProgress)
            return
        loginError = ""
        authUrl = ""
        loginInProgress = true
        loginProc.command = ["pkexec", root._tsBin, "up"]
        loginProc._lastErr = ""
        loginProc.running = true
    }

    function cancelLogin() {
        if (loginProc.running)
            loginProc.running = false
        loginInProgress = false
        authUrl = ""
    }

    Process {
        id: loginProc
        running: false
        property string _lastErr: ""
        function _scan(line) {
            if (!line || root.authUrl.length > 0)
                return
            let m = line.match(/https?:\/\/\S*login\.tailscale\.com\S*/)
            if (!m)
                m = line.match(/https?:\/\/\S+/)
            if (m)
                root.authUrl = m[0]
        }
        stdout: SplitParser { splitMarker: "\n"; onRead: data => loginProc._scan(data) }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                loginProc._scan(data)
                if (data && data.length > 0)
                    loginProc._lastErr = data
            }
        }
        onExited: exitCode => {
            root.loginInProgress = false
            if (exitCode === 0) {
                root.authUrl = ""        // authenticated; subscription flips `connected`
                root.loginError = ""
            } else if (exitCode === 126 || exitCode === 127) {
                root.loginError = I18n.tr("Login cancelled")
                root.authUrl = ""
            } else {
                root.loginError = loginProc._lastErr.length > 0 ? loginProc._lastErr : I18n.tr("Login failed")
            }
        }
    }

    // clear login state once we are connected
    onConnectedChanged: if (connected) {
        authUrl = ""
        loginInProgress = false
        loginError = ""
    }
```

- [ ] **Step 2: Verify it loads (journal clean)**

Run: `sleep 2 && journalctl --user -u dms.service --since "20 seconds ago" | grep -iE "TailscaleService|\.qml:[0-9]|error:|is not defined" | grep -v INFO | tail`
Expected: empty.

- [ ] **Step 3: Commit**

```bash
git add quickshell/Services/TailscaleService.qml
git commit -m "feat(tailscale): login flow — pkexec tailscale up + auth-URL capture"
```

---

### Task 2: Not-connected state card in `TailscalePanel.qml`

**Files:**
- Modify: `quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml`

**Interfaces:**
- Consumes: `TailscaleService.connected`, `statusKind`, `authUrl`, `loginInProgress`, `loginError`, `login()`.
- Produces: the state card; hides search/chips/list when not connected.

- [ ] **Step 1: Gate the existing status line + search + chips + list on `connected`**

Change the four `visible:` bindings:
- the status-line `StyledText` (currently always-on): set `visible: TailscaleService.connected`
- the `DankTextField` (search): `visible: TailscaleService.connected`
- the `DankFilterChips`: `visible: TailscaleService.connected`
- the peer-list `DankFlickable`: `visible: TailscaleService.connected`

(Replace each existing `visible: TailscaleService.available` with `visible: TailscaleService.connected`.)

- [ ] **Step 2: Add the state card after the header RowLayout**

Immediately after the header `RowLayout { … }` (the back/title/refresh row), add:

```qml
        // ---- not-connected state card (login / activate / errors) ----
        Column {
            width: parent.width
            spacing: Theme.spacingS
            visible: !TailscaleService.connected
            topPadding: Theme.spacingM

            DankIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: {
                    if (TailscaleService.authUrl.length > 0) return "open_in_browser"
                    const k = TailscaleService.statusKind
                    if (k === "needsLogin" || k === "needsAuth") return "person_off"
                    if (k === "stopped") return "cloud_off"
                    if (k === "starting") return "sync"
                    return "vpn_key_off"
                }
                size: 40
                color: Theme.surfaceVariantText
                RotationAnimation on rotation {
                    running: TailscaleService.statusKind === "starting" || (TailscaleService.loginInProgress && TailscaleService.authUrl.length === 0)
                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                }
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: tsCol.island.textColor
                wrapMode: Text.WordWrap
                text: {
                    if (TailscaleService.loginInProgress && TailscaleService.authUrl.length === 0) return I18n.tr("Connecting… approve in the dialog")
                    if (TailscaleService.authUrl.length > 0) return I18n.tr("Authenticate in your browser")
                    const k = TailscaleService.statusKind
                    if (k === "needsLogin" || k === "needsAuth") return I18n.tr("No active account")
                    if (k === "stopped") return I18n.tr("Tailscale is stopped")
                    if (k === "starting") return I18n.tr("Connecting…")
                    return I18n.tr("Tailscale unavailable")
                }
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: TailscaleService.loginError.length > 0
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                wrapMode: Text.WordWrap
                text: TailscaleService.loginError
            }

            // primary action: Sign in / Activate / Retry
            DankButton {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: TailscaleService.authUrl.length === 0
                    && TailscaleService.statusKind !== "starting"
                    && !(TailscaleService.loginInProgress && TailscaleService.authUrl.length === 0)
                iconName: "login"
                text: {
                    if (TailscaleService.loginError.length > 0) return I18n.tr("Retry")
                    if (TailscaleService.statusKind === "stopped") return I18n.tr("Activate")
                    return I18n.tr("Sign in")
                }
                onClicked: TailscaleService.login()
            }

            // auth-url actions: open browser / copy link
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingS
                visible: TailscaleService.authUrl.length > 0
                DankButton {
                    iconName: "open_in_new"
                    text: I18n.tr("Open browser")
                    onClicked: Quickshell.execDetached(["xdg-open", TailscaleService.authUrl])
                }
                DankButton {
                    iconName: "content_copy"
                    text: I18n.tr("Copy link")
                    backgroundColor: Theme.surfaceContainerHigh
                    onClicked: Quickshell.execDetached(["dms", "cl", "copy", TailscaleService.authUrl])
                }
            }
        }
```

- [ ] **Step 3: Verify panel renders (open it) + journal clean**

Run: `dms ipc call island close; sleep 1; dms ipc call island open tailscale; sleep 2; journalctl --user -u dms.service --since "15 seconds ago" | grep -iE "TailscalePanel|\.qml:[0-9]|error:|is not a function|is not defined" | grep -v INFO | tail`
Expected: `ISLAND_OPEN:tailscale`; grep empty. (Connected → still shows the peer list; the card is hidden.)

- [ ] **Step 4: Commit**

```bash
git add quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml
git commit -m "feat(island): Tailscale panel login/error state card for logged-out machines"
```

---

### Task 3: Verification

- [ ] **Step 1: Connected path unchanged**

Open the panel (connected): expect the normal status header + search + chips + peer list (no state card).

- [ ] **Step 2: Render the not-connected card without disturbing the live session**

Temporarily force the card by binding the card's `visible` to `true` OR temporarily edit `TailscalePanel` so `visible: !TailscaleService.connected` is `visible: true` for a screenshot — capture with `dms screenshot full` to confirm icon + "No active account" + "Sign in" render. Revert the temporary edit. (Do NOT actually log out the live session.)

- [ ] **Step 3: Copy-link path (stubbed)**

With a stubbed `authUrl` (temporarily set `authUrl: "https://login.tailscale.com/a/test"` default during the screenshot), click "Copy link" and verify `wl-paste` returns the URL. Revert.

- [ ] **Step 4: Real e2e (user, on a logged-out machine)**

On an actually logged-out machine: open the panel → "No active account" → "Sign in" → polkit password prompt → an auth URL appears → "Open browser" authenticates → panel flips to the peer list. (Cannot be done on the live always-connected host.)

- [ ] **Step 5: Final**

Run: `git status` → only unrelated `QuizDaemon.qml`/`QuizOverlay.qml` should be unstaged; all login-flow work committed.

---

## Self-Review

**Spec coverage:**
- Login API (`authUrl`/`loginInProgress`/`loginError`/`login()`/`cancelLogin()`, pkexec, abs-path, URL capture, exit-code handling, clear-on-connected) → Task 1 ✅
- State card (needsLogin/stopped/starting/error; Sign in/Activate/Retry; open-browser/copy-link; spinner) → Task 2 ✅
- Crash hardening (card replaces list when not connected → no null peer delegates) → Task 2 Step 1 ✅
- Testing → Task 3 ✅

**Placeholder scan:** none — all code is complete.

**Type consistency:** `authUrl`/`loginInProgress`/`loginError`/`login()` defined in Task 1 and used verbatim in Task 2. `statusKind` values match the existing service. `DankButton`/`DankIcon`/`StyledText` props match their widget definitions. `tsCol.island.textColor` — `tsCol` is the panel root id, `island` is its property (existing).
