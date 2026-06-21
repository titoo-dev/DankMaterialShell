# Quiz Widget — Mode « Apprentissage » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter un mode « Apprentissage » mono-sujet où l'IA (prof cool organique) délivre surtout des leçons (et parfois un quiz), avec persistance de l'avancement, activable via un sélecteur de mode dans les réglages.

**Architecture:** Un seul appel `claude -p` « enseigne la suite » renvoie un JSON `{type:"lesson"|"quiz", ...}` selon l'historique persisté. `QuizEngine.js` (pur, testé node) porte le prompt + le parsing. `QuizProvider` ajoute `fetchLearningStep`. Une nouvelle `LessonCard.qml` affiche les leçons ; `QuizOverlay` route quiz↔leçon. `QuizDaemon` branche selon `mode` et persiste `learningHistory`. `QuizSettings` ajoute le sélecteur + la section apprentissage.

**Tech Stack:** Quickshell (QML), JavaScript `.pragma library`, `Proc.runCommand` + `claude -p`, `PluginSettings`/`pluginService`, `node --test`.

## Global Constraints

- **Emplacement :** `quickshell/PLUGINS/QuizWidget/`. Composants importés en cache → après modif QML/JS, **`dms restart`** ; déployer par `rsync quickshell/PLUGINS/QuizWidget/ ~/.config/DankMaterialShell/plugins/QuizWidget/`.
- **claude -p :** chemin absolu `QuizEngine.claudeBinary(Quickshell.env("HOME"))` ; **timeout explicite** (5ᵉ arg de `Proc.runCommand` ; le 4ᵉ est `debounceMs`) — 60 s pour les leçons/questions.
- **Tokens thème réels** (`Common/Theme.qml`) : `surfaceText`, `surfaceVariantText`, `primary`, `primaryText`, `surfaceContainer{,High,Highest}`, `cornerRadius`, `spacing{XS,S,M,L}`, `fontSize{Small,Medium,Large}`, `iconSizeSmall`, `elevationLevel3`, `elevationEnabled` ; bordure inset `Qt.rgba(1,1,1,0.14)` ; `SettingsData.popoutElevationEnabled` ; `DankIcon` → `size:`. Markdown via `textFormat: Text.MarkdownText` + `elide: Text.ElideNone`.
- **Délégués Repeater :** `index`/`modelData` implicites.
- **Clés réglages (nouvelles) :** `mode` (`"quiz"`|`"learning"`, défaut `"quiz"`), `learningSubject` (string), `learningHistory` (string[]), `learningHistorySubject` (string). Historique plafonné à 60 ; 40 dernières envoyées au prompt.
- **Tests node cross-realm :** comparer via `Array.from(...)`.
- **Ordonnancement :** Tasks 1-5 sont **additives** (le mode quiz par défaut reste intact) ; Task 6 (daemon) met le mode learning en service.

---

### Task 1 : `QuizEngine.js` — prompt + parsing apprentissage (TDD node)

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizEngine.js`
- Modify: `quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`

**Interfaces:**
- Consumes : `validate`, `extractJsonObject`, `hashString`, `randomNudgeAngle`, `NUDGE_ANIMATIONS` (existants).
- Produces :
  - `buildLessonPrompt(subject, history) -> string`
  - `parseLearningStep(stdout) -> {type:"lesson",title,content,summary} | {type:"quiz",question,choices,answer,explanation,id,summary} | null`
  - `summarizeStep(step) -> string`
  - `buildNudgePrompt(angle, context)` gagne un 2ᵉ param `context` (défaut inchangé).

- [ ] **Step 1 : Étendre le loader + ajouter les tests échouants**

Dans `tests/quizEngine.test.mjs`, après la ligne `+ " animationIndex: ...,"` du loader, ajouter :
```js
        + " buildLessonPrompt: typeof buildLessonPrompt !== 'undefined' ? buildLessonPrompt : undefined,"
        + " parseLearningStep: typeof parseLearningStep !== 'undefined' ? parseLearningStep : undefined,"
        + " summarizeStep: typeof summarizeStep !== 'undefined' ? summarizeStep : undefined,"
