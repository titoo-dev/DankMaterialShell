# Liquid Island — Handoff

Reprise du projet : transformer **DankMaterialShell (DMS)** pour que la barre soit
remplacée par une **Dynamic Island** (style Apple/macOS) — mêmes services DMS, mais
surface/animations/interactivité = île. Fork de DMS, l'île est un "style" activable.

## État : fonctionnel, en prod (Hyprland, 2 écrans eDP-1 + HDMI-A-1). Branche `feat/dynamic-island` (fork `titoo-dev/DankMaterialShell`), dernier commit `7c4c6bbb`.

---

## ✅ MODULARISATION TERMINÉE (2026-06-02)

Le monolithe est entièrement découpé. Contrôleur `DynamicIsland.qml` : ~1040 → **619 lignes**.
Ajouter un panneau/pane = créer 1 fichier. Structure finale :
- `DynamicIsland.qml` — contrôleur pur : props/services partagés, machine à états, géométrie
  (`pillW`/`pillH`), fenêtre+masque, shell du pill (fond/verre/ombre/squash/behaviors), handlers
  (Hover/Wheel/bgClick/scrim), bump, `SystemClock`, `QsMenuAnchor`. Instancie tous les composants.
- `ControlCenterPanel.qml` — hub mode expanded. Instancie les 4 panels (`import "panels"`).
- `NotificationBanners.qml` — deck bannières macOS.
- `panels/` — 4 vues drill-down : `WifiPanel`, `BluetoothPanel`, `AudioPanel`, `NotificationsPanel`.
- `panes/` — 5 panes au repos : `CompactPane`, `ChipPane`, `IdlePane`, `MediaPane`, `PresenterPane`.
- `IslandHub.qml` — singleton + IpcHandler.

Vérifié par capture cette session : **compact, idle, media, presenter, chip, control-center hub,
wifi drill-down** rendent tous sans erreur QML.

Helpers ajoutés au contrôleur pour les panes extraites :
- `clockShort` / `clockLong` (string) — `clock.date` formaté (les panes ne voient plus l'id `clock`).
- `openTrayMenu(menuObj, rect)` — la `IdlePane` délègue l'ouverture du menu tray (l'id `trayMenu`
  reste dans le contrôleur).

Géométrie : les panes exposent en `readonly property` ce que `pillW` lit, et le contrôleur les lit
via l'id de l'instance :
- `compactPane.contentWidth` (compact), `mediaPane.titleW` + `mediaPane.controlsWidth` (media),
  `idlePane.wsWidth` + `idlePane.clusterWidth` (idle).

## GOTCHAs d'extraction (composant → fichier)
- Composant = `Item/Column { property var island: null; … }` ; `root.` → `island.` (sed
  `s/root\\./island./g` sur le bloc) ; exposer en `readonly property` ce que la géométrie lit.
- **RÉ-IMPORTER** ce que le bloc utilise — sinon « Type X unavailable / Non-existent attached
  object » : `QtQuick.Controls` (ToolTip), `QtQuick.Shapes` (PathAngleArc), `Quickshell.Services.Notifications`
  (NotificationUrgency), etc.
- ⚠️ **Numéros de ligne dérivent** entre edits — toujours re-`grep`/`awk` les bornes AVANT un
  `sed -i 'a,bd'`. (J'ai eu 2 décalages off-by-2 cette session.) Garder un backup (`cp` vers /tmp).
- Pas de bloc JS multi-instruction dans un binding `text:` (`{ var…; if…; return }`) → « Unexpected
  token ; ». Utiliser une expression unique.

---

## Où se trouve le code

- **Fork DMS** (= ce repo cloné) : `~/Projects/DankMaterialShell/`
  - **MODULARISÉ — 100% (2026-06-02)** — `Modules/DynamicIsland/` :
    - `DynamicIsland.qml` (~619 l.) — **contrôleur pur** : props/services partagés, machine à états
      (`mode`/`panelView`), géométrie (`pillW`/`pillH`), fenêtre+masque, shell du pill (fond, verre,
      ombre, squash, behaviors), HoverHandler/WheelHandler/bgClick/scrim, bump, `SystemClock`,
      `QsMenuAnchor`. Instancie tous les composants. `import "panels"` + `import "panes"`.
    - `ControlCenterPanel.qml` (~196 l.) — hub mode expanded (toggles/sliders/now-playing/footer).
      `property var island` ; expose `viewHeight` (lu par `pillH`). Instancie les 4 panels.
    - `panels/` — 4 vues drill-down : `WifiPanel`, `BluetoothPanel`, `AudioPanel`,
      `NotificationsPanel`. Ids internes conservés (`wifiCol`/`btCol`/`audioCol`/`notifCol`) →
      `viewHeight` lit `wifiCol.implicitHeight` etc.
    - `panes/` — 5 panes au repos : `CompactPane` (expose `contentWidth`), `ChipPane`,
      `IdlePane` (expose `wsWidth`/`clusterWidth`, délègue à `island.openTrayMenu`),
      `MediaPane` (expose `titleW`/`controlsWidth`), `PresenterPane`. `pillW` lit ces tailles via
      l'id de l'instance (`compactPane`/`idlePane`/`mediaPane`).
    - `NotificationBanners.qml` (~245 l.) — deck de bannières macOS. `property var island` ;
      `NotificationBanners { id: notifBanners; island: root }` (réf. dans le `mask`).
    - `IslandHub.qml` — singleton + IpcHandler (target `island`).
  - **PATTERN d'extraction** (rappel) : un composant = `Item/Column { property var island: null; … }` ;
    `root.` → `island.` ; exposer ce que la géométrie lit (`viewHeight`, `contentWidth`,
    `titleW`…) en `readonly property` ; placer dans un sous-dossier et `import "<dossier>"`.
    ⚠️ ré-importer ce qu'utilise le bloc (`QtQuick.Controls` pour `ToolTip`, `QtQuick.Shapes` pour
    `Shape/PathAngleArc`…). Ce qui n'est PAS exposable en property (id comme `clock`, `trayMenu`) →
    exposer une property dérivée (`clockShort`) ou une fonction (`openTrayMenu`) sur le contrôleur.
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

## Masquage en plein écran (fait 2026-06-03)

L'île se cache sur un moniteur quand celui-ci affiche une fenêtre **plein écran** (films, focus).
- Flag `SettingsData.dynamicIslandHideOnFullscreen` (def `true`) + toggle « Hide on fullscreen »
  dans la carte DankBarTab (gated par `dynamicIslandEnabled`).
