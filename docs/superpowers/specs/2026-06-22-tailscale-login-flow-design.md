# Tailscale logged-out state + login flow — design

**Date:** 2026-06-22
**Status:** approved (design)
**Branch:** `feat/dynamic-island`

## Problem

Opening the island Tailscale panel (SUPER+ALT+T) on a machine that is **not logged
in / has no active account** shows an empty, broken "Disconnected" view with no way
forward (the user reports it as a possible crash — at minimum a dead-end UX). The
panel must instead show an actionable state: "Pas de compte actif" with a
**Se connecter** button that runs `tailscale up`, captures the generated auth URL,
and lets the user **open it in the browser** or **copy the link**. Once
authenticated, the panel flips to the normal peer list.

`tailscale up` / `login` require root or operator rights — on a freshly-set-up
machine neither a Tailscale account nor an operator is configured — so the login
must escalate privilege. The codebase already escalates via **`pkexec`**
(`UsersService` runs `["pkexec", "useradd", …]`) and DMS ships a polkit agent, so
`pkexec tailscale up` pops a GUI password prompt and works regardless of operator
state. (Decided during brainstorming.)

## Approach

Extend the existing `TailscaleService` singleton with a login API
(`pkexec tailscale up`, auth-URL capture) and replace the panel's empty
not-connected view with a state-driven card. No Go backend changes.

## Components

### 1. `quickshell/Services/TailscaleService.qml` — login API

State:
- `property string authUrl: ""` — the `https://login.tailscale.com/…` URL captured
  from `tailscale up` output.
- `property bool loginInProgress: false`
- `property string loginError: ""`

Binary resolution: `pkexec` sanitizes `PATH`, so `pkexec tailscale up` would fail
on NixOS (tailscale lives in `/run/current-system/sw/bin`). Resolve the absolute
path once at startup via a `which tailscale` Process into `_tsBin` (fallback
`"tailscale"`).

`function login()`:
- no-op if `loginInProgress`; reset `authUrl`/`loginError`; set `loginInProgress = true`.
- run `["pkexec", _tsBin, "up"]` via a `Process`. The DMS polkit agent shows the
  password prompt; `up` runs as root and **blocks** until the node authenticates.
- parse stdout AND stderr line-by-line; extract the first match of
  `https?://\S*login\.tailscale\.com\S*` (fallback: first `https?://\S+`) → `authUrl`.
- `onExited(code)`: `loginInProgress = false`. `code === 0` → success (the
  subscription will flip `connected`; clear `authUrl`). polkit cancel
  (`code === 126 || code === 127`) → `loginError = "Connexion annulée"`. other
  non-zero → `loginError =` last stderr line (or a generic message).
- clear `authUrl` and `loginError` when `connected` becomes `true` (Connections on
  the existing state).

`function cancelLogin()`: kill the login Process, reset `loginInProgress`/`authUrl`.

`statusKind` (already exists) drives the panel: `"needsLogin" | "stopped" |
"starting" | "running" | "error"`.

### 2. `quickshell/Modules/DynamicIsland/panels/TailscalePanel.qml` — state card

When `!TailscaleService.connected`, the search field / filter chips / peer list are
replaced by one state card driven by `statusKind` and the login state:

- **`needsLogin`** (no account): icon + "Pas de compte actif" + **[Se connecter]**
  → `TailscaleService.login()`.
  - `loginInProgress && authUrl === ""` → spinner + "Connexion… autorisez dans la fenêtre".
  - `authUrl !== ""` → "Authentifiez-vous dans le navigateur" +
    **[Ouvrir le navigateur]** (`xdg-open authUrl`) + **[Copier le lien]**
    (`dms cl copy authUrl`).
  - `loginError !== ""` → error text + **[Réessayer]** (`login()`).
- **`stopped`** (account OK, daemon down): "Tailscale est arrêté" + **[Activer]**
  → `login()` (same `tailscale up`; no browser step, flips to Running).
- **`starting`**: "Connexion en cours…" (spinner, no button).
- **`error`** / not available: generic message + **[Réessayer]**.

The connected case is unchanged (status header + search + chips + peer list + the
Taildrop drop targets).

### 3. Crash hardening (null-safety)

The state card replaces the list when not connected, so no peer-card delegate
instantiates with a null `selfNode`/empty peers. Audit the not-connected path for
null dereferences; keep `peer.*` accesses guarded. This converts the empty/broken
"Disconnected" view (the reported "crash") into the actionable card.

## Error handling & edge cases

- **polkit cancelled** → `loginError = "Connexion annulée"`, no spam; the
  [Se connecter] button returns.
- **`up` fails** (network, etc.) → `loginError` from stderr; [Réessayer] available.
- **auth URL never appears** (e.g. immediate failure) → after the Process exits with
  non-zero and no `authUrl`, show `loginError`.
- **binary not found** → `_tsBin` falls back to `"tailscale"`; if that also fails,
  the Process exits non-zero → `loginError`.
- **already connecting elsewhere** → `login()` is a no-op while `loginInProgress`.
- **success while panel closed** → `connected` flips via the subscription; `authUrl`
  cleared; next open shows the peer list.

## Testing & verification

- **Go:** none.
- **QML:** not unit-tested → manual:
  1. Loads with no QML errors (journal scan).
  2. Force the state card to render without disturbing the live session (temporarily
     simulate `statusKind`/`!connected` for a screenshot), confirm the card + buttons
     render.
  3. "Copier le lien" puts a URL on the clipboard (`wl-paste` check) when `authUrl`
     is set (can stub `authUrl`).
  4. Real end-to-end login (polkit prompt → browser → Running) is verified by the
     user on an actually-logged-out machine.
- Verify via the live working-tree shell ([[verifying-qml-changes-no-qmllint]]).

## Out of scope (v1)

- A logout / "switch account" flow.
- Auto-opening the browser (explicit buttons only, per the user).
- Surfacing the auth URL as an island splash (it lives in the panel).
- A Go backend `tailscale.up`/login command (shell-out + pkexec is enough).
