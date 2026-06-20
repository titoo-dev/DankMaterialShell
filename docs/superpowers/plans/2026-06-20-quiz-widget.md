# Quiz Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construire un plugin daemon DankMaterialShell qui, selon des cycles pomodoro, propose des QCM à choix unique (banque locale JSON + génération IA) via une carte flottante en coin bas-droit.

**Architecture:** Plugin `daemon` autonome. `QuizDaemon` (PluginComponent, toujours mappé → Timer pomodoro jamais gelé) orchestre ; `QuizProvider` fournit une question (banque locale, ou IA via curl avec fallback) ; `QuizOverlay`/`QuizCard` affichent une pastille « quiz dispo » qui s'ouvre à la demande en carte QCM persistante ; `QuizEngine.js` (pur, testé sous node) porte la sélection/validation/parsing.

**Tech Stack:** Quickshell (QML), JavaScript (`.pragma library`), `Proc.runCommand` + `curl` pour l'API Claude, `PluginSettings`/`pluginService` pour la persistance, `node --test` pour la logique pure.

## Global Constraints

- **Emplacement versionné :** `quickshell/PLUGINS/QuizWidget/` — déployé en lien symbolique vers `~/.config/DankMaterialShell/plugins/QuizWidget` pour le shell vivant.
- **Type plugin :** `daemon` ; permissions exactement `["settings_read", "settings_write", "process", "network"]` (validé contre `quickshell/PLUGINS/plugin-schema.json`).
- **Modèle IA :** `claude-haiku-4-5` exactement (ne pas suffixer de date). Endpoint `POST https://api.anthropic.com/v1/messages`, en-têtes `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`. Sortie contrainte via `output_config.format` (json_schema).
- **Tokens de thème :** uniquement ceux de `quickshell/PLUGINS/THEME_REFERENCE.md` — `Theme.onSurface` / `Theme.onSurfaceVariant` / `Theme.outline` / `Theme.primary` / `Theme.onPrimary` / `Theme.error` / `Theme.success` / `Theme.surfaceContainer{,High,Highest}` / `Theme.cornerRadius{,Large}` / `Theme.spacing{XS,S,M,L}` / `Theme.fontSize{Small,Medium,Large}` / `Theme.iconSize{Small,}`. Bordure : `Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.08)`. PAS de `Theme.surfaceText`, `primaryContainer`, `outlineMedium` (n'existent pas).
- **Convention JS :** `.pragma library` en tête ; import via `import "QuizEngine.js" as QuizEngine`.
- **YAGNI v1 :** pas de stats, pas d'adaptation de difficulté, QCM choix unique uniquement, une seule question en attente, pas de raccourcis clavier.
- **Style de code :** suivre les composants existants (`qs.Widgets` : `StyledRect`, `StyledText`, `DankIcon`).

## File Structure

| Fichier | Responsabilité |
|---|---|
| `quickshell/PLUGINS/QuizWidget/plugin.json` | Manifest daemon |
| `quickshell/PLUGINS/QuizWidget/QuizEngine.js` | Logique pure : `validate`, `pickQuestion`, `buildAiRequestBody`, `parseAiQuestion` |
| `quickshell/PLUGINS/QuizWidget/QuizProvider.qml` | Source de questions : banque locale + IA (curl) avec fallback |
| `quickshell/PLUGINS/QuizWidget/QuizCard.qml` | Carte QCM (question, choix, validation, feedback) |
| `quickshell/PLUGINS/QuizWidget/QuizOverlay.qml` | PanelWindow coin bas-droit : pastille ↔ carte |
| `quickshell/PLUGINS/QuizWidget/QuizDaemon.qml` | PluginComponent : Timer pomodoro + machine à états + câblage |
| `quickshell/PLUGINS/QuizWidget/QuizSettings.qml` | Premier setup (sujets, durée, toggle IA, clé) |
| `quickshell/PLUGINS/QuizWidget/banks/algorithmes.json` | Banque seed |
| `quickshell/PLUGINS/QuizWidget/banks/culture-generale.json` | Banque seed |
| `quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs` | Tests node de la logique pure |

---

### Task 0 : Scaffold, manifest, déploiement & vérification de chargement

**Files:**
- Create: `quickshell/PLUGINS/QuizWidget/plugin.json`
- Create: `quickshell/PLUGINS/QuizWidget/QuizDaemon.qml` (stub)

**Interfaces:**
- Produces: un plugin `quizWidget` de type `daemon` qui se charge et logge au démarrage.

- [ ] **Step 1 : Écrire le manifest**

`quickshell/PLUGINS/QuizWidget/plugin.json` :
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

- [ ] **Step 2 : Écrire le daemon stub**

`quickshell/PLUGINS/QuizWidget/QuizDaemon.qml` :
```qml
import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root
    property var popoutService: null
    Component.onCompleted: console.info("QuizDaemon: started (stub)")
    Component.onDestruction: console.info("QuizDaemon: stopped")
}
```

> Note : `QuizSettings.qml` est référencé dans le manifest mais créé en Task 8. Si le shell refuse de charger faute du fichier `settings`, créer un stub vide `QuizSettings.qml` (`import QtQuick; import qs.Modules.Plugins; PluginSettings { pluginId: "quizWidget" }`) maintenant et l'étoffer en Task 8.

- [ ] **Step 3 : Déployer en lien symbolique vers la config du shell vivant**

Run :
```bash
mkdir -p ~/.config/DankMaterialShell/plugins
ln -sfn "$PWD/quickshell/PLUGINS/QuizWidget" ~/.config/DankMaterialShell/plugins/QuizWidget
ls -l ~/.config/DankMaterialShell/plugins/QuizWidget
```
Expected : le lien pointe vers le dossier du repo.

- [ ] **Step 4 : Activer le plugin et vérifier le chargement**

Activer le plugin via l'onglet Plugins des réglages DMS (toggle `Quiz Widget`). Puis :
```bash
journalctl --user -u dms -n 80 --no-pager | grep -i quiz
```
Expected : ligne `QuizDaemon: started (stub)`. Aucune erreur QML (`grep -i error`).

- [ ] **Step 5 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/plugin.json quickshell/PLUGINS/QuizWidget/QuizDaemon.qml
git commit -m "feat(quiz-widget): scaffold daemon plugin manifest and stub"
```

---

### Task 1 : Banques seed + `QuizEngine.validate` (TDD node)

**Files:**
- Create: `quickshell/PLUGINS/QuizWidget/banks/algorithmes.json`
- Create: `quickshell/PLUGINS/QuizWidget/banks/culture-generale.json`
- Create: `quickshell/PLUGINS/QuizWidget/QuizEngine.js`
- Create: `quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`

**Interfaces:**
- Produces: `QuizEngine.validate(q) -> bool`. Question valide = objet `{ question:string non vide, choices:string[] (≥2, non vides), answer:int dans [0, choices.length), explanation:string non vide }`.

- [ ] **Step 1 : Écrire les banques seed**

`quickshell/PLUGINS/QuizWidget/banks/algorithmes.json` :
```json
[
  { "id": "algo-001", "question": "Quelle est la complexité d'une recherche dichotomique ?", "choices": ["O(n)", "O(log n)", "O(n²)", "O(1)"], "answer": 1, "explanation": "L'espace de recherche est divisé par deux à chaque étape." },
  { "id": "algo-002", "question": "Quelle structure suit le principe LIFO ?", "choices": ["File", "Pile", "Arbre", "Graphe"], "answer": 1, "explanation": "Une pile (stack) est Last-In First-Out." }
]
```

`quickshell/PLUGINS/QuizWidget/banks/culture-generale.json` :
```json
[
  { "id": "cg-001", "question": "En quelle année a eu lieu la Révolution française ?", "choices": ["1689", "1789", "1889", "1989"], "answer": 1, "explanation": "La prise de la Bastille date du 14 juillet 1789." }
]
```

- [ ] **Step 2 : Écrire le test échouant (validate)**

`quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs` :
```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

// Charge QuizEngine.js (fichier .pragma library) dans un contexte node.
function loadEngine() {
    const path = fileURLToPath(new URL("../QuizEngine.js", import.meta.url));
    const src = readFileSync(path, "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
    const ctx = {};
    vm.createContext(ctx);
    vm.runInContext(
        src + "\n;globalThis.__api = { validate, pickQuestion, buildAiRequestBody, parseAiQuestion };",
        ctx
    );
    return ctx.__api;
}
const E = loadEngine();

const good = { question: "Q ?", choices: ["a", "b"], answer: 1, explanation: "parce que" };

test("validate accepte une question correcte", () => {
    assert.equal(E.validate(good), true);
});
test("validate rejette answer hors bornes", () => {
    assert.equal(E.validate({ ...good, answer: 5 }), false);
});
test("validate rejette < 2 choix", () => {
    assert.equal(E.validate({ ...good, choices: ["a"] }), false);
});
test("validate rejette question vide", () => {
    assert.equal(E.validate({ ...good, question: "  " }), false);
});
test("validate rejette explication manquante", () => {
    assert.equal(E.validate({ ...good, explanation: "" }), false);
});
```

- [ ] **Step 3 : Lancer le test pour vérifier l'échec**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : FAIL (le fichier `QuizEngine.js` n'existe pas → erreur de lecture / `validate is not defined`).

- [ ] **Step 4 : Écrire l'implémentation minimale**

`quickshell/PLUGINS/QuizWidget/QuizEngine.js` :
```js
.pragma library

function validate(q) {
    if (!q || typeof q !== "object") return false;
    if (typeof q.question !== "string" || q.question.trim() === "") return false;
    if (typeof q.explanation !== "string" || q.explanation.trim() === "") return false;
    if (!Array.isArray(q.choices) || q.choices.length < 2) return false;
    for (var i = 0; i < q.choices.length; i++) {
        if (typeof q.choices[i] !== "string" || q.choices[i].trim() === "") return false;
    }
    if (typeof q.answer !== "number" || Math.floor(q.answer) !== q.answer) return false;
    if (q.answer < 0 || q.answer >= q.choices.length) return false;
    return true;
}
```

- [ ] **Step 5 : Lancer le test pour vérifier le succès**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : PASS (5 tests).

- [ ] **Step 6 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizEngine.js quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs quickshell/PLUGINS/QuizWidget/banks/
git commit -m "feat(quiz-widget): seed banks and QuizEngine.validate with tests"
```

---

### Task 2 : `QuizEngine.pickQuestion` (TDD node)

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizEngine.js`
- Modify: `quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`

**Interfaces:**
- Consumes: `validate`.
- Produces: `pickQuestion(bank, seen, rng?) -> { question, seen } | null`. Choisit une question valide non vue (`seen` = tableau d'`id`) ; si toutes vues, recycle (repart de `seen=[]`). `rng` optionnel (défaut `Math.random`) pour des tests déterministes. Retourne `null` si aucune question valide.

- [ ] **Step 1 : Écrire les tests échouants (pickQuestion)**

Ajouter à `tests/quizEngine.test.mjs` (le loader `E` est déjà défini en tête) :
```js
const bank = [
    { id: "a", question: "Qa ?", choices: ["1", "2"], answer: 0, explanation: "ea" },
    { id: "b", question: "Qb ?", choices: ["1", "2"], answer: 1, explanation: "eb" }
];

test("pickQuestion choisit la première du pool avec rng=0", () => {
    const r = E.pickQuestion(bank, [], () => 0);
    assert.equal(r.question.id, "a");
    assert.deepEqual(r.seen, ["a"]);
});
test("pickQuestion évite les déjà-vues", () => {
    const r = E.pickQuestion(bank, ["a"], () => 0);
    assert.equal(r.question.id, "b");
    assert.deepEqual(r.seen, ["a", "b"]);
});
test("pickQuestion recycle quand tout est vu", () => {
    const r = E.pickQuestion(bank, ["a", "b"], () => 0);
    assert.equal(r.question.id, "a");
    assert.deepEqual(r.seen, ["a"]); // seen réinitialisé puis 1 ajout
});
test("pickQuestion ignore les questions invalides", () => {
    const mixed = [{ id: "bad", question: "", choices: ["1"], answer: 9, explanation: "" }, bank[0]];
    const r = E.pickQuestion(mixed, [], () => 0);
    assert.equal(r.question.id, "a");
});
test("pickQuestion retourne null sur banque vide/invalide", () => {
    assert.equal(E.pickQuestion([], [], () => 0), null);
});
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : FAIL (`pickQuestion is not defined` / résultats `null`).

- [ ] **Step 3 : Implémenter**

Ajouter à `QuizEngine.js` :
```js
function pickQuestion(bank, seen, rng) {
    rng = rng || Math.random;
    seen = seen || [];
    var valid = (bank || []).filter(validate);
    if (valid.length === 0) return null;
    var unseen = valid.filter(function (q) { return seen.indexOf(q.id) === -1; });
    var recycling = unseen.length === 0;
    var pool = recycling ? valid : unseen;
    var nextSeen = recycling ? [] : seen.slice();
    var idx = Math.floor(rng() * pool.length);
    if (idx >= pool.length) idx = pool.length - 1;
    var chosen = pool[idx];
    nextSeen.push(chosen.id);
    return { question: chosen, seen: nextSeen };
}
```

- [ ] **Step 4 : Lancer pour vérifier le succès**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : PASS (tous les tests).

- [ ] **Step 5 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizEngine.js quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs
git commit -m "feat(quiz-widget): QuizEngine.pickQuestion with rotation and tests"
```

---

### Task 3 : `QuizEngine.buildAiRequestBody` + `parseAiQuestion` (TDD node)

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizEngine.js`
- Modify: `quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`

**Interfaces:**
- Consumes: `validate`.
- Produces:
  - `buildAiRequestBody(subject) -> string` (JSON) : corps de requête Claude (`model: "claude-haiku-4-5"`, `output_config.format` json_schema = forme question).
  - `parseAiQuestion(stdout) -> question | null` : parse la réponse API (`stdout` curl), extrait `content[].type==="text"` → `JSON.parse` → `validate` ; assigne un `id` stable (`"ai-"+hash`) si absent. `null` si invalide à n'importe quelle étape.

- [ ] **Step 1 : Écrire les tests échouants**

Ajouter à `tests/quizEngine.test.mjs` :
```js
test("buildAiRequestBody produit un corps valide pour Claude", () => {
    const body = JSON.parse(E.buildAiRequestBody("algorithmes"));
    assert.equal(body.model, "claude-haiku-4-5");
    assert.equal(body.output_config.format.type, "json_schema");
    assert.deepEqual(body.output_config.format.schema.required, ["question", "choices", "answer", "explanation"]);
    assert.match(JSON.stringify(body.messages), /algorithmes/);
});

const apiOk = JSON.stringify({
    content: [{ type: "text", text: JSON.stringify({ question: "Qx ?", choices: ["1", "2", "3", "4"], answer: 2, explanation: "ex" }) }]
});

test("parseAiQuestion extrait et valide une question", () => {
    const q = E.parseAiQuestion(apiOk);
    assert.equal(q.question, "Qx ?");
    assert.equal(q.answer, 2);
    assert.ok(q.id.startsWith("ai-"));
});
test("parseAiQuestion retourne null sur stdout non-JSON", () => {
    assert.equal(E.parseAiQuestion("curl: (6) could not resolve host"), null);
});
test("parseAiQuestion retourne null si le texte n'est pas une question valide", () => {
    const bad = JSON.stringify({ content: [{ type: "text", text: JSON.stringify({ question: "Q", choices: ["x"], answer: 0, explanation: "" }) }] });
    assert.equal(E.parseAiQuestion(bad), null);
});
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : FAIL (`buildAiRequestBody`/`parseAiQuestion` non définis).

- [ ] **Step 3 : Implémenter**

Ajouter à `QuizEngine.js` :
```js
function hashString(s) {
    var h = 0;
    for (var i = 0; i < s.length; i++) { h = ((h << 5) - h + s.charCodeAt(i)) | 0; }
    return Math.abs(h);
}

function buildAiRequestBody(subject) {
    return JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: 1024,
        system: "Tu es un générateur de QCM. Génère UNE question à choix unique, claire et factuelle, "
              + "avec 4 propositions dont une seule correcte, et une explication courte. "
              + "Réponds uniquement via le format structuré.",
        messages: [{ role: "user", content: "Sujet : " + subject + ". Génère une question QCM." }],
        output_config: {
            format: {
                type: "json_schema",
                schema: {
                    type: "object",
                    properties: {
                        question: { type: "string" },
                        choices: { type: "array", items: { type: "string" } },
                        answer: { type: "integer" },
                        explanation: { type: "string" }
                    },
                    required: ["question", "choices", "answer", "explanation"],
                    additionalProperties: false
                }
            }
        }
    });
}

