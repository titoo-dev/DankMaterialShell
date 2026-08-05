# Dynamic Island — Audit système complet (2026-06-10)

> **MISE À JOUR (même jour)** : la Phase 0 entière, les quick wins et le batch 1 de la Phase 2
> (OSD interactif segmenté, états transitoires Wi-Fi/BT, transport statique) sont **implémentés
> et vérifiés live** (journal propre, smoke tests IPC, notifs, OSD). Détail dans
> `ISLAND_HANDOFF.md` § « Audit complet + Phase 0/2 ». Les findings C1-C3, C5, H1-H3, H6 (partiel),
> H7 (partiel), H8, H9, H11, **H13 (fenêtre plein écran éclatée en 4 surfaces — vérifié par
> `hyprctl layers`)**, H14 (12 panels lazy via registre+Loader), H15, H17, H18 et 2.1/2.2 sont
> donc **réglés** ; C4 (défaut `dynamicIslandEnabled`) est conservé volontairement sur ce fork
> personnel (concerne une éventuelle distribution).

> **MISE À JOUR (2026-07-04)** — session « solde de l'audit », tout vérifié live :
>
> **Réglés ce jour** :
> - **H10** : script d'insertion emoji/texte portable — `focuswindow` stock avec fallback
>   `hl.dsp.focus` (fork lua), bloc hyprctl entièrement sauté hors Hyprland (niri rend le
>   focus tout seul à la chute du grab).
> - **H12** : l'ouverture sur l'écran focalisé replie toute île épinglée d'un autre écran ;
>   `island close` replie TOUS les écrans.
> - **H4 (reste)** : ClipboardPanel tient un `Ref { service: ClipboardService }` (liste live) ;
>   nav clavier déjà en place. **H5** était déjà réglé (rates réactifs).
> - **hmap bannières** par clé de groupe (plus de décalage à la fermeture du milieu) ;
>   **edge glow** par identité du popup le plus récent (éviction+ajout même tick couvert) ;
>   **eventsRev** calendrier lié à l'identité de l'objet ; **ring du chip** snap au rewind
>   au lieu de 900 ms à rebours ; batterie idle via `Theme.getBatteryIcon` ; largeur presenter
>   partagée (`presenterW`) ; reveal du mdp Wi-Fi ; « Click to pair ».
> - **Échap universel** : grab clavier étendu à TOUTE vue expanded (l'île est déjà modale via
>   le scrim) + catcher d'Échap au niveau du stage → drill → hub → fermé, partout. `_kbViews`
>   supprimé (les champs de recherche gardent la priorité de focus).
>   *(2026-07-26 : Échap ne fait plus l'escalier — il **ferme l'île d'un coup** depuis
>   n'importe quelle vue, via `closeIsland()`. Le pas-à-pas reste sur `ipc call island back`.)*
> - **DrillHeader.qml partagé** (back 44 px + titre + slot trailing, a11y intégrée) — 11 panels
>   migrés ; Spotlight/Emoji/Clipboard (header champ de recherche), Shelf (titre empilé) et
>   Tailscale (icône de statut) gardent leur header spécifique, volontairement.
> - **Perf** : Notifications & Clipboard en `ListView reuseItems`, Emoji en `GridView` (+
>   FileView async + debounce 120 ms) ; ombre MultiEffect par carte de bannière remplacée par
>   le liseré (langage capsule, plus de FBO par carte) ; timer 1 s du MediaPane dédupliqué sur
>   `island.mediaTick`. Wi-Fi garde volontairement son Repeater (liste courte + prompt mdp
>   stateful que le pooling détruirait).
> - **Wi-Fi 802.1X** : champ identité inline (le service acceptait déjà `username`).
> - **A11y** : passe `Accessible.name/role/onPressAction` sur les contrôles interactifs du
>   module, cibles élargies à ~44 px via marges de MouseArea, reduced-motion (`animationSpeed
>   = None`) respecté par les springs/squash/bump de l'île.
> - **Cohérence OSD** : la totalité des OSD système passe par l'île en mode island — kind
>   « mic » (barre + mute), splashes pour Caps Lock / keep-awake / power profile / sortie
>   audio ; MediaVolume/MediaPlayback gatés (l'état lecture vit déjà dans le chip).
> - `island-blur.conf` : doc d'installation agnostique du chemin. Fix connexe hors module :
>   `Theme.error` dynamique suivait toujours le ton dark (privacy/power/critiques illisibles
>   en clair) — corrigé via `getMatugenColor`.
>
> **Différés, avec raison** :
> - **IslandState typé / god-object** : refactor invasif sur ~28 fichiers pour un gain surtout
>   testabilité — pas de bug concret associé ; à faire si le module doit être partagé upstream.
> - **Duplication avec les popouts DMS natifs** (2 control centers…) : choix assumé du fork.
> - **Virtualisation Wi-Fi** (voir ci-dessus), **EQ 5/6 valeurs** (cosmétique), fallback
>   `screens[0]` (uniquement quand le compositeur ne rapporte aucun focus), presenter
>   interactif ≠ click-through (choix design : l'OSD de l'île est manipulable).
> - **Spotlight riche / mixer par app / squircle** : Phase 3, features nouvelles
>   hors périmètre « correctifs ».

> **MISE À JOUR (2026-07-26)** — **la feature emoji est SUPPRIMÉE** : `EmojiPanel.qml`,
> `EmojiData.js`, la vue drill `emoji`, l'IPC `island type` et tout le chemin d'insertion
> wtype/wl-copy sont partis (plus le plugin d'exemple `ExampleEmojiPlugin`). Les findings
> **H9, H10** et l'item de roadmap « Emoji v2 » sont donc **sans objet** ; ils restent listés
> plus bas comme trace de l'audit d'origine.

Audit d'ingénierie de `Modules/DynamicIsland/` (branche `feat/dynamic-island`, ~5 080 lignes,
30 fichiers) : correctness, performance, architecture, UX, accessibilité — avec gap-analysis
vs macOS / Windows 11 et roadmap pour atteindre puis dépasser ce niveau.

Méthode : lecture intégrale du module + contrôleur, comparaison aux modules DMS natifs
(ControlCenter, NotificationCenter, DankLauncherV2, Clipboard), inspection du journal runtime
(`dms.service`, instance live), vérification croisée de chaque finding critique.

---

## 1. Synthèse exécutive

L'île est **fonctionnelle et déjà riche** (7 modes, 13 drill-views, bannières macOS, IPC,
multi-compositeur). Le travail accompli est réel. Mais elle n'est pas encore « digne d'un
macOS » : ce qui sépare un bon prototype d'un produit Apple, ce sont **les états transitoires
(connexion en cours, erreurs), la cohérence clavier/accessibilité, la discipline de
performance, et la profondeur de chaque surface**. C'est exactement là que se concentrent les
findings.

### Scorecard

| Axe | Note | Constat |
|---|---|---|
| Couverture fonctionnelle | 7/10 | Surfaces nombreuses, mais chacune ~60 % de la profondeur macOS/Win11 |
| Feedback & états UX | 4/10 | Quasi aucun état « en cours / échec » ; actions destructives sans confirmation |
| Performance | 4/10 | Fenêtre fullscreen Overlay permanente ×2 écrans, 12 panels eager, Repeaters non stables, Canvas CPU |
| Robustesse | 5/10 | 2 erreurs runtime live au journal, code mort branché, courses d'état multi-écrans |
| Accessibilité | 1/10 | Zéro `Accessible.*`, Échap inopérant sur la plupart des vues, cibles < 44 px |
| i18n | 6/10 | I18n.tr majoritaire mais trous (« Unknown », « Mo Tu We », « now »), calendrier non localisé |
| Architecture | 5/10 | Modularisation faite, mais god-object `island`, registre de vues dupliqué ×4, duplication avec DMS natif |

### Les 5 chiffres à retenir

- **1 fonctionnalité morte** : se connecter à un Wi-Fi sécurisé non sauvegardé est
  **impossible** (le champ mot de passe ne reçoit jamais le clavier).
- **1 risque utilisateur** : Shut Down / Restart s'exécutent **au simple clic**, sans
  confirmation, en ignorant `powerActionConfirm` (true par défaut).
- **2 erreurs runtime** confirmées au journal de l'instance en prod.
- **24 fenêtres de contenu** instanciées en permanence (12 drill-views × 2 écrans) même île
  fermée.
- **0 attribut d'accessibilité** dans tout le module (~40 contrôles interactifs invisibles
  aux lecteurs d'écran et au clavier).

---

## 2. Bugs confirmés en production (journal `dms.service`)

### 2.1 `NotificationBanners.qml[222]: ReferenceError: modelData is not defined` *(observé 09:16:55, ×2)*
Le deck de bannières est un `Repeater { model: bannerArea.items }` où `items` est un tableau JS
refiltré à chaque changement de `popups` → **tous les délégués sont détruits/recréés** à chaque
ajout/retrait. Un handler (release/timer) qui se déclenche pendant le teardown perd son contexte
→ `modelData` n'existe plus. Même cause : animations qui repartent de zéro, état de swipe perdu,
textures MultiEffect recréées.
**Fix** : modèle stable (`ScriptModel { objectProp }` ou `NotificationService.visibleNotifications`),
et garder les handlers défensifs.

### 2.2 `ControlCenterPanel.qml[202]: Cannot open: file:///tmp/.com.google.Chrome.RZykiw`
La pochette « Now Playing » du hub pointe sur l'art MPRIS de Chrome, un fichier temp supprimé.
Le fallback `music_note` est lié à la **présence de l'URL** (`!trackArtUrl`), pas à l'état de
chargement → URL présente + chargement échoué = **case vide**. C'est la même classe de bug déjà
corrigée pour `notifImg` (cf. handoff « Notif image stale »).
**Fix** : `visible: art.status !== Image.Ready` sur le fallback (pattern déjà validé).

---

## 3. Findings critiques (P0)

### C1 — Le panneau Wi-Fi ne peut pas saisir de mot de passe
`DynamicIsland.qml:487` : `_kbViews = ["apps", "clipboard", "emoji", "wallpaper"]` — `"wifi"`
absent → `WlrLayershell.keyboardFocus = None` quand le champ `pwField` (WifiPanel.qml:137)
s'ouvre. Sous layer-shell Wayland, **aucun événement clavier n'atteint la surface** : le champ
s'affiche mais reste muet. La connexion à un réseau sécurisé non sauvegardé est impossible
depuis l'île.
**Fix** : exposer `island.wifiNeedsKeyboard` (vrai quand `pwOpen`), l'inclure dans la condition
du grab, `forceActiveFocus()` à l'ouverture, soumission sur Enter (`onAccepted`).

### C2 — Extinction sans confirmation
`PowerPanel.qml:98-100` : `SessionService.logout()/reboot()/poweroff()` au **simple clic**, en
ignorant `SettingsData.powerActionConfirm` (def. true) que le `PowerMenuModal` natif respecte
avec un hold-to-confirm. Le panneau s'ouvre sous le pointeur → un misclick éteint la machine.
**Fix** : respecter `powerActionConfirm` — hold-to-confirm (pattern natif réutilisable) ou
second clic « Confirmer ? » inline.

### C3 — Pipeline de timeout des bannières doublonné et faux
`NotificationBanners.qml:198-201` : Timer local **hardcodé 5000 ms** qui force `popup = false`,
en concurrence avec le timer du `NotificationService` qui respecte
`notificationTimeoutLow/Normal/Critical`. Conséquences : un timeout réglé à 10 s est tué à 5 s,
un timeout 0 (persistant) est tué à 5 s, et le « pause au survol » ne pause que le timer local —
**le timer du service dismisse la bannière en plein survol**.
**Fix** : supprimer le timer local ; piloter `modelData.timer` (stop au hover, restart à la
sortie), comme `NotificationPopup.qml:721`.

### C4 — Défaut `dynamicIslandEnabled: true` sans migration
`SettingsSpec.js:41` : tout utilisateur existant du fork qui met à jour **perd silencieusement
sa DankBar**. Aucune entrée de migration.
**Fix** : défaut `false` (opt-in) + activation guidée, ou migration qui ne l'active que sur
installation vierge.

### C5 — État mort `"notif"` encore branché en 6 endroits
`DynamicIsland.qml:301-323` : `showNotif()` n'a **aucun appelant** et référence `pendingPopup`,
propriété **jamais déclarée** → ReferenceError si jamais rappelé. Le mode `"notif"` reste câblé
dans `glowActive`, `pillW` (524/464), `pillH` (80), `alertBorder`, le HoverHandler et
`notifTimer` — un pill 524×80 **vide** si réactivé.
**Fix** : purger `showNotif`/`notifTimer`/`notifActions`/`notifCritical`/`defaultAction`(pill)
et toutes les branches `"notif"`.

---

## 4. Findings haute sévérité (P1)

### Correctness / état
| # | Localisation | Problème | Fix |
|---|---|---|---|
| H1 | `DynamicIsland.qml:267` | `onPlayingChanged` retombe en `restMode()` sans exclure `"expanded"` → **le Control Center se referme tout seul** quand une piste démarre/se met en pause (le clic-pour-étendre ne pin pas) | Ajouter `mode !== "expanded"` à la garde |
| H2 | `NotificationBanners.qml:23,218` | `expanded: areaHover.hovered` (binding) **écrasé** par `bannerArea.expanded = true` au tap → après le 1er tap, le deck reste déplié pour toujours | Propriété `pinnedOpen` séparée + `expanded: hovered \|\| pinnedOpen`, reset à `n === 0` |
| H3 | `SpotlightPanel.qml:73 vs 151` | `move()` clampe à `results.length-1` mais seuls 24 items sont rendus → sélection invisible, scroll hors bornes, **Enter lance une app non visible** | Clamper à `min(results.length, 24)-1` ou ListView virtualisée complète |
| H4 | `ClipboardPanel.qml` | Grab clavier **Exclusive** mais **zéro navigation** : ni ↑/↓, ni Enter ; et données stale (`refCount` du service jamais incrémenté → pas de live-update) | Répliquer le pattern nav de Spotlight ; `refCount++/--` sur visible |
| H5 | `SystemMonitorPanel.qml:143` | Sparkline réseau **figée** : `DgopService.networkHistory` est muté en place (`push/shift`) sans notify → évalué une seule fois | Dépendre de `networkRxRate/TxRate` ou réassigner l'objet dans DgopService |
| H6 | `WifiPanel.qml:122-152` | Aucun état « connexion en cours » ni erreur (`isConnecting`/`connectingSSID`/`lastConnectionError` inutilisés) ; mauvais mot de passe → **modal global par-dessus l'île** ; pas de garde anti double-clic | Spinner par ligne, erreur inline, réouverture du champ via `credentialsNeeded` |
| H7 | `BluetoothPanel.qml:147` | Connexion fire-and-forget : pas d'état `Connecting` (le natif l'affiche), pas d'erreur (casque éteint = silence) ; `pairingAddrs` sans timeout (spinner infini) ; devices fantômes après arrêt discovery | État `BluetoothDeviceState.Connecting`, timeout 30 s, vider « Available » quand `!discovering` |
| H8 | `IdlePane.qml:108` | Icônes tray **cassées** pour Spotify/Electron : la réécriture `?path=` de `SystemTrayBar.qml:48-66` n'est pas appliquée, aucun fallback | Extraire `trayIconSourceFor` en helper partagé + fallback `DankIcon` |
| H9 | `EmojiData.js:286` | Entrée cricket = `"�" + surrogate isolé` : **chaîne Unicode invalide, injectée telle quelle via wtype/wl-copy** si cliquée (+ doublon U+1F605 :28/:84) | `e: "🏏"` littéral ; dédupe |
| H10 | `DynamicIsland.qml:284-299` | `insertText()` 100 % Hyprland + dispatcher **Lua personnel** (`hl.dsp.focus`) → échec silencieux sur niri et Hyprland stock | Brancher par compositeur via `CompositorService` ; fallback wl-copy + toast explicite |
| H11 | `IslandHub.qml:52` | `open(view)` **sans whitelist** : `island open foo` → île étendue VIDE | Valider contre le registre des vues, `ISLAND_ERROR:unknown-view` |
| H12 | `DynamicIsland.qml:389-437` | Multi-écrans : une île épinglée-étendue sur l'écran A **capture tout l'input de A** quand le focus part sur B ; `close`/`toggle` IPC ne touchent que l'écran focalisé | Broadcast de fermeture aux instances non focalisées à l'ouverture d'une autre |

