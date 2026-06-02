# Liquid Island — Handoff

Reprise du projet : transformer **DankMaterialShell (DMS)** pour que la barre soit
remplacée par une **Dynamic Island** (style Apple) — mêmes menus DMS, mais
disposition / animations / interactivité = île. Fork de DMS, l'île est un "style"
activable.

## État : fonctionnel, en prod sur la machine (Hyprland, 2 écrans eDP-1 + HDMI-A-1)

---

## Où se trouve le code

- **Fork DMS** (= ce repo cloné) : `~/Projects/DankMaterialShell/`
  - `quickshell/Modules/DynamicIsland/DynamicIsland.qml` — **le composant principal**
  - `quickshell/Modules/DynamicIsland/IslandHub.qml` — singleton + IpcHandler (target `island`)
  - `quickshell/Modules/DynamicIsland/island-blur.conf` — snippet Hyprland pour le flou (opt-in)
  - `quickshell/DMSShell.qml` — intègre l'île (Variants par écran), supprime la DankBar quand l'île est ON, supprime VolumeOSD/BrightnessOSD
  - `quickshell/Common/SettingsData.qml` + `Common/settings/SettingsSpec.js` — flags `dynamicIslandEnabled` (def true), `dynamicIslandBlur` (def false)
  - `quickshell/Modules/Settings/DankBarTab.qml` — carte "Dynamic Island Style" (2 toggles)
- **Ancien prototype standalone** (référence, obsolète) : `~/Projects/DankMaterialShell/island-lab/`

## Comment c'est lancé (persistant)

Service systemd user **dms.service**, override drop-in :
`~/.config/systemd/user/dms.service.d/override.conf`
```
[Service]
ExecStart=
ExecStart=/run/current-system/sw/bin/dms -c /home/titosy/Projects/DankMaterialShell/quickshell run --session
```
- Démarre le fork au boot (service `enabled`).
- **Revenir à DMS nix d'origine** : `rm -rf ~/.config/systemd/user/dms.service.d && systemctl --user daemon-reload && systemctl --user restart dms`

---

## ⚠️ GOTCHAS DE WORKFLOW (lire avant de coder)

1. **HOT-RELOAD PEU FIABLE** : les edits sur `Modules/*.qml` ne sont souvent PAS
   repris (rendu obsolète → on croit que le fix ne marche pas). **Toujours
   `systemctl --user restart dms.service` après un edit**, puis vérifier.
2. **`console.log` est filtré** (niveau debug, absent du journal). Pour debugger :
   `console.warn(...)` puis `journalctl --user -u dms.service --since "8 sec ago" | grep '\[DI\]'`.
3. **Déclencher idle sans survol** : Hyprland (config lua) refuse
   `hyprctl dispatch movecursor`. Pour tester l'état idle, mettre temporairement
   `property string mode: "idle"` (ligne ~134), restart, lire, puis remettre `"compact"`.
4. **systemd Type=dbus, BusName=org.freedesktop.Notifications** : un seul shell peut
   posséder ce nom. Tuer tout autre shell avant `systemctl start dms`. `dms run -d -c <path>`
   PERD le `-c` au ré-exec daemon → utiliser le `run --session` du service.
5. **Envoyer une notif de test** :
   `gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify "App" 0 "" "Titre" "Corps" "[]" "{}" 5000`

---

## Données live utilisées (singletons DMS / Quickshell)

Theme (couleurs Matugen) · MprisController (média) · BatteryService · NotificationService.popups ·
AudioService.sink.audio (volume) · DisplayService (brightness) · PrivacyService (mic/cam/screenshare) ·
CavaService + Common/Ref (spectre audio, `cava` installé) · SystemTray.items · ToplevelManager.activeToplevel
(fenêtre focus) · NetworkService.vpnConnected · WeatherService.weather · Hyprland.monitors/workspaces ·
NiriService (multi-compositeur) · PopoutService (ouvre les menus) · CompositorService.

## Modes (machine à états, propriété `mode`)

`compact` (repos: horloge + icônes privacy/batterie-basse) · `chip` (repos+média: mini art + EQ cava) ·
`idle` (survol: workspaces | titre fenêtre tronqué | horloge·météo·VPN·kb·tray·batterie) ·
`media` (art + titre + ⏮⏯⏭ + scrubber drag-to-seek) · `expanded` (clic: 5 lanceurs de menus DMS) ·
`notif` (carte app→titre→corps + badge +N + ✕ dismiss) · `presenter` (OSD volume/brightness/batterie).

Design : **rectangle arrondi** (radius 12 compact / 22 étendu), très compact au repos,
ressorts (SpringAnimation) + morph scale/opacity, glow accent via shadowColor en média/chip/notif,
bordure ROUGE quand privacy actif. Pas de shader/goutte liquide (retiré).

