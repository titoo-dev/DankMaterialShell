# Quiz Widget — Mode « Apprentissage » (prof IA organique, persistance de l'avancement)

> Spec de conception. Date : 2026-06-21. Suit `2026-06-20-quiz-content-design.md` (mode Quiz).

## Goal

Ajouter un **second mode** au widget : un parcours d'apprentissage **mono-sujet** (ex. « Vim ») où l'IA joue un **prof cool** qui distille surtout des **leçons** progressives (et **parfois** un quiz, quand elle le juge pertinent), avec **persistance de l'avancement** entre les sessions. La bulle n'invite plus seulement à un quiz mais à « continuer d'apprendre ».

## Décisions (cadrage validé)

| Sujet | Choix |
|---|---|
| Structure du parcours | **Mentor organique** : pas de roadmap figée ; l'IA enseigne « la prochaine notion utile » en fonction de l'**historique** déjà couvert. |
| Quiz dans le parcours | **L'IA décide** : surtout des leçons, un quiz inséré quand c'est pertinent. |
| Activation | **Sélecteur de mode** dans les réglages : `Quiz` (actuel) ou `Apprentissage`. |
| Sujet | **Un seul** sujet en texte libre (ex. « Vim »). |

## Modèle de données (réglages persistés)

Nouvelles clés (à côté de `paused`, `workMinutes`, `selectedTopics`, `customTopics`) :

- `mode` : `"quiz"` (défaut) | `"learning"`.
- `learningSubject` : string (ex. `"Vim"`).
- `learningHistory` : `string[]` — résumés courts des notions déjà couvertes (leçons + quiz), dans l'ordre. Sert de mémoire envoyée à l'IA.
- `learningHistorySubject` : string — le sujet auquel `learningHistory` se rapporte (pour réinitialiser l'historique si le sujet change).

L'historique est **plafonné** à 60 entrées en stockage ; on envoie au prompt les **40 dernières** (borne la taille du prompt).

## Interaction IA (un seul appel « enseigne la suite »)

`claude -p` reçoit le sujet + l'historique et renvoie **soit une leçon, soit un quiz**, en JSON.

**Prompt** (`buildLessonPrompt(subject, history)`) — esprit :
- « Tu es un prof cool et concis de **<subject>**. Déjà couvert : <history ou "rien encore">. Donne la PROCHAINE étape, en construisant sur l'acquis, sans répéter.
- La plupart du temps : une **leçon** courte et digeste (une notion, exemples concrets, markdown `**gras**`/`code`, un emoji en tête).
- De temps en temps (si plusieurs notions vues et qu'un check est pertinent) : un **quiz** à choix unique sur ce qui a été vu.
- Réponds UNIQUEMENT en JSON :
  - leçon : `{"type":"lesson","title":"...","content":"...(markdown)","summary":"..."}`
  - quiz : `{"type":"quiz","question":"...","choices":["..","..","..",".."],"answer":0,"explanation":"...","summary":"..."}`
  - `summary` = courte phrase résumant la notion (pour le suivi). »

**Parse** (`parseLearningStep(stdout)` → objet normalisé | null), réutilise `extractJsonObject` :
- `type:"lesson"` → exige `title` et `content` non vides ; `summary` ⟶ défaut = `title`. Renvoie `{type:"lesson", title, content, summary}`.
- `type:"quiz"` → réutilise `validate(q)` sur `{question,choices,answer,explanation}` ; `id = "ai-"+hash` ; `summary` ⟶ défaut = `"Quiz : " + question` tronqué. Renvoie `{type:"quiz", question, choices, answer, explanation, id, summary}`.
- sinon → `null`.

`summarizeStep(step)` → string : `summary` du step (déjà normalisé). Le daemon l'ajoute à `learningHistory`.

## Composants

| Fichier | Rôle |
|---|---|
| `QuizEngine.js` (modif) | + `buildLessonPrompt`, `parseLearningStep`, `summarizeStep` (logique pure, testée node). Réutilise `validate`/`extractJsonObject`/`hashString`. |
| `QuizProvider.qml` (modif) | + `fetchLearningStep(subject, history, callback(step\|null))` via `claude -p` (même mécanique que `fetchQuestion` : `claudeBinary`, timeout 60 s). |
| `LessonCard.qml` (nouveau) | Carte leçon : badge sujet, **titre**, **contenu markdown**, bouton « Compris 👍 / Suivant », bouton ×, reporter (snooze). Signaux `next()`, `close()`, `snooze(ms)`. Même style bento que `QuizCard`. |
| `QuizOverlay.qml` (modif) | Route le contenu : `property var lesson`, `property string contentType: "quiz"`. En `open`, montre `QuizCard` si `contentType==="quiz"`, sinon `LessonCard`. + signal `lessonDone()`. Dimensionnement du `content` étendu à la carte leçon. |
| `QuizDaemon.qml` (modif) | Branche selon `mode`. Dispatcher `requestNext()` (appelé par les timers) → `requestQuiz()` (existant) si `mode==="quiz"`, sinon `requestLearningStep()`. Persistance de l'historique. Reset historique si le sujet change. |
| `QuizSettings.qml` (modif) | `SelectionSetting "mode"` en tête. Section Quiz (TopicPicker) visible si `mode==="quiz"` ; section Apprentissage (sujet + progression + reset) visible si `mode==="learning"`. |

## Flux

**Cycle d'apprentissage** (`requestLearningStep`)
1. recharger réglages ; si `learningSubject` vide → ne rien faire (réglages invitent à le saisir) ; si le sujet a changé vs `learningHistorySubject` → vider `learningHistory` + mettre à jour `learningHistorySubject`.
2. `provider.fetchLearningStep(subject, last40(history), cb)`.
3. `cb(step)` : si `null` → log + saute le cycle. Sinon : `overlay.lesson`/`overlay.question` selon `step.type`, `overlay.contentType = step.type`, attacher `topicLabel=subject`/`topicCategory="Apprentissage"`, `fetchNudge(onReady, "une nouvelle leçon de "+subject)` puis afficher la bulle dans `onReady` (la bulle attend la réponse du nudge, comme en mode quiz).

**Leçon lue → suivant** : `LessonCard.next()` → overlay `lessonDone()` → daemon ajoute `summarizeStep(lesson)` à `learningHistory`, persiste, `overlay.reset()`. Le prochain cycle enchaîne.

**Quiz répondu** (mode learning) : flux quiz existant (open→feedback→fermer) ; à la fermeture/validation, ajouter `summarizeStep(quiz)` à l'historique (persisté). Réutilise la `QuizCard`.

**Onboarding / 1er lancement** : en mode learning sans `learningSubject`, pas de carte d'onboarding (l'utilisateur saisit le sujet dans les réglages) ; la bulle ne s'affiche pas tant que le sujet est vide. (L'onboarding multi-sujets reste réservé au mode quiz.)

