# Quiz Widget — Contenu via `claude -p` + sélection de sujets dev/IT — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Brancher la génération de questions sur `claude -p` (plus de clé API), avec un catalogue dev/IT curaté et un sélecteur de sujets partagé (carte d'onboarding au 1er lancement + panel réglages) qui alimente le contexte du prompt.

**Architecture:** La logique pure passe dans `QuizEngine.js` (prompt + extraction JSON robuste) et un nouveau `Catalog.js` (taxonomie dev/IT), tous deux testés sous `node`. `QuizProvider` appelle `claude -p` (fallback banque locale par `topicId` si présente, sinon cycle sauté). Un composant `TopicPicker.qml` (chips toggleables, présentation pure + binding réglages optionnel) est réutilisé dans `QuizSettings.qml` et dans une `QuizOnboardingCard.qml` montée par `QuizOverlay`. `QuizDaemon` pioche un `id` dans `selectedTopics`, le résout via `Catalog`, et déclenche l'onboarding au 1er lancement.

**Tech Stack:** Quickshell (QML), JavaScript (`.pragma library`), `Proc.runCommand` + `claude -p` (CLI Claude Code local), `PluginSettings`/`pluginService` pour la persistance, `node --test` pour la logique pure.

## Global Constraints

- **Emplacement versionné :** `quickshell/PLUGINS/QuizWidget/`. Composants importés (overlay/card/picker/Catalog.js) en cache moteur → après modif, **`dms restart`** (le `dms ipc plugins reload quizWidget` ne cache-bust que le composant principal).
- **Modèle IA :** `claude -p --model claude-haiku-4-5` (ne pas suffixer de date). Pas de clé API : `claude -p` s'appuie sur la session Claude Code locale (pattern prouvé par le nudge).
- **Tokens de thème RÉELS** (vérifiés dans `Common/Theme.qml`, le `THEME_REFERENCE.md` est partiellement faux) : `Theme.surfaceText`, `Theme.surfaceVariantText`, `Theme.primary`, `Theme.primaryText` (PAS `onPrimary`), `Theme.surfaceContainer{,High,Highest}`, `Theme.cornerRadius` (PAS `cornerRadiusLarge`), `Theme.spacing{XS,S,M,L}`, `Theme.fontSize{Small,Medium,Large}`, `Theme.iconSizeSmall`, `Theme.elevationLevel3`, `Theme.elevationEnabled`. Bordure inset blanche : `Qt.rgba(1, 1, 1, 0.14)`. `SettingsData.popoutElevationEnabled` pour l'ombre. `DankIcon` → `size:` (pas `font.pixelSize`).
- **Délégués `Repeater` :** utiliser `index`/`modelData` **implicites** (les `required property` posent problème dans cette version de Qt — cf. QuizCard). Pour accéder au `modelData` d'un Repeater parent depuis un Repeater imbriqué, **capturer** : `property var cat: modelData` sur le délégué parent.
- **Convention JS :** `.pragma library` en tête ; import via `import "Catalog.js" as Catalog` / `import "QuizEngine.js" as QuizEngine`.
- **YAGNI v1 :** catalogue dev/IT fixe (pas de saisie libre), un sujet par question, difficulté fixe « intermédiaire », pas de stats.
- **Comparaison de tableaux cross-realm (tests node) :** les tableaux renvoyés par le contexte `vm` ont un autre `Array.prototype` → comparer via `arrEq` (helper existant : `assert.deepEqual(Array.from(actual), expected)`).
- **Ordre des tâches & non-régression :** `QuizProvider` (signature + props) et `QuizDaemon` (bindings + appel) sont couplés → ils changent **dans la même tâche** (Task 6) pour ne jamais laisser le shell avec un binding sur propriété inexistante. Les Tasks 3-5 sont **additives ou inertes** pour l'ancien daemon (au pire dormant, jamais en erreur).

---

### Task 1 : `Catalog.js` — taxonomie dev/IT curatée (TDD node)

**Files:**
- Create: `quickshell/PLUGINS/QuizWidget/Catalog.js`
- Create: `quickshell/PLUGINS/QuizWidget/tests/catalog.test.mjs`

**Interfaces:**
- Produces :
  - `CATALOG : [{ id:string, label:string, category:string }]`
  - `CATEGORIES : string[]` (ordre fixe `["Technologies","Concepts","Méthodologies"]`)
  - `allCategories() -> string[]`
  - `topicById(id) -> {id,label,category} | null`
  - `topicsByCategory(category) -> [{...}]`
  - `categoriesWithTopics() -> [{ category, topics:[...] }]`

- [ ] **Step 1 : Écrire le test échouant**