function parseAiQuestion(stdout) {
    var resp;
    try { resp = JSON.parse(stdout); } catch (e) { return null; }
    if (!resp || !Array.isArray(resp.content)) return null;
    var textBlock = null;
    for (var i = 0; i < resp.content.length; i++) {
        if (resp.content[i] && resp.content[i].type === "text") { textBlock = resp.content[i]; break; }
    }
    if (!textBlock || typeof textBlock.text !== "string") return null;
    var q;
    try { q = JSON.parse(textBlock.text); } catch (e2) { return null; }
    if (!validate(q)) return null;
    if (!q.id) q.id = "ai-" + hashString(q.question);
    return q;
}
```

- [ ] **Step 4 : Lancer pour vérifier le succès**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : PASS (tous les tests).

- [ ] **Step 5 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizEngine.js quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs
git commit -m "feat(quiz-widget): QuizEngine AI request body + response parsing with tests"
```

---

### Task 4 : `QuizProvider.qml` (banque locale + IA avec fallback)

**Files:**
- Create: `quickshell/PLUGINS/QuizWidget/QuizProvider.qml`

**Interfaces:**
- Consumes: `QuizEngine.pickQuestion`, `QuizEngine.buildAiRequestBody`, `QuizEngine.parseAiQuestion` ; `Proc.runCommand` (`qs.Common`).
- Produces: `QuizProvider` (Item) avec propriétés `aiEnabled:bool`, `apiKey:string` et la fonction `fetchQuestion(subject, seen, callback)` où `callback(question|null, newSeen)`.

