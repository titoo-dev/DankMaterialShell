# Quiz Widget — Contenu réel via `claude -p` + sélection de sujets dev/IT

> Spec de conception. Date : 2026-06-20. Suit le spec initial `2026-06-20-quiz-widget-design.md` (v1 du widget, déjà implémenté).

## Goal

Passer du « squelette » au **contenu réel** :

1. Générer les questions via **`claude -p`** (CLI Claude Code local, comme les nudges) — plus de clé API, plus de `curl`.
2. Offrir un **catalogue dev/IT curaté et catégorisé** (Technologies / Concepts / Méthodologies) où l'utilisateur **coche** ses sujets préférés.
3. Présenter ce choix via un **composant partagé** : une **carte d'onboarding** au tout premier lancement **ET** un panel intégré aux réglages.
4. Le sujet choisi alimente le **contexte du prompt** envoyé à `claude -p`.

## État actuel (vérifié)

- `QuizProvider._fetchAi` appelle l'**API Anthropic via `curl`** (`x-api-key`, modèle `claude-haiku-4-5`), pas `claude -p`. Conditionné à `aiEnabled: true` **et** `apiKey` non vide ; sinon fallback banque locale.
- Seul **le nudge** (`QuizDaemon.fetchNudge`) utilise `claude -p` (texte de la pastille).
- Banques = **3 questions de test** (`banks/algorithmes.json` ×2, `banks/culture-generale.json` ×1).
- Sujets = **texte libre** (`ListSettingWithInput`, stocké `[{name}]`), injecté brut : `"Sujet : <x>. Génère une question QCM."`.
- **Aucun composant multi-select / chips** dans le framework de réglages (`quickshell/Modules/Plugins/`). À créer.
- `QuizEngine.js` (pur, testé sous node) porte : `validate`, `pickQuestion`, `buildAiRequestBody`, `parseAiQuestion`, plus les helpers nudge.

## Décisions

| Décision | Choix |
|---|---|
| Source des questions | **`claude -p`** (Approche 1, voir §1). Suppression du chemin `curl`/clé API. |
| JSON fiable depuis le CLI | Prompt « JSON uniquement » + **extracteur robuste** (`extractQuestionJson`), testé node. |
| Catalogue | **Curaté, fixe, catégorisé** (3 catégories). Pas de saisie libre en v1. |
| UX de setup | **Composant partagé** : carte d'onboarding 1er lancement **+** panel réglages. |
| Fallback si `claude -p` échoue | `banks/<topicId>.json` **si présent**, sinon **saute le cycle** (log + retry au prochain pomodoro). Jamais de question hors-sujet forcée. |
| Réglages supprimés | `apiKey`, `aiEnabled`, `subjects`. |

---

## §1 — Génération de questions via `claude -p`

### Provider
`QuizProvider._fetchAi(subject, callback)` devient un appel CLI, sur le modèle exact du nudge existant :

```qml
Proc.runCommand("quizWidget.gen",
    ["claude", "-p", "--model", "claude-haiku-4-5", prompt],
    function (stdout, exitCode) {
        if (exitCode !== 0) { console.warn("QuizProvider: claude -p exit", exitCode); callback(null); return; }
        callback(QuizEngine.extractQuestionJson(stdout));
    }, 0);
```

