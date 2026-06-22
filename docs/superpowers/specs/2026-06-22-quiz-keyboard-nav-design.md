# Quiz Widget — navigation clavier (UX sans souris)

Date : 2026-06-22
Statut : validé (design approuvé, prêt pour plan d'implémentation)

## Objectif

Permettre d'utiliser le widget Quiz **entièrement au clavier**, sans souris :
1. **Globalement** (depuis n'importe quelle appli) : ouvrir / reporter / ignorer la pastille en attente.
2. **Dans la carte** (une fois ouverte) : sélectionner une réponse, valider, passer à la suivante, poser une question, reporter, fermer.

Contexte : la pastille (`overlay.mode === "pending"`) n'a **volontairement pas** le focus clavier (fix anti-vol de focus, `QuizOverlay.qml`). L'ouvrir au clavier passe donc forcément par un **raccourci global** (IPC), pas par un `Keys` local sur la pastille. Les cartes ouvertes (`open`/`feedback`) ont le focus `OnDemand` et peuvent recevoir les touches.

## Non-objectifs (YAGNI)

- Pas de keymaps configurables par l'utilisateur (chords en dur dans `hyprland.lua`, défauts in-card en dur).
- Pas de choix de durée de snooze au clavier dans la carte : une seule touche = report 5 min par défaut (le choix fin reste à la souris / aux 4 boutons existants).
- Pas de navigation clavier dans l'onboarding (hors scope ; reste à la souris).

## Architecture

Trois morceaux, faiblement couplés :

1. **IPC global** — un `IpcHandler { target: "quiz" }` dans `QuizDaemon.qml` expose `open` / `snooze` / `dismiss`. No-op (avec message de retour) si aucune pastille n'est en attente.
2. **Binds Hyprland** — 3 `hl.bind` dans `~/personal/dotfiles/hypr/hyprland.lua` appelant `dms ipc call quiz <fn>` (même pattern que `dms ipc call island …`).
3. **Nav in-card** — un gestionnaire `Keys` **au niveau de l'overlay** (`QuizOverlay.qml`), qui pilote la machine à états déjà existante (l'overlay possède `mode`/`selected` et émet `quizAnswered`/`lessonDone`/`dismissed`). Les cartes restent des vues déclaratives ; on ne duplique pas leur logique.

### Pourquoi les keymaps au niveau de l'overlay (et pas dans chaque carte)

L'overlay détient déjà l'état (`mode`, `selected`, `contentType`) et le câblage des signaux des cartes (`onSubmit`, `onClose`, `onNext`, `onSnoozeRequested`…). Mettre les `Keys` ici évite de dupliquer cette logique dans `QuizCard`/`LessonCard` et garde les cartes comme vues pures. Le handler agit exactement comme les `MouseArea` existantes (mêmes mutations d'état, mêmes signaux).

## Composant 1 — IPC daemon (`QuizDaemon.qml`)

Ajouter `import Quickshell.Io` et :

```qml
IpcHandler {
    target: "quiz"
    function open(): string { /* si pending → overlay.mode = "open" */ }
    function snooze(): string { /* si pending → reporter 5 min + masquer */ }
    function dismiss(): string { /* si pending → masquer/ignorer */ }
}
```

Sémantique :
- **open** : si `overlay.mode === "pending"` → `overlay.mode = "open"` (identique au clic sur la pastille). Sinon retourne `"rien en attente"`.
- **snooze** : si en attente → reporter de 5 min (chemin existant `root.snooze(300000)`) **et** masquer l'overlay (`overlay.reset()`), sans ouvrir la carte. Sinon no-op.
- **dismiss** : si en attente → masquer/ignorer (purge le contenu en attente puis `overlay.reset()`), sans ouvrir. Pour une leçon non validée, conserver le comportement existant de `onDismissed` (retenir la notion à ré-expliquer). Sinon no-op.

Chaque fonction retourne une `string` de statut (idiome de l'île : `dms ipc call quiz open` affiche le retour).

**Hypothèse à valider tôt** : un `IpcHandler` déclaré dans un **plugin chargé dynamiquement** (le daemon) s'enregistre bien auprès de l'IPC Quickshell et devient atteignable via `dms ipc call quiz …` (l'île le fait depuis le cœur ; même moteur/instance, donc attendu — mais à confirmer avant d'aller plus loin).

## Composant 2 — Binds Hyprland (`~/personal/dotfiles/hypr/hyprland.lua`, cross-repo)

Lettre libre **L** (= Learn), aucun conflit avec les chords Super existants :

```lua
hl.bind(mainMod .. " + L",         hl.dsp.exec_cmd("dms ipc call quiz open"))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("dms ipc call quiz snooze"))
hl.bind(mainMod .. " + ALT + L",   hl.dsp.exec_cmd("dms ipc call quiz dismiss"))
```

## Composant 3 — Nav clavier in-card (`QuizOverlay.qml`)

Quand une carte est ouverte (`open`/`feedback`), le contenu doit avoir le focus actif pour recevoir les touches : forcer `forceActiveFocus()` sur l'item gestionnaire de touches au passage en `open`. Un `Keys.onPressed` route selon `overlay.mode` + `overlay.contentType` :

### Carte quiz (QCM) — `contentType === "quiz"`
| Touche | Action |
|---|---|
| `A` `B` `C` `D` (ou `1` `2` `3` `4`) | sélectionner le choix (mode `open`) → `overlay.selected = i` |
| `Entrée` / `Return` | mode `open` + un choix sélectionné → valider (`overlay.mode = "feedback"; overlay.quizAnswered()`) ; mode `feedback` → fermer (`overlay.reset()`) |
| `S` | reporter 5 min (`overlay.snoozeRequested(300000); overlay.reset()`) |
| `Échap` | fermer (`overlay.reset()`) |

### Carte leçon — `contentType === "lesson"`
| Touche | Action |
|---|---|
| `Entrée` / `Return` ou `N` | « Suivant » (`overlay.lessonDone(); overlay.reset()`) |
| `Q` ou `?` | ouvrir « Des questions ? » et focus le champ |
| `S` | reporter 5 min |
| `Échap` | fermer |

### Suspension quand le champ « Des questions ? » a le focus
Quand le `DankTextField` de la leçon (`askInput`) a le focus actif, les lettres doivent aller au champ — pas aux keymaps. La chaîne de focus QML fait que le champ consomme déjà les caractères et `Entrée` (→ `onAccepted` envoie la question). Le handler `Keys` de l'overlay ne doit pas intercepter dans ce cas. `Échap` referme le champ (retour à la nav leçon) plutôt que fermer la carte. `LessonCard` expose donc l'état « champ actif » (p.ex. propriété `inputActive`) que l'overlay consulte pour suspendre ses keymaps.

## Cas limites

- **Aucune pastille en attente** : les fonctions IPC sont no-op et renvoient un statut clair ; aucun effet visuel.
- **Mode `feedback`** : `Entrée` et `Échap` = fermer.
- **Champ de question actif** : keymaps suspendues (cf. ci-dessus) ; `Échap` = fermer le champ, `Entrée` = envoyer la question.
- **Re-mapping / focus** : ne PAS régresser le fix anti-vol-de-focus — la pastille (`pending`) garde `keyboardFocus: None`. Le focus actif n'est forcé qu'en `open`/`feedback`/`onboarding`.

## Portée fichiers

Repo DMS :
- `QuizDaemon.qml` — `import Quickshell.Io` + `IpcHandler` (open/snooze/dismiss).
- `QuizOverlay.qml` — item focusable + `Keys.onPressed`, focus forcé à l'ouverture.
- `LessonCard.qml` — exposer l'état « champ actif » (`inputActive`) pour la suspension des keymaps.
- (`QuizCard.qml` — a priori inchangé : la nav pilote l'état via l'overlay.)

Cross-repo :
- `~/personal/dotfiles/hypr/hyprland.lua` — 3 binds.

## Vérification

- **IPC** : `dms ipc call quiz open|snooze|dismiss` (sans pastille → message no-op ; avec pastille forcée → effet attendu, observé via `hyprctl layers` / `journalctl`).
- **Binds** : après reload Hyprland, `Super+L` ouvre, `Super+Shift+L` reporte, `Super+Alt+L` ignore.
- **Nav in-card** : test comportemental (taper réellement via `wtype` dans un terminal témoin qui logge ses frappes) — ouvrir une carte, taper `A`/`Entrée`/`Échap`, vérifier sélection/validation/fermeture. Vérifier qu'en mode « questions » les lettres vont au champ.
- Pas de qmllint sur cette machine : scan d'erreurs QML via `journalctl --user -u dms.service` après reload (cf. méthode de vérif projet).

## Déploiement

Comme les correctifs précédents : edits live via le symlink working-tree `~/.config/DankMaterialShell/plugins/QuizWidget` ; pour rendre permanent dans le package nix → commit + push + `nix flake update dms` + rebuild. Les binds `hyprland.lua` sont des dotfiles (pris en compte au prochain reload Hyprland / rebuild selon le mécanisme de linkage).