### Performance structurelle
| # | Localisation | Problème | Fix |
|---|---|---|---|
| H13 | `DynamicIsland.qml:498` | **Fenêtre Overlay PLEIN ÉCRAN par moniteur, mappée en permanence** : casse le direct scanout/unredirect (vidéo fullscreen) sur tous les écrans, tout le temps — coût GPU/batterie réel pour une pastille de 92×28 | Éclater : fenêtre pill dimensionnée au contenu + fenêtre bannières top-right + scrim plein écran **créé seulement en expanded** + glow éphémère |
| H14 | `ControlCenterPanel.qml:270-281` | **12 drill-views instanciées eager, par moniteur**, vivantes même île repliée (Repeaters de notifs/réseaux/emoji/calendrier évalués en arrière-plan ×2 écrans) | Un `Loader` piloté par `panelView` (map vue→Component) ; `viewHeight` lit `loader.item` |
| H15 | `MediaPane.qml:69-74` | Model JS du transport recalculé sur `playing/canGoNext/...` → les 3 boutons **détruits/recréés à chaque play/pause** (perte hover, flash) | 3 boutons statiques avec bindings internes |
| H16 | `NotchVisual.qml:9` | Canvas = raster **CPU** + upload texture à chaque frame des morphs spring (jusqu'à ~500×620, par moniteur) + MultiEffect par-dessus | `Shape { preferredRendererType: Shape.CurveRenderer }` (GPU, AA propre, gère les flares concaves) |
| H17 | `IdlePane.qml:25,100` | Repeaters workspaces/tray sur tableaux JS reconstruits à chaque événement compositor, **actifs même pane invisible** | Gater les models par `visible`, ou ScriptModel keyé |
| H18 | `BluetoothPanel.qml:22-27` | `availableDevices` re-trié à chaque tick RSSI → churn complet des délégués pendant la discovery | `ScriptModel { objectProp: "address" }` (pattern du natif `BluetoothDetail.qml:464`) |

---

## 5. Findings moyens (P2) — condensés

**Correctness**
- `NotificationsPanel.qml:106` : clic = `actions[0]` aveugle au lieu de chercher
  `identifier === "default"` → risque d'invoquer « Delete » au lieu d'ouvrir.
- `NotificationsPanel.qml:75` : `appIcon` (nom d'icône thème) passé en `Image.source` → échec
  silencieux, fallback cloche systématique. Garde du natif (`file://`/`http`) + `Quickshell.iconPath()`.
- `CalendarPanel.qml:13-17` : init hardcodée **2026** ; `:130` `isToday` jamais réévalué à
  minuit ; `:19` `eventsRev` (compteur de clés) redondant et faux.
- `WifiPanel.qml:94` : réseaux **enterprise (802.1X)** non gérés (mdp seul) ; `:137` `pwField.text`
  jamais effacé (secret conservé), pas de reveal, pas d'Enter.
- `BluetoothPanel.qml:33` : `adapter.discovering` écrit directement sans refcount → coupe la
  discovery sous les pieds du ControlCenter natif ; pas de `Component.onDestruction`.
- `WifiPanel` (global) : pas de `NetworkService.addRef()` → liste stale si on reste dans la vue ;
  le chemin IPC `open wifi` ne déclenche **aucun scan**.
- `DynamicIsland.qml:126-134` : edge glow déclenché par comparaison de longueur → un
  retrait+ajout dans le même tick (éviction `maxVisibleNotifications`) est raté.
- `DynamicIsland.qml:26` : fallback « focalisé » = `screens[0]` arbitraire ; ignore
  `notificationFocusedMonitor` et `getFilteredScreens("notifications"/"osd")` de DMS.
- `DynamicIsland.qml:498` + mask : `exclusiveZone: -1` → la bande top-center (jusqu'à 480+ px)
  **avale les clics destinés aux onglets/barres de titre** des fenêtres maximisées. Option :
  exclusiveZone = hauteur du pill au repos (surtout en notch mode).
- Presenter : reste dans la région d'input pendant 1,5 s (l'OSD macOS est click-through) ;
  volume muted affiché « 0 % » (faux — afficher « Muted ») ; icône batterie toujours
  `battery_full` (utiliser `Theme.getBatteryIcon`, jamais utilisé dans l'île).
- `PresenterPane.qml:12` : largeur `320 - spacing` duplique en dur le `pillW` presenter (320) —
  couplage magique.
- `ChipPane.qml` : ring animé à rebours au changement de piste (Behavior 900 ms sur sweep
  décroissant) ; EQ 5 barres pour 6 valeurs ; largeur figée 220 (clip à fontScale élevé).
- `NotificationBanners.qml:29` : `hmap` indexé par `index` → hauteurs décalées à la fermeture
  d'une carte du milieu.
- `DMSShell.qml:1245-1305` : gating OSD **incohérent** — Volume/Brightness remplacés par l'île,
  mais MicVolume/MediaVolume/MediaPlayback/IdleInhibitor/CapsLock/PowerProfile restent au style
  DMS natif → deux langages visuels d'OSD coexistent.

**Performance**
- Listes `Flickable + Column + Repeater` **non virtualisées** partout (Wi-Fi 50+ réseaux,
  notifications potentiellement des centaines, emoji ~80+ cellules, clipboard 50) → `ListView`/
  `GridView` avec `reuseItems`.
- `NotificationsPanel.qml:72` : images de notif sans `sourceSize` → une image 4K décodée pleine
  taille pour 28 px.
- `NotificationBanners.qml:83` : un FBO + MultiEffect **par carte** → une seule ombre sous le deck.
- `EmojiPanel.qml:64` : `FileView { blockLoading: true }` = IO synchrone à l'instanciation,
  ×2 moniteurs ; recherche sans debounce.
- `WallpaperPanel.qml:84` : énumération du dossier **au boot**, par moniteur ; `*.gif` accepté
  mais non caché par CachingImage → décodage pleine taille.
- `MediaPane.qml:101` : timer 1 s local dupliquant `island.mediaTick` (deux timers pour la même
  donnée) ; timestamps recalculés à `opacity: 0`.
- `ChipPane.qml:22-43` : deux `Shape` permanents + Behavior 900 ms relancé chaque seconde
  (re-tessellation continue) → Loader + animation courte.

**Architecture**
- **God-object** : chaque vue prend `property var island` non typé et **mute** directement
  `island.panelView/pinned/mode`. Intestable, contrat implicite, autocomplétion nulle.
  → Extraire un `IslandState` (QtObject typé, état en lecture + signaux `openView/back/close`),
  injecté en `required property`.
- **Registre de vues dupliqué ×4** : ternaire géant `viewHeight` (13 branches), commentaire
  `panelView`, `_kbViews`, doc IPC. Tout ajout de vue doit toucher 4 endroits, l'oubli est
  silencieux. → Registre central `[{ id, component, needsKeyboard, title }]` consommé partout
  (y compris whitelist IPC).
- **Duplication avec DMS natif** : 2 control centers, 2 centres de notifs, spotlight/clipboard/
  emoji/calendar réimplémentés → chaque fix devra être porté deux fois. → Extraire des composants
  de contenu headless à deux habillages (popout / île).
- Header drill (back + titre/recherche) **copié-collé ×7** → `DrillHeader.qml`.
- `island-blur.conf` : chemin `~/Projects/...` en dur (faux pour les installs nix).
- Panes : `property var island: null` sans gardes (`island?.`) → TypeErrors au teardown des
  Variants ; `required property var island` recommandé.

**A11y / i18n / cohérence**
- **Zéro `Accessible.name/role`** dans tout le module ; aucune navigation Tab/flèches dans le
  hub et les vues système ; Échap inopérant hors des 4 `_kbViews` (calendar/notifications/
  monitor/power : sortie souris/IPC uniquement).
- Cibles < 44 px (back/refresh 30×30, pickers 32×32, switch 44×24).
- Chaînes en dur : « Unknown » (CC:209, MediaPane:55), en-têtes `["Mo","Tu",…]` anglais +
  lundi forcé (→ `Qt.locale()`), « now »/« m ago » (NotificationService), « Tap to pair » sur
  desktop, unités KB=KiB.
- ~~`ToolTip` QtQuick.Controls brut (style Basic hors charte) au lieu de `DankTooltip`.~~
  **Corrigé 2026-08-05** : capsule morphée unique (`TooltipManager` + `DankTooltipMorph` +
  `DankTip`), 49 tooltips couvrant tous les boutons-icônes. Cf. handoff « Tooltips morphés macOS ».
- Springs/durées en dur ignorant `SettingsData.animationSpeed` (reduced-motion impossible).
- Mic et caméra même couleur (`Theme.error`) — iOS différencie orange/vert.
- Tailles d'icônes hardcodées non scalées par `fontScale`.

---

## 6. Gap-analysis UX vs macOS / Windows 11

Ce qui manque par surface pour être « au niveau », puis « au-dessus » :

| Surface | Manque pour parité | Pour dépasser |
|---|---|---|
| **Repos (compact/chip)** | Identité de piste dans le chip (art leading / EQ trailing autour d'un gap, split iPhone) ; clic art = play/pause ; press-and-hold → media sans pin (`TapHandler.onLongPressed`) — LE geste signature iOS manquant | Badge notifs non lues, point DND, timer d'enregistrement d'écran (macOS l'affiche) |
| **Idle** | Icône de l'app active devant le titre (menu bar macOS) ; clock cliquable → calendar ; cap tray à 5 + overflow « ⋯ » | Météo cliquable → drill météo |
| **Media** | `player.raise()` au clic sur l'art ; masquer la barre pour les flux sans durée ; molette sur la barre = seek | Switcher multi-players MPRIS ; shuffle/repeat ; volume inline |
| **OSD (presenter)** | 16 crans segmentés macOS ; icône = toggle mute ; barre draggable ; « Muted » au lieu de 0 % ; nom du device de sortie | OSD CapsLock/mic routés vers l'île (cohérence visuelle totale) |
| **Wi-Fi** | Spinner connexion, erreur inline, forget/disconnect/details (« … » par ligne), réseaux connus, hidden network | Partage **QR code** (le modal existe déjà dans DMS !) |
| **Bluetooth** | État Connecting, forget, batterie par device | Sélecteur de **codec** (backend existant), icônes de signal |
| **Audio** | Slider master en tête, alias devices (`getDeviceAlias` ignoré), icônes par type, vu-mètre micro (macOS l'a) | **Mixer par application** (Pipewire streams) — Win11 l'a, macOS NON : différenciateur |
| **Power** | Hold-to-confirm, Hibernate (`hibernateSupported` détecté), Switch User (modal existant) | — |
| **Spotlight** | Calculatrice, fichiers, actions d'apps, presse-papiers — **80 % du code existe** dans DankLauncherV2 (`searchAppActions`, file-search à préfixes, `getLauncherEntries`, plugins) ; récents/fréquents en requête vide | Sections avec badges de source ; conversions d'unités |
| **Clipboard** | Nav clavier complète, pin UI (le service trie déjà pinned-first **sans indicateur**), Clear-all (annoncé en commentaire, absent), vignettes images (mécanisme `ClipboardThumbnail` existant) | Shift+Enter = coller directement (`pasteEntry` existe) |
| **Calendrier** | Localisation (premier jour + noms de jours), molette = mois, agenda cliquable | Heure de fin, multi-jours, indicateur de débordement |
| **Wallpaper** | Préview avant application + undo (clic = application immédiate aujourd'hui) | Sous-dossiers inline, « appliquer à tous les écrans » |
| **Notifications (panel + bannières)** | **Groupement par app** (`groupedPopups`/`groupedNotifications` existent), body expansible, boutons d'action dans le panel, DND toggle dans l'en-tête | **Inline reply** (Quickshell expose `hasInlineReply`/`sendInlineReply`) |
| **Control Center (hub)** | Navigation clavier ; Échap = fermer | Tuiles configurables + drag-réorganiser (le natif DMS le fait) |
| **Notch** | Clamp des bannières sur petits écrans (≤1024 px : chevauchement) ; flare/hauteur en réglages | Squircle (courbure continue Apple) ; accent adaptatif extrait de la pochette |
| **Réglages** | Onglet dédié : activation par moniteur, exclusive zone, position bannières, **doc des keybinds IPC** (aujourd'hui dans un commentaire), installateur du snippet blur | Aperçu live de l'île dans les réglages |
| **Système (Live Activities)** | — | **Framework de file d'activités** avec priorités (charge, enregistrement, téléchargements, minuteurs) au lieu d'appels `showSplash` ad hoc — LE différenciateur macOS+ |

---

## 7. Roadmap proposée

### Phase 0 — Correctifs immédiats (1 session, aucun risque de design)
1. **C1** Grab clavier Wi-Fi (champ mdp) + Enter submit.
2. **C2** Hold-to-confirm PowerPanel (respect `powerActionConfirm`).
3. **C3** Timer bannières : supprimer le 5000 ms local, piloter `wrapper.timer`.
4. **2.1/2.2** Modèle stable des bannières + fallback art sur `status`.
5. **C5** Purge de l'état mort `"notif"` ; **H1** garde `expanded` dans `onPlayingChanged` ;
   **H2** fix binding `expanded` ; **H9** cricket Unicode ; **H11** whitelist IPC ;
   **H3** clamp selIndex Spotlight.

### Phase 1 — Fondations (architecture + perf, 2-3 sessions)
6. **Éclater la fenêtre plein écran** (H13) : pill dimensionné, bannières séparées, scrim
   éphémère. Restaure le scanout, simplifie le mask, règle l'exclusiveZone au passage.
7. **Registre de vues + Loaders** (H14) : `[{id, component, needsKeyboard, title}]` → un seul
   Loader, whitelist IPC, `_kbViews`, `viewHeight` dérivés. Fin du ternaire à 13 branches.
8. **`IslandState` typé** à la place de `property var island` muté partout : état lecture seule
   + signaux. Chemin naturel vers le partage de contenu avec les popouts natifs.
9. **Unification du pipeline notifs** : timer service unique, `ScriptModel`, hmap → vrai layout.
10. Virtualisation des listes (ListView/GridView), `sourceSize` sur toutes les vignettes,
    NotchVisual en `Shape.CurveRenderer`, transport MediaPane statique, models gated par
    `visible` (IdlePane), `ScriptModel` BT.

### Phase 2 — Parité macOS/Win11 (3-4 sessions)
11. **États transitoires partout** : spinners + erreurs inline Wi-Fi/BT (H6/H7), timeout pairing,
    refcounts service (NetworkService.addRef, discovery BT).
12. **Clavier & a11y** : Échap universel (grab OnDemand en expanded), Tab/flèches dans hub et
    listes, `Accessible.name/role` sur chaque contrôle, cibles 44 px, durées via
    `SettingsData.animationSpeed`.
13. **OSD interactif segmenté** (16 crans, mute au clic, drag, « Muted », device name) +
    routage Mic/CapsLock vers l'île.
14. **Notifications niveau macOS** : groupement par app, body expansible, inline reply,
    actions dans le panel, fix default-action/iconPath.
15. **Spotlight riche** : brancher les providers DankLauncherV2 + calculatrice.
16. Actions secondaires par ligne (« … ») : Wi-Fi forget/details/QR, BT forget/codec,
    audio alias ; Hibernate ; press-and-hold chip→media ; identité de piste dans le chip.

### Phase 3 — Dépassement (différenciateurs)
17. **Framework Live Activities** : file d'activités priorisée (remplace les `showSplash` ad
    hoc) — charge, enregistrement d'écran, téléchargements, minuteurs, médias.
18. **Mixer de volume par application** (Pipewire) — Win11 l'a, macOS non.
19. **Polish signature** : squircle (courbure continue), accent adaptatif extrait de la
    pochette, préview wallpaper avec undo, calendrier localisé interactif, onglet de réglages
    dédié avec aperçu live + doc keybinds.

### Quick wins (< 30 min chacun, n'importe quand)
`Theme.getBatteryIcon` partout · ~~`DankTooltip` au lieu de ToolTip Basic~~ (fait 2026-08-05) · `I18n.tr("Unknown")` ·
en-têtes calendrier via `Qt.locale()` · init calendrier `new Date()` · clear `pwField` au repli ·
« Muted » au lieu de 0 % · mic orange / caméra verte · `island?.` ou `required property` sur
panes/panels · clic clock idle → calendar drill · masquer trackBar si `mediaLen <= 0` ·
`visible: opacity > 0` sur les timestamps · vider « Available » BT quand `!discovering`.

---

## 8. Verdict

Le socle est bon : la machine à états est saine, la modularisation panes/panels est faite, le
multi-compositeur est pensé, et plusieurs choix (bannières indépendantes, drill-down, IPC) sont
les bons. Pour être « digne d'un macOS », l'effort doit maintenant porter sur **ce qui ne se
voit pas en démo** : les états d'attente et d'erreur, le clavier, l'accessibilité, la stabilité
des modèles, et le coût GPU de fond. La Phase 0 corrige tout ce qui est cassé aujourd'hui ; les
Phases 1-2 amènent la parité réelle ; la Phase 3 (Live Activities, mixer par app)
fait passer l'île **devant** macOS sur plusieurs points.