- Détection : `CompositorService.hasFullscreenToplevelOnScreen(modelData)` (cross-compositeur
  Hyprland/niri, **par moniteur**). Recalculée dans `_updateFullscreen()` sur
  `CompositorService.onToplevelsChanged` + `NiriService.onAllWorkspacesChanged` (mêmes triggers que
  l'auto-hide de la DankBar) + au démarrage (ready Timer). Property `hasFullscreenOnScreen`.
- Portée = **« seulement le pill »** (choix user) : `pillSuppressed = hideOnFullscreen &&
  hasFullscreenOnScreen && mode !== "presenter" && mode !== "expanded"`. Donc l'OSD volume/luminosité
  (presenter) ET un panneau ouvert volontairement (expanded, via keybind) restent visibles ; les
  **bannières de notif** vivent dans un autre item de fenêtre → inchangées.
- Effets quand `pillSuppressed` : le pill fade `opacity→0` (`visible: opacity>0`, Behavior), l'art-glow
  d'ambiance forcé à 0, et le pill est **retiré du masque d'input** (`Region.item: pillSuppressed ?
  null : pill`) pour que les clics au centre-haut atteignent l'app plein écran dessous.
- ⚠️ Test (config Lua) : `hyprctl dispatch fullscreen` est parsé comme du lua et ÉCHOUE → utiliser
  `hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })'`. Vérifié
  par log `[DI]` : moniteur avec fenêtre plein écran → `suppressed=true`, l'autre → `false` (par
  moniteur, pas global).

## Raccourcis clavier (IPC `island`)

IPC dispo (`IslandHub.qml`, target `island`) :
- `dms ipc call island toggle` — expand/collapse du control center
- `dms ipc call island expand` — ouvre (idempotent)
- `dms ipc call island close` — replie quel que soit l'état affiché (`onCloseRequested` → unpin + `panelView="controls"` + `settle()`)
- `dms ipc call island back` — recule d'un niveau : une drill view revient au hub, le hub se ferme (`onBackRequested`)
- `dms ipc call island open <view>` — ouvre direct sur une drill view (re-presser = referme).
  views : `controls | wifi | bluetooth | audio | notifications | calendar | apps | clipboard | emoji`.
  Handler contrôleur `onOpenViewRequested` (gated `isFocusedScreen`) → `openPanel(view)`.
  Pour `apps`/`clipboard` le grab clavier Exclusive s'engage SANS clic (vérifié : ouverture par IPC
  puis `wtype "fire"` filtre sur Firefox).

Binds Hyprland — **CÂBLÉS (2026-06-03)** dans `~/.config/hypr/hyprland.lua` (config active depuis
Hyprland 0.55 ; `hyprland.conf` n'est plus chargé). Bloc « Dynamic Island control » après les binds
Spotlight (`SUPER+R`) / emoji (`SUPER+;`). `SUPER+ALT` = namespace dédié sans conflit pour ouvrir
chaque drill view :
```
SUPER + I            toggle (control center hub)
SUPER + SHIFT + I    close  (replie quoi qu'il arrive)
SUPER + SHIFT + B    back   (recule d'un niveau)
SUPER + ALT + C      open controls       SUPER + ALT + N    open notifications
SUPER + ALT + W      open wifi           SUPER + ALT + K    open calendar (kalendar)
SUPER + ALT + B      open bluetooth      SUPER + ALT + V    open clipboard
SUPER + ALT + A      open audio          SUPER + ALT + E    open emoji
SUPER + ALT + Space  open apps (Spotlight)
```
Note : `SUPER+R` (apps) et `SUPER+;` (emoji) gardent leurs binds historiques ; `SUPER+V` reste vicinae.
Vérifié 2026-06-03 : les 12 binds sont enregistrés (`hyprctl binds`, modmask 64/65/72) et chaque
commande IPC répond (`ISLAND_TOGGLE/CLOSE/BACK/OPEN:*`), sans erreur QML au restart.

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
- **Notif image stale / boîte vide (ex. screenshot DMS)** : les images de notif sont souvent des
  URLs de provider transitoires `image://qsimage/N/M` (vérifié : screenshot DMS → `image://qsimage/2/1`).
  Avec `cache: true` (défaut), Qt sert l'ANCIENNE image en cache quand le provider réutilise un
  handle → display stale. De plus le bell-fallback était caché dès que `cleanImage` était défini,
  donc image échouée = boîte vide. Fix : `cache: false` + `asynchronous: true` sur `notifImg`, et
  bell `visible: notifImg.status !== Image.Ready` (fallback sur le statut réel de chargement).
- **Île étendue qui ne se replie pas au clic dehors** : le `mask: Region { item: pill }` ne capte
  que les clics SUR le pill → un clic dehors part en passthrough, jamais reçu. Le clic d'expansion
  mettait `pinned=true` qui BLOQUE `settle()`. Fix : le clic d'expansion ne pin plus (seul Super+I
  pin). **Comportement macOS (refonte)** : le panneau expanded reste ouvert et se ferme au **clic
  EN DEHORS**, pas sur sortie de souris. Implémentation : la fenêtre est passée en **PLEIN ÉCRAN**
  (`anchors` top+bottom+left+right, margins 0) ; `mask: Region { item: mode==="expanded" ? stage
  : pill }` → masque limité au pill (reste click-through) SAUF en expanded où tout l'écran est
  capté ; un `MouseArea` scrim plein écran (z:-5, `enabled: mode==="expanded"`, derrière le pill)
  ferme au clic dehors. Le pill se positionne lui-même (`y: notchMode ? 0 : 4`, x centré via
  `stage.cx`). `hideTimer` (1800 ms) ne s'applique plus au mode expanded (idle/média seulement).
  ⚠️ Le plein écran repose sur le `mask` pour le passthrough (clics hors pill → fenêtres dessous) —
  même mécanisme qu'avant, juste étendu.
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
    SUITE (2026-06-02) : `openMenu()` utilise désormais les variantes **`open*`** (openControlCenter,
    openNotificationCenter, openDankDash, openDankLauncherV2) au lieu de `toggle*`. Un launcher doit
    OUVRIR, pas basculer : si le `shouldBeVisible` d'un popout restait `true` (stale), `toggle()` le
    REFERMAIT → « rien ne s'affiche au clic réglages ». Vérifié par capture : le control center
    s'ouvre et rend bien (BT, Night/Dark mode), layers `dms:control-center` créés.

## Apple UX batch (fait 2026-06-02) — 10 améliorations

Inspiration Apple / macOS. Toutes dans `DynamicIsland.qml` (+ flag `dynamicIslandNotchMode`).
1. **Spring Apple + squash-and-stretch** : W/H springs asymétriques (H plus rebondi) ; à chaque
   `onModeChanged`, `squashAnim` (squashX/squashY via `transform: Scale`) → morph gélatineux.
