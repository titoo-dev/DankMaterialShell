# Taildrop in the Dynamic Island — design

**Date:** 2026-06-22
**Status:** approved (design)
**Branch:** `feat/dynamic-island`

## Problem

The island can now monitor Tailscale (status, peers, exit node). The natural next
step — and the user's request — is **Taildrop**: transfer files over Tailscale,
"like the Shelf but for file transfer". Two directions:
- **Send** files to one of your own Tailscale devices.
- **Receive** files others send you, automatically.

Tailscale already exposes this via CLI: `tailscale file cp <files…> <target>:`
(send) and `tailscale file get [--loop] [--conflict=rename] <dir>` (receive). The
Go backend has no file/taildrop support (only `getStatus`/`refresh`), but the
codebase routinely shells out for peer actions (the Tailscale widget runs
`dms cl copy`, the Shelf and emoji picker shell out), so shelling out to
`tailscale file` is the consistent, low-risk path. No Go changes in v1.

## Prerequisite (one-time, user action)

`tailscale file cp/get` require **operator rights or root**. The user must run
once:

```
sudo tailscale set --operator=$USER
```

A desktop shell cannot sudo, so this is a setup step, not something the feature
performs. The service **detects** the access-denied error and surfaces a one-time
hint ("Taildrop: run `sudo tailscale set --operator=$USER`") instead of failing
silently. Decided by the user during brainstorming: bidirectional scope, and the
send UX is **drop-onto-the-device-card** in the Tailscale panel.

## Approach

A single `TaildropService` singleton that shells out to `tailscale file`,
consumed by:
- the Tailscale drill panel — peer cards become drop targets (send);
- the island controller — live-activity splashes for send/receive feedback.

*Alternative considered and rejected:* a Go backend `taildrop.*` command set with
transfer progress. More robust progress/error reporting, but a large lift; the
shell-out path delivers the full feature for v1 and a backend can replace it later
behind the same `TaildropService` interface.

## Components

### 1. `quickshell/Services/TaildropService.qml` (new singleton)

Encapsulates both directions and the operator state. Reads
`SettingsData.taildropReceive` / `taildropReceiveDir`; observes
`TailscaleService.connected`.

**Send:**
- `function send(paths, peer)` — runs `tailscale file cp <paths…> <ip>:` where
  `ip = peer.tailscaleIp`, via a `Process`. Tracks one in-flight transfer label
  (`<n> file(s) → <hostname>`).
- Signals: `sendStarted(string label, string peerHost)`,
  `sendFinished(string label, string peerHost, bool ok, string error)`.
- On stderr/exit indicating access-denied → set `needsOperatorSetup = true` and
  emit a finished(ok=false) with a setup-hint error.

**Receive (daemon):**
- A `Process` running
  `tailscale file get --loop --verbose --conflict=rename <dir>`, active while
  `SettingsData.taildropReceive && TailscaleService.connected && !needsOperatorSetup`.
- `mkdir -p <dir>` before launching.
- Parses stdout lines for written filenames → signal `received(string name)`.
- Restart-on-exit with a debounce timer (≥2s) so a failing command doesn't hot-loop;
  stops when disconnected or the toggle is off.
- Access-denied on launch → `needsOperatorSetup = true`, stop trying.

**State:** `property bool needsOperatorSetup`, `readonly property bool sending`.

### 2. `quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml`

Each peer card that is **online and owned by me** gets a `DropArea` accepting file
URLs:
- `onEntered`: accept only if `drag.hasUrls` and the peer is a valid send target;
  show a highlight + "Déposer pour envoyer" affordance.
- `onDropped`: map `drop.urls` (file:// only) to local paths and call
  `TaildropService.send(paths, modelData)`.
- Offline / non-owned peers are not drop targets (Taildrop only reaches your own
  devices).

### 3. `quickshell/Modules/DynamicIsland/DynamicIsland.qml`

- Hold a reference to `TaildropService` (a gated `Loader`/`Ref`-style instantiation
  so the singleton — and thus the receive daemon — is alive while the feature is
  usable: `TailscaleService.available`).
- `Connections { target: TaildropService }` → `pushActivity` splashes:
  - `onSendStarted` → `cloud_upload` "Envoi… <label>"
  - `onSendFinished` → ok: `cloud_done` "Envoyé ✓ → <peerHost>"; else `error`
    "Échec: <error>" (priority 2 for the operator-setup hint).
  - `onReceived` → `cloud_download` "📥 <name> reçu" (the CLI does not expose the
    sender, so only the filename is shown).

### 4. Settings (`SettingsData.qml` + `settings/SettingsSpec.js` + `Modules/Settings/DankBarTab.qml`)

- `property bool taildropReceive: true` — enables the receive daemon.
- `property string taildropReceiveDir: ""` — empty means resolve to
  `$XDG_DOWNLOAD_DIR` or `~/Downloads` at use time.
- A toggle ("Taildrop: recevoir les fichiers") + a directory field in the island
  settings section, consistent with the existing `dynamicIsland*` toggles. If
  `TaildropService.needsOperatorSetup`, show the one-time-setup hint text near the
  toggle.
- Send has no toggle (manual action); it is available whenever Tailscale is
  connected.

## Error handling & edge cases

- **Not operator** → one-time hint splash + settings note; no spam (gated by
  `needsOperatorSetup`).
- **Send to offline/non-owned peer** → blocked at the DropArea (not a target).
- **`cp` failure** (peer offline mid-send, rejected) → "Échec" splash with the
  trimmed last stderr line.
- **Receive daemon dies** → debounced restart while connected; full stop when
  disconnected or toggle off.
- **Name conflict on receive** → `--conflict=rename` (never overwrite).
- **Non-file drop** (text/link) onto a peer card → ignored (Taildrop is files only).
- **Multi-file drop** → one `cp` invocation with all paths.

## Testing & verification

- **Go:** none.
- **QML:** not unit-tested here → manual, after the user sets the operator:
  1. `tailscale file get <dir>` returns without "access denied" (operator OK).
  2. Receive: send a file from the phone (pixel-4a) to thorfinn via Taildrop →
     lands in the receive dir + "reçu" splash.
  3. Send: drop a file onto an online peer card → `cp` runs; with no online
     accepting peer, the failure path itself verifies error handling.
  4. Drop affordance highlights on drag-over; offline peers reject the drag.
  5. Toggle `taildropReceive` off → daemon stops; on → restarts.
- Verify via the live working-tree shell (journal scan for QML errors; see
  [[verifying-qml-changes-no-qmllint]] in project memory).

## Out of scope (v1)

- A Go backend `taildrop.*` command with transfer progress bars.
- Sending arbitrary text/links (files only).
- A send history / queue UI (single in-flight label is enough).
- Per-peer "this device can taildrop to me" capability checks beyond `myOnlinePeers`.
