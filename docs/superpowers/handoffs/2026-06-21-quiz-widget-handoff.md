# Handoff — Quiz/Learning Widget (DMS plugin)

> Date : 2026-06-21 · Branche : `feat/dynamic-island` · Arbre propre · Tests **76/76**
> Plugin : `quickshell/PLUGINS/QuizWidget/` · État live actuel : **mode learning, sujet « Vim », 9 notions apprises**.

## TL;DR

Plugin daemon DMS (Quickshell/QML) qui fait apparaître une **pastille flottante** en bas-droite, à intervalle pomodoro, avec **deux modes** (sélecteur dans Réglages → Plugins → Quiz Widget) :
- **Quiz** : QCM générés par `claude -p` sur des sujets dev/IT (catalogue curaté + sujets libres).
- **Apprentissage** (mono-sujet, ex. Vim) : un « prof IA » organique qui distille surtout des **leçons** (parfois un quiz), avec **persistance de l'avancement**, **ré-explication** d'une notion non validée, et une **Q&A** (« Des questions ? ») contextuelle.

Tout le contenu vient de `claude -p` (CLI local, pas de clé API). Logique pure dans `QuizEngine.js` + `Catalog.js`, testée sous `node --test`.

---

## ⚠️ Boucle de dev / déploiement (À LIRE EN PREMIER)

Le shell vivant **ne charge PAS le plugin depuis le repo** — il le lit depuis une **copie** dans `~/.config/DankMaterialShell/plugins/QuizWidget/`. Après CHAQUE modif :

```bash
rsync -a quickshell/PLUGINS/QuizWidget/ ~/.config/DankMaterialShell/plugins/QuizWidget/
dms restart            # restart obligatoire : les composants importés (.qml/.js) sont cachés par l'engine ; `dms ipc plugins reload` ne suffit pas
sleep 6
journalctl --user -u dms -n 150 --no-pager | grep -iE "quizdaemon|\.qml.*error|TypeError"
```

Gotchas durement appris (voir mémoires `dms-plugin-deploy-and-verify`, `dms-claude-p-from-plugin`) :
- **`claude` introuvable depuis DMS** : le PATH de la session n'a pas `~/.local/bin`. On appelle le **chemin absolu** via `QuizEngine.claudeBinary(Quickshell.env("HOME"))` → `$HOME/.local/bin/claude`. Ne PAS revenir à `"claude"` nu.
- **`Proc.runCommand(id, cmd, cb, debounceMs, timeoutMs)`** : le 4ᵉ arg est le **debounce**, le 5ᵉ le **timeout**. Toujours passer un timeout explicite (génération claude >10 s, le défaut 10 s tue le process). Questions/leçons : 60 s ; réponses Q&A : 45 s ; nudge : 15 s.
- **Pas de capture des overlays** : `grim` n'est pas installé et `dms screenshot` **exclut les surfaces shell** (pastille/cartes). Pour vérifier l'affichage : `hyprctl layers | grep dms:quiz` (surface mappée ⇒ pastille/carte visible). Le rendu visuel se confirme avec l'utilisateur.
- **Horloge** : le journal et `date` divergent parfois (skew) ; se fier au **relatif** (`-n N`, `--since`).

---

## Architecture (carte des fichiers)

