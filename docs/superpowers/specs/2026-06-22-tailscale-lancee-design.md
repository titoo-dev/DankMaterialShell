# Tailscale "lancée" — exit-node selector + per-peer latency + send-to-default — design

**Date:** 2026-06-22
**Status:** approved (design)
**Branch:** `feat/dynamic-island`

## Problem

Three cohesive follow-ups to the Tailscale island integration:

1. **Exit-node selector** — route through / clear an exit node in one click from the
   panel (today the panel only *shows* the active exit node, read-only).
2. **Per-peer latency** — show RTT + route ("24 ms · direct" / "via relay") on each
   peer card.
3. **Send to a default device without opening the panel** — drop a file on the
   island and choose between the Shelf and Taildrop-to-default-device via a
   two-zone drop surface.

All shell out to the `tailscale` CLI; privileged actions use `pkexec` (the pattern
already added for the login flow). Exit-node *candidates* (`ExitNodeOption`) are
read QML-side from `tailscale status --json` (no root, no backend rebuild) — the Go
subscription does not carry that field and rebuilding the `dms` binary is out of
band, so reading it directly keeps the feature working immediately.

## Decisions (from brainstorming)

- One combined spec; each feature is an independent deliverable.
- Send-to-default UX = **two-zone drop surface** (Shelf | → <peer>) shown only when
  a default device is configured and online; otherwise the pill drop stays the
  Shelf, unchanged.
- The default device is chosen via a **star toggle on a peer card** (no dedicated
  settings UI).
- Latency is auto-pinged for `myOnlinePeers` on panel open (small set) + manual
  refresh; `tailscale ping` needs no root.
- Exit-node set/clear go through `pkexec`.

## Components

### 1. `quickshell/Services/TailscaleService.qml` — exit-node candidates (QML-side read)

`tailscale set --exit-node=<x>` only makes sense for peers that *offer* exit, and
the Go subscription doesn't carry `ExitNodeOption`. Read it directly:
- `property var exitNodeOfferIps: ({})` — set of Tailscale IPs that offer exit.
- `function refreshExitInfo()` — runs `["tailscale", "status", "--json"]` (no root),
  parses `.Peer[]` (and `.Self`), collecting `TailscaleIPs[0]` of every node where
  `ExitNodeOption === true` into `exitNodeOfferIps`. Called on panel open and after
  a set/clear.
- `readonly property var exitNodePeers: allPeersList.filter(p => exitNodeOfferIps[p.tailscaleIp])`
  — candidates, matched to the subscription's peer objects by IP.

(Optional future cleanup, out of scope: add `ExitNodeOption` to the Go `Peer` type
so it flows through the existing subscription instead of a separate status read.)

### 2. `quickshell/Services/TailscaleService.qml` — exit-node actions + latency

**Exit-node actions** (reuse `_tsBin` + pkexec from the login flow):
- `function setExitNode(peer)` → `["pkexec", _tsBin, "set", "--exit-node=" + (peer.tailscaleIp || peer.hostname)]`
- `function clearExitNode()` → `["pkexec", _tsBin, "set", "--exit-node="]`
- one shared `Process` (`exitNodeProc`); on non-zero exit (≠126/127 cancel) set a
  transient `exitNodeError`; on success call `refreshExitInfo()` and `getStatus()`.

**Per-peer latency:**
- `property var pings: ({})` — map `ip -> { ms: int, route: "direct"|"relay", at: epoch }`.
- `function pingPeer(ip)` — runs `["tailscale", "ping", "--c", "1", "--timeout", "5s", ip]`
  via a small pool of `Process`es (or sequential queue to bound concurrency).
  Parse the pong line: RTT from `/in ([0-9.]+)ms/`; route = `relay` if the line
  contains `DERP`/`via DERP`, else `direct`; no match / timeout → record a "—" entry.
  Emit a change so cards re-render.
- `function pingMyOnline()` — ping every `myOnlinePeers` IP (bounded). Called by the
  panel on open + on refresh.