- [ ] **Step 1 : Implémenter**

`quickshell/PLUGINS/QuizWidget/QuizProvider.qml` :
```qml
import QtQuick
import qs.Common
import "QuizEngine.js" as QuizEngine

Item {
    id: provider
    property bool aiEnabled: false
    property string apiKey: ""

    // fetchQuestion(subject, seen, callback(question|null, newSeen))
    function fetchQuestion(subject, seen, callback) {
        if (provider.aiEnabled && provider.apiKey !== "") {
            _fetchAi(subject, function (q) {
                if (q) {
                    var ns = (seen || []).slice();
                    ns.push(q.id);
                    callback(q, ns);
                } else {
                    _fetchLocal(subject, seen, callback); // fallback
                }
            });
        } else {
            _fetchLocal(subject, seen, callback);
        }
    }

    function _fetchLocal(subject, seen, callback) {
        var bank = _loadBank(subject);
        var res = QuizEngine.pickQuestion(bank, seen);
        if (res) callback(res.question, res.seen);
        else callback(null, seen || []);
    }

    function _loadBank(subject) {
        var path = Qt.resolvedUrl("banks/" + subject + ".json");
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", path, false);
            xhr.send();
            if (xhr.status === 200 || xhr.status === 0)
                return JSON.parse(xhr.responseText);
        } catch (e) {
            console.warn("QuizProvider: cannot load bank", subject, e);
        }
        return [];
    }

    function _fetchAi(subject, callback) {
        var body = QuizEngine.buildAiRequestBody(subject);
        Proc.runCommand("quizWidget.gen", [
            "curl", "-s", "-X", "POST", "https://api.anthropic.com/v1/messages",
            "-H", "x-api-key: " + provider.apiKey,
            "-H", "anthropic-version: 2023-06-01",
            "-H", "content-type: application/json",
            "-d", body
        ], function (stdout, exitCode) {
            if (exitCode !== 0) { console.warn("QuizProvider: AI curl exit", exitCode); callback(null); return; }
            callback(QuizEngine.parseAiQuestion(stdout));
        }, 0);
    }
}
```

