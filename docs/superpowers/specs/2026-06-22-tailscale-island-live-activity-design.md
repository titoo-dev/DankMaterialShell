# Tailscale live activity in the Dynamic Island — design

**Date:** 2026-06-22
**Status:** approved (design)
**Branch:** `feat/dynamic-island`

## Problem

Tailscale is installed and running on this machine, but the Dynamic Island shows
nothing about it. The shell *does* know about Tailscale — `TailscaleService` is a
complete singleton fed by the Go `DMSService` backend, and it is already surfaced
in the **Control Center** (`TailscaleWidget`: peer list, search, filters, copy-IP).
The **Dynamic Island has zero Tailscale presence**. (The island's idle-row
`vpn_lock` icon is driven by `NetworkService.vpnConnected` — NetworkManager VPN
profiles — which is unrelated to Tailscale's TUN, so it never lights up for it.)

Goal: give Tailscale a first-class "live activity" presence in the island — a
persistent at-rest indicator, transient splashes on state changes, a warning
satellite when something is wrong, and a drill-in detail panel.

## Approach

**Direct wiring into the island's existing live-activity primitives** — Tailscale
becomes an ongoing activity using exactly the patterns Bluetooth / privacy /
charging already use. No new framework.

The island already provides everything needed:
- `pushActivity(icon, label, opts)` — priority splash queue (presenter mode).
- the **satellite bubble** — a persistent detached circle for an ongoing state
  (`satKind`/`satIcon`/`satColor`), shown while the pill is compact/chip.
- idle-row **mini-indicators** (`IdlePane.qml` `rightCluster`).
- drill-in **panels** (`panels/*.qml`) routed via `panelView` + `openPanel(view)`.

*Alternative considered and rejected:* a generic "service-activity registry"
(declarative registration for any service). Over-engineering for v1 — the island
already has the primitives and there is effectively one consumer. Can be extracted
later if a second service wants the same treatment.

## Decisions (locked)

- **Scope:** full integration — indicator + splashes + satellite + drill panel.
- **Splash triggers:** connect/disconnect, exit-node on/off, backend error/down
  (high priority), and *my* peer comes online (noise-tamed).
- **Exit node:** track + show, read-only (no connect/clear actions in v1).
- **NM `vpn_lock` indicator:** kept as-is; Tailscale gets its own separate glyph.
- **"This machine is an exit node" (advertising):** out of v1 (optional Go change).

## Components

### 1. Service layer — extend `quickshell/Services/TailscaleService.qml`

Add read-only derived properties. **No Go backend change needed for v1** — the
per-peer `exitNode` flag already arrives in the payload (`client.go` maps
`ps.ExitNode`).

- `readonly property var activeExitNode: allPeersList.find(p => p.exitNode) || null`
- `readonly property bool usingExitNode: !!activeExitNode`
- `readonly property string exitNodeName: activeExitNode ? (activeExitNode.hostname || "") : ""`
- `readonly property string statusKind:` derived from `backendState`:
  - `"Running"` → `"running"`
  - `"Starting"` / `"NoState"` → `"starting"`
  - `"Stopped"` → `"stopped"`
  - `"NeedsLogin"` → `"needsLogin"`
  - `"NeedsMachineAuth"` → `"needsAuth"`
  - anything else (e.g. `"Unreachable"`) → `"error"`
- `readonly property bool needsAttention:`
  `available && ((statusKind !== "running" && statusKind !== "starting") || (connected && onlinePeerCount === 0))`
  — covers down / login / auth / unreachable states and the "connected but isolated" case.

Ref-counting is unchanged: the island holds a `Ref` (see §2) so the Go
subscription stays live while the feature is shown.

*Optional stretch (not v1):* map `ExitNodeOption` on `Self` in `core/.../client.go`
+ `types.go` to expose `isExitNode` ("this machine advertises as an exit node").

### 2. Island controller — `quickshell/Modules/DynamicIsland/DynamicIsland.qml`

**Keep-alive ref.** A gated ref so the subscription is live whenever the feature
is enabled and available:

```qml
Loader {
    active: SettingsData.dynamicIslandTailscale && TailscaleService.available
    sourceComponent: Component { Ref { service: TailscaleService } }
}
```

**Pass-through props** (mirroring the existing `vpnOn` / `weatherReady` style):
`tsAvailable`, `tsConnected`, `tsPeerCount`, `tsUsingExitNode`, `tsExitNodeName`,
`tsNeedsAttention`, `tsStatusKind`. All read `SettingsData.dynamicIslandTailscale`
where relevant so the feature toggle gates them.

**Splash triggers** — `Connections { target: TailscaleService }`, every handler
guarded by `root.ready` (existing 1.5s startup gate) and the settings toggle:

| Event | Watch | Splash |
|---|---|---|
| Connected | `onConnectedChanged` | `device_hub` "Tailscale · N online" / `vpn_key_off` "Tailscale disconnected" |
| Exit node | `onUsingExitNodeChanged` / `onExitNodeNameChanged` | `public` "Exit node: <name>" / "Exit node off" |
| Health | `onNeedsAttentionChanged` / `onStatusKindChanged` | **priority 2** `warning` "Tailscale needs login" / "tailscaled stopped" |
| Peer online | `onMyOnlinePeersChanged` | "<host> online" — tamed (see below) |

**Peer-online noise control** (the user opted in despite the noise risk):
- only *my* peers (`myOnlinePeers`).
- suppress the **initial** set: keep a `_tsKnownOnline` hostname set, seeded on the
  first non-empty update and on every connect, so only true deltas fire.
- coalesce a burst: if >1 new host appears in the same change, show
  "N devices online" instead of one splash each.
- priority 1 (queues behind status/exit-node splashes).

**Disconnect debounce:** `"Starting"` / brief flaps must not fire a false
"disconnected" splash. Gate the disconnect splash on a settled transition
(`statusKind === "stopped"` held for a short timer, not merely `connected===false`).

**Satellite bubble:** add a `"tailscale"` case to `satKind` (shown when
`tsNeedsAttention` and pill is compact/chip), with `satIcon` = `vpn_key`/`public`
and `satColor` = `Theme.error`/`Theme.warning`. Tapping it → `openPanel("tailscale")`.

### 3. Idle-row indicator — `quickshell/Modules/DynamicIsland/panes/IdlePane.qml`

A small clickable cluster in `rightCluster`, near (and separate from) the existing
NM `vpn_lock` icon:
- glyph `vpn_lock` (or `device_hub`) + peer count text, plus a `public` glyph when
  `island.tsUsingExitNode`.
- color: `island.accent` when connected & healthy, `Theme.warning` when
  `island.tsNeedsAttention`, `island.subText` when off.
- `visible: island.tsAvailable && SettingsData.dynamicIslandTailscale`.
- click → `island.openPanel("tailscale")`.

### 4. Drill-in panel — `quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml`

New panel, structured like `WifiPanel.qml`, reusing the peer-list UI from
`TailscaleWidget.qml` (search field, filter chips My/Online/All, refresh button,
peer cards with hostname/IP/OS/relay, expandable DNS/tags/owner, copy-IP). Add a
header line: status + tailnet name + "via <exit-node> 🌐" when using an exit node.

- refs the service while open (`addRef`/`removeRef` on `panelView === "tailscale"`,
  matching how `WifiPanel` refs `NetworkService`).
- wired into `ControlCenterPanel`'s drill `Loader` (panelView → component switch).
- `"tailscale"` added to the `panelView` doc-comment enum in `DynamicIsland.qml`.

### 5. Reachability / IPC — `IslandHub.qml`

`openPanel("tailscale")` reachable from: the idle-row indicator, the satellite tap,
and `dms ipc call island open tailscale` (add `"tailscale"` to `IslandHub`'s
openable-view set / `onOpenViewRequested` allow-list). No Control Center hub
quick-tile in v1.

### 6. Settings — `quickshell/Common/SettingsData.qml` (+ settings tab)

- `property bool dynamicIslandTailscale: true`
- a toggle in the island settings tab, consistent with the existing
  `dynamicIslandEnabled` / `dynamicIslandBlur` / `dynamicIslandNotchMode` /
  `dynamicIslandHideOnFullscreen` toggles (and `SettingsSpec.js` if persistence
  is declared there).
- Gates the indicator + splashes; effectively no-op when `!available`.

## Error handling & edge cases

- `available === false` (Tailscale not installed / no backend capability) → fully
  silent: indicator hidden, no splashes, no satellite.
- Startup: the existing `root.ready` gate suppresses splashes for 1.5s;
  `_tsKnownOnline` seeding suppresses the initial peer-online burst.
- `"Starting"` is treated as healthy-in-progress (no disconnect splash; debounce).
- Multi-monitor: splashes already gate to `isFocusedScreen` inside `pushActivity`;
  the persistent indicator/satellite show on every island (intended).

## Testing & verification

- **Go:** no required change in v1, so existing `client_test.go` / `manager_test.go`
  stand. (If the optional `ExitNodeOption` mapping is later added, extend
  `client_test.go`'s converter test.)
- **QML:** not unit-tested in this repo → manual verification by running the
  working-tree shell and exercising real transitions:
  1. `tailscale down` → expect "Tailscale disconnected" splash, indicator dims.
  2. `tailscale up` → expect "Tailscale · N online" splash, indicator shows count.
  3. `tailscale set --exit-node=<peer>` / `--exit-node=` → expect exit-node
     splash + "via <node>" in indicator/panel.
  4. a peer toggling online → expect a (single, deltas-only) "<host> online" splash.
  5. open the panel via indicator click and `dms ipc call island open tailscale`.
  6. toggle the setting off → all Tailscale island surfaces disappear.
- **Verification caveat:** per project memory, `dms.service` runs the working tree
  only via a systemd override that can vanish after a nix rebuild — confirm the
  override is active (running the edited files, not the store build) before
  trusting manual verification.

## Out of scope (v1)

- Exit-node connect/clear actions from the island.
- "This machine advertises as an exit node" badge (optional Go change).
- Control Center hub quick-tile for Tailscale.
- A generic multi-service live-activity registry.