```

Puis ajouter ces tests (en fin de fichier) :
```js
test("buildLessonPrompt inclut le sujet, l'historique, leçon/quiz et exige du JSON", () => {
    const p = E.buildLessonPrompt("Vim", ["modes", "dd/yy"]);
    assert.match(p, /Vim/);
    assert.match(p, /modes/);
    assert.match(p, /le[çc]on/i);
    assert.match(p, /quiz/i);
    assert.match(p, /JSON/);
});
test("buildLessonPrompt gère un historique vide", () => {
    const p = E.buildLessonPrompt("Vim", []);
    assert.match(p, /rien encore/);
});
test("parseLearningStep — leçon valide", () => {
    const s = E.parseLearningStep('{"type":"lesson","title":"Les modes","content":"**Normal** et `i`","summary":"modes de base"}');
    assert.equal(s.type, "lesson");
    assert.equal(s.title, "Les modes");
    assert.match(s.content, /Normal/);
    assert.equal(s.summary, "modes de base");
});
test("parseLearningStep — leçon sans summary -> summary = title", () => {
    const s = E.parseLearningStep('{"type":"lesson","title":"Le registre","content":"..."}');
    assert.equal(s.summary, "Le registre");
});
test("parseLearningStep — leçon sans contenu -> null", () => {
    assert.equal(E.parseLearningStep('{"type":"lesson","title":"X","content":"  "}'), null);
});
test("parseLearningStep — quiz valide", () => {
    const s = E.parseLearningStep('{"type":"quiz","question":"Quitter Vim ?","choices":[":q",":w",":x",":e"],"answer":0,"explanation":"...","summary":"sortie"}');
    assert.equal(s.type, "quiz");
    assert.equal(s.answer, 0);
    assert.ok(s.id.startsWith("ai-"));
    assert.equal(s.summary, "sortie");
});
test("parseLearningStep — quiz invalide (validate) -> null", () => {
    assert.equal(E.parseLearningStep('{"type":"quiz","question":"Q","choices":["a"],"answer":0,"explanation":""}'), null);
});
test("parseLearningStep — type inconnu / non-JSON -> null", () => {
    assert.equal(E.parseLearningStep('{"type":"autre"}'), null);
    assert.equal(E.parseLearningStep("désolé"), null);
});
test("parseLearningStep gère les fences markdown", () => {
    const s = E.parseLearningStep('```json\n{"type":"lesson","title":"T","content":"C"}\n```');
    assert.equal(s.type, "lesson");
});
test("summarizeStep renvoie le summary", () => {
    assert.equal(E.summarizeStep({ type: "lesson", summary: "abc" }), "abc");
});
test("buildNudgePrompt inclut le context fourni et garde le défaut", () => {
    assert.match(E.buildNudgePrompt("a", "une nouvelle leçon de Vim"), /nouvelle leçon de Vim/);
    assert.match(E.buildNudgePrompt("a"), /mini-quiz/);
});
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : FAIL (`buildLessonPrompt`/`parseLearningStep`/`summarizeStep` non définis ; le test context échoue car `buildNudgePrompt` ignore le 2ᵉ arg).

- [ ] **Step 3 : Implémenter dans `QuizEngine.js`**

Remplacer la signature de `buildNudgePrompt` pour accepter `context` :
```js
function buildNudgePrompt(angle, context) {
    var a = angle || randomNudgeAngle();
    var ctx = context || "un mini-quiz qui vient d'apparaître";
    return "Tu animes une pastille : " + ctx + ". Génère une accroche courte ET "
         + "choisis l'animation d'attention qui colle le mieux à l'émotion du message. "
         + "Style/ton à adopter : " + a + " — cool, taquin, drôle, légèrement provoc, mais bienveillant, jamais vulgaire. "
         + "Réponds UNIQUEMENT avec un objet JSON valide, sans texte ni balises autour, de la forme : "
         + '{"message": "...", "emoji": "🔥", "animation": "tada"} '
         + "Contraintes : message en français, max 7 mots, sans guillemets superflus ; "
         + "emoji = UN seul emoji expressif qui matche le ton ; "
         + "animation = EXACTEMENT une valeur parmi : " + NUDGE_ANIMATIONS.join(", ") + ". "
         + "Choisis selon l'énergie : excité/joyeux → tada, pop, bounce ; taquin/moqueur → wobble, shake, headshake ; "
         + "doux/posé → float, heartbeat, swing ; insistant → metronome, tilt, jump.";
}
```