**Default Taildrop device:**
- resolved from `SettingsData.taildropDefaultPeer` (a hostname). Helper
  `readonly property var defaultPeer:` = the matching peer object (or null), and
  `readonly property bool defaultPeerOnline:` = `defaultPeer && defaultPeer.online`.

### 3. `quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml`

- **Exit-node section** (between the status line and the search, visible when
  `connected && (exitNodePeers.length > 0 || usingExitNode)`): a header
  "Sortie : via <name> 🌐" with a **[Couper]** button when `usingExitNode`; a list
  of `exitNodePeers` each with **[Utiliser]** (the active one shown as **Actif**).
  Buttons call `setExitNode`/`clearExitNode` → pkexec prompt.
- **Per-card latency pill**: a small text on each peer card showing
  `pings[ip]` → "24 ms · direct" / "via relais" / "…" (pending) / "—" (failed).
- **Star toggle** on each owned peer card: filled when
  `modelData.hostname === SettingsData.taildropDefaultPeer`; click toggles
  `taildropDefaultPeer` (set to this hostname, or clear if already default).
- On `tsActive` becoming true, call `TailscaleService.pingMyOnline()`; the refresh
  button also re-pings.

### 4. `quickshell/Modules/DynamicIsland/DynamicIsland.qml` — two-zone drop surface

When a file drag enters the island **and** `TailscaleService.defaultPeerOnline`,
open a two-zone drop surface instead of the plain shelf:
- implemented as a dedicated drill view `panelView === "dropchoose"` (opened from the
  pill `DropArea.onEntered` when a default peer is online; otherwise it opens the
  shelf as today).
- the view has two side-by-side `DropArea`s:
  - left "📥 Shelf" → `ShelfService.addUrls(drop.urls)` (+ text fallback).
  - right "→ <peer>" → map file URLs to paths → `TaildropService.send(paths, defaultPeer)`.
- drag leaves without dropping → revert to the previous rest state (same as the
  shelf auto-open revert via `_shelfAutoOpened`).
- when no default peer is online, the existing single-shelf drop path is unchanged.

### 5. Settings

- `SettingsData.qml`: `property string taildropDefaultPeer: ""`.
- `settings/SettingsSpec.js`: `taildropDefaultPeer: { def: "" }`.
- No settings-tab UI (the star toggle in the panel sets it).

## Error handling & edge cases

- **Exit-node:** pkexec cancelled (126/127) → no-op, no error pop; other failure →
  `exitNodeError` → a brief island pop. Setting an exit node on a peer that stopped
  offering it → tailscale errors → surfaced via `exitNodeError`.
- **Latency:** offline/unreachable/timeout → "—"; first ping may traverse via relay
  before NAT punch — we show the *actual* route, which is honest. Bound concurrent
  pings (queue) so a big tailnet doesn't spawn dozens of processes.
- **Default device:** if the starred device is later removed/renamed, `defaultPeer`
  resolves null → the right drop zone simply doesn't appear.
- **Drop surface:** non-file payloads (text/links) → only the Shelf zone accepts
  them; the Taildrop zone accepts file URLs only.

## Testing & verification

- **Go:** none (exit-node candidates read QML-side via `tailscale status --json`).
- **QML:** not unit-tested → manual:
  1. Loads with no QML errors (journal scan).
  2. Exit-node section + latency pills + star render (force-show via temp edit +
     screenshot, then revert) — same technique used for the login card.
  3. `tailscale status --json` parse works (the candidate list populates if any peer
     offers exit; on this tailnet none may, so the section stays hidden — verify the
     parse runs without error).
  4. Real e2e (user, needs a second online device / an exit-node offerer):
     set/clear an exit node (pkexec prompt → status flips), ping shows an RTT,
     star a device then drag a file onto the island → two zones → right zone sends.
- Verify via the live working-tree shell ([[verifying-qml-changes-no-qmllint]]).

## Out of scope (v1)

- `--advertise-exit-node` (making *this* machine an exit node).
- `--exit-node-allow-lan-access` toggle.
- Continuous/auto latency refresh (ping on open + manual only).
- A settings-tab UI for the default device (star toggle only).
- Per-peer Taildrop history / multiple default devices.