## Fonctionnalités faites

Per-monitor workspaces · privacy/recording signal · notif+OSD sur écran focus seulement ·
tray menus (QsMenuAnchor, clic droit) · titre fenêtre tronqué · indicateurs météo/VPN/kb ·
drag-to-seek + tooltips · notif quick-dismiss ✕ · **notif action buttons** (voir ci-dessous) ·
Super+I (voir ci-dessous) · 1 seul MultiEffect (perf) ·
EQ audio réel (cava) · workspaces multi-compositeur (Hyprland+niri).

## Notif action buttons (fait 2026-06-02)

Mode `notif` affiche jusqu'à **2 chips d'action** (ex. Répondre / Archiver) dans le cluster
droit `notifRight`, avant le badge +N et le ✕. Source : `latestPopup.actions`
(`list<NotificationAction>`), filtrée via `root.notifActions` (exclut l'action implicite
`identifier === "default"` = clic sur le corps, exige `text` non vide, cap 2). Clic chip →
`action.invoke()` + `popup = false` + `settle()` (parité avec `NotificationPopup.qml`).
- Pill élargi : `pillW` notif passe 464 → **524** quand `notifActions.length > 0`.
- Le `notifTimer` (4 s) est **mis en pause au survol** d'une notif actionnable (HoverHandler),
  relancé à la sortie → on a le temps de cliquer.
- GOTCHA constaté : lire `notifActions` **impérativement dans `showNotif`** renvoie l'ancienne
  valeur (`[]`) — le binding n'est pas encore recalculé à cet instant. Les *bindings* (pillW,
  Repeater model) le recalculent correctement, donc le rendu est bon. Ne pas se fier à une
  lecture impérative de cette property dans le même tick que `onLatestPopupChanged`.
- Test : `gdbus call ... Notify "Messages" 0 "" "Léa" "Coucou" "['reply','Répondre','archive','Archiver']" "{}" 6000`

## Super+I (toggle clavier)

`dms ipc call island toggle` marche. Pour le raccourci, ajouter à `~/.config/hypr/hyprland.conf` :
```
bind = SUPER, I, exec, dms ipc call island toggle
```

## Réglages de positionnement actuels (DynamicIsland.qml)

- Fenêtre : `implicitWidth 620`, `implicitHeight 300`, `WlrLayershell.margins { top: 4 }`, centrée.
- Largeurs/hauteurs par mode : voir `pillW`/`pillH`. notif 464/524×80, expanded 488×80,
  compact auto×28. **idle (≥480) et media (≥410) sont DYNAMIQUES** (clampés `screenW-40`).
- **Popouts centrés sous l'île** : `openMenu()` passe `sx = (sw - w)/2` (bord gauche de l'île),
  car le popout se centre sur `triggerX + triggerWidth/2` (DankPopout ligne ~660).
- **Distance verticale popout** : `sy = 52` dans `openMenu()` — *c'est LE chiffre à régler*
  si l'utilisateur veut plus/moins d'écart sous l'île.

## Corrections de bugs notables (ne pas régresser)

- **notif bloqué/blanc** : `settle()` ne doit PAS garder `mode==="notif"` (sinon notifTimer
  ne peut pas sortir). + `onLatestPopupChanged` dismiss si popup null.
- **titre disparu** : NE JAMAIS lier `width` d'un Text à son propre `contentWidth`/`implicitWidth`
  (boucle → collapse à 0). Le titre idle est un StyledText `anchors.fill` d'un `centerSlot`
  ancré entre `wsRow.right` et `rightCluster.left`. StyledText par défaut = WordWrap sans cap →
  toujours mettre `elide:ElideRight; maximumLineCount:1; wrapMode:Text.NoWrap` pour tronquer.
- **OSD volume désynchronisé** : `presenterValue`/`presenterIcon` sont des BINDINGS réactifs
  dérivés de `volPct`/`muted`/`batPct`/`brightnessLevel` selon `presenterKind` — PAS un snapshot
  impératif. `showPresenter()` ne fait que poser `presenterKind` + `mode="presenter"`. Avant,
  `presenterValue = volPct` dans `onVolumeChanged` lisait une dérivée pas encore recalculée →
  l'OSD affichait la valeur du palier PRÉCÉDENT. (Même classe de bug que la lecture impérative
  de `notifActions`/`notifCritical` dans `showNotif`.) Vérifié wpctl 30/72/45 → exact.