2. **Progress ring pochette (chip)** : `QtQuick.Shapes` `PathAngleArc` autour de l'art, `sweepAngle
   = 360*mediaFrac`. Helpers partagés `mediaTick`/`mediaFrac`/`mediaLen`/`fmtTime()`.
3. **Timestamps scrubber** : écoulé / `-restant` aux extrémités, révélés au hover/drag du scrubber.
4. **Notch mode** (toggle `dynamicIslandNotchMode`, carte DankBarTab) : `margins.top 0` + coins haut
   carrés (`topLeftRadius/topRightRadius = 0`), coins bas arrondis. Look encoche MacBook.
5. **Verre dépoli** : overlay gradient (sheen blanc en haut + inner-shadow noire en bas) suivant les
   coins du pill ; `islandColor` alpha 0.72 en mode blur (vibrancy).
6. **Halo couleur d'ambiance pochette** : copie floutée (`MultiEffect blur 64`) de l'art DERRIÈRE le
   pill en média/chip → bloom couleur de l'album, GPU-only (pas d'extraction). Hors masque input.
7. **Notifs empilées + swipe-to-dismiss** : ledge `peek` derrière quand `popups>1` ; drag sur le
   corps (`notifPane.dragX/dragY` + `transform: Translate`) → dismiss si swipe-up>26 ou |dx|>64,
   sinon ressort retour ; tap propre (<6px) = action default / centre de notif.
8. **Splash Live Activity (Bluetooth)** : nouvel état `presenterKind="splash"` (icône + label, sans
   barre) ; watcher `btConnected: BluetoothService.connected` → `showSplash(...)` 2.6 s.
9. **Micro-interactions** : press-scale homogène + hover-lift (workspaces, tray, chips notif,
   launchers expanded). (Le parallax souris a été retiré sur demande utilisateur.)
10. (= #1 dans la liste) cf. spring/squash ci-dessus.

GOTCHA Shapes : `PathAngleArc.sweepAngle` accepte un Behavior pour animer la progression.
GOTCHA mask : `mask: Region { item: pill }` = région d'INPUT seulement ; le halo (#6) rend bien
au-delà du pill (passthrough), pas clippé visuellement.

## Mode expanded = Control Center INLINE (refonte UX 2026-06-02)

Remplace les 5 icônes-launchers (qui ouvraient des popouts séparés) par un vrai panneau
type macOS Control Center, rendu DANS l'île :
- **4 tuiles toggle** (Repeater key wifi/bt/dnd/theme) : `NetworkService.toggleWifiRadio()`,
  `BluetoothService.adapter.enabled`, `SessionData.setDoNotDisturb()`, `Theme.setLightMode()`.
  Accent quand actif, état live (bindings sur les services).
- **2 DankSlider** luminosité (`DisplayService.setBrightness(v,"",true)`) + volume
  (`audioNode.volume = v/100`).
- **Now Playing** inline (art + titre + ⏮⏯⏭) visible si `player`.
- **Footer** : 4 petites icônes (apps / notifs / presse-papier / tune=control center complet)
  via `openMenu()` pour les surfaces lourdes.
- Géométrie : `pillW` expanded = 460, `pillH` expanded = `ccColumn.implicitHeight + spacingM*2`
  (s'adapte au contenu). Fenêtre `implicitHeight` montée à 440. Un `MouseArea` plein absorbe les
  clics internes (pas de collapse accidentel) ; le repli se fait au pointer-leave (hideTimer).
- GARDE : `showPresenter()` retourne tôt si `mode==="expanded"` — sinon régler le volume via le
  slider déclencherait l'OSD et sortirait du control center.
Vérifié par capture : tuiles + sliders + rendu OK.

## Panneaux île-natifs (unification UX, 2026-06-02)

But : NE PLUS ouvrir les popouts DMS par défaut ; héberger des vues maison île-stylées qui lisent
les mêmes services. Navigation **drill-down macOS**.
- État : `property string panelView: "controls" | "wifi"`. `onModeChanged` reset à "controls" à la
  fermeture. Le hub (ccColumn) et chaque vue détail coexistent dans le mode expanded, en
  cross-fade + slide (`Translate.x` ±24, opacity), `pillH` = hauteur de la vue active.
- **Tuile Wi-Fi = drill-in** (chevron) → `panelView="wifi"` + `scanWifiNetworks()`. (Les tuiles
  BT/DND/Thème restent des toggles directs.)
- **Vue Wi-Fi** (`wifiCol`) : header back + titre + switch radio (`toggleWifiRadio`) ; liste
  scrollable (Flickable, hauteur adaptative cap 232) des `NetworkService.wifiNetworks`
  ({ssid, signal, secured, saved}) ; connecté = `ssid === currentWifiSSID` ; tap → `connectToWifi`,
  réseau sécurisé non sauvegardé → champ mot de passe inline (DankTextField echoMode Password) +
  bouton connexion ; état vide « No networks / Scanning… / Wi-Fi off ». Vérifié par capture.
  **Bouton refresh** (fait 2026-06-03) dans le header (avant le switch radio) → `scanWifiNetworks()` ;
  l'icône `refresh` **tourne** tant que `NetworkService.isScanning` (RotationAnimation, reset à 0 à
  l'arrêt) ; désactivé/atténué si Wi-Fi off. Remplace l'ancien texte « Scanning… » du header.
- **Vue Bluetooth** (`btCol`, panelView "bluetooth", drill depuis la tuile BT) : header back + titre
  + switch radio (`adapter.enabled`) ; liste `BluetoothService.pairedDevices` (icône
  `getDeviceIcon`, nom, Connected/Disconnected + batterie%, ✓/+ ) ; tap → `connectDeviceWithTrust` /
  `device.disconnect()` ; discovery activée à l'entrée. État vide « Bluetooth is off / No devices ».
  **Bouton refresh** (fait 2026-06-03) dans le header (avant le switch radio) → **redémarre la
  discovery** (`adapter.discovering=false` puis `btRescanTimer` 250 ms le repasse à `true` → balayage
  frais) ; l'icône `refresh` tourne tant que `BluetoothService.discovering` ; désactivé si BT off.
  **Appairage d'un nouvel appareil** (fait 2026-06-03) : section « Available » sous les appareils
  appairés, listant les appareils découverts non-appairés (`availableDevices` = même filtre que le
  DMS natif : `!paired && !pairing && !blocked && signalStrength>0`, trié par `sortDevices`). La
  **discovery démarre/s'arrête automatiquement** avec la vue (`btActive = mode==="expanded" &&
  panelView==="bluetooth"` → `onBtActiveChanged: ensureDiscovery()` ; bound sur un bool, PAS sur
  `visible` qui traîne derrière le fade ; aussi re-déclenché sur `BluetoothService.onEnabledChanged`).
  Tap sur une ligne → `pairNew()` → `BluetoothService.pairDevice(dev, cb)` (agent bluez DMS si
  `enhancedPairingAvailable`, sinon trust+connect), toast succès/erreur (`ToastService`), spinner
  par-appareil via `pairingAddrs` (map address→true réassignée) + `modelData.pairing`. État vide :
  « Searching for devices… » (si discovering) / « Tap refresh to scan ». ⚠️ Pas testé avec un vrai
  appareil (aucun à proximité dans la session) ; chemin identique à `ControlCenter/Details/BluetoothDetail.qml`.
- **Vue Audio/Output** (`audioCol`, panelView "audio", drill depuis le bouton 🔊 à droite du slider
  volume) : header back + « Output » ; liste `AudioService.typedSinks` (icône, `description`, ✓ si
  courant via `sink.name`) ; tap → `AudioService.setSink(node)`. Vérifié par capture.
- **Vue Input/Micro** (`inputCol`, `panels/InputPanel.qml`, panelView "input", fait 2026-06-03) :
  miroir exact de la vue Output mais pour les **sources** — drill depuis un 2e bouton (icône `mic`)
  ajouté à droite du bouton 🔊 dans la Row volume (slider rétréci à `parent.width - 80`). Header back
  + « Input » ; liste `AudioService.typedSources` (icône `mic`, `description`, ✓ si courant via
  `source.name`) ; tap → `AudioService.setSource(node)`. API symétrique de l'output
  (`typedSources`/`source`/`setSource`, l. 17/101/132 de AudioService). Instancié dans
  ControlCenterPanel + câblé dans `viewHeight`. Accessible aussi par `dms ipc call island open input`.
  Vérifié : 4 sources listées, courant = MC001 Pro (log `[INPUT]`), aucune erreur QML.
- **Vue Notifications** (`notifCol`, panelView "notifications") : header back + titre + « Clear all »
  (`clearAllNotifications`) ; liste scrollable (Flickable adaptatif cap 300) de
  `NotificationService.notifications` (NotifWrapper : appName/summary/body/cleanImage/appIcon/
  timeStr/actions) ; chaque ligne = icône (image cache:false + fallback cloche sur `status`),
  eyebrow app + `timeStr`, titre, corps, ✕ dismiss au survol (`dismissNotification`) ; tap ligne =
  invoque l'action par défaut si présente. Entrées : footer hub (icône notifs) + clic-corps d'une
  notif active (`openPanel("notifications")`). Vérifié par capture (3 notifs listées). Remplace le
  centre de notif DMS dans le flux île.
- Drill-views île-natives : **Wi-Fi, Bluetooth, Audio, Notifications, Calendar, Spotlight (apps),
  Clipboard**. Le footer du hub (5 icônes : apps/notifications/calendar/clipboard/settings) n'ouvre
  plus qu'UN popout DMS : « All settings » (`control`) — gardé exprès comme passerelle vers l'app
  complète (équivalent « Réglages système… » macOS).

## Spotlight (apps) + Clipboard en drill view (fait 2026-06-02)

- `panels/SpotlightPanel.qml` (id `appCol`, `panelView="apps"`) : champ de recherche + liste de
  résultats. Recherche `AppSearchService.searchApplications(query)` ; lancement
  `SessionService.launchDesktopEntry(app)` ; icônes via `AppIconRenderer`.
  ⚠️ **`results` calculé en IMPÉRATIF** (`property var results: []` + `refresh()` sur `onTextEdited`
  / `onVisibleChanged`), PAS en binding : `searchApplications()` écrit ses propres caches qu'il lit
  → un binding réactif boucle (« Binding loop detected for property results »).
  ⚠️ **Icône réelle** : `AppIconRenderer` est un `Item` SANS taille implicite → il FAUT lui donner
  `width`/`height` (pas seulement `iconSize`), sinon l'`IconImage` (anchors.fill) est 0×0 et l'icône
  est invisible (on voyait du vide/fallback). `iconValue: modelData.icon` se résout via
  `Paths.resolveIconPath` → vraie icône du thème.
  🔎 **Fuzzy subsequence** : `searchApplications()` ne fait que du fuzzy Levenshtein (typos), pas du
  subsequence type fzf. Le panel ajoute une passe `fuzzy(text, q)` (tous les chars de q dans l'ordre,
  bonus runs consécutifs + début de mot) sur `getVisibleApplications()`, et **append** au résultat du
  service les apps qu'il a ratées (ex. « sttgs » → System Settings, « vsc » → VS Code). On garde le bon
  classement frecency/prefix du service en tête. Vérifié : « sttgs » → « System Settings ».
  ⌨️ **Nav clavier** : `selIndex` + `move(±1)` (clampé) + `ensureVisible()` (auto-scroll du Flickable)
  + `launchSel()`. Le `DankTextField` a `ignoreUpDownKeys: true` et `keyForwardTargets: [navHandler]`
  → ↑/↓ pilotent la liste (pas le caret), Enter (`onAccepted`) lance le sélectionné, Esc revient au
  hub (via le navHandler). La ligne `index === selIndex` est surlignée ; le survol souris met aussi
  à jour `selIndex`. Vérifié : `wtype "set"` filtre, ↓↓ déplace la sélection d'exactement 2 lignes.
- `panels/ClipboardPanel.qml` (id `clipCol`, `panelView="clipboard"`) : recherche + liste
  `ClipboardService.clipboardEntries` (filtre local sur `.preview`, ici un binding pur = OK car
  lecture seule). `refresh()` à l'ouverture ; clic = `copyEntry(entry)` ; ✕ = `deleteEntry(entry)` ;
  images = icône `image` + label « Image ». Backend = daemon DMS (cliphist).
- ⚠️ **FOCUS CLAVIER** : la fenêtre île est `keyboardFocus: None` par défaut. Pour ces 2 vues (champ
  de saisie) le contrôleur passe à **`WlrKeyboardFocus.Exclusive`** quand `mode==="expanded" &&
  panelView ∈ {apps,clipboard}`, sinon `None`. Choix d'Exclusive (et pas OnDemand comme DMS sur
  Hyprland) : OnDemand ne s'engage qu'au **clic pointeur** sur la surface → la saisie ne marchait pas
  à l'ouverture ; Exclusive (grab modal) marche tout de suite. Le champ fait `forceActiveFocus()` à
  l'ouverture (`onVisibleChanged`). Esc renvoyé au hub via `keyForwardTargets:[escHandler]` du
  `DankTextField`. Le grab est relâché dès que `panelView` quitte apps/clipboard. Vérifié par
  capture : `wtype "set"` filtre sur « System Settings », Esc revient au hub.

## Emoji picker île-natif (fait 2026-06-02)

`panels/EmojiPanel.qml` (id `emojiCol`, `panelView="emoji"`) + dataset `panels/EmojiData.js`.
Expérience moderne : recherche, onglets de catégories, grille **couleur** (Noto Color Emoji),
**récents persistés**, navigation clavier 2D.
- **Dataset** `EmojiData.js` (`.pragma library`) : `CATEGORIES` (recent + 9 catégories) et `EMOJI`
  (curé ~280 emojis : `{e,n,k,c}` = char/nom/keywords/catégorie). `search(q)` (substring sur nom+kw),
  `byCategory(cat)`. Pas exhaustif (la longue traîne est rare) mais couvre l'usage courant.
- **Auto-paste (pas de copie)** : à la sélection, on **tape l'emoji dans le champ focus** via `wtype`
  (façon emoji picker Windows) au lieu de copier → ne pollue PAS le presse-papier. ⚠️ GROS GOTCHA :
  après la fermeture, Hyprland **ne restaure PAS** le focus clavier vers l'app en dessous (le grab
  Exclusive d'un layer-shell persistant ne déclenche pas de re-focus). Donc `wtype` partait dans le
  vide. FIX dans le contrôleur (`insertText()`) :
  1. on capture EN CONTINU l'adresse de la dernière app active hors-expanded
     (`onActiveWinChanged: if (mode!=="expanded") _typeAddr = _hyprActiveAddr()`) — car pendant le
     grab `ToplevelManager.activeToplevel` peut devenir null. `_hyprActiveAddr()` matche
     `Hyprland.toplevels.values[i].wayland === ToplevelManager.activeToplevel` → `.address`.
  2. `pick()` → `island.insertText(e)` : ferme l'île, puis `insertFocusTimer` (150 ms) appelle
     `HyprlandService.focusWindow(_typeAddr)` (re-focalise explicitement), puis `insertTypeTimer`
     (70 ms) **colle via presse-papier + Ctrl+V** (PAS un wtype direct de l'emoji). Toast « Inserted … ».
  - ⚠️⚠️ **Saga de l'insertion (diagnostiquée à fond, par log de debug + tests user)** :
     - `wtype` tape l'emoji dans les apps **natives Wayland**, mais **n'atteint PAS XWayland** du tout.
     - `ydotool` (uinput) atteint XWayland mais SEULEMENT pour les touches simples : il ne tape pas
       l'emoji, et ses combos modificateur (Ctrl+V, Shift+Insert) **ne sont pas reçus** par XWayland.
     - `xdotool` parle **X11 natif** → il atteint les clients XWayland et envoie un vrai Ctrl+V que
       Discord comprend (mais ne marche PAS pour les apps natives Wayland).
     - Gotcha focus en config **Lua** : `hyprctl dispatch focuswindow` est interprété comme du lua et
       ÉCHOUE → bonne forme : `hyprctl dispatch 'hl.dsp.focus({ window = "address:0x..." })'`.
     - L'île est un layer-shell persistant → relâcher le grab Exclusive ne rend pas le focus tout seul ;
       on re-focalise explicitement la fenêtre active (qui reste l'« activewindow » même pendant le grab).
  - **Tentative xdotool (échec)** : `xdotool key ctrl+v` colle bien dans Discord en test MANUEL (focus X
     stable), mais dans le flux du picker — juste après le relâchement du grab clavier de l'île — le
     **modificateur Ctrl du Ctrl+V synthétique ne s'enregistre pas** (les touches simples passent : un
     `xdotool type 'Q'` apparaît, mais le combo Ctrl+V no-op). Curiosité : la séquence `type 'Q'` +
     keydown/keyup ctrl+v + `type 'R'` collait (`Q🚀R`), mais impossible à reproduire proprement (un
     warmup `key shift` ne suffit pas, un `type` de caractère oui mais laisse une trace). Bridge clipboard
     XWayland lent aussi (restaurer < 2 s écrase avant lecture). Abandonné comme non fiable.
  - **Solution finale RETENUE (fiable)** — `insertText()` : ferme l'île → re-focalise (`hl.dsp.focus`) →
     si la fenêtre est **native Wayland** (`! grep 'xwayland: 1'`) : `wtype "<emoji>"` (vrai auto-insert,
     sans presse-papier) ; si **XWayland** (Discord, ...) : `wl-copy` l'emoji → **l'utilisateur fait
     Ctrl+V** (son collage manuel marche à 100 %). Pas d'auto-paste forcé dans XWayland (non atteignable
     de façon fiable avec wtype/ydotool/xdotool ici). `xdotool` + `programs.ydotool.enable` restent dans
     le nix-config mais ne sont **plus utilisés** par le code (inoffensifs ; à retirer si on veut).
  - TODO éventuel : reprendre l'auto-paste XWayland (la séquence `type` + ctrl+v marche par moments) —
     ou tester un `ydotool`/`wtype` sur compositeur sans XWayland.
  - ⚠️ Test headless impossible dans cette session : le focus clavier seat reste sur le terminal
    Claude Code (multi-écran), donc les `wtype` de test fuient dans l'input Claude au lieu de la
    cible. À VÉRIFIER côté user : `mainMod + semicolon` dans un vrai champ.
  - Keybind : `mainMod + semicolon` (dotfiles `hyprland.lua`, style Win+;).
- **Récents** : `FileView` (Quickshell.Io) → `~/.local/state/DankMaterialShell/island-emoji-recents.json`
  (`setText(JSON.stringify(...))`, cap 36, dédupe). ⚠️ `StandardPaths` vient de `import QtCore` (pas
  Quickshell). `onLoadFailed` → `recents=[]` (1er lancement, warning "file does not exist" bénin).
- **Nav clavier** : `selIndex` + `move(dx,dy)` (2D, `columns = floor(gridWidth/cell)`, clamp +
  auto-scroll). `DankTextField` avec `ignoreUpDownKeys` + `ignoreLeftRightKeys` + `keyForwardTargets:
  [navHandler]` → les 4 flèches pilotent la grille, Enter copie le sélectionné, Esc revient au hub.
- Entrées : 6e icône footer du hub (`mood`, footer passé `/5`→`/6`) ET `dms ipc call island open emoji`
  (keybind). Ajouté à la condition keyboardFocus Exclusive (apps|clipboard|emoji) et à `viewHeight`.
- Vérifié par capture : ouverture via IPC, recherche « fire » → 🔥, Enter copie (presse-papier = 🔥,
  récents = `["🔥"]`), toast + repli, nav 2D « face » déplace la sélection.

## Bannières de notification macOS (refonte complète, 2026-06-02)

Le mode "notif" du pill (style iPhone Dynamic Island) est **retiré**. Les notifications suivent
désormais le modèle **macOS** : des **bannières indépendantes en haut-droite**, stylées comme l'île,
qui n'interrompent JAMAIS l'interaction en cours.
- **`bannerArea`** (refonte deck, 2026-06-02) : `Item` top-right + `Repeater` (model `popups`) à
  positionnement ABSOLU (plus de ListView). Rang `r = n-1-index` (0 = newest, en haut, z le plus
  haut). **Collapse system** : `collapsed = n>1 && !expanded` ; `expanded = areaHover.hovered`.
  - Collapsé : deck — newest plein, cartes derrière à `y = min(r,2)*peek(9)`, `scale 1-min(r,2)*0.05`,
    opacity 0 si r≥3 ; chip compteur « +N » en bas-droite.
  - Déplié (survol) : spread vertical, `y = spreadY` (cumul des hauteurs via `hmap` index→hauteur,
    `setH`/`cardH`), gap 10. Hauteur du conteneur animée (collapsedH ↔ expandedH).
  - Carte raffinée : radius 24, padding 16, icône 46, eyebrow app + heure (baseline-aligné, time à
    droite), titre fontSizeMedium 1 ligne élidée, corps fontSizeSmall 2 lignes élidées (lineHeight
    1.15), chips d'action arrondis, ✕ au survol. Glass + shadow (rouge si critique).
  - Auto-dismiss 5 s (pause si `areaHover.hovered`), critique persiste, swipe-droite>90 = dismiss,
    tap = action default (ou déplie le deck si collapsé). MouseArea `enabled: bWrap.active` (seule la
    carte du dessus interactive en collapsé). GOTCHA : pas de bloc JS multi-instruction dans `text:`.
- **Carte bannière** (île visuelle) : radius 22, `islandColor`, bordure (ROUGE si critique), overlay
  verre (sheen + inner-shadow), MultiEffect shadow (glow rouge si critique), hover-lift, icône
  (image `cache:false` + fallback cloche), eyebrow app + `timeStr`, summary, body (2 lignes),
  chips d'action (exclut "default", cap 3, press-scale), ✕ au survol.
- **Auto-dismiss** 5 s par carte (Timer), **critique = persiste**, **pause au survol**. **Swipe
  droite > 80px = dismiss** ; **tap = action default**. `modelData.popup = false` retire la carte
  (→ transition remove).
- **Masque d'input** : `Region { Region{pill/stage} ; Region{bannerList} }` (UNION) — les boutons
  des bannières sont cliquables, le reste reste click-through.
- **DMS natif supprimé** : `NotificationPopupManager` Variants gated par `!dynamicIslandEnabled`
  dans DMSShell (sinon double notif — bas-droite DMS + haut-droite île).
- Code mort retiré : bloc visuel NOTIF du pill (~184 lignes), ledge stack, `settle()` simplifié,
  `pendingPopup`/`engaged` supprimés. (Restent inertes/inoffensifs : `showNotif`/`notifTimer`/
  `notifActions`/`notifCritical` + refs `mode==="notif"` jamais atteintes.)
Vérifié par capture : bannières haut-droite, île non hijackée, chips/✕/swipe OK.

## Enhancements UI/UX batch (fait 2026-06-02) — 5 features

Suite à une session de propositions (10 enhancements Apple/macOS), 5 retenus & implémentés :
1. **Glow de bord d'écran sur notif** — `NotificationEdgeGlow.qml` (composant overlay dans `stage`,
   HORS masque input → passthrough). Dégradés sur les 4 bords, pulse (220 ms↑ / 1100 ms↓) à chaque
   NOUVEAU popup. Accent, ou ROUGE si critique. Déclencheur : `onPopupsChanged` dans le contrôleur
   (compare `popups.length` à `_popupCount`), gated `isFocusedScreen` + `!doNotDisturb`. Vérifié en
   figeant `pulse:1`.
2. **Tick volume macOS** — `WheelHandler.onWheel` appelle `AudioService.playVolumeChangeSoundIfEnabled()`.
   ⚠️ Les sons notif/batterie sont DÉJÀ câblés côté service (`NotificationService:707`,
   `BatteryService:115`) → ne pas les redoubler depuis l'île.
3. **Live Activities** (réutilise le splash presenter via `showSplash`) : **charge** plug/unplug
   (`onChargingChanged` → "Charging • N%") et **Focus/DND** (`Connections` sur `SessionData.doNotDisturb`).
   ⚠️ PAS de power-profile : `PowerProfileOSD` DMS n'est PAS gated par `dynamicIslandEnabled` dans
   DMSShell (~ligne 1293) → il s'affiche déjà, doublon évité. (Volume/Media/Brightness OSD, eux, SONT
   gated `dynamicIslandEnabled ? [] : …`.)
4. **Pop tactile au hover-expand** — `bump()` quand l'île se déplie de compact/chip au survol.
5. **Drill-down Calendrier** — `panels/CalendarPanel.qml` (`panelView="calendar"`, id `calCol`) : grille
   du mois Monday-first, today/sélection surlignés, dots d'events, nav mois, bouton "Today", agenda du
   jour sélectionné. Events via `CalendarService` (backend `khal` ; agenda vide si khal absent).
   Entrée : 5e icône footer du hub (`calendar_month`, footer passé `/4`→`/5`). Câblé dans `viewHeight`.

Restants des 10 proposés (non faits) : navigation clavier du Control Center, gestes média swipe-to-skip,
notifications groupées par app, pill squircle (courbure continue), accent adaptatif depuis la pochette
(nécessite une extraction de couleur — aucune dans le repo).

## Boutons d'option (lock / settings / power) — fait 2026-06-03

Intégrés dans le **hub** (mode expanded) avec un design « title bar » macOS original.
- **Header du hub** (`ControlCenterPanel.qml`, en tête de `ccColumn`, AVANT les tuiles) : à gauche
  l'**avatar** (`DankCircularImage`, `PortalService.profileImage`, fallback `person`) + nom
  (`UserInfoService.fullName||username`) + sous-titre « Control Center » ; à droite **3 boutons orbe**
  circulaires (36px, radius 18) frostés : `lock`, `settings`, `power`. Hover = fill teinté + ring
  (`border` accent ; **rouge `Theme.error`** pour power), icône recolorée, press-scale 0.88. ToolTips.
- **Actions** : `lock` → `island.closeIsland()` + `IdleService.lockRequested()` (chemin lock canonique
  DMS, cf. DMSShell:109) ; `settings` → `island.closeIsland()` + `PopoutService.openSettings()`
  (modal Réglages DMS = « réglages de l'OS ») ; `power` → drill-in `panelView="power"`.
- **Helper contrôleur** `closeIsland()` (près de `settle()`) : `panelView="controls"; pinned=false;
  mode=restMode()` — force le repli même si le pointeur est encore sur l'île (settle() ne replierait
  pas car `hovered`). Utilisé par les orbes lock/settings et par chaque action du PowerPanel.
- **Vue Power** (`panels/PowerPanel.qml`, id `powerCol`, `panelView="power"`) : header back + « Power » ;
  2 grandes tuiles (Lock / Sleep) puis 3 lignes pleine largeur (Log Out / Restart / Shut Down,
  les 2 destructives teintées `Theme.error` au survol). Actions = `IdleService.lockRequested()`,
  `SessionService.suspend/logout/reboot/poweroff()` ; chaque clic `closeIsland()` d'abord.
  Instanciée dans `ControlCenterPanel` + câblée dans `viewHeight`. Accessible aussi par
  `dms ipc call island open power` (pas de whitelist IPC → marche d'office).
- Vérifié : restart sans erreur QML, `open controls`/`open power`/`back` OK, zéro binding loop/TypeError.
  ⚠️ Capture d'écran impossible cette session (ni grim/grimblast, spectacle headless échoue).
- **« All Settings » retiré (2026-06-03)** : l'orbe Settings + les vues île-natives couvrent tout, donc
  le 6e icône footer `tune`→`control` (qui ouvrait le **Control Center natif DMS** en popout) est
  supprimé. Footer repassé `/6`→`/5` (apps/notifications/calendar/emoji/clipboard), `onClicked`
  simplifié en `island.panelView = modelData.which` (toutes les surfaces sont des drill views).
  La fonction `openMenu()` du contrôleur — devenue **sans aucun appelant** — est supprimée (le seul
  popout DMS restant accessible depuis l'île est désormais la **modal Réglages** via l'orbe Settings).

## Audit complet + Phase 0/2 (fait 2026-06-10)

Audit d'ingénierie complet dans **`ISLAND_AUDIT.md`** (~70 findings cités fichier:ligne,
scorecard, gap-analysis macOS/Win11, roadmap 4 phases). Correctifs appliqués et **vérifiés
live** (restart + journal propre + smoke tests IPC + notifs gdbus + OSD wpctl) :

**Phase 0 (bugs)** :
1. **Wi-Fi mot de passe ENFIN saisissable** : `island.wifiNeedsKeyboard` (posé par WifiPanel quand
   un prompt est ouvert via `pwSsid`) étend le grab `keyboardFocus` — "wifi" manquait dans `_kbViews`.
   + Enter submit (`onAccepted`), `forceActiveFocus()`, champ vidé au repli, prompt exclusif (1 SSID).
2. **PowerPanel** : logout/reboot/poweroff = **2e clic de confirmation** (3 s, ligne rouge « Click
   again to confirm ») respectant `SettingsData.powerActionConfirm`. Lock/Sleep restent directs.
3. **Bannières** : Timer local 5000 ms SUPPRIMÉ → le **timer du service** (respecte
   `notificationTimeout*`, critique persistant) est pausé/relancé au hover du deck.
   Modèle **`ScriptModel`** (diff par identité → délégués stables, fin du ReferenceError modelData
   du journal). ⚠️ `values` exige un **vrai tableau JS** (pas une QQmlListReference) → `items`
   matérialisé via boucle. Fix binding `expanded` écrasé → `pinnedOpen` séparé (réinit à n=0).
4. **État mort "notif" purgé** du contrôleur (showNotif/notifTimer/notifActions/notifCritical/
   defaultAction + branches pillW/pillH/glowActive/alertBorder/hover). `onPlayingChanged` n'éjecte
   plus le mode **expanded**.
5. **IPC `open` whitelisté** (`IslandHub.views`, source unique) → `ISLAND_ERROR:unknown-view:…`.
6. Spotlight : `move()` clampé aux **24 lignes rendues** (sélection ne sort plus de l'écran).
7. EmojiData : cricket 🏏 (chaîne Unicode invalide U+FFFD+surrogate) réparé, doublon 😅 retiré.
8. Art « Now Playing » (hub + MediaPane) : fallback lié à `Image.status` (plus de boîte vide sur
   tmp file Chrome disparu — erreur vue au journal), `cache:false; asynchronous:true`.

**Phase 2 (parité macOS, batch 1)** :
9. **OSD interactif segmenté** : PresenterPane = **16 crans** macOS ; **clic icône = mute** (volume) ;
   **drag sur la barre** règle volume/luminosité (`DisplayService.setBrightness(v,"",true)`) ;
   `island.holdPresenter()` maintient l'OSD pendant l'interaction ; `bump()` seulement à la
   1re apparition (plus de pulse à chaque cran) ; volume muted affiche **« Muted »** (plus « 0% »).
10. **Wi-Fi états transitoires** : spinner `sync` rotatif + « Connecting… » par ligne
    (`connectingSSID`), **erreur inline** rouge sur le réseau qui a échoué (`lastConnectionError`
    attribué via `lastTriedSsid`), réouverture du prompt sur `passwordDialogShouldReopen` (plus de
    modal global par-dessus l'île), garde anti double-clic, `NetworkService.addRef()/removeRef()`
    + scan à l'activation (le chemin IPC `open wifi` scanne enfin).
11. **Bluetooth** : sous-titre **« Connecting…/Disconnecting… »** (`BluetoothDeviceState`, import
    `Quickshell.Bluetooth`), icône sync rotative, ligne désactivée pendant la transition ;
    « Available » vidée quand `!discovering` (fin des appareils fantômes).
12. **Transport média statique** (MediaPane + hub) : `model: ["prev","play","next"]` + bindings
    dans le délégué — les boutons survivent au play/pause (fin du churn destroy/recreate).
13. Quick wins : calendrier **localisé** (premier jour + noms de jours `Qt.locale()`, init
    `new Date()`, `isToday` réactif à minuit via `clockShort`) ; trackBar masquée si flux sans durée ;
    timestamps `visible: opacity>0` ; `Theme.getBatteryIcon` (presenter + compact) ; mic **orange** /
    caméra **verte** (langage iOS) ; horloge idle cliquable → drill calendar ; `I18n.tr("Unknown")`.

**Phase 1 (même jour, 2e commit) — lazy-loading & modèles stables** :
14. **Les 12 drill-views sont LAZY** : `ControlCenterPanel` remplace les 12 instances eager par un
    **registre** `viewRegistry` (panelView → Component) + un **Loader unique** (`drillLoader`).
    `viewHeight` = ternaire à 3 branches (hub / loader.item / fallback). Transition d'entrée
    générique (fade + slide 24px) via `drillEnter` — l'animation d'entrée interne des panels ne
    joue plus (ils naissent avec leur binding déjà actif). ⚠️ **GOTCHA Loader** : la propriété par
    défaut d'un Loader est `sourceComponent` → ne JAMAIS déclarer un enfant (animation…) dans le
    Loader ; le `ParallelAnimation` vit à côté. ⚠️ **GOTCHA activation** : un panel chargé naît
    `visible: true` → `onVisibleChanged` ne tire PAS ; chaque panel à hook d'activation
    (Spotlight/Clipboard/Emoji/Wallpaper/Calendar) a maintenant un `Component.onCompleted: if
    (visible) …` équivalent (refresh/focus/reset). WallpaperPanel n'énumère plus le dossier au
    boot (c'était par moniteur !). BluetoothPanel stoppe la discovery en `Component.onDestruction`.
15. **Modèles stables** : listes BT paired/available en **`ScriptModel { objectProp: "address" }`**
    (les ticks RSSI mettent à jour les délégués EN PLACE) ; Repeaters workspaces/tray de l'IdlePane
    **gated par `visible`** (zéro churn au repos) ; icônes tray **réparées** (helper
    `trayIconSourceFor` répliqué de SystemTrayBar : réécriture `?path=` des SNI Electron/Spotify)
    + fallback `DankIcon` sur le status réel.
16. **Clipboard pilotable au clavier** (il tient un grab Exclusive !) : ↑/↓ + Enter copie + Esc,
    surlignage de sélection (bord accent), hover synchronise `selIndex` — motif Spotlight.
17. **NotificationsPanel** : clic = action **`default`** (plus jamais `actions[0]` aveugle) ;
    `appIcon` nom-de-thème résolu via `Quickshell.iconPath` (au lieu d'échouer en silence dans
    `Image.source`) ; `sourceSize 76×76` (plus de décodage 4K pour une case de 38px).

Vérifié live : cycle IPC des 12 vues ×2 restarts, notifs, journal 100% propre.
⚠️ À sanity-checker à la main (non testable headless) : la saisie clavier dans apps/clipboard/
emoji/wallpaper après le passage au Loader (le `forceActiveFocus` part de `Component.onCompleted`
désormais), et le champ mot de passe Wi-Fi.

**Phase 1 finale (même jour, 3e commit) — ÉCLATEMENT DE LA FENÊTRE PLEIN ÉCRAN** :
18. La racine de `DynamicIsland.qml` est passée de `PanelWindow` (fullscreen permanent par
    moniteur) à **`Scope`** possédant **4 surfaces layer-shell indépendantes** :
    - **`pillWindow`** (`dms:dynamic-island`) : bande haute **1920×620 fixe** (resize d'une layer
      surface à chaque frame de spring = storm de configures → hauteur fixe), anchors
      top+left+right, mask = pill seul, `visible: pill.opacity > 0` → **DÉMAPPÉE entièrement**
      quand le pill est suppressed (fullscreen) → **direct scanout restauré**. Porte le
      `keyboardFocus` (dérivé de `root._kbViews`/`wifiNeedsKeyboard`).
    - **`bannerWindow`** (`-banners`) : 440×720 top-right, `visible: isFocusedScreen && popups>0`,
      mask = `Region { item: notifBanners }`. Mappée seulement pendant des popups (vérifié).
    - **`scrimWindow`** (`-scrim`) : fullscreen, `visible: mode === "expanded"` seulement.
      ⚠️ GOTCHA : une surface fraîchement mappée arrive AU-DESSUS de sa layer → le scrim couvre le
      pill ; son mask **soustrait** (`Intersection.Subtract`) les rects du pill ET du deck de
      bannières pour laisser passer leurs clics. Clic ailleurs = dismiss.
    - **`glowWindow`** (`-glow`) : fullscreen, `visible: edgeGlow.pulse > 0` (~2 s), mask vide
      (click-through total). ⚠️ Sur la layer **Top** (pas Overlay) : sinon, remappée à chaque
      pulse, elle peinturerait son dégradé PAR-DESSUS l'île/bannières.
    - `QsMenuAnchor.anchor.window: pillWindow` ; le scrim MouseArea in-stage et le mask union
      d'avant sont supprimés.
    **Vérifié par `hyprctl layers`** : au repos = 2 bandes 1920×620 SEULEMENT (avant : 2 fullscreen
    1080 permanents) ; expanded → scrim mappé sur l'écran focus puis démappé ; notif → glow+banners
    mappés ~5 s puis démappés ; **fullscreen → le pill de l'écran passe de mappé à DÉMAPPÉ** puis
    revient. Zéro erreur QML.

**Phase 2 suite (même jour, 4e commit) — bannières GROUPÉES par app + INLINE REPLY** :
19. `NotificationBanners` consomme **`NotificationService.groupedPopups`** (une carte par app,
    `ScriptModel { objectProp: "key" }`) : la carte montre `latestNotification` + **badge « ×N »**
    dans l'eyebrow ; ✕ et swipe-droite **effacent le groupe entier** ; tap = action default de la
    plus récente. ⚠️ `groupedPopups` est trié **newest-first** → le rang du deck est `r = index`
    (les popups bruts étaient oldest-first avec `r = n-1-index`).
20. **Inline reply** (le DMS natif ne l'implémente NULLE PART — l'île le dépasse ici) : chip
    « Reply » quand `topNotif.notification.hasInlineReply` (le serveur déclare
    `inlineReplySupported: true`) → champ inline dans la carte → Enter/bouton =
    `notification.sendInlineReply(text)` + dismiss. **Grab clavier** : `bannerWindow` passe
    `keyboardFocus: Exclusive` tant que `notifBanners.needsKeyboard` (replyKey ≠ "") ; Esc ferme
    (keyForwardTargets). Pendant la saisie : timers du groupe stoppés, deck maintenu déplié
    (`expanded` inclut `replyKey !== ""`), et `onReplyKeyChanged` relance les timers si le pointeur
    est déjà dehors. `syncTimers(stop)` factorise hover-pause/resume sur TOUTES les notifs des
    groupes.
21. ⚠️ **GOTCHA z-order corrigé** : `bArea` (tap/swipe plein-carte) était déclaré APRÈS `bCol` →
    au-dessus → il volait les clics des chips/du champ. Passé `z: -1` : les enfants interactifs
    (chips, reply, send) reçoivent leurs clics, le corps inerte tombe sur tap/swipe.
    + icônes bannières : résolution `Quickshell.iconPath` des noms de thème + `sourceSize 92`.
    Testé : 2 notifs « Messages » groupées + 1 « Mail », zéro erreur QML, fenêtre bannières
    mappée/démappée proprement. ⚠️ Rendu visuel du badge ×N et du champ reply à sanity-checker
    à l'œil (pas de capture possible headless).

**Sprint final (même jour, 5e commit) — Spotlight riche, gestes, mixer par app** :
22. **Spotlight multi-providers** (`SpotlightPanel` réécrit) : la liste unifiée mêle
    **apps** (service + fuzzy subsequence, inchangé), **calculatrice inline** (`tryCalc` :
    whitelist regex `[0-9+\-*/%^().,\s]` puis `Function("use strict"...)` — aucune identifiant ne
    peut passer la regex ; `=2*3` ou `23*48` direct ; Enter = copie wl-copy + toast),
    **actions d'apps** (`AppSearchService.searchAppActions`, lancées via
    `SessionService.launchDesktopAction(parentApp, actionData)`, cap 3) et **presse-papiers**
    (`ClipboardService.getLauncherEntries(q, 4, 2)`, clic = copyEntry). Rows typées
    `{kind: "calc"|"app"|"action"|"clip"}` + badge de source à droite ; nav clavier inchangée.
    ⚠️ **Recherche de FICHIERS non branchée** : le backend DMS est `dsearch`, ABSENT de cette
    machine (`DSearchService.dsearchAvailable=false`) — à brancher si dsearch est installé un jour.
23. **Gestes signature** : `TapHandler.onLongPressed` sur le pill (touch : chip→media,
    compact/idle→expanded — à la souris le hover a déjà fait la transition) ; clic pochette
    MediaPane = **`player.raise()`** (ouvre l'app, gardé `canRaise`) + closeIsland ; tap pochette
    chip = play/pause ; **molette sur le scrubber = seek ±5 s** (le WheelHandler volume du pill
    se désengage via `island.seekHover`, posé par seekArea.containsMouse, reset à la sortie du
    mode media).
24. **Mixer par application** (`panels/MixerPanel.qml`, panelView `"mixer"`) — Win11 l'a, macOS
    NON : une carte par stream de lecture Pipewire (`Pipewire.nodes` filtré
    `audio && isSink && isStream`, pattern du AudioOutputDetail natif), nom
    (`AudioService.displayName`) + `media.name`, slider volume + mute par stream.
    ⚠️ **`PwObjectTracker { objects: streams }` local OBLIGATOIRE** (celui d'AudioService exclut
    les streams → sans lui, volume/mute ne sont pas liés). Entrées : bouton `tune` à côté du
    slider volume du hub (slider rétréci à width-120) + `dms ipc call island open mixer`.
    Câblé : viewRegistry + whitelist IPC + commentaire panelView.
    Vérifié : apps/mixer/audio/controls s'ouvrent par IPC, zéro erreur QML. À sanity-checker à
    l'œil : la calculatrice (`=2*3` + Enter), une action d'app (« private »), le mixer avec un
    média en lecture.

Restent dans la roadmap (ISLAND_AUDIT.md §7) : IslandState typé, virtualisation ListView/GridView,
NotchVisual en Shape CurveRenderer, recherche de fichiers Spotlight (si dsearch installé),
a11y/Échap universel, Phase 3 (Live Activities, emoji v2, squircle/accent adaptatif).

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