Ajouter (après `parseNudge`) :
```js
// --- mode apprentissage (prof IA organique) ---

function buildLessonPrompt(subject, history) {
    var covered = (history && history.length) ? history.join(" ; ") : "rien encore";
    return "Tu es un prof cool, concis et bienveillant de « " + subject + " ». "
        + "Déjà couvert par l'apprenant : " + covered + ". "
        + "Donne LA PROCHAINE étape d'apprentissage, en construisant logiquement sur l'acquis, sans répéter. "
        + "La plupart du temps : une LEÇON courte et digeste (UNE notion à la fois, un exemple concret, "
        + "un emoji en tête, markdown **gras**/`code`). "
        + "De temps en temps seulement, si plusieurs notions ont déjà été vues et qu'une vérification est pertinente : "
        + "un QUIZ à choix unique sur ce qui a été couvert. "
        + "Réponds UNIQUEMENT avec un objet JSON valide, sans texte ni balises autour. "
        + 'Leçon : {"type":"lesson","title":"...","content":"...","summary":"..."} (content en markdown). '
        + 'Quiz : {"type":"quiz","question":"...","choices":["..","..","..",".."],"answer":0,"explanation":"...","summary":"..."}. '
        + "summary = courte phrase (max ~8 mots) résumant la notion, pour le suivi de progression.";
}

function parseLearningStep(stdout) {
    var o = extractJsonObject(stdout);
    if (!o || typeof o.type !== "string") return null;
    if (o.type === "lesson") {
        if (typeof o.title !== "string" || o.title.trim() === "") return null;
        if (typeof o.content !== "string" || o.content.trim() === "") return null;
        var lsum = (typeof o.summary === "string" && o.summary.trim() !== "") ? o.summary.trim() : o.title.trim();
        return { type: "lesson", title: o.title, content: o.content, summary: lsum };
    }
    if (o.type === "quiz") {
        if (!validate(o)) return null;
        var qsum = (typeof o.summary === "string" && o.summary.trim() !== "") ? o.summary.trim() : ("Quiz : " + o.question);
        if (qsum.length > 60) qsum = qsum.slice(0, 60);
        return {
            type: "quiz", question: o.question, choices: o.choices, answer: o.answer,
            explanation: o.explanation, id: o.id || ("ai-" + hashString(o.question)), summary: qsum
        };
    }
    return null;
}

function summarizeStep(step) {
    return (step && typeof step.summary === "string") ? step.summary : "";
}
```

- [ ] **Step 4 : Lancer pour vérifier le succès**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs`
Expected : PASS (tous).

- [ ] **Step 5 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizEngine.js quickshell/PLUGINS/QuizWidget/tests/quizEngine.test.mjs
git commit -m "feat(quiz-widget): learning-mode engine — buildLessonPrompt/parseLearningStep/summarizeStep + nudge context"
```

---

### Task 2 : `LessonCard.qml` (carte leçon)

**Files:**
- Create: `quickshell/PLUGINS/QuizWidget/LessonCard.qml`

**Interfaces:**
- Consumes : `Theme`, `qs.Widgets` (`StyledRect`, `StyledText`, `DankIcon`), `Catalog.categoryEmoji`.
- Produces : `LessonCard` avec `property var lesson` (`{title, content, summary, topicLabel, topicCategory}`) ; signaux `next()`, `close()`, `snooze(int ms)`.

- [ ] **Step 1 : Créer `LessonCard.qml`**