- **Barre OSD qui « sweepe » depuis 0 à la réouverture** : le contenu presenter était
  `anchors.fill: parent` → la track était ancrée au pill qui SPRINGE de la taille compacte (92)
  vers 320 → `track.width` grandissait → `fill = track.width*frac` partait petit et grandissait
  de gauche. FIX : contenu presenter à **largeur FIXE** (`320 - spacingL*2`, `anchors.centerIn`)
  → la track a une largeur constante, la barre garde sa proportion correcte et se contente de
  scale/fade-in pendant que le PILL (la forme) springe derrière. `pill.clip` masque le léger
  débord pendant l'ouverture. Garde le `Behavior on width` (anime seulement les vrais
  changements de valeur, ex. scroll pendant que l'OSD est affiché).

## Audit-batch 2 (fait 2026-06-02) — 14 correctifs

Suite à un audit complet, appliqués dans `DynamicIsland.qml` (+ `IslandHub.qml`) :
1. **`latestPopup` = la PLUS RÉCENTE** (`popups[length-1]`, pas `[0]`). `NotificationService`
   fait `allWrappers.push` → `[0]` est la plus ANCIENNE ; avant, une nouvelle notif n'écrasait
   jamais l'ancienne affichée. **Bug majeur corrigé.**
2. **Notif critique persistante** : `latestPopup.urgency === NotificationUrgency.Critical`
   (import `Quickshell.Services.Notifications`) → `notifTimer` stoppé (pas d'auto-dismiss),
   bordure ROUGE (`pill.alertBorder`). Le HoverHandler ne relance PAS le timer si critique.
3. **Notif actionnable déjà sous le curseur** : `showNotif` ne (re)lance pas le timer si
   `hovered && actionable`. ⚠️ `showNotif` lit `latestPopup.urgency/.actions` **en direct**
   (les dérivées `notifCritical`/`notifActions` ont 1 tick de retard — voir gotcha plus haut).
4. **Clic-corps notif → action `default`** si présente (`defaultAction()`), sinon centre de notif.
5. **Clic badge `+N` → `NotificationService.dismissAllPopups()`** (tout effacer).
6. **`isFocusedScreen` fallback = écran primaire** (`Quickshell.screens[0]`) au lieu de « tous »
   quand le compositeur ne reporte pas de moniteur focus → plus de notif/OSD dupliqués 2 écrans.
7. **Largeur idle/media DYNAMIQUE** (clampée largeur écran) : idle grossit si les clusters sont
   larges (anti-collapse du titre) ; media grossit pour le titre. Pas de boucle de binding
   (lit `implicitWidth` de `wsRow`/`rightCluster`/`mTitle`, indépendants de la largeur du pill).
8. **Eyebrow média** = `player.identity` ou "NOW PLAYING".
9. **Scrubber** : `MprisController.activePlayerStableLength` au lieu de `player.length` brut.
10. **Strip suffixe navigateur** du titre fenêtre idle (Chrome/Firefox/…).
11. **Mute au clic-molette** sur fond d'île (`bgClick` accepte MiddleButton).
12. **EQ fallback** dans un buffer local `eqFallback` au lieu de muter `CavaService.values`.
13. **IPC `island expand` ≠ `toggle`** : `expand` force l'ouverture (idempotent), `toggle` bascule
    (signaux séparés `expandRequested`/`toggleRequested`).
14. **Cloche / réglages ouvrent enfin leur popout** : `notificationCenterLoader` et
    `controlCenterLoader` sont des `LazyLoader active:false` que la DankBar activait — or la barre
    est supprimée en mode île. `openMenu()` fait désormais `…Loader.active = true` AVANT le toggle
    (activation **synchrone** : le `Component.onCompleted` du popout assigne la ref dans la foulée,
    vérifié). `toggleDankDash` s'auto-activait déjà, d'où dash OK mais notif/control muets avant.
    → clic cloche = centre de notifications (= **historique des notifs**).

## Backlog restant (priorité basse)

- Keyboard-layout sur Hyprland (DMS n'expose pas la source ; OK sur niri/dwl).
- Flou frosted : runtime `hyprctl keyword layerrule` REFUSÉ par ce Hyprland → utiliser le
  snippet `island-blur.conf` sourcé depuis hyprland.conf, puis activer le toggle "Frosted blur".
- Refactor (non-fonctionnel) : factoriser le boilerplate des 6 blocs de mode (opacity/visible/
  scale/Behaviors) en un composant `IslandPane` réutilisable. Reporté (risque de régression).

## Commandes utiles

```bash
systemctl --user restart dms.service      # recharger après edit (OBLIGATOIRE)
journalctl --user -u dms.service --since "10 sec ago" | grep -iE "error|\.qml|\[DI\]"
hyprctl layers | grep dynamic-island      # vérifier que l'île tourne (2 = 2 écrans)
dms ipc call island toggle                # toggle expand
qs ipc --pid $(pgrep -f 'quickshell -p /home/titosy/Projects/DankMaterialShell/quickshell') show
```