- [ ] **Step 2 : Vérifier manuellement (banque locale)**

Câbler temporairement un test dans le daemon stub pour exercer le provider : dans `QuizDaemon.qml` ajouter sous le `PluginComponent` un `QuizProvider { id: provider }` et, dans `Component.onCompleted`, après le log : `provider.fetchQuestion("algorithmes", [], function (q, s) { console.info("QUIZTEST local:", q ? q.question : "null"); });`. Recharger (le shell hot-reload). Puis :
```bash
journalctl --user -u dms -n 60 --no-pager | grep QUIZTEST
```
Expected : `QUIZTEST local:` suivi d'un énoncé de `algorithmes.json`. Aucune erreur QML.

- [ ] **Step 3 : Vérifier manuellement (fallback IA)**

Mettre `provider.aiEnabled = true` et `provider.apiKey = "sk-ant-INVALIDE"` dans le test temporaire. Recharger. Expected (journalctl) : un warning `AI curl exit` non-zéro OU un `parseAiQuestion`→null, puis tout de même `QUIZTEST local:` avec une question de la banque (le fallback a joué). Retirer ensuite le bloc de test temporaire.

- [ ] **Step 4 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizProvider.qml
git commit -m "feat(quiz-widget): QuizProvider with local bank and AI fallback"
```

---

### Task 5 : `QuizCard.qml` (carte QCM)

**Files:**
- Create: `quickshell/PLUGINS/QuizWidget/QuizCard.qml`

**Interfaces:**
- Consumes: `Theme`, `qs.Widgets` (`StyledRect`, `StyledText`).
- Produces: `QuizCard` avec propriétés `question:var`, `mode:string` (`"open"`|`"feedback"`), `selected:int` ; signaux `select(int index)`, `submit()`, `close()`.

- [ ] **Step 1 : Implémenter**

`quickshell/PLUGINS/QuizWidget/QuizCard.qml` :
```qml
import QtQuick
import qs.Common
import qs.Widgets