| Fichier | Rôle |
|---|---|
| `QuizEngine.js` (.pragma library, **testé**) | Logique pure : `validate`, `pickQuestion` ; `buildQuestionPrompt`/`extractQuestionJson` (quiz, JSON) ; `claudeBinary` ; nudges (`buildNudgePrompt`/`parseNudge`/`animationIndex`/`NUDGE_ANIMATIONS`/`LOCAL_NUDGES`/`NUDGE_ANGLES`/`cleanNudge`) ; apprentissage (`buildLessonPrompt`/`buildRelearnPrompt`/`parseLearningStep` **format texte à délimiteurs**, `summarizeStep`, `buildAnswerPrompt`) ; rendu (`mdToHtml`/`escapeHtml`, `extractJsonObject`). |
| `Catalog.js` (.pragma library, **testé**) | Catalogue dev/IT curaté (3 catégories) ; `topicById`, `topicsByCategory`, `categoriesWithTopics`, `allCategories`, `addCustom`, `buildTopicPool`, `categoryEmoji`. |
| `QuizProvider.qml` | Appelle `claude -p` : `fetchQuestion` (quiz), `fetchLearningStep` (leçon/quiz, + ré-explication via `relearnNotion`), `fetchAnswer` (Q&A) ; fallback banque locale `banks/<id>.json`. |
| `QuizDaemon.qml` | `PluginComponent` : timers (workTimer = intervalle, firstQuizTimer 30 s, retryTimer 25 s ×4, snoozeTimer, renudgeTimer 5 min) ; dispatcher `requestNext()` → `requestQuiz()` / `requestLearningStep()` ; `answerQuestion()` ; persistance ; nudge. |
| `QuizOverlay.qml` | `PanelWindow` layer-shell (`dms:quiz`, `keyboardFocus: OnDemand`) : pastille ↔ carte ; route `contentType` quiz/leçon ; modes `hidden/pending/open/feedback/onboarding` ; signaux `lessonDone/quizAnswered/askQuestion/onboardingComplete`. |
| `QuizCard.qml` | Carte QCM : badge sujet, pastilles **A/B/C/D colorées**, markdown (RichText via `mdToHtml`), feedback, snooze ; zone question/choix/feedback **plafonnée + scrollable** (`DankFlickable`). |
| `LessonCard.qml` | Carte leçon : badge, titre, contenu markdown **plafonné+scroll** ; **« Compris 👍 Suivant »** (valide), **« Des questions ? » / « Fermer ✕ »** (toggle Q&A : input bas + panneau réponse plafonné), snooze. |
| `QuizOnboardingCard.qml` | Setup 1er lancement (mode quiz) : `TopicPicker` plafonné+scroll + « Commencer ». |
| `TopicPicker.qml` | Sélecteur de chips (catalogue + sujets libres), partagé onboarding/réglages. |
| `QuizSettings.qml` | Sélecteur de **Mode** (Quiz/Apprentissage) ; section quiz (TopicPicker) ou apprentissage (sujet + progression + reset), visibilité réactive. |
| `banks/*.json` | Banques seed (fallback). |
| `tests/*.test.mjs` | `node --test` (loader `vm` ; cross-realm via `Array.from`). |

## Données persistées (`~/.config/DankMaterialShell/plugin_settings.json` → `quizWidget`)

`mode` (`quiz`|`learning`), `paused`, `workMinutes`, `selectedTopics` (ids catalogue), `customTopics` (libres), `learningSubject`, `learningHistory` (résumés des notions validées, plafonné 60), `learningHistorySubject` (reset si le sujet change), `learningPendingNotion` (notion non validée à ré-expliquer). Clés legacy ignorées : `subjects`, `aiEnabled`, `apiKey`, `enabled`.

---

## Fait (chronologie des commits)

Mode quiz : scaffold → catalogue dev/IT + sujets libres → bascule `claude -p` (drop curl/clé API) → fix « aucune quiz » (chemin claude + timeout) → questions fun (emoji/markdown) → carte colorée (badge, A/B/C/D, markdown) → animation pilotée par claude (JSON nudge) → pastille affichée seulement quand le nudge est prêt.
Mode apprentissage : spec+plan → moteur (prompt/parse) → LessonCard → provider → overlay routing → réglages mode → daemon live (cycle, persistance, FR forcé) → **fermer ≠ valider** (ré-explique la notion) → **markdown propre** (mdToHtml+RichText, format texte délimiteurs robuste) → **hauteur plafonnée + scroll** → **Q&A « Des questions ? »** → Q&A **avec contexte** (historique+leçon) → toggle ouvrir/fermer clair → **réessai rapide** sur échec → pastille **plus cinglante** (clash).

Commits clés récents : `79a4572c`, `722d75bc`, `1f650b6a`, `5a0b56ea`, `4b070001`, `4e066cf5`, `ecdc4c02`, `dfd81be0`. Specs/plans : `docs/superpowers/specs/2026-06-21-learning-mode-design.md`, `docs/superpowers/plans/2026-06-21-learning-mode.md` (+ les `2026-06-20-quiz-content-*`).