## Bulle (nudge) adaptée

`buildNudgePrompt(angle, context)` gagne un paramètre `context` (défaut `"un mini-quiz qui vient d'apparaître"`). En mode learning : `context = "une nouvelle leçon de " + subject` → la bulle invite à apprendre (« Nouvelle leçon Vim ! 📖 ») et l'IA choisit toujours l'emoji + l'animation assortis. JSON nudge inchangé (`{message,emoji,animation}`).

## Réglages (UI)

- En tête : `SelectionSetting "mode"` (`Quiz` / `Apprentissage`, défaut `Quiz`).
- Si `Quiz` : sections existantes (Pause, Durée, TopicPicker).
- Si `Apprentissage` : Pause, Durée, `StringSetting "learningSubject"` (placeholder « Vim »), une ligne de **progression** (« N notions apprises »), et un bouton **« Réinitialiser la progression »** (vide `learningHistory`).
- La visibilité des sections suit le `mode` courant (réactif au changement du sélecteur).

## Tests

**Node (`tests/quizEngine.test.mjs`)**
- `buildLessonPrompt(subject, history)` : contient le sujet, mentionne « leçon » et « quiz », exige du JSON, et inclut l'historique fourni.
- `parseLearningStep` : leçon valide → `{type:"lesson",title,content,summary}` ; leçon sans `summary` → summary = title ; leçon sans title/content → null ; quiz valide → `{type:"quiz",...,id,summary}` ; quiz invalide (validate) → null ; `type` inconnu → null ; fences markdown gérées ; non-JSON → null.
- `summarizeStep` : renvoie le summary (leçon et quiz).
- `buildNudgePrompt(angle, context)` : inclut le `context` fourni ; défaut conservé si absent.

**Vérif live** : basculer en mode Apprentissage, sujet « Vim » ; la bulle apparaît ; clic → **carte leçon** (titre + markdown) ; « Suivant » → historique +1 (vérifier `plugin_settings.json`) ; au fil des cycles, l'IA varie et insère parfois un quiz ; changer de sujet réinitialise la progression. `journalctl` sans erreur QML.

## Hors périmètre (YAGNI)

- Roadmap structurée / étapes planifiées à l'avance (mentor organique choisi).
- Plusieurs sujets simultanés en mode learning (un seul).
- Édition manuelle de l'historique ; export ; statistiques de rétention.
- Quiz « espacés » algorithmiques (spaced repetition) — l'IA décide simplement.