StyledRect {
    id: card
    property var question: null
    property string mode: "open"   // "open" | "feedback"
    property int selected: -1
    signal select(int index)
    signal submit()
    signal close()

    readonly property bool correct: question && selected === question.answer

    implicitWidth: 360
    implicitHeight: col.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadiusLarge
    color: Theme.surfaceContainer
    border.width: 1
    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.08)

    Column {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        StyledText {
            width: parent.width
            text: card.question ? card.question.question : ""
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Medium
            color: Theme.onSurface
        }

        Column { // choix
            width: parent.width
            spacing: Theme.spacingXS
            visible: card.mode === "open"
            Repeater {
                model: card.question ? card.question.choices : []
                StyledRect {
                    required property int index
                    required property var modelData
                    width: parent.width
                    implicitHeight: choiceText.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: index === card.selected ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    border.width: index === card.selected ? 1 : 0
                    border.color: Theme.primary
                    StyledText {
                        id: choiceText
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        text: modelData
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.onSurface
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.select(index)
                    }
                }
            }
        }

        StyledText { // feedback
            width: parent.width
            visible: card.mode === "feedback"
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeMedium
            text: card.question
                  ? ((card.correct ? "✓ Correct" : "✗ Incorrect — réponse : " + card.question.choices[card.question.answer])
                     + "\n" + card.question.explanation)
                  : ""
            color: card.correct ? Theme.success : Theme.error
        }

        Row { // actions
            anchors.right: parent.right
            spacing: Theme.spacingS
            StyledRect {
                visible: card.mode === "open"
                implicitWidth: validateText.implicitWidth + Theme.spacingM * 2
                implicitHeight: validateText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: card.selected >= 0 ? Theme.primary : Theme.surfaceContainerHigh
                StyledText {
                    id: validateText
                    anchors.centerIn: parent
                    text: "Valider"
                    font.pixelSize: Theme.fontSizeMedium
                    color: card.selected >= 0 ? Theme.onPrimary : Theme.onSurfaceVariant
                }
                MouseArea { anchors.fill: parent; enabled: card.selected >= 0; cursorShape: Qt.PointingHandCursor; onClicked: card.submit() }
            }
            StyledRect {
                visible: card.mode === "feedback"
                implicitWidth: closeText.implicitWidth + Theme.spacingM * 2
                implicitHeight: closeText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                StyledText { id: closeText; anchors.centerIn: parent; text: "Fermer"; font.pixelSize: Theme.fontSizeMedium; color: Theme.onSurface }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: card.close() }
            }
        }
    }
}
```

> Si `required property int index` n'est pas supporté dans ce Repeater, utiliser les variables implicites `index`/`modelData` directement (selon la version de Qt). La vérification hot-reload (Task 7) le confirmera.

- [ ] **Step 2 : Vérifier manuellement (rendu isolé)**

La carte sera rendue via l'overlay en Task 6/7 ; pas de runner QML isolé. Vérifier ici uniquement l'absence d'erreur de chargement : recharger le shell et `journalctl --user -u dms -n 40 --no-pager | grep -i "QuizCard\|error"`. Expected : aucune erreur référant `QuizCard.qml` (le composant n'est pas encore instancié, on valide juste la syntaxe au parse si le shell pré-compile ; sinon la vraie validation arrive en Task 7).

- [ ] **Step 3 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizCard.qml
git commit -m "feat(quiz-widget): QuizCard QCM component"
```

---

### Task 6 : `QuizOverlay.qml` (PanelWindow coin bas-droit, pastille ↔ carte)

**Files:**
- Create: `quickshell/PLUGINS/QuizWidget/QuizOverlay.qml`

**Interfaces:**
- Consumes: `Quickshell`, `Quickshell.Wayland`, `Theme`, `qs.Widgets`, `QuizCard`.
- Produces: `QuizOverlay` (PanelWindow) avec propriété `question:var`, signal `closed()`, fonctions `showPending()` et `reset()`. États internes via `mode` : `"hidden"|"pending"|"open"|"feedback"`.

- [ ] **Step 1 : Implémenter**

`quickshell/PLUGINS/QuizWidget/QuizOverlay.qml` :
```qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

PanelWindow {
    id: overlay

    property var question: null
    signal closed()

    property string mode: "hidden" // "hidden"|"pending"|"open"|"feedback"
    property int selected: -1

    function showPending() { overlay.selected = -1; overlay.mode = "pending"; overlay.visible = true; }
    function reset() { overlay.mode = "hidden"; overlay.selected = -1; overlay.visible = false; overlay.closed(); }

    color: "transparent"
    visible: false

    WlrLayershell.namespace: "dms:quiz"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { bottom: true; right: true }
    margins { bottom: Theme.spacingL; right: Theme.spacingL }

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    Item {
        id: content
        anchors.fill: parent
        implicitWidth: card.visible ? card.implicitWidth : pill.implicitWidth
        implicitHeight: card.visible ? card.implicitHeight : pill.implicitHeight
        opacity: overlay.mode === "hidden" ? 0 : 1
        scale: overlay.mode === "hidden" ? 0.9 : 1
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        StyledRect { // pastille
            id: pill
            visible: overlay.mode === "pending"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            implicitWidth: pillRow.implicitWidth + Theme.spacingM * 2
            implicitHeight: pillRow.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                DankIcon { name: "quiz"; color: Theme.primary; font.pixelSize: Theme.iconSizeSmall }
                StyledText { text: "Quiz dispo"; font.pixelSize: Theme.fontSizeMedium; color: Theme.onSurface }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: overlay.mode = "open" }
        }

        QuizCard { // carte
            id: card
            visible: overlay.mode === "open" || overlay.mode === "feedback"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            question: overlay.question
            mode: overlay.mode === "feedback" ? "feedback" : "open"
            selected: overlay.selected
            onSelect: (i) => overlay.selected = i
            onSubmit: overlay.mode = "feedback"
            onClose: overlay.reset()
        }
    }
}
```

- [ ] **Step 2 : Vérifier manuellement (rendu pastille→carte→feedback)**

