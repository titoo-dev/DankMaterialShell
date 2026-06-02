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
- **Vue Bluetooth** (`btCol`, panelView "bluetooth", drill depuis la tuile BT) : header back + titre
  + switch radio (`adapter.enabled`) ; liste `BluetoothService.pairedDevices` (icône
  `getDeviceIcon`, nom, Connected/Disconnected + batterie%, ✓/+ ) ; tap → `connectDeviceWithTrust` /
  `device.disconnect()` ; discovery activée à l'entrée. État vide « Bluetooth is off / No devices ».
- **Vue Audio/Output** (`audioCol`, panelView "audio", drill depuis le bouton 🔊 à droite du slider
  volume) : header back + « Output » ; liste `AudioService.typedSinks` (icône, `description`, ✓ si
  courant via `sink.name`) ; tap → `AudioService.setSink(node)`. Vérifié par capture.
- **Vue Notifications** (`notifCol`, panelView "notifications") : header back + titre + « Clear all »
  (`clearAllNotifications`) ; liste scrollable (Flickable adaptatif cap 300) de
  `NotificationService.notifications` (NotifWrapper : appName/summary/body/cleanImage/appIcon/
  timeStr/actions) ; chaque ligne = icône (image cache:false + fallback cloche sur `status`),
  eyebrow app + `timeStr`, titre, corps, ✕ dismiss au survol (`dismissNotification`) ; tap ligne =
  invoque l'action par défaut si présente. Entrées : footer hub (icône notifs) + clic-corps d'une
  notif active (`openPanel("notifications")`). Vérifié par capture (3 notifs listées). Remplace le
  centre de notif DMS dans le flux île.
- Drill-views île-natives COMPLÈTES : **Wi-Fi, Bluetooth, Audio, Notifications**. Le footer du hub
  n'ouvre plus de popouts DMS que pour apps (spotlight), presse-papier et « réglages complets »
  (surfaces app/launcher, pas des panneaux de connectivité — hors périmètre d'unification).

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