## Décisions de conception verrouillées

- **Format de contenu apprentissage = texte à délimiteurs** (`TYPE: lesson|quiz`, `TITRE/RESUME/CONTENU`, `A`–`D`/`REPONSE`), PAS de JSON : le markdown riche (guillemets, antislashs, blocs ```` ``` ````) casse trop souvent le JSON généré par le LLM. Le mode **quiz** garde le JSON (`extractJsonObject` durci : échappe les caractères de contrôle + répare les `\x` invalides).
- **Mentor organique** (pas de roadmap figée) ; l'IA décide quand glisser un quiz.
- **Validation = « Suivant »** uniquement ; fermer/snooze garde la notion et la **ré-explique autrement** au cycle suivant.
- **Q&A** : `buildAnswerPrompt(subject, question, history, currentTitle)` → réponse brève FR, markdown.

---

## Vérifier (rapide)

```bash
# tests purs
node --test quickshell/PLUGINS/QuizWidget/tests/*.test.mjs        # attendu : pass 76

# pipeline réel (leçon) — utilise le vrai code engine
node -e 'const{readFileSync}=require("fs");const{execFileSync}=require("child_process");const vm=require("vm");
const s=readFileSync("quickshell/PLUGINS/QuizWidget/QuizEngine.js","utf8").replace(/^\s*\.pragma\s+library\s*$/m,"");
const c={};vm.createContext(c);vm.runInContext(s+"\n;globalThis.x={buildLessonPrompt,parseLearningStep};",c);
const o=execFileSync("claude",["-p","--model","claude-haiku-4-5",c.x.buildLessonPrompt("Vim",[])],{encoding:"utf8",timeout:90000,maxBuffer:1e7});
console.log(c.x.parseLearningStep(o));'

# live : pastille mappée ?
hyprctl layers | grep -i dms:quiz
```

## Limitations connues / caveats

- **`claude -p` se modère** : ses messages de pastille restent « défi joueur » ; les **presets locaux** (`LOCAL_NUDGES`) tapent le plus fort (et s'affichent instantanément). Pour plus de mordant : enrichir les presets ou réduire le poids de l'override IA.
- **Réponses hors-format** intermittentes (claude répond en méta au lieu du `TYPE:`) → géré par `retryTimer` (4× 25 s) ; au-delà, attend le prochain pomodoro.
- **Rendu visuel non vérifiable par l'agent** (pas de grim) → faire confirmer par l'utilisateur (markdown/code stylé, scroll des cartes, saisie clavier de la Q&A via `OnDemand`).
- **`historique` = résumés courts** (pas le contenu complet des leçons) → les rappels Q&A re-dérivent depuis le topic ; suffisant mais pas verbatim.
- **Délai d'apparition** ~30 s (firstQuizTimer) + génération ~15-25 s.

## Pistes / next steps (non commencés)

- Confirmer visuellement (utilisateur) : Q&A clavier, scroll, code stylé.
- Punchlines pastille : laisser l'utilisateur définir le **niveau de méchanceté** / ajouter ses propres lignes ; option « presets only » (ne pas laisser l'IA adoucir).
- Apprentissage : valider auto une notion après N ré-explications (ou un mini-quiz de validation) ; stocker plus de détail par leçon pour des rappels verbatim ; historique d'échanges Q&A.
- Difficulté réglable (prompt fixé « intermédiaire »).
- Nettoyage : enlever les clés legacy du store ; éventuel `network` déjà retiré de `plugin.json`.
- Décider de l'intégration de la branche `feat/dynamic-island` (PR/merge) — non demandé pour l'instant ; tout le travail quiz vit sur cette branche.

## Travailler dessus

Mémoires pertinentes (chargées en contexte) : `dms-plugin-deploy-and-verify`, `dms-claude-p-from-plugin`, `dms-live-shell-from-worktree`, `dms-island-timer-freeze-on-unmap`. Le shell vivant tourne ; après modif → rsync + `dms restart` + journalctl. Les Edit QML peuvent buguer sur des lignes contenant des backticks/regex — relire avec Read/`sed -n … | cat -A` en cas de doute (un placeholder ` ` peut s'afficher comme un espace).