```qml
import QtQuick
import qs.Common
import qs.Widgets
import "Catalog.js" as Catalog

StyledRect {
    id: card
    property var lesson: null
    signal next()
    signal close()
    signal snooze(int ms)

    readonly property color insetBorder: Qt.rgba(1, 1, 1, 0.14)
    readonly property color insetBorderSoft: Qt.rgba(1, 1, 1, 0.08)

    implicitWidth: 400
    implicitHeight: col.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: card.insetBorder

    ElevationShadow {
        anchors.fill: parent
        z: -1
        level: Theme.elevationLevel3
        targetRadius: card.radius
        targetColor: card.color
        borderColor: card.border.color
        borderWidth: card.border.width
        shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled
    }

    StyledRect {
        id: closeButton
        z: 1
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        width: 28
        height: 28
        radius: width / 2
        color: closeBtnArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"
        DankIcon {
            anchors.centerIn: parent
            name: "close"
            size: Theme.iconSizeSmall
            color: Theme.surfaceText
        }
        MouseArea {
            id: closeBtnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.close()
        }
    }

    Column {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        // badge sujet
        StyledRect {
            visible: card.lesson && card.lesson.topicLabel
            implicitWidth: badgeRow.implicitWidth + Theme.spacingM * 2
            implicitHeight: badgeRow.implicitHeight + Theme.spacingXS * 2
            radius: height / 2
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
            border.width: 1
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
            Row {
                id: badgeRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.lesson ? Catalog.categoryEmoji(card.lesson.topicCategory) : ""
                    font.pixelSize: Theme.fontSizeSmall
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.lesson ? (card.lesson.topicLabel || "") : ""
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.primary
                }
            }
        }

        // titre (markdown + emoji)
        StyledText {
            width: parent.width - Theme.iconSize
            text: card.lesson ? (card.lesson.title || "") : ""
            textFormat: Text.MarkdownText
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        // contenu (markdown)
        StyledText {
            width: parent.width
            text: card.lesson ? (card.lesson.content || "") : ""
            textFormat: Text.MarkdownText
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
        }

        // action : Suivant
        Row {
            anchors.right: parent.right
            spacing: Theme.spacingS
            StyledRect {
                implicitWidth: nextText.implicitWidth + Theme.spacingL * 2
                implicitHeight: nextText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: Theme.primary
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.22)
                StyledText {
                    id: nextText
                    anchors.centerIn: parent
                    text: "Compris 👍 Suivant"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.primaryText
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.next()
                }
            }
        }

        // reporter (snooze)
        Row {
            spacing: Theme.spacingXS
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Reporter :"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
            Repeater {
                model: [
                    { label: "30 s", ms: 30000 },
                    { label: "5 min", ms: 300000 },
                    { label: "15 min", ms: 900000 },
                    { label: "1 h", ms: 3600000 }
                ]
                StyledRect {
                    radius: Theme.cornerRadius
                    color: snoozeArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                    border.width: 1
                    border.color: card.insetBorderSoft
                    implicitWidth: snoozeLabel.implicitWidth + Theme.spacingM * 2
                    implicitHeight: snoozeLabel.implicitHeight + Theme.spacingXS * 2
                    StyledText {
                        id: snoozeLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }
                    MouseArea {
                        id: snoozeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.snooze(modelData.ms)
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
rsync -a quickshell/PLUGINS/QuizWidget/ ~/.config/DankMaterialShell/plugins/QuizWidget/
dms restart && sleep 4
journalctl --user -u dms -n 60 --no-pager | grep -iE "LessonCard|error" | grep -i "\.qml\|error" | head || echo "(aucune)"
```
Expected : aucune erreur QML référant `LessonCard.qml`.

- [ ] **Step 3 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/LessonCard.qml
git commit -m "feat(quiz-widget): LessonCard component (markdown lesson + next/snooze)"
```

---

### Task 3 : `QuizProvider.fetchLearningStep`

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizProvider.qml`

**Interfaces:**
- Consumes : `QuizEngine.buildLessonPrompt`, `QuizEngine.parseLearningStep`, `QuizEngine.claudeBinary` ; `Proc.runCommand`.
- Produces : `fetchLearningStep(subject, history, callback(step|null))`.

- [ ] **Step 1 : Ajouter la méthode (après `_fetchAi`)**

```qml
    // Apprentissage : une étape (leçon OU quiz) via `claude -p`, selon l'historique.
    function fetchLearningStep(subject, history, callback) {
        var prompt = QuizEngine.buildLessonPrompt(subject, history);
        Proc.runCommand("quizWidget.learn", [
            QuizEngine.claudeBinary(Quickshell.env("HOME")), "-p", "--model", "claude-haiku-4-5", prompt
        ], function (stdout, exitCode) {
            if (exitCode !== 0) {
                console.warn("QuizProvider: learn claude -p exit", exitCode);
                callback(null);
                return;
            }
            callback(QuizEngine.parseLearningStep(stdout));
        }, 0, 60000);
    }
```

- [ ] **Step 2 : Vérifier le chargement**

Run :
```bash
rsync -a quickshell/PLUGINS/QuizWidget/ ~/.config/DankMaterialShell/plugins/QuizWidget/
dms restart && sleep 4
journalctl --user -u dms -n 60 --no-pager | grep -iE "QuizProvider.*error|\.qml.*error" | head || echo "(aucune)"
```
Expected : aucune erreur QML (méthode non encore appelée).

