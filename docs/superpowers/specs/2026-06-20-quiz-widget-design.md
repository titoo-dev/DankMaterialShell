# Quiz Widget — Design (spec)

- **Date :** 2026-06-20
- **Statut :** design validé (brainstorming) → prêt pour `writing-plans`
- **Ticket :** #1 (Handoff — Quiz Widget intelligent, pomodoro + QCM)
- **Branche :** `feat/dynamic-island` (une branche dédiée `feat/quiz-widget` peut être créée au moment de l'implémentation)

## Objectif

Créer un **widget flottant intelligent** pour DankMaterialShell qui, selon des cycles
pomodoro, propose des **QCM à choix unique** sur les sujets préférés de l'utilisateur.
But : garder le cap face à l'IA — l'humain doit continuer à apprendre activement.

## Décisions verrouillées

Du ticket (via AskUserQuestion) :

1. **Source des questions : HYBRIDE** — banque locale JSON par défaut + toggle « Générer via IA ».
2. **Présentation : CARTE FLOTTANTE EN COIN** (bas-droit), interactive, persistante jusqu'à réponse.
3. **Hébergement : PLUGIN AUTONOME** de type `daemon`, dans `quickshell/PLUGINS/QuizWidget/`,
   déployé vers `~/.config/DankMaterialShell/plugins/`.

Tranchées au design (via AskUserQuestion) :

4. **Étendue v1 : HYBRIDE COMPLET** — banque locale ET génération IA livrées et testées dès la v1.
5. **Cycle : SIMPLE RAPPEL, OUVERT À LA DEMANDE** — en fin de cycle, une pastille discrète
   signale un quiz dispo ; l'utilisateur l'ouvre quand il veut. Les cycles tournent sur leur
   propre horloge (non bloquant).
6. **Stats : AUCUNE EN V1** (YAGNI).

## Architecture

Plugin `daemon` : un `PluginComponent` chargé en arrière-plan par `DMSShell.qml`
(`Instantiator`/`Loader`). Le composant de fond **reste mappé en permanence**, donc son
`Timer` pomodoro ne gèle jamais (les `Timer`/animations QML gèlent quand *toutes* les
surfaces d'un scope se démappent — le timing doit vivre dans le composant de fond, pas dans
l'overlay).

### Arborescence cible

```
quickshell/PLUGINS/QuizWidget/
├── plugin.json          # type: daemon, settings, permissions
├── QuizDaemon.qml        # PluginComponent : cycle pomodoro + état "quiz dispo"
├── QuizOverlay.qml       # PanelWindow coin bas-droit : pastille ↔ carte QCM
├── QuizCard.qml          # contenu de la carte (question + choix radio + feedback)
├── QuizEngine.js         # logique pure : sélection question, parsing IA, validation schéma
├── QuizProvider.qml      # abstraction source : banque locale | IA (curl)
├── QuizSettings.qml      # premier setup (sujets, durées, toggle IA + clé)
└── banks/
    ├── algorithmes.json
    └── ...               # quelques sujets seed
```

### Frontières des composants

| Unité | Rôle | Dépend de | Ne connaît pas |
|---|---|---|---|
| `QuizDaemon` | Horloge & orchestration (machine à états) | `QuizProvider`, `QuizOverlay` | le rendu, la source concrète |
| `QuizOverlay` + `QuizCard` | Présentation (pastille ↔ carte) | `Theme`, widgets `qs.Widgets` | le timing, la source |
| `QuizProvider` | Fournit une question (banque ou IA) | `QuizEngine.js`, `Proc` | l'UI, le timing |
| `QuizEngine.js` | Logique pure (sélection, parsing, validation) | — | tout le reste (testable isolément) |

## Manifest (`plugin.json`)

```json
{
  "id": "quizWidget",
  "name": "Quiz Widget",
  "description": "Quiz QCM pomodoro pour continuer à apprendre activement",
  "version": "0.1.0",
  "author": "Titosy",
  "type": "daemon",
  "capabilities": ["learning", "pomodoro"],
  "component": "./QuizDaemon.qml",
  "settings": "./QuizSettings.qml",
  "icon": "quiz",
  "permissions": ["settings_read", "settings_write", "process", "network"]
}
```

- `process` + `network` : nécessaires au chemin IA (curl via `Proc.runCommand`).
- `settings_read` / `settings_write` : premier setup + persistance des sujets/réglages.
- Validé contre `quickshell/PLUGINS/plugin-schema.json` (champs requis : `id, name, description,
  version, author, type, capabilities, component`).

## Daemon pomodoro — machine à états

`QuizDaemon` tient un `Timer` (intervalle = durée de travail configurée, défaut **25 min**).
Cycle **non bloquant** :

```
[IDLE] --(work timer écoulé)--> [QUIZ_PENDING] --(user ouvre)--> [QUIZ_OPEN]
   ^                                  |                              |
   |                                  | (le timer redémarre          | (répondu)
   |                                  |  immédiatement, non bloquant) v
   +----------------------------------+--------------------------- [FEEDBACK] --(fermé)--> [IDLE]
```

- Fin de cycle → `QUIZ_PENDING` : le daemon demande une question à `QuizProvider`, lève le flag
  « quiz dispo » (→ pastille), puis le `Timer` redémarre aussitôt.
- **Une seule question en attente à la fois** (YAGNI) : si un cycle s'achève alors qu'une est
  déjà pending, on garde l'existante.
- Activable/désactivable via réglages ; pause optionnelle.

## Overlay (`QuizOverlay.qml` + `QuizCard.qml`)

Un seul `PanelWindow` ancré bas-droit, **2 états visuels**. Pas d'auto-hide → **aucun `Timer`
gel-sensible dans l'overlay** (cohérent avec « persistant jusqu'à réponse »).

```
État PENDING (pastille)          État OPEN (carte QCM)
┌───────────────┐                ┌──────────────────────────────┐
│ ◉ Quiz dispo  │  ── clic ──▶   │  Algorithmes                  │
└───────────────┘                │  Quelle est la complexité… ?  │
                                  │  ○ O(n)   ○ O(log n)          │
                                  │  ○ O(n²)  ○ O(1)              │
                                  │            [ Valider ]        │
                                  └──────────────────────────────┘
                                          │ (valider)
                                          ▼
                                  ┌──────────────────────────────┐
                                  │ ✓ Correct — O(log n) car…     │
                                  │              [ Fermer ]       │
                                  └──────────────────────────────┘
```

Pattern repris du module OSD (`quickshell/Modules/OSD/`), débarrassé de ses singletons couplés
(`OSDManager`, `AudioService`, `DisplayService`…) :

- `import Quickshell`, `import Quickshell.Wayland`
- `WlrLayershell.namespace: "dms:quiz"`, `WlrLayershell.layer: WlrLayer.Overlay`
- `WlrLayershell.exclusiveZone: -1` (overlay non exclusif)
- `WlrLayershell.keyboardFocus: WlrKeyboardFocus.None` (ne vole pas le focus du travail ;
  sélection à la souris)
- `color: "transparent"` ; contenu animé via `Behavior on opacity` + `Behavior on scale`
- Positionnement coin : `anchors { bottom: true; right: true }` + `WlrLayershell.margins`
  (marge configurable)
- Thème via le singleton **`Theme`** + widgets `qs.Widgets` (`StyledRect`, `StyledText`,
  `DankIcon`) → cohérence visuelle, pas de couplage fonctionnel.

**Coexistence Dynamic Island** : overlay indépendant sur le layer Overlay, hors du système de
notifications/popout (il ne passe pas par les bannières island). À surveiller : le coin
bas-droit ne doit pas chevaucher une surface island → marge configurable.

## Source des questions (`QuizProvider` + `QuizEngine.js`)

Format banque locale `banks/<sujet>.json` :

```json
[
  {
    "id": "algo-001",
    "question": "Quelle est la complexité d'une recherche dichotomique ?",
    "choices": ["O(n)", "O(log n)", "O(n²)", "O(1)"],
    "answer": 1,
    "explanation": "On divise l'espace de recherche par deux à chaque étape."
  }
]
```

- **Banque locale** (défaut) : `QuizEngine.pickQuestion(bank, seen)` → question non encore vue de
  la session (rotation anti-répétition).
- **IA** (hybride, livré en v1) : `Proc.runCommand("quizWidget.gen", ["curl","-s",
  "https://api.anthropic.com/v1/messages", "-H", …], cb, debounceMs)` →
  `POST` avec en-têtes `x-api-key`, `anthropic-version: 2023-06-01`, modèle **`claude-haiku-4-5`**
  (rapide/éco), corps utilisant **`output_config.format` (json_schema)** dont le schéma est la
  forme `{question, choices, answer, explanation}`. Le JSON renvoyé est garanti parseable par
  `QuizEngine.parseAiQuestion()`.
- **Sélection du sujet** : aléatoire parmi les sujets configurés.

### Schéma de validation (`QuizEngine.js`)

`QuizEngine.validate(q)` rejette toute question dont : `choices` n'est pas un tableau de ≥ 2
chaînes ; `answer` n'est pas un index entier valide dans `choices` ; `question` ou
`explanation` vides. Toute question invalide (banque ou IA) est écartée.

## Réglages — premier setup (`QuizSettings.qml`)

Via `PluginSettings` (auto-save, composants `qs.Modules.Plugins`) :

- `ListSettingWithInput` **sujets** (mappés vers `banks/<sujet>.json` + prompts IA) — quelques
  seeds livrés.
- `SelectionSetting` **durée de travail** (15 / 25 / 45 / 60 min, défaut 25).
- `ToggleSetting` **activer le widget** ; `ToggleSetting` **pause**.
- `ToggleSetting` **« Générer via IA »** (OFF par défaut).
- `StringSetting` **clé API** (placeholder `sk-ant-…`).

## Gestion d'erreurs

| Cas | Comportement |
|---|---|
| Banque sujet absente/vide | Skip le sujet ; si aucune source dispo → pas de pastille, log warning |
| IA échoue (réseau / exit≠0 / JSON invalide) | **Fallback automatique** sur la banque locale ; toast erreur seulement si la banque est aussi vide |
| Clé API absente alors que toggle IA ON | Toujours banque locale ; hint dans les réglages |
| Toutes les questions de session vues | Reset du `seen` (recyclage) |

Principe : **jamais d'écran vide** — l'IA est un enrichissement opportuniste, la banque locale
est le socle fiable.

## Stratégie de test

- **`QuizEngine.js`** = logique pure → testable en isolation : `pickQuestion` (rotation
  anti-répétition), `parseAiQuestion`, `validate`, comportement de fallback.
- **Manuel / shell vivant** : les edits QML hot-reload dans le desktop actif → vérifier
  `journalctl --user -u dms` après chaque modif. Scénarios :
  - déclenchement de la pastille en fin de cycle ;
  - expand → sélection → valider → feedback (correct/incorrect + explication) → fermer ;
  - fallback IA (clé bidon / réseau coupé) ;
  - coexistence avec la Dynamic Island (pas de chevauchement coin bas-droit).

## Hors périmètre v1 (YAGNI)

- Statistiques / historique de réussite.
- Adaptation de difficulté.
- Types de questions autres que QCM à choix unique.
- File de plusieurs quiz en attente.
- Raccourcis clavier (focus `None` en v1 ; sélection souris uniquement).

## Étapes suivantes

1. Validation utilisateur de ce spec.
2. `superpowers:writing-plans` → plan d'implémentation détaillé.