Câbler temporairement dans `QuizDaemon.qml` : `QuizOverlay { id: ov }` + dans `onCompleted` un délai de test :
```qml
Timer { interval: 1500; running: true; repeat: false; onTriggered: {
    ov.question = { question: "Test ?", choices: ["A", "B", "C", "D"], answer: 1, explanation: "B est correct." };
    ov.showPending();
} }
```
Recharger. Expected visuel : après ~1.5 s, une pastille « Quiz dispo » apparaît en bas-droite ; clic → carte avec 4 choix ; sélectionner B → « Valider » s'active → feedback « ✓ Correct … » ; « Fermer » → disparaît.
```bash
journalctl --user -u dms -n 60 --no-pager | grep -i "quiz\|error\|warning"
```
Expected : pas d'erreur QML (notamment pas de propriété Wayland/Theme inconnue).

> Si le `PanelWindow` ne s'affiche pas ou loggue une erreur de surface, l'envelopper dans un `LazyLoader { active: overlay.mode !== "hidden"; ... }` comme dans `Modules/OSD/`. Si une propriété Wayland diffère (`margins` vs `WlrLayershell.margins`), s'aligner sur la source réelle de `quickshell/Modules/OSD/DankOSD.qml`. Retirer le bloc de test temporaire après validation.

- [ ] **Step 3 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizOverlay.qml
git commit -m "feat(quiz-widget): QuizOverlay panel (pill <-> card)"
```

---

### Task 7 : `QuizDaemon.qml` (pomodoro + machine à états + câblage)

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizDaemon.qml`

**Interfaces:**
- Consumes: `QuizProvider.fetchQuestion`, `QuizOverlay.showPending`/`reset`, `pluginService.loadPluginData`, `QuizEngine` (indirectement).
- Produces: daemon complet. `requestQuiz()` ; état `pendingQuestion`, `sessionSeen` ; Timer pomodoro.

- [ ] **Step 1 : Implémenter le daemon complet**

Remplacer le contenu de `quickshell/PLUGINS/QuizWidget/QuizDaemon.qml` :
```qml
import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root
    property var popoutService: null

    // réglages (chargés en onCompleted, défauts ci-dessous)
    property bool widgetEnabled: true
    property bool paused: false
    property int workMinutes: 25
    property var subjects: []
    property bool aiEnabled: false
    property string apiKey: ""

    // état runtime
    property var pendingQuestion: null
    property var sessionSeen: ({})

    QuizProvider {
        id: provider
        aiEnabled: root.aiEnabled
        apiKey: root.apiKey
    }

    QuizOverlay {
        id: overlay
        question: root.pendingQuestion
        onClosed: root.pendingQuestion = null
    }

    Timer {
        id: workTimer
        interval: Math.max(1, root.workMinutes) * 60 * 1000
        repeat: true
        running: root.widgetEnabled && !root.paused
        onTriggered: root.requestQuiz()
    }

    function seenFor(subject) {
        return root.sessionSeen[subject] ? root.sessionSeen[subject] : [];
    }

    function requestQuiz() {
        if (root.pendingQuestion) return;            // une seule en attente
        if (!root.subjects || root.subjects.length === 0) return;
        var subject = root.subjects[Math.floor(Math.random() * root.subjects.length)];
        provider.fetchQuestion(subject, root.seenFor(subject), function (q, newSeen) {
            if (!q) { console.warn("QuizDaemon: pas de question pour", subject); return; }
            var s = root.sessionSeen;
            s[subject] = newSeen;
            root.sessionSeen = s;
            root.pendingQuestion = q;
            overlay.showPending();
        });
    }

    Component.onCompleted: {
        if (typeof pluginService !== "undefined" && pluginService) {
            root.widgetEnabled = pluginService.loadPluginData("quizWidget", "enabled", true);
            root.paused = pluginService.loadPluginData("quizWidget", "paused", false);
            root.workMinutes = parseInt(pluginService.loadPluginData("quizWidget", "workMinutes", "25")) || 25;
            root.subjects = pluginService.loadPluginData("quizWidget", "subjects", []);
            root.aiEnabled = pluginService.loadPluginData("quizWidget", "aiEnabled", false);
            root.apiKey = pluginService.loadPluginData("quizWidget", "apiKey", "");
        }
        console.info("QuizDaemon: started, work", root.workMinutes, "min, subjects", JSON.stringify(root.subjects));
    }
    Component.onDestruction: console.info("QuizDaemon: stopped")
}
```

- [ ] **Step 2 : Vérifier manuellement (cycle complet, intervalle court)**

Pour observer sans attendre 25 min : éditer temporairement `interval:` du `workTimer` en `10 * 1000` (10 s) ET initialiser `subjects: ["algorithmes"]` en dur (le réglage UI arrive en Task 8). Recharger. Expected : après ~10 s, la pastille apparaît ; le flux pastille→carte→réponse→feedback→fermer fonctionne ; ~10 s plus tard, une nouvelle pastille (rotation anti-répétition). Vérifier :
```bash
journalctl --user -u dms -n 80 --no-pager | grep -i "QuizDaemon\|error"
```
Expected : `QuizDaemon: started …` ; pas d'erreur. Rétablir `interval` (binding minutes) et retirer le `subjects` codé en dur après validation.