- [ ] **Step 3 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizProvider.qml
git commit -m "feat(quiz-widget): QuizProvider.fetchLearningStep (claude -p lesson/quiz)"
```

---

### Task 4 : `QuizOverlay.qml` — routage quiz ↔ leçon

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizOverlay.qml`

**Interfaces:**
- Consumes : `LessonCard`.
- Produces : `property var lesson`, `property string contentType` (`"quiz"`|`"lesson"`), `signal lessonDone()`. La carte affichée dépend de `contentType`.

- [ ] **Step 1 : Ajouter propriétés + signal**

Après `signal onboardingComplete(var ids, var customs)`, ajouter :
```qml
    property var lesson: null
    property string contentType: "quiz" // "quiz" | "lesson"
    signal lessonDone()
```

- [ ] **Step 2 : Restreindre la QuizCard au type quiz**

Dans le bloc `QuizCard { id: card ... }`, remplacer la ligne `visible:` par :
```qml
            visible: (overlay.mode === "open" || overlay.mode === "feedback") && overlay.contentType === "quiz"
```

- [ ] **Step 3 : Ajouter la LessonCard**

Juste après le bloc `QuizCard { ... }` (et avant `QuizOnboardingCard`), ajouter :
```qml
        LessonCard {
            id: lessonCard
            visible: overlay.mode === "open" && overlay.contentType === "lesson"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            lesson: overlay.lesson
            onNext: {
                overlay.lessonDone();
                overlay.reset();
            }
            onClose: overlay.reset()
            onSnooze: (ms) => { overlay.snoozeRequested(ms); overlay.reset(); }
        }
```

- [ ] **Step 4 : Étendre le dimensionnement du `content`**

Remplacer les deux lignes `implicitWidth:`/`implicitHeight:` de l'`Item { id: content … }` par :
```qml
        implicitWidth: onboardingCard.visible ? onboardingCard.implicitWidth
                       : lessonCard.visible ? lessonCard.implicitWidth
                       : card.visible ? card.implicitWidth : pill.implicitWidth
        implicitHeight: onboardingCard.visible ? onboardingCard.implicitHeight
                        : lessonCard.visible ? lessonCard.implicitHeight
                        : card.visible ? card.implicitHeight : pill.implicitHeight
```

- [ ] **Step 5 : Vérifier le chargement**

Run :
```bash
rsync -a quickshell/PLUGINS/QuizWidget/ ~/.config/DankMaterialShell/plugins/QuizWidget/
dms restart && sleep 4
journalctl --user -u dms -n 70 --no-pager | grep -iE "QuizOverlay|LessonCard|\.qml.*error" | grep -i error | head || echo "(aucune)"
```
Expected : aucune erreur QML ; le mode quiz fonctionne toujours (la pastille apparaît au cycle suivant).

- [ ] **Step 6 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizOverlay.qml
git commit -m "feat(quiz-widget): overlay routes quiz vs lesson (contentType + LessonCard)"
```

---

### Task 5 : `QuizSettings.qml` — sélecteur de mode + section apprentissage

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizSettings.qml`

**Interfaces:**
- Consumes : `PluginSettings` (`loadValue`/`saveValue`/`settingChanged`), `SelectionSetting`, `StringSetting`, `TopicPicker`.
- Produces : réglage `mode` + `learningSubject` ; visibilité conditionnelle ; affichage progression + reset.