- `--model claude-haiku-4-5` : rapide et économique pour de la génération fréquente (modifiable plus tard).
- `prompt` est désormais une **chaîne** (plus un corps JSON d'API).
- Pas de clé : `claude -p` s'appuie sur la session Claude Code locale (déjà prouvé par le nudge).

### `QuizEngine.js`
Remplace `buildAiRequestBody` / `parseAiQuestion` par :

- **`buildQuestionPrompt(topicLabel, category)` → string** : prompt FR demandant **uniquement** un objet JSON :
  - une question QCM claire et factuelle sur `topicLabel` (catégorie `category`), niveau intermédiaire ;
  - exactement **4 propositions**, une seule correcte ;
  - une explication courte ;
  - **« Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour, sans balises Markdown. »**
  - Forme attendue : `{ "question": string, "choices": [string×4], "answer": int (0-3), "explanation": string }`.

- **`extractQuestionJson(stdout)` → question | null** :
  1. retire d'éventuelles fences ```` ```json … ``` ```` ;
  2. isole le **premier objet `{…}` équilibré** dans la sortie (tolère du texte parasite avant/après) ;
  3. `JSON.parse` ; en cas d'échec → `null` ;
  4. `validate(q)` (réutilise l'existant) ; si invalide → `null` ;
  5. assigne `q.id = "ai-" + hashString(q.question)` si absent (réutilise `hashString`).

### Fallback
`fetchQuestion(topicId, label, category, seen, callback)` :
1. tente `claude -p` ;
2. si `null` (échec CLI ou JSON invalide) → tente `banks/<topicId>.json` via le mécanisme `FileView` + `pickQuestion` **existant** ;
3. si pas de banque pour ce `topicId` → `callback(null, seen)` → le daemon **saute le cycle** (warn) et réessaiera au prochain pomodoro.

### Suppressions
- Le bloc `curl` dans `_fetchAi`.
- `buildAiRequestBody`, `parseAiQuestion` (+ leurs tests).
- Réglages `apiKey` et `aiEnabled` (et leur lecture dans le daemon).

---

## §2 — Catalogue dev/IT curaté

Nouveau module pur **`Catalog.js`** (`.pragma library`) :

```js
.pragma library
var CATALOG = [
    // { id, label, category }
];
function topicById(id) { /* … */ }
function topicsByCategory(cat) { /* … */ }
function allCategories() { /* ordre fixe */ }
```

- `id` : slug stable (sert de clé de réglage et de nom de banque optionnelle).
- `category` ∈ `{ "Technologies", "Concepts", "Méthodologies" }`.

**Starter (v1, extensible) :**

- **Technologies** — `js` JavaScript/TypeScript · `python` Python · `go` Go · `rust` Rust · `java` Java/JVM · `react` React · `node` Node.js · `sql` SQL/PostgreSQL · `docker` Docker · `kubernetes` Kubernetes · `linux` Linux/shell · `git` Git · `cloud` Cloud (AWS/GCP/Azure)
- **Concepts** — `algorithms` Algorithmes & complexité · `datastructures` Structures de données · `oop` Programmation orientée objet · `fp` Programmation fonctionnelle · `networking` Réseaux (TCP/IP, HTTP) · `security` Sécurité (web, crypto) · `concurrency` Concurrence & parallélisme · `databases` Bases de données & modélisation · `os` Systèmes d'exploitation · `patterns` Design patterns · `architecture` Architecture logicielle (REST, microservices)
- **Méthodologies** — `agile` Agile/Scrum · `tdd` Tests & TDD · `cicd` CI/CD · `devops` DevOps · `gitflow` Workflow Git (branching) · `codereview` Revue de code · `cleancode` Clean code / refactoring

Helpers testables node (`topicById`, `topicsByCategory`, unicité des `id`).

---

## §3 — Composant partagé `TopicPicker.qml` + onboarding

### `TopicPicker.qml` (présentation pure, sans persistance)
Contrat :
- **Entrées** : `catalog` (depuis `Catalog.CATALOG`), `selectedIds` (`var`, tableau d'`id`).
- **Sortie** : signal `toggle(string id)`.
- **Rendu** : pour chaque catégorie (ordre `allCategories()`), un en-tête + un `Flow` de **chips** toggleables. Chip = `StyledRect` arrondi + `StyledText` ; sélectionné → fond `Theme.primary` / texte `Theme.onPrimary` ; non-sélectionné → `Theme.surfaceContainerHigh` / `Theme.surfaceText`. `MouseArea` → `toggle(id)`.

C'est le **parent** qui décide de la persistance (voir ci-dessous). Tokens de thème conformes à `Common/Theme.qml` (cf. notes du spec v1 : `cornerRadius`, pas `cornerRadiusLarge` ; `surfaceText` réel ; `DankIcon.size`).

Esquisse :
```
┌──────────────────────────────────────────────┐
│ Choisis tes sujets                             │
│ TECHNOLOGIES                                   │
│ [JavaScript/TS] [Python] [Go] [React] [Docker] │
│ [Kubernetes] [SQL] [Git] [Linux] [Cloud] …     │
│ CONCEPTS                                       │
│ [Algorithmes] [Structures de données] [POO] …  │
│ MÉTHODOLOGIES                                  │
│ [Agile] [TDD] [CI/CD] [DevOps] …               │
│                              [ Commencer ]     │
└──────────────────────────────────────────────┘
```

### Réglages (`QuizSettings.qml`)
- Retirer le `ListSettingWithInput "subjects"`, les toggles `aiEnabled`, et `StringSetting "apiKey"`.
- Intégrer `TopicPicker` lié au store : à chaque `toggle(id)`, le parent met à jour `selectedTopics` et persiste (`setPluginSetting`/store `PluginSettings`), **immédiatement** (cohérent avec le reste des réglages).
- Conserver `paused` et `workMinutes`.

### Onboarding (1er lancement)
- `QuizOverlay` gagne un mode `"onboarding"` (en plus de `"hidden"|"pending"|"open"|"feedback"`).
- La carte d'onboarding **enveloppe `TopicPicker`** + un bouton **« Commencer »** (activé si ≥ 1 sujet coché).
- En mode onboarding, la sélection est **locale** ; « Commencer » **émet** la liste finale → le daemon persiste `selectedTopics` puis ferme la carte.

---

## §4 — Câblage daemon & flux

### `requestQuiz()`
1. `if (pendingQuestion) return;`
2. recharger les réglages (pattern existant `loadSettings` + `Qt.callLater`).
3. si `selectedTopics` vide → ne rien faire ici (l'onboarding gère le 1er lancement).
4. piocher un `id` aléatoire dans `selectedTopics`.
5. `var t = Catalog.topicById(id)` → `label`, `category`.
6. `provider.fetchQuestion(id, t.label, t.category, seenFor(id), cb)`.
7. dans le callback : si `q` → `pendingQuestion = q`, `overlay.showPending()`, `fetchNudge()` (inchangé) ; sinon `warn` et on laisse le prochain cycle réessayer.

### Premier lancement
- À la fin de `loadSettings`, si `selectedTopics` est **vide** → `overlay.showOnboarding()` (au lieu d'attendre le pomodoro).
- À la complétion de l'onboarding (signal de la carte) :
  - persister `selectedTopics` ;
  - fermer l'onboarding ;
  - **déclencher une première question après un court délai (~30 s)** pour que l'utilisateur voie immédiatement la feature fonctionner, puis reprendre le cycle pomodoro normal.
- Déclencheur d'onboarding = `selectedTopics.length === 0` (pas de flag séparé : se désélectionner totalement re-propose le setup, ce qui est souhaitable — au moins un sujet requis).

### Clés de réglage finales
- Conservées : `paused`, `workMinutes`, `selectedTopics` (tableau d'`id`).
- Supprimées : `apiKey`, `aiEnabled`, `subjects`.

---

## §5 — Tests

### Node (`tests/quizEngine.test.mjs` + éventuellement `tests/catalog.test.mjs`)
- `extractQuestionJson` :
  - JSON brut valide → question + `id` `ai-…` ;
  - JSON entouré de fences ```` ```json ``` ```` → ok ;
  - JSON précédé/suivi de texte parasite → ok (isole l'objet) ;
  - sortie non-JSON (« I can't… ») → `null` ;
  - JSON valide mais question invalide (1 seul choix / explication vide) → `null`.
- `buildQuestionPrompt(label, category)` : contient `label` et `category`, exige explicitement du JSON, mentionne 4 propositions.
- `Catalog` : `topicById` trouve/`undefined` ; `topicsByCategory` filtre ; **`id` tous uniques** ; chaque entrée a `category` dans `allCategories()`.
- On **garde** les tests `validate` / `pickQuestion`. On **retire** les tests `buildAiRequestBody` / `parseAiQuestion`.
- Adapter le loader `vm` du harness aux nouvelles fonctions exportées (cf. note « loader robuste » du spec v1).

### Vérification live (shell vivant, Hyprland)
1. Réinitialiser `selectedTopics` à vide → recharger → **carte d'onboarding** apparaît au coin bas-droit ; cocher 2-3 sujets ; « Commencer ».
2. ~30 s après → pastille « Quiz dispo » ; ouvrir → **question réellement générée par `claude -p`** sur un sujet choisi ; valider correct/incorrect → feedback + explication.
3. Réglages → Plugins → Quiz Widget : le `TopicPicker` reflète la sélection ; (dé)cocher persiste ; pas de champ clé API.
4. `journalctl --user -u dms` : pas d'erreur QML ; en cas d'échec `claude -p`, voir `claude -p exit`/parse `null` puis fallback banque ou cycle sauté (jamais de crash).
5. Abaisser temporairement l'intervalle pomodoro pour observer la rotation anti-répétition.

---

## Hors périmètre (YAGNI v2)

- Difficulté réglable / adaptative (prompt fixe « niveau intermédiaire » en v1).
- Ajout de sujets en texte libre (catalogue fixe d'abord).
- Mélange multi-sujets dans une même question (un sujet par question).
- Sujets hors dev/IT (catalogue dev/IT uniquement d'abord).
- Stats / streak.

## Risques & notes

- **Latence `claude -p`** : génération asynchrone (timeout `0` comme le nudge) ; la pastille n'apparaît que quand la question est prête. Un cycle peut être sauté si la CLI échoue — acceptable.
- **Cache du moteur QML** : `TopicPicker.qml` / `Catalog.js` sont des composants importés → après modif, **`dms restart`** (cf. note déploiement du spec v1, le `reload` ne cache-bust que le composant principal).
- **Fiabilité du JSON CLI** : entièrement couverte par les tests node de `extractQuestionJson` ; le `validate` + fallback garantissent qu'aucune question malformée n'atteint l'UI.