`quickshell/PLUGINS/QuizWidget/tests/catalog.test.mjs` :
```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

function loadCatalog() {
    const path = fileURLToPath(new URL("../Catalog.js", import.meta.url));
    const src = readFileSync(path, "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
    const ctx = {};
    vm.createContext(ctx);
    vm.runInContext(
        src + "\n;globalThis.__api = { CATALOG, CATEGORIES, allCategories, topicById, topicsByCategory, categoriesWithTopics };",
        ctx
    );
    return ctx.__api;
}
const C = loadCatalog();

test("topicById trouve un sujet existant", () => {
    const t = C.topicById("python");
    assert.equal(t.label, "Python");
    assert.equal(t.category, "Technologies");
});
test("topicById renvoie null pour un id inconnu", () => {
    assert.equal(C.topicById("zzz"), null);
});
test("topicsByCategory filtre par catégorie", () => {
    const concepts = C.topicsByCategory("Concepts");
    assert.ok(concepts.length > 0);
    assert.ok(concepts.every(t => t.category === "Concepts"));
});
test("toutes les catégories du catalogue sont déclarées", () => {
    const cats = Array.from(C.allCategories());
    for (const t of C.CATALOG) {
        assert.ok(cats.includes(t.category), "catégorie inconnue: " + t.category);
    }
});
test("les id du catalogue sont uniques", () => {
    const ids = C.CATALOG.map(t => t.id);
    assert.equal(new Set(ids).size, ids.length);
});
test("chaque sujet a un label non vide", () => {
    for (const t of C.CATALOG) {
        assert.ok(typeof t.label === "string" && t.label.trim().length > 0);
    }
});
test("categoriesWithTopics regroupe par catégorie dans l'ordre", () => {
    const groups = C.categoriesWithTopics();
    assert.equal(groups.length, 3);
    assert.equal(groups[0].category, "Technologies");
    assert.ok(groups[0].topics.length > 0);
});
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/catalog.test.mjs`
Expected : FAIL (`Catalog.js` n'existe pas → erreur de lecture).

- [ ] **Step 3 : Implémenter**

`quickshell/PLUGINS/QuizWidget/Catalog.js` :
```js
.pragma library

var CATEGORIES = ["Technologies", "Concepts", "Méthodologies"];

var CATALOG = [
    // Technologies
    { id: "js", label: "JavaScript / TypeScript", category: "Technologies" },
    { id: "python", label: "Python", category: "Technologies" },
    { id: "go", label: "Go", category: "Technologies" },
    { id: "rust", label: "Rust", category: "Technologies" },
    { id: "java", label: "Java / JVM", category: "Technologies" },
    { id: "react", label: "React", category: "Technologies" },
    { id: "node", label: "Node.js", category: "Technologies" },
    { id: "sql", label: "SQL / PostgreSQL", category: "Technologies" },
    { id: "docker", label: "Docker", category: "Technologies" },
    { id: "kubernetes", label: "Kubernetes", category: "Technologies" },
    { id: "linux", label: "Linux / shell", category: "Technologies" },
    { id: "git", label: "Git", category: "Technologies" },
    { id: "cloud", label: "Cloud (AWS/GCP/Azure)", category: "Technologies" },
    // Concepts
    { id: "algorithms", label: "Algorithmes & complexité", category: "Concepts" },
    { id: "datastructures", label: "Structures de données", category: "Concepts" },
    { id: "oop", label: "Programmation orientée objet", category: "Concepts" },
    { id: "fp", label: "Programmation fonctionnelle", category: "Concepts" },
    { id: "networking", label: "Réseaux (TCP/IP, HTTP)", category: "Concepts" },
    { id: "security", label: "Sécurité (web, crypto)", category: "Concepts" },
    { id: "concurrency", label: "Concurrence & parallélisme", category: "Concepts" },
    { id: "databases", label: "Bases de données & modélisation", category: "Concepts" },
    { id: "os", label: "Systèmes d'exploitation", category: "Concepts" },
    { id: "patterns", label: "Design patterns", category: "Concepts" },
    { id: "architecture", label: "Architecture (REST, microservices)", category: "Concepts" },
    // Méthodologies
    { id: "agile", label: "Agile / Scrum", category: "Méthodologies" },
    { id: "tdd", label: "Tests & TDD", category: "Méthodologies" },
    { id: "cicd", label: "CI/CD", category: "Méthodologies" },
    { id: "devops", label: "DevOps", category: "Méthodologies" },
    { id: "gitflow", label: "Workflow Git (branching)", category: "Méthodologies" },
    { id: "codereview", label: "Revue de code", category: "Méthodologies" },
    { id: "cleancode", label: "Clean code / refactoring", category: "Méthodologies" }
];

function allCategories() {
    return CATEGORIES.slice();
}

function topicById(id) {
    for (var i = 0; i < CATALOG.length; i++) {
        if (CATALOG[i].id === id) return CATALOG[i];
    }
    return null;
}

function topicsByCategory(category) {
    var out = [];
    for (var i = 0; i < CATALOG.length; i++) {
        if (CATALOG[i].category === category) out.push(CATALOG[i]);
    }
    return out;
}

function categoriesWithTopics() {
    var out = [];
    for (var c = 0; c < CATEGORIES.length; c++) {
        out.push({ category: CATEGORIES[c], topics: topicsByCategory(CATEGORIES[c]) });
    }
    return out;
}
```

- [ ] **Step 4 : Lancer pour vérifier le succès**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/catalog.test.mjs`
Expected : PASS (7 tests).

- [ ] **Step 5 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/Catalog.js quickshell/PLUGINS/QuizWidget/tests/catalog.test.mjs
git commit -m "feat(quiz-widget): curated dev/IT topic catalog with tests"
```

---

### Task 2 : `QuizEngine.js` — `buildQuestionPrompt` + `extractQuestionJson` (TDD node)

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizEngine.js`
- Modify: `quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`

**Interfaces:**
- Consumes : `validate`, `hashString` (existants).
- Produces :
  - `buildQuestionPrompt(topicLabel, category) -> string` (prompt FR exigeant un JSON brut).
  - `extractQuestionJson(stdout) -> question | null` (strip fences, isole l'objet `{…}` équilibré en ignorant les accolades dans les chaînes, `JSON.parse`, `validate`, assigne `id`).
- Removes : `buildAiRequestBody`, `parseAiQuestion`.

> Note de non-régression : retirer ces deux fonctions ne casse pas l'ancien `QuizProvider` au chargement — il ne les appelle que via le chemin IA (`aiEnabled` + `apiKey`), inactif par défaut. Le provider est réécrit en Task 6.

- [ ] **Step 1 : Mettre à jour le harness de test (loader + remplacement des tests)**

Dans `quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`, **remplacer** les deux lignes du loader (qui exposaient `buildAiRequestBody`/`parseAiQuestion`) par :
```js
        + " buildQuestionPrompt: typeof buildQuestionPrompt !== 'undefined' ? buildQuestionPrompt : undefined,"
        + " extractQuestionJson: typeof extractQuestionJson !== 'undefined' ? extractQuestionJson : undefined,"
```
(le reste de l'objet `__api` — `validate`, `pickQuestion`, `randomNudge`, `randomEmoji`, `randomNudgeAngle`, `nudgePrompt`, `cleanNudge` — est conservé.)

Puis **supprimer** le bloc des tests `buildAiRequestBody`/`parseAiQuestion` et la constante `apiOk` (les `test(...)` « buildAiRequestBody produit… », « parseAiQuestion extrait… », « parseAiQuestion retourne null sur stdout non-JSON », « parseAiQuestion retourne null si le texte… »).

Enfin **ajouter** les nouveaux tests :
```js
test("buildQuestionPrompt inclut le label et la catégorie et exige du JSON", () => {
    const p = E.buildQuestionPrompt("Docker", "Technologies");
    assert.match(p, /Docker/);
    assert.match(p, /Technologies/);
    assert.match(p, /JSON/);
    assert.match(p, /4 propositions/);
});

const cliJson = JSON.stringify({ question: "Qx ?", choices: ["1", "2", "3", "4"], answer: 2, explanation: "ex" });

test("extractQuestionJson parse du JSON brut", () => {
    const q = E.extractQuestionJson(cliJson);
    assert.equal(q.question, "Qx ?");
    assert.equal(q.answer, 2);
    assert.ok(q.id.startsWith("ai-"));
});
test("extractQuestionJson gère les fences markdown", () => {
    const q = E.extractQuestionJson("Voici ta question :\n```json\n" + cliJson + "\n```\nVoilà !");
    assert.equal(q.question, "Qx ?");
});
test("extractQuestionJson isole l'objet au milieu de texte parasite", () => {
    const q = E.extractQuestionJson("Bien sûr ! " + cliJson + " J'espère que ça aide.");
    assert.equal(q.answer, 2);
});
test("extractQuestionJson gère une accolade à l'intérieur d'une chaîne", () => {
    const tricky = JSON.stringify({ question: "Que fait {} en JS ?", choices: ["1", "2", "3", "4"], answer: 0, explanation: "objet vide" });
    const q = E.extractQuestionJson(tricky);
    assert.equal(q.question, "Que fait {} en JS ?");
});
test("extractQuestionJson renvoie null sur une sortie non-JSON", () => {
    assert.equal(E.extractQuestionJson("Désolé, je ne peux pas répondre."), null);
});
test("extractQuestionJson renvoie null si la question est invalide", () => {
    const bad = JSON.stringify({ question: "Q", choices: ["x"], answer: 0, explanation: "" });
    assert.equal(E.extractQuestionJson(bad), null);
});
test("extractQuestionJson gère une entrée non-string", () => {
    assert.equal(E.extractQuestionJson(null), null);
});
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : FAIL (`buildQuestionPrompt`/`extractQuestionJson` non définis → `undefined is not a function`).

- [ ] **Step 3 : Implémenter dans `QuizEngine.js`**

**Supprimer** les fonctions `buildAiRequestBody` (lignes ~38-63) et `parseAiQuestion` (lignes ~65-79). **Ajouter** à la place (après `hashString`) :
```js
function buildQuestionPrompt(topicLabel, category) {
    return "Génère UNE question de quiz à choix unique, en français, de niveau intermédiaire, "
        + "sur le sujet suivant (catégorie « " + category + " ») : " + topicLabel + ". "
        + "La question doit être claire et factuelle, avec EXACTEMENT 4 propositions dont une seule correcte, "
        + "et une explication courte de la bonne réponse. "
        + "Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour, sans balises Markdown, de la forme : "
        + '{"question": "...", "choices": ["...", "...", "...", "..."], "answer": 0, "explanation": "..."} '
        + "où \"answer\" est l'index (0 à 3) de la bonne proposition dans \"choices\".";
}

function extractQuestionJson(stdout) {
    if (typeof stdout !== "string") return null;
    var text = stdout;
    // retire d'éventuelles fences markdown ```json … ```
    var fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
    if (fence) text = fence[1];
    // isole le premier objet {…} équilibré (en ignorant les accolades dans les chaînes)
    var start = text.indexOf("{");
    if (start === -1) return null;
    var depth = 0, end = -1, inStr = false, esc = false;
    for (var i = start; i < text.length; i++) {
        var ch = text.charAt(i);
        if (inStr) {
            if (esc) esc = false;
            else if (ch === "\\") esc = true;
            else if (ch === "\"") inStr = false;
            continue;
        }
        if (ch === "\"") inStr = true;
        else if (ch === "{") depth++;
        else if (ch === "}") { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end === -1) return null;
    var q;
    try { q = JSON.parse(text.substring(start, end + 1)); } catch (e) { return null; }
    if (!validate(q)) return null;
    if (!q.id) q.id = "ai-" + hashString(q.question);
    return q;
}
```

- [ ] **Step 4 : Lancer pour vérifier le succès**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : PASS (tous les tests, dont les 8 nouveaux ; plus aucune référence `buildAiRequestBody`/`parseAiQuestion`).

- [ ] **Step 5 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizEngine.js quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs
git commit -m "feat(quiz-widget): claude -p question prompt + robust JSON extraction (drop curl API helpers)"
```

---

### Task 3 : `TopicPicker.qml` — sélecteur de chips partagé

**Files:**
- Create: `quickshell/PLUGINS/QuizWidget/TopicPicker.qml`

**Interfaces:**
- Consumes : `Catalog.categoriesWithTopics` ; `Theme`, `qs.Widgets` (`StyledRect`, `StyledText`) ; le `PluginSettings` parent (`saveValue`/`loadValue`) quand `settingKey` est défini.
- Produces : `TopicPicker` (Column) avec `property string settingKey`, `property var selectedIds`, fonctions `toggle(id)`/`isSelected(id)`/`loadValue()`, signaux `toggled(string id)` et `changed(var ids)`.

- [ ] **Step 1 : Implémenter `TopicPicker.qml`**

```qml
import QtQuick
import qs.Common
import qs.Widgets
import "Catalog.js" as Catalog

Column {
    id: root

    // Mode réglages (optionnel) : si settingKey est défini, charge/persiste via le PluginSettings parent.
    property string settingKey: ""
    // Source de vérité de la sélection (liste d'id). En onboarding, lire selectedIds + écouter changed.
    property var selectedIds: []
    property bool isLoading: false

    signal toggled(string id)
    signal changed(var ids)

    width: parent ? parent.width : implicitWidth
    spacing: Theme.spacingM

    Component.onCompleted: if (root.settingKey !== "") loadValue()

    function loadValue() {
        var settings = findSettings();
        if (settings) {
            isLoading = true;
            selectedIds = settings.loadValue(settingKey, []);
            isLoading = false;
        }
    }

    function findSettings() {
        var item = parent;
        while (item) {
            if (item.saveValue !== undefined && item.loadValue !== undefined)
                return item;
            item = item.parent;
        }
        return null;
    }

    function isSelected(id) {
        return (root.selectedIds || []).indexOf(id) !== -1;
    }

    function toggle(id) {
        var ids = (root.selectedIds || []).slice();
        var i = ids.indexOf(id);
        if (i === -1) ids.push(id);
        else ids.splice(i, 1);
        root.selectedIds = ids;
        root.toggled(id);
        root.changed(ids);
        if (root.settingKey !== "" && !root.isLoading) {
            var settings = findSettings();
            if (settings) settings.saveValue(settingKey, ids);
        }
    }

    Repeater {
        model: Catalog.categoriesWithTopics()

        Column {
            id: catBlock
            property var cat: modelData
            width: root.width
            spacing: Theme.spacingS

            StyledText {
                text: catBlock.cat.category
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            Flow {
                width: root.width
                spacing: Theme.spacingS

                Repeater {
                    model: catBlock.cat.topics

                    StyledRect {
                        id: chip
                        property var topic: modelData
                        readonly property bool sel: (root.selectedIds || []).indexOf(chip.topic.id) !== -1
                        implicitWidth: chipText.implicitWidth + Theme.spacingM * 2
                        implicitHeight: chipText.implicitHeight + Theme.spacingS * 2
                        radius: Theme.cornerRadius
                        color: chip.sel ? Theme.primary : (chipArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer)
                        border.width: 1
                        border.color: chip.sel ? Theme.primary : Qt.rgba(1, 1, 1, 0.14)

                        StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.topic.label
                            font.pixelSize: Theme.fontSizeSmall
                            color: chip.sel ? Theme.primaryText : Theme.surfaceText
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggle(chip.topic.id)
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2 : Vérifier le chargement (parse seul)**

Run :
```bash
dms restart
sleep 3
journalctl --user -u dms -n 60 --no-pager | grep -i "TopicPicker\|error" | head
```
Expected : aucune erreur QML référant `TopicPicker.qml` (non encore instancié — validation visuelle en Tasks 4/5/7).

- [ ] **Step 3 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/TopicPicker.qml
git commit -m "feat(quiz-widget): shared TopicPicker chip selector component"
```

---

### Task 4 : `QuizSettings.qml` — intégrer `TopicPicker`, retirer clé API/IA/sujets libres

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizSettings.qml` (réécriture complète)

**Interfaces:**
- Consumes : `PluginSettings`, `ToggleSetting`, `SelectionSetting` (`qs.Modules.Plugins`), `TopicPicker`.
- Produces : UI persistant `paused`, `workMinutes`, `selectedTopics`. Clés `apiKey`/`aiEnabled`/`subjects` retirées de l'UI.

> Non-régression : l'ancien daemon lit encore `subjects` à ce stade → il devient simplement **dormant** (aucune quiz) jusqu'à Task 6. Pas d'erreur.

- [ ] **Step 1 : Réécrire `QuizSettings.qml`**

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
        color: Theme.surfaceText
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

    StyledText {
        width: parent.width
        text: "Sujets (dev & IT)"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Choisis les technos, concepts et méthodologies à réviser. Les questions sont générées par Claude (claude -p) sur ces sujets."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    TopicPicker {
        settingKey: "selectedTopics"
    }
}
```

- [ ] **Step 2 : Vérifier en live (panel réglages)**

Run : `dms restart`, puis ouvrir Réglages → Plugins → Quiz Widget.
Expected visuel : le panel montre Pause, Durée de travail, puis les **chips par catégorie** (Technologies / Concepts / Méthodologies). Cliquer une chip la remplit (`primary`) ; rouvrir le panel → la sélection persiste. Plus de champ « Clé API » ni de toggle « Générer via IA ».
```bash
journalctl --user -u dms -n 60 --no-pager | grep -i "QuizSettings\|TopicPicker\|error" | head
```
Expected : aucune erreur QML.

- [ ] **Step 3 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizSettings.qml
git commit -m "feat(quiz-widget): settings topic picker; remove api-key/ai toggle/free-text subjects"
```

---

### Task 5 : `QuizOnboardingCard.qml` + mode onboarding dans `QuizOverlay.qml`

**Files:**
- Create: `quickshell/PLUGINS/QuizWidget/QuizOnboardingCard.qml`
- Modify: `quickshell/PLUGINS/QuizWidget/QuizOverlay.qml`

**Interfaces:**
- `QuizOnboardingCard` : `signal start(var ids)` ; affiche un titre + `TopicPicker` autonome + bouton « Commencer » (actif si ≥ 1 sujet).
- `QuizOverlay` : nouveau mode `"onboarding"` ; `function showOnboarding()` ; `signal onboardingComplete(var ids)`.

> Non-régression : les ajouts à `QuizOverlay` sont **additifs** (nouveaux signal/mode/fonction) — l'ancien daemon continue de fonctionner sans les utiliser.

- [ ] **Step 1 : Créer `QuizOnboardingCard.qml`**

```qml
import QtQuick
import qs.Common
import qs.Widgets

StyledRect {
    id: cardRoot
    signal start(var ids)

    readonly property color insetBorder: Qt.rgba(1, 1, 1, 0.14)

    implicitWidth: 460
    implicitHeight: col.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: cardRoot.insetBorder

    ElevationShadow {
        anchors.fill: parent
        z: -1
        level: Theme.elevationLevel3
        targetRadius: cardRoot.radius
        targetColor: cardRoot.color
        borderColor: cardRoot.border.color
        borderWidth: cardRoot.border.width
        shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled
    }

    Column {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        StyledText {
            width: parent.width
            text: "Bienvenue 👋 Choisis tes sujets"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Sélectionne les technos, concepts et méthodologies dev/IT que tu veux réviser. Claude te posera des questions dessus."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        TopicPicker {
            id: picker
            width: parent.width
        }

        Item {
            width: parent.width
            height: startBtn.implicitHeight

            StyledRect {
                id: startBtn
                anchors.right: parent.right
                enabled: picker.selectedIds.length > 0
                implicitWidth: startText.implicitWidth + Theme.spacingL * 2
                implicitHeight: startText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: startBtn.enabled ? Theme.primary : Theme.surfaceContainer
                border.width: 1
                border.color: startBtn.enabled ? Qt.rgba(1, 1, 1, 0.22) : cardRoot.insetBorder

                StyledText {
                    id: startText
                    anchors.centerIn: parent
                    text: "Commencer"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: startBtn.enabled ? Theme.primaryText : Theme.surfaceVariantText
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: startBtn.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cardRoot.start(picker.selectedIds)
                }
            }
        }
    }
}
```

- [ ] **Step 2 : Ajouter le mode onboarding à `QuizOverlay.qml`**

Dans `quickshell/PLUGINS/QuizWidget/QuizOverlay.qml` :

(a) Après `signal snoozeRequested(int ms)` (ligne ~16), ajouter :
```qml
    signal onboardingComplete(var ids)
```

(b) Le commentaire du `property string mode` (ligne ~18) : étendre les modes documentés à `"hidden"|"pending"|"open"|"feedback"|"onboarding"`.

(c) Après `function showPending() { … }` (ligne ~24), ajouter :
```qml
    function showOnboarding() { overlay.mode = "onboarding"; overlay.visible = true; }
```

(d) Dans l'`Item { id: content … }`, remplacer les deux lignes `implicitWidth`/`implicitHeight` (lignes ~48-49) par :
```qml
        implicitWidth: onboardingCard.visible ? onboardingCard.implicitWidth : (card.visible ? card.implicitWidth : pill.implicitWidth)
        implicitHeight: onboardingCard.visible ? onboardingCard.implicitHeight : (card.visible ? card.implicitHeight : pill.implicitHeight)
```

(e) Juste après le bloc `QuizCard { id: card … }` (avant la fermeture de l'`Item { id: content }`), ajouter :
```qml
        QuizOnboardingCard {
            id: onboardingCard
            visible: overlay.mode === "onboarding"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            onStart: (ids) => {
                overlay.onboardingComplete(ids);
                overlay.mode = "hidden";
                overlay.visible = false;
            }
        }
```

- [ ] **Step 3 : Vérifier le chargement (parse seul)**

Run :
```bash
dms restart
sleep 3
journalctl --user -u dms -n 80 --no-pager | grep -i "QuizOverlay\|QuizOnboardingCard\|TopicPicker\|error" | head
```
Expected : aucune erreur QML. (Le déclenchement de l'onboarding se câble en Task 6 ; la carte n'apparaît pas encore.)

- [ ] **Step 4 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizOnboardingCard.qml quickshell/PLUGINS/QuizWidget/QuizOverlay.qml
git commit -m "feat(quiz-widget): onboarding card + overlay onboarding mode"
```

---

### Task 6 : `QuizProvider.qml` (claude -p) + `QuizDaemon.qml` (câblage) — bascule live

> Les deux fichiers changent **ensemble** : le provider perd sa signature/props et le daemon perd ses bindings + appelle la nouvelle signature. Les faire dans la même tâche évite tout binding sur propriété inexistante.

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizProvider.qml` (réécriture complète)
- Modify: `quickshell/PLUGINS/QuizWidget/QuizDaemon.qml` (réécriture complète)

**Interfaces:**
- `QuizProvider` : `fetchQuestion(topicId, label, category, seen, callback(question|null, newSeen))`. Plus de props `aiEnabled`/`apiKey`.
- `QuizDaemon` : `selectedTopics` (liste d'id) ; `requestQuiz()` ; `completeOnboarding(ids)` ; déclenchement onboarding au 1er lancement ; `firstQuizTimer` (~30 s).
- Consumes : `Catalog.topicById` ; `QuizEngine.buildQuestionPrompt`/`extractQuestionJson`/`pickQuestion` ; `overlay.showOnboarding`/`showPending` + `onboardingComplete` ; `pluginService.loadPluginData`/`savePluginData`.

- [ ] **Step 1 : Réécrire `QuizProvider.qml`**

```qml
import QtQuick
import Quickshell.Io
import qs.Common
import "QuizEngine.js" as QuizEngine

Item {
    id: provider

    // fetchQuestion(topicId, label, category, seen, callback(question|null, newSeen))
    function fetchQuestion(topicId, label, category, seen, callback) {
        _fetchAi(label, category, function (q) {
            if (q) {
                var ns = (seen || []).slice();
                ns.push(q.id);
                callback(q, ns);
            } else {
                _fetchLocal(topicId, seen, callback); // fallback banque locale si présente
            }
        });
    }

    // Génération via `claude -p` (CLI Claude Code local — pas de clé API, comme le nudge).
    function _fetchAi(label, category, callback) {
        var prompt = QuizEngine.buildQuestionPrompt(label, category);
        Proc.runCommand("quizWidget.gen", [
            "claude", "-p", "--model", "claude-haiku-4-5", prompt
        ], function (stdout, exitCode) {
            if (exitCode !== 0) {
                console.warn("QuizProvider: claude -p exit", exitCode);
                callback(null);
                return;
            }
            callback(QuizEngine.extractQuestionJson(stdout));
        }, 0);
    }

    function _fetchLocal(topicId, seen, callback) {
        _loadBank(topicId, function (bank) {
            var res = QuizEngine.pickQuestion(bank, seen);
            if (res)
                callback(res.question, res.seen);
            else
                callback(null, seen || []);
        });
    }

    // Lecture asynchrone de banks/<topicId>.json via FileView (pattern prouvé du repo).
    function _loadBank(topicId, cb) {
        var url = Qt.resolvedUrl("banks/" + topicId + ".json").toString();
        var path = url.indexOf("file://") === 0 ? url.substring(7) : url;
        bankFvComp.createObject(provider, { "path": path, "cb": cb });
    }

    Component {
        id: bankFvComp
        FileView {
            property var cb: null
            onLoaded: {
                var bank = [];
                try {
                    bank = JSON.parse(text());
                } catch (e) {
                    console.warn("QuizProvider: parse bank failed", path, e);
                }
                if (cb)
                    cb(bank);
                destroy();
            }
            onLoadFailed: err => {
                console.warn("QuizProvider: bank load failed", path, err);
                if (cb)
                    cb([]);
                destroy();
            }
        }
    }
}
```

- [ ] **Step 2 : Réécrire `QuizDaemon.qml`**

```qml
import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import "QuizEngine.js" as QuizEngine
import "Catalog.js" as Catalog

PluginComponent {
    id: root
    property var popoutService: null

    // réglages (chargés via Qt.callLater, défauts ci-dessous)
    property bool paused: false
    property bool snoozing: false
    property int workMinutes: 25
    property var selectedTopics: []

    // état runtime
    property var pendingQuestion: null
    property var sessionSeen: ({})
    property string nudgeText: "Quiz dispo"
    property string nudgeEmoji: "🦉"
    property int animIndex: 0

    QuizProvider {
        id: provider
    }

    QuizOverlay {
        id: overlay
        question: root.pendingQuestion
        nudge: root.nudgeText
        emoji: root.nudgeEmoji
        animIndex: root.animIndex
        onDismissed: root.pendingQuestion = null
        onSnoozeRequested: (ms) => root.snooze(ms)
        onOnboardingComplete: (ids) => root.completeOnboarding(ids)
    }

    // Accroche affichée sur la pastille : preset local immédiat, puis enrichie via `claude -p`.
    function fetchNudge() {
        root.nudgeText = QuizEngine.randomNudge();
        root.nudgeEmoji = QuizEngine.randomEmoji();
        root.animIndex = Math.floor(Math.random() * Math.max(1, overlay.animCount));
        Proc.runCommand("quizWidget.nudge", ["claude", "-p", QuizEngine.nudgePrompt()], function (stdout, exitCode) {
            if (exitCode === 0) {
                var n = QuizEngine.cleanNudge(stdout);
                if (n)
                    root.nudgeText = n;
            }
        }, 0);
    }

    Timer {
        id: workTimer
        interval: Math.max(1, root.workMinutes) * 60 * 1000
        repeat: true
        running: !root.paused && !root.snoozing
        onTriggered: root.requestQuiz()
    }

    Timer {
        id: snoozeTimer
        repeat: false
        onTriggered: {
            root.snoozing = false;
            root.requestQuiz();
        }
    }

    Timer {
        id: renudgeTimer
        interval: 5 * 60 * 1000
        repeat: true
        running: overlay.mode === "pending"
        onTriggered: {
            root.fetchNudge();
            console.info("QuizDaemon: re-nudge (quiz ignorée)");
        }
    }

    // Première quiz peu après l'onboarding (gratification immédiate), puis cadence pomodoro normale.
    Timer {
        id: firstQuizTimer
        interval: 30 * 1000
        repeat: false
        onTriggered: root.requestQuiz()
    }

    function snooze(ms) {
        root.pendingQuestion = null;
        snoozeTimer.interval = Math.max(1, ms);
        root.snoozing = true;
        snoozeTimer.restart();
        console.info("QuizDaemon: snooze", ms, "ms");
    }

    function seenFor(topicId) {
        return root.sessionSeen[topicId] ? root.sessionSeen[topicId] : [];
    }

    function requestQuiz() {
        if (root.pendingQuestion)
            return; // une seule en attente
        root.loadSettings(); // re-lecture fraîche (robuste à la course de chargement + réglages à chaud)
        if (!root.selectedTopics || root.selectedTopics.length === 0)
            return;
        var id = root.selectedTopics[Math.floor(Math.random() * root.selectedTopics.length)];
        var t = Catalog.topicById(id);
        if (!t) {
            console.warn("QuizDaemon: sujet inconnu", id);
            return;
        }
        provider.fetchQuestion(id, t.label, t.category, root.seenFor(id), function (q, newSeen) {
            if (!q) {
                console.warn("QuizDaemon: pas de question pour", id);
                return;
            }
            var s = root.sessionSeen;
            s[id] = newSeen;
            root.sessionSeen = s;
            root.pendingQuestion = q;
            root.fetchNudge();
            overlay.showPending();
        });
    }

    function completeOnboarding(ids) {
        if (typeof pluginService !== "undefined" && pluginService)
            pluginService.savePluginData("quizWidget", "selectedTopics", ids);
        root.selectedTopics = ids;
        console.info("QuizDaemon: onboarding terminé,", (ids ? ids.length : 0), "sujets");
        firstQuizTimer.restart();
    }

    function loadSettings() {
        if (typeof pluginService === "undefined" || !pluginService)
            return;
        root.paused = pluginService.loadPluginData("quizWidget", "paused", false);
        root.workMinutes = parseInt(pluginService.loadPluginData("quizWidget", "workMinutes", "25")) || 25;
        root.selectedTopics = pluginService.loadPluginData("quizWidget", "selectedTopics", []);
    }

    Component.onCompleted: {
        Qt.callLater(function () {
            root.loadSettings();
            if (!root.selectedTopics || root.selectedTopics.length === 0)
                overlay.showOnboarding();
            console.info("QuizDaemon: started, work", root.workMinutes, "min,", (root.selectedTopics ? root.selectedTopics.length : 0), "sujets");
        });
    }
    Component.onDestruction: console.info("QuizDaemon: stopped")
}
```

- [ ] **Step 3 : Vérifier en live (onboarding → `claude -p`)**

Pré-requis : aucune sélection enregistrée (sinon tout décocher via Réglages avant).
```bash
dms restart
sleep 3
journalctl --user -u dms -n 80 --no-pager | grep -i "QuizDaemon\|QuizProvider\|error"
```
Expected : `QuizDaemon: started …` sans erreur ; si `selectedTopics` vide, la **carte d'onboarding** apparaît en bas-droite. Cocher 2-3 sujets → « Commencer » → log `onboarding terminé, N sujets`. ~30 s après → pastille « Quiz dispo » → clic → carte avec **une vraie question `claude -p`** sur un sujet choisi.

- [ ] **Step 4 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizProvider.qml quickshell/PLUGINS/QuizWidget/QuizDaemon.qml
git commit -m "feat(quiz-widget): claude -p provider + selectedTopics/catalog/onboarding wiring"
```

---

### Task 7 : Vérification end-to-end + nettoyage

**Files:** (aucun nouveau, sauf nettoyage optionnel de `plugin.json`)

- [ ] **Step 1 : Suite de tests pure complète**

Run :
```bash
node --test quickshell/PLUGINS/QuizWidget/tests/
```
Expected : PASS (quizEngine.test.mjs + catalog.test.mjs). Aucune référence résiduelle à `buildAiRequestBody`/`parseAiQuestion`.

- [ ] **Step 2 : Parcours complet `claude -p`**

`dms restart`. Avec une sélection (ex. `docker`, `algorithms`, `tdd`), abaisser temporairement `firstQuizTimer` (5 s) ou `workTimer` si besoin pour observer vite. Forcer un cycle.
Expected : pastille → carte avec **une vraie question générée par `claude -p`** ; réponse correcte → feedback vert « ✓ Correct » + explication ; réponse incorrecte (relancer) → rouge « ✗ Incorrect — réponse : … ».
```bash
journalctl --user -u dms -n 120 --no-pager | grep -i "QuizProvider\|QuizDaemon\|claude -p\|error"
```
Expected : pas d'erreur QML ; génération aboutie (ou, en cas d'échec CLI, `claude -p exit` puis fallback banque/cycle sauté — jamais de crash ni de question malformée).

- [ ] **Step 3 : Panel réglages + ré-onboarding**

Réglages → Plugins → Quiz Widget : le `TopicPicker` reflète la sélection ; (dé)cocher persiste après réouverture ; aucun champ clé API. Tout décocher puis `dms restart` → l'onboarding réapparaît (au moins un sujet requis).

- [ ] **Step 4 : Fallback & robustesse**

Provoquer un échec `claude -p` (ex. couper la connexion réseau le temps d'un cycle) : le cycle est sauté proprement (`claude -p exit` non-zéro), pas de pastille, le pomodoro suivant réessaie. Aucune erreur QML, pas de question malformée.

- [ ] **Step 5 : (Optionnel) nettoyer la permission `network`**

Le plugin n'effectue plus d'appel réseau direct (`claude -p` s'en charge). On peut retirer `"network"` de `permissions` dans `quickshell/PLUGINS/QuizWidget/plugin.json` (garder `process`, `settings_read`, `settings_write`). Vérifier que le plugin charge toujours après `dms restart`.

- [ ] **Step 6 : Restaurer les intervalles de test + commit final (si ajustements)**

Rétablir `firstQuizTimer`/`workTimer` à leurs valeurs nominales.
```bash
git add quickshell/PLUGINS/QuizWidget/
git commit -m "test(quiz-widget): end-to-end verification adjustments"
```

---

## Notes pour l'implémenteur

- **Cache moteur :** toute modif de composant importé (`QuizProvider`, `QuizOverlay`, `QuizCard`, `TopicPicker`, `QuizOnboardingCard`, `Catalog.js`, `QuizEngine.js`) exige **`dms restart`** pour vider le cache (le `reload` ne suffit pas).
- **Pas de secret :** plus de clé API. Le prompt `claude -p` est visible via `ps` — sans importance.
- **Course de chargement des réglages :** `loadSettings` est rappelé dans `requestQuiz` (réglages à chaud + robustesse). Le déclenchement de l'onboarding se fait une seule fois dans le `Qt.callLater` de `Component.onCompleted`.
- **Carte d'onboarding haute :** ~31 chips sur 3 catégories ⇒ carte potentiellement haute. Si elle dépasse l'écran, l'envelopper plus tard dans un `Flickable` (hors périmètre v1).
- **Tokens de thème :** se référer à `Common/Theme.qml`. Texte sur `primary` = `Theme.primaryText`.