- [ ] **Step 3 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizDaemon.qml
git commit -m "feat(quiz-widget): pomodoro daemon state machine and wiring"
```

---

### Task 8 : `QuizSettings.qml` (premier setup)

**Files:**
- Modify/Create: `quickshell/PLUGINS/QuizWidget/QuizSettings.qml`

**Interfaces:**
- Consumes: `PluginSettings` et composants `qs.Modules.Plugins` (`ToggleSetting`, `SelectionSetting`, `StringSetting`, `ListSettingWithInput`).
- Produces: UI de réglages persistant les clés `enabled`, `paused`, `workMinutes`, `subjects`, `aiEnabled`, `apiKey` (lues par le daemon).

- [ ] **Step 1 : Implémenter**

`quickshell/PLUGINS/QuizWidget/QuizSettings.qml` :
```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "quizWidget"

    StyledText {
        width: parent.width
        text: "Quiz Widget"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.onSurface
    }

    ToggleSetting {
        settingKey: "enabled"
        label: "Activer le widget"
        description: "Affiche des quiz à la fin des cycles de travail"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "paused"
        label: "Pause"
        description: "Suspendre temporairement les quiz"
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "workMinutes"
        label: "Durée de travail"
        description: "Intervalle avant chaque quiz"
        options: [
            { label: "15 minutes", value: "15" },
            { label: "25 minutes", value: "25" },
            { label: "45 minutes", value: "45" },
            { label: "60 minutes", value: "60" }
        ]
        defaultValue: "25"
    }

    ListSettingWithInput {
        settingKey: "subjects"
        label: "Sujets"
        description: "Sujets à réviser (doit correspondre à un fichier banks/<sujet>.json et/ou un prompt IA)"
        defaultValue: []
        fields: [
            { id: "name", label: "Sujet", placeholder: "algorithmes", width: 220, required: true }
        ]
    }

    ToggleSetting {
        settingKey: "aiEnabled"
        label: "Générer via IA"
        description: "Utilise Claude pour générer des questions (sinon banque locale uniquement)"
        defaultValue: false
    }

    StringSetting {
        settingKey: "apiKey"
        label: "Clé API Anthropic"
        description: "Requise si « Générer via IA » est activé"
        placeholder: "sk-ant-…"
        defaultValue: ""
    }
}
```

> Note : `ListSettingWithInput` stocke des objets `{name: "..."}`. Le daemon attend un tableau de chaînes pour `subjects`. Adapter : soit le daemon mappe `subjects.map(s => s.name || s)`, soit on documente que `subjects` contient des objets. **Décision : adapter le daemon** — voir Step 2.

- [ ] **Step 2 : Adapter le daemon au format de `subjects`**

Dans `QuizDaemon.qml`, fonction `requestQuiz()`, remplacer la ligne de sélection du sujet par une normalisation tolérante (chaîne OU objet `{name}`) :
```qml
        var raw = root.subjects[Math.floor(Math.random() * root.subjects.length)];
        var subject = (raw && typeof raw === "object") ? (raw.name || "") : raw;
        if (!subject) return;
```

- [ ] **Step 3 : Vérifier manuellement (persistance + lecture par le daemon)**

Ouvrir réglages → onglet Plugins → Quiz Widget. Renseigner : durée 15 min, ajouter le sujet `algorithmes`, laisser IA OFF. Fermer/rouvrir les réglages → les valeurs persistent. Puis recharger le shell et :
```bash
journalctl --user -u dms -n 40 --no-pager | grep "QuizDaemon: started"
```
Expected : la ligne montre `work 15 min` et `subjects` contient `algorithmes` → confirme que le daemon lit bien ce que l'UI écrit. (Si les clés diffèrent, aligner `loadPluginData` sur les clés réellement écrites par `PluginSettings`.)

- [ ] **Step 4 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizSettings.qml quickshell/PLUGINS/QuizWidget/QuizDaemon.qml
git commit -m "feat(quiz-widget): first-setup settings UI and subject normalization"
```

---

### Task 9 : Vérification end-to-end + nettoyage

**Files:** (aucun nouveau)

**Interfaces:** valide l'ensemble du parcours.

- [ ] **Step 1 : Re-lancer toute la suite de tests pure**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : PASS (tous).

- [ ] **Step 2 : Parcours manuel complet (banque locale)**

Réglages : durée 15 min (ou abaisser temporairement `interval`), sujet `algorithmes`, IA OFF. Attendre/forcer un cycle → pastille → carte → réponse correcte ET incorrecte (relancer) → feedback correct vs error → fermer. Expected : feedback vert « ✓ Correct » quand bonne réponse, rouge « ✗ Incorrect — réponse : … » + explication sinon.

- [ ] **Step 3 : Parcours manuel (IA réelle, optionnel)**

Si une vraie clé est dispo : activer IA + saisir la clé. Forcer un cycle. Expected : une question générée par Claude s'affiche (ou fallback banque locale si l'appel échoue — vérifier `journalctl` pour `AI curl exit` / `parseAiQuestion`). Tester aussi clé invalide → fallback silencieux vers la banque.

- [ ] **Step 4 : Coexistence Dynamic Island**

Avec l'île activée, déclencher un quiz : la carte apparaît en bas-droite sans passer par les bannières de notification ni chevaucher une surface de l'île. Si chevauchement, augmenter `margins.bottom/right`.

- [ ] **Step 5 : Vérifier l'absence de fuite de timer / d'erreurs**

```bash
journalctl --user -u dms -n 120 --no-pager | grep -i "quiz\|error\|warning"
```
Expected : aucune erreur QML résiduelle ; le Timer pomodoro continue de tourner même après fermeture de la carte (état `pendingQuestion=null`, prochain cycle reprogrammé).

- [ ] **Step 6 : Commit final (si ajustements)**

```bash
git add quickshell/PLUGINS/QuizWidget/
git commit -m "test(quiz-widget): end-to-end verification adjustments"
```

---

## Notes pour l'implémenteur