- [ ] **Step 1 : Réécrire `QuizSettings.qml`**

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: settingsRoot
    pluginId: "quizWidget"

    property string currentMode: "quiz"
    property int learnedCount: 0
    function refreshState() {
        currentMode = loadValue("mode", "quiz");
        var h = loadValue("learningHistory", []);
        learnedCount = Array.isArray(h) ? h.length : 0;
    }
    Component.onCompleted: refreshState()
    onSettingChanged: refreshState()

    StyledText {
        width: parent.width
        text: "Quiz Widget"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    SelectionSetting {
        settingKey: "mode"
        label: "Mode"
        description: "Quiz ponctuels, ou parcours d'apprentissage guidé sur un sujet"
        options: [
            { label: "Quiz", value: "quiz" },
            { label: "Apprentissage", value: "learning" }
        ]
        defaultValue: "quiz"
    }

    ToggleSetting {
        settingKey: "paused"
        label: "Pause"
        description: "Suspendre temporairement"
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "workMinutes"
        label: "Intervalle"
        description: "Temps entre chaque quiz / leçon"
        options: [
            { label: "15 minutes", value: "15" },
            { label: "25 minutes", value: "25" },
            { label: "45 minutes", value: "45" },
            { label: "60 minutes", value: "60" }
        ]
        defaultValue: "25"
    }

    // --- section Quiz ---
    Column {
        width: parent.width
        spacing: Theme.spacingM
        visible: settingsRoot.currentMode === "quiz"

        StyledText {
            width: parent.width
            text: "Sujets (dev & IT)"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }
        StyledText {
            width: parent.width
            text: "Choisis les technos, concepts et méthodologies à réviser. Questions générées par Claude."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
        TopicPicker {
            settingKey: "selectedTopics"
            customSettingKey: "customTopics"
        }
    }

    // --- section Apprentissage ---
    Column {
        width: parent.width
        spacing: Theme.spacingM
        visible: settingsRoot.currentMode === "learning"

        StyledText {
            width: parent.width
            text: "Sujet à apprendre"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }
        StyledText {
            width: parent.width
            text: "Un seul sujet. L'IA joue un prof cool : surtout des leçons, parfois un quiz, et garde le fil de ta progression."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
        StringSetting {
            settingKey: "learningSubject"
            label: "Sujet"
            description: "Ex. Vim, Rust, théorie musicale…"
            placeholder: "Vim"
            defaultValue: ""
        }
        StyledText {
            width: parent.width
            text: "📚 " + settingsRoot.learnedCount + " notion(s) apprise(s)"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
        }
        StyledRect {
            implicitWidth: resetText.implicitWidth + Theme.spacingL * 2
            implicitHeight: resetText.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: resetArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
            StyledText {
                id: resetText
                anchors.centerIn: parent
                text: "Réinitialiser la progression"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
            MouseArea {
                id: resetArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    settingsRoot.saveValue("learningHistory", []);
                    settingsRoot.saveValue("learningHistorySubject", settingsRoot.loadValue("learningSubject", ""));
                    settingsRoot.refreshState();
                }
            }
        }
    }
}
```

- [ ] **Step 2 : Vérifier en live (bascule de mode)**

Run : `rsync -a quickshell/PLUGINS/QuizWidget/ ~/.config/DankMaterialShell/plugins/QuizWidget/ && dms restart`. Réglages → Plugins → Quiz Widget.
Expected : sélecteur **Mode** ; en `Quiz` → le TopicPicker s'affiche ; en `Apprentissage` → champ « Sujet » + « 📚 N notion(s) » + bouton reset ; bascule réactive. `journalctl` sans erreur.

- [ ] **Step 3 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizSettings.qml
git commit -m "feat(quiz-widget): settings mode selector + learning section (subject/progress/reset)"
```

---

### Task 6 : `QuizDaemon.qml` — branchement mode + persistance de l'avancement (mise en service)

**Files:**
- Modify: `quickshell/PLUGINS/QuizWidget/QuizDaemon.qml`

**Interfaces:**
- Consumes : `QuizProvider.fetchLearningStep`, `QuizEngine.summarizeStep`, `QuizEngine.buildNudgePrompt(angle, context)` (via `fetchNudge`), `QuizOverlay` (`lesson`, `contentType`, `lessonDone`, `showPending`), `pluginService`.
- Produces : dispatcher `requestNext()`, `requestLearningStep()`, persistance `learningHistory`/`learningHistorySubject`.

- [ ] **Step 1 : Propriétés learning + binding overlay + persistance d'historique**

Après `property var customTopics: []`, ajouter :
```qml
    property string mode: "quiz"
    property string learningSubject: ""
    property var learningHistory: []
    property string learningHistorySubject: ""
    property var pendingLesson: null
```

Dans le bloc `QuizOverlay { id: overlay ... }`, ajouter le binding leçon et remplacer le handler `onDismissed` :
```qml
        lesson: root.pendingLesson
        onDismissed: {
            if (root.mode === "learning" && root.pendingQuestion && root.pendingQuestion.summary)
                root.recordHistory(QuizEngine.summarizeStep(root.pendingQuestion));
            root.pendingQuestion = null;
            root.pendingLesson = null;
        }
        onLessonDone: {
            if (root.pendingLesson)
                root.recordHistory(QuizEngine.summarizeStep(root.pendingLesson));
        }
```

Ajouter la fonction `recordHistory` (près de `loadSettings`) :
```qml
    function recordHistory(summary) {
        if (!summary)
            return;
        var h = (root.learningHistory || []).slice();
        h.push(summary);
        if (h.length > 60)
            h = h.slice(h.length - 60);
        root.learningHistory = h;
        if (typeof pluginService !== "undefined" && pluginService)
            pluginService.savePluginData("quizWidget", "learningHistory", h);
    }
```

- [ ] **Step 2 : Dispatcher + `requestLearningStep` + timers**

Remplacer les `onTriggered: root.requestQuiz()` de `workTimer`, `snoozeTimer`, `firstQuizTimer` par `onTriggered: root.requestNext()` (pour `snoozeTimer`, garder aussi `root.snoozing = false;` avant). Concrètement :
- `workTimer.onTriggered: root.requestNext()`
- `snoozeTimer.onTriggered: { root.snoozing = false; root.requestNext(); }`
- `firstQuizTimer.onTriggered: root.requestNext()`

Dans `requestQuiz()`, juste avant `root.fetchNudge(...)`, ajouter `overlay.contentType = "quiz";`.

Mettre à jour `fetchNudge` pour accepter et transmettre un `context` (le mode quiz appelle sans → défaut conservé) :
- signature : `function fetchNudge(onReady, context) {`
- l'appel claude : `QuizEngine.buildNudgePrompt(undefined, context)` à la place de `QuizEngine.buildNudgePrompt()`.

(Le `requestQuiz` existant appelle `root.fetchNudge(function () { overlay.showPending(); })` — `context` reste `undefined`, donc le prompt nudge quiz est inchangé.)

Ajouter le dispatcher et l'étape d'apprentissage (après `requestQuiz`) :
```qml
    function requestNext() {
        if (root.mode === "learning")
            root.requestLearningStep();
        else
            root.requestQuiz();
    }

    function requestLearningStep() {
        if (root.pendingQuestion || root.pendingLesson)
            return;
        root.loadSettings();
        var subject = (root.learningSubject || "").trim();
        if (!subject)
            return;
        if (root.learningHistorySubject !== subject) {
            root.learningHistory = [];
            root.learningHistorySubject = subject;
            if (typeof pluginService !== "undefined" && pluginService) {
                pluginService.savePluginData("quizWidget", "learningHistory", []);
                pluginService.savePluginData("quizWidget", "learningHistorySubject", subject);
            }
        }
        var hist = root.learningHistory || [];
        var recent = hist.slice(Math.max(0, hist.length - 40));
        provider.fetchLearningStep(subject, recent, function (step) {
            if (!step) {
                console.warn("QuizDaemon: pas de leçon pour", subject);
                return;
            }
            step.topicLabel = subject;
            step.topicCategory = "Apprentissage";
            if (step.type === "lesson") {
                root.pendingLesson = step;
                overlay.contentType = "lesson";
            } else {
                root.pendingQuestion = step;
                overlay.contentType = "quiz";
            }
            root.fetchNudge(function () {
                overlay.showPending();
            }, "une nouvelle leçon de " + subject);
        });
    }
```

- [ ] **Step 3 : Charger les nouveaux réglages + démarrage selon le mode**

Dans `loadSettings()`, ajouter :
```qml
        root.mode = pluginService.loadPluginData("quizWidget", "mode", "quiz");
        root.learningSubject = pluginService.loadPluginData("quizWidget", "learningSubject", "");
        root.learningHistory = pluginService.loadPluginData("quizWidget", "learningHistory", []);
        root.learningHistorySubject = pluginService.loadPluginData("quizWidget", "learningHistorySubject", "");
```

Remplacer le corps du `Qt.callLater` de `Component.onCompleted` par :
```qml
        Qt.callLater(function () {
            root.loadSettings();
            if (root.mode === "learning") {
                if ((root.learningSubject || "").trim() !== "" && !root.paused)
                    firstQuizTimer.restart();
                console.info("QuizDaemon: started, mode learning, sujet", JSON.stringify(root.learningSubject), root.learningHistory ? root.learningHistory.length : 0, "notions");
            } else {
                var nCat = root.selectedTopics ? root.selectedTopics.length : 0;
                var nCustom = root.customTopics ? root.customTopics.length : 0;
                if (nCat === 0 && nCustom === 0)
                    overlay.showOnboarding();
                else if (!root.paused)
                    firstQuizTimer.restart();
                console.info("QuizDaemon: started, mode quiz,", nCat, "catalogue +", nCustom, "libres");
            }
        });
```

- [ ] **Step 4 : Vérifier en live (cycle apprentissage)**

Run : `rsync -a quickshell/PLUGINS/QuizWidget/ ~/.config/DankMaterialShell/plugins/QuizWidget/`. Régler mode = Apprentissage, sujet = « Vim » dans les réglages. `dms restart`.
```bash
sleep 6; journalctl --user -u dms -n 40 --no-pager | grep -iE "QuizDaemon: started|pas de leçon|error.*qml"
# attendre ~la pastille (firstQuizTimer 30s + génération), puis vérifier l'historique
for i in $(seq 1 18); do hyprctl layers 2>/dev/null | grep -qi "dms:quiz" && { echo "pastille OK"; break; }; sleep 5; done
python3 - <<'PY' 2>/dev/null || cat ~/.config/DankMaterialShell/plugin_settings.json
import json; print(json.load(open('/home/titosy/.config/DankMaterialShell/plugin_settings.json'))['quizWidget'])
PY
```
Expected : `mode learning, sujet "Vim"` ; pastille « nouvelle leçon » apparaît ; clic → carte leçon (titre + markdown) ; « Suivant » → `learningHistory` gagne une entrée dans `plugin_settings.json`. Au fil des cycles, parfois un quiz.

- [ ] **Step 5 : Commit**

```bash
git add quickshell/PLUGINS/QuizWidget/QuizDaemon.qml
git commit -m "feat(quiz-widget): learning mode live — dispatcher, lesson/quiz cycle, progress persistence"
```

---

### Task 7 : Vérification end-to-end + nettoyage

**Files:** (aucun nouveau)

- [ ] **Step 1 : Suite de tests pure**

Run : `node --test quickshell/PLUGINS/QuizWidget/tests/*.test.mjs`
Expected : PASS (tous).

- [ ] **Step 2 : Parcours apprentissage complet**

Mode Apprentissage, sujet « Vim ». Vérifier : la bulle invite à une leçon ; la carte leçon rend le markdown + badge « ✨ Vim » ; « Suivant » avance ; après plusieurs leçons, un quiz apparaît parfois (carte quiz) ; l'historique grandit (`plugin_settings.json`). Les leçons ne se répètent pas (l'IA construit sur l'historique).

- [ ] **Step 3 : Changement de sujet & reset**

Changer le sujet (ex. « Rust ») → au cycle suivant, `learningHistory` est réinitialisé (sujet différent). Le bouton « Réinitialiser la progression » vide aussi l'historique.

- [ ] **Step 4 : Non-régression mode Quiz**

Repasser en mode Quiz → le flux quiz (catalogue/sujets libres, pastille, carte QCM colorée) fonctionne comme avant.

- [ ] **Step 5 : Robustesse**

`journalctl` : pas d'erreur QML ; si `claude -p` échoue (timeout/réseau), cycle sauté proprement (`learn claude -p exit`), pas de crash.

- [ ] **Step 6 : Commit final (si ajustements)**

```bash
git add quickshell/PLUGINS/QuizWidget/
git commit -m "test(quiz-widget): learning mode end-to-end verification adjustments"
```

---

## Notes pour l'implémenteur

- **Cache moteur :** toute modif d'un composant importé exige `dms restart` (le `reload` ne suffit pas).
- **Persistance live :** le daemon écrit `learningHistory` via `pluginService.savePluginData` ; le panneau réglages lit la valeur à l'ouverture (compteur « N notions »).
- **Bulle d'attente :** comme en mode quiz, la pastille n'apparaît qu'après la réponse du nudge (`fetchNudge(onReady, context)`), donc directement avec la bonne animation.
- **Sujet changé = progression réinitialisée** (détecté via `learningHistorySubject`). Documenté pour l'utilisateur via le bouton reset.
- **Markdown :** `Text.MarkdownText` + `elide: Text.ElideNone`. Le `THEME_REFERENCE.md` est partiellement faux — se référer à `Common/Theme.qml` (`primaryText`, etc.).