- **Shell vivant depuis le worktree :** les edits QML se rechargent dans le desktop actif ; après chaque modif QML, vérifier `journalctl --user -u dms`. Les blocs de test temporaires (Tasks 4/6/7) doivent être retirés avant le commit de la tâche.
- **Timer pomodoro jamais gelé :** il vit dans le `PluginComponent` (composant de fond toujours mappé), pas dans l'overlay — ne pas déplacer la logique de timing dans l'overlay (les Timers gèlent quand toutes les surfaces d'un scope se démappent).
- **Clé API dans les args de process :** visible via `ps`. Acceptable pour un plugin desktop personnel ; ne pas logger la clé.
- **APIs Wayland incertaines :** en cas d'erreur de surface/propriété sur l'overlay, s'aligner sur `quickshell/Modules/OSD/DankOSD.qml` (référence réelle du pattern) — `LazyLoader`, `WlrLayershell.margins`, etc.

## Corrections appliquées pendant l'exécution (harness node)

Deux ajustements du harness de test (vs le code des Tasks 1-3) ont été nécessaires et sont déjà dans `tests/quizEngine.test.mjs` :

1. **Loader robuste aux fonctions absentes :** la ligne d'injection doit garder chaque fonction par `typeof` (les T1/T2 n'ont pas encore défini toutes les fonctions, sinon `ReferenceError`) :
   ```js
   src + "\n;globalThis.__api = {"
       + " validate: typeof validate !== 'undefined' ? validate : undefined,"
       + " pickQuestion: typeof pickQuestion !== 'undefined' ? pickQuestion : undefined,"
       + " buildAiRequestBody: typeof buildAiRequestBody !== 'undefined' ? buildAiRequestBody : undefined,"
       + " parseAiQuestion: typeof parseAiQuestion !== 'undefined' ? parseAiQuestion : undefined };"
   ```
2. **Comparaison de tableaux cross-realm :** les tableaux créés dans le contexte `vm` ont un `Array.prototype` d'un autre realm → `deepStrictEqual` échoue. Utiliser un helper `const arrEq = (a, b) => assert.deepEqual(Array.from(a), b);` pour toute comparaison de `r.seen` / `schema.required`.

## Corrections appliquées pendant l'exécution (QML, vérif live)

Vérifié sur le shell vivant (Hyprland) via `dms ipc plugins enable/reload` + `dms restart` + `journalctl`. Bugs corrigés :

1. **`THEME_REFERENCE.md` est partiellement faux** vs `Common/Theme.qml` : `Theme.cornerRadiusLarge` n'existe pas (utiliser `Theme.cornerRadius`) ; `DankIcon` expose `size` (pas `font.pixelSize`).
2. **Signal `closed()` interdit sur `PanelWindow`** (collision avec `QWindow.closed`) → renommé `dismissed()` (+ handler `onDismissed`).
3. **PanelWindow margins** : utiliser `WlrLayershell.margins { }` (pas un `margins {}` top-level), comme `Modules/OSD/DankOSD.qml`.
4. **`required property index`** dans un délégué Repeater : retiré au profit des `index`/`modelData` implicites.
5. **Collision de clé `"enabled"`** : `PluginService.enablePlugin` écrit `setPluginSetting(id, "enabled", true)` dans le même store que `PluginSettings` → retirer la `ToggleSetting "enabled"` (l'activation du plugin via l'onglet Plugins fait foi).
6. **Course de chargement des réglages** : lire les réglages via `Qt.callLater(loadSettings)` ET re-lire dans `requestQuiz()` (sinon `subjects` vaut `[]` car `pluginSettings` finit de charger après `Component.onCompleted`). Bonus : réglages pris en compte à chaud.
7. **Lecture de banque** : `XMLHttpRequest` synchrone lève « Invalid state » sous Quickshell → utiliser `FileView` (`Quickshell.Io`), pattern prouvé du repo (`PluginService.loadPluginManifestFile`).
8. **Couleur de texte** : `StyledText` a `color: Theme.surfaceText` par défaut (token texte réel). `Theme.onSurface` est un alias de `surfaceText`. Pour la lisibilité, garder un **texte clair sur surface sombre** (`surfaceContainer`/`surface`) — éclaircir le fond casse le contraste. Ne pas se fier au `THEME_REFERENCE.md` (plusieurs entrées fausses : `cornerRadiusLarge`, `DankIcon.font.pixelSize`, tokens texte) — vérifier `Common/Theme.qml`.

## Redesign visuel (bento)

Sur demande utilisateur, carte redessinée façon **bento** : tuiles arrondies distinctes (choix/feedback/actions), **bordures blanches en inset** (`Qt.rgba(1,1,1,0.14)`), survols, `ElevationShadow` (`Common/ElevationShadow.qml`, `level: Theme.elevationLevel3`) avec marge de rendu (`shadowPad`) dans l'overlay pour que l'ombre ne soit pas clippée. Surfaces sombres du thème (carte `surfaceContainer`, tuiles `surface`) + texte `surfaceText` → contraste fort, suit le thème dynamique. Vérif visuelle via captures `dms screenshot` (limite : occulté par les fenêtres ; crops utilisateur).

## Déploiement & découverte (à connaître)

- Le `FolderListModel userWatcher` de `PluginService` **ne détecte pas un symlink** ajouté à chaud (et un dossier ajouté à chaud n'est pas re-scanné en live de façon fiable). Déployer une **vraie copie** dans `~/.config/DankMaterialShell/plugins/QuizWidget/` puis **redémarrer le shell** (`dms restart`) pour la découverte initiale, ou ouvrir l'onglet Réglages → Plugins (qui appelle `scanPlugins()`).
- Activation/rechargement à chaud sans restart : `dms ipc plugins enable|reload|disable|status quizWidget`. ⚠️ `reload` cache-bust seulement le composant principal ; les composants QML importés (overlay/card) restent en cache → après modif d'un composant importé, **restart** pour vider le cache de l'engine.
