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

function hashString(s) {
    var h = 0;
    for (var i = 0; i < s.length; i++) { h = ((h << 5) - h + s.charCodeAt(i)) | 0; }
    return Math.abs(h);
}

// Chemin absolu du binaire claude. Le process DMS (lancé par la session) n'a pas ~/.local/bin
// dans son PATH, donc l'appeler par "claude" échoue ("binary could not be found"). On résout
// depuis HOME vers l'emplacement d'install standard de Claude Code.
function claudeBinary(home) {
    return home ? home + "/.local/bin/claude" : "claude";
}

// Prompt pour `claude -p` : exige UN objet JSON brut (le CLI n'a pas de json_schema).
function buildQuestionPrompt(topicLabel, category) {
    return "Tu es un créateur de quiz fun et malin. Génère UNE question à choix unique, en français, "
        + "de niveau intermédiaire, vraiment intéressante (angle surprenant ou piège subtil) mais 100% factuelle, "
        + "sur le sujet suivant (catégorie « " + category + " ») : " + topicLabel + ". "
        + "Ton vivant et ludique. "
        + "Commence la question par UN emoji pertinent. "
        + "Utilise du markdown léger : **gras** pour les termes clés et `code` pour le code, les commandes ou les valeurs littérales. "
        + "Donne EXACTEMENT 4 propositions plausibles (distracteurs crédibles), SANS emoji au début des propositions "
        + "(tu peux y mettre du `code` si pertinent). "
        + "L'explication : courte (1-2 phrases), fun et mémorable, commençant par un emoji, avec **gras**/`code` si utile. "
        + "Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour ni balises de code, de la forme : "
        + '{"question": "...", "choices": ["...", "...", "...", "..."], "answer": 0, "explanation": "..."} '
        + "où \"answer\" est l'index (0 à 3) de la bonne proposition dans \"choices\".";
}

// Extrait le premier objet JSON {…} d'une sortie `claude -p` : retire les fences markdown,
// isole l'objet équilibré (en ignorant les accolades dans les chaînes), parse. null si échec.
function extractJsonObject(stdout) {
    if (typeof stdout !== "string") return null;
    var text = stdout;
    var fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
    if (fence) text = fence[1];
    var start = text.indexOf("{");
    if (start === -1) return null;
    var depth = 0, end = -1, inStr = false;
    var out = "";
    for (var i = start; i < text.length; i++) {
        var ch = text.charAt(i);
        if (inStr) {
            if (ch === "\"") { out += ch; inStr = false; continue; }
            if (ch === "\\") {
                var nx = text.charAt(i + 1);
                if (nx === "u") { out += text.substr(i, 6); i += 5; continue; } // \uXXXX
                if (nx !== "" && "\"\\/bfnrt".indexOf(nx) !== -1) { out += "\\" + nx; i += 1; continue; } // échappement valide
                out += "\\\\"; // échappement invalide (ex. \d, \w de regex/code) → antislash littéral
                continue;
            }
            // JSON interdit les caractères de contrôle bruts dans les chaînes ; claude
            // pretty-printe parfois du contenu multi-ligne → on les échappe pour JSON.parse.
            if (ch === "\n") { out += "\\n"; continue; }
            if (ch === "\r") { out += "\\r"; continue; }
            if (ch === "\t") { out += "\\t"; continue; }
            out += ch;
            continue;
        }
        out += ch;
        if (ch === "\"") inStr = true;
        else if (ch === "{") depth++;
        else if (ch === "}") { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end === -1) return null;
    try { return JSON.parse(out); } catch (e) { return null; }
}

// Question valide depuis la sortie claude -p (objet JSON validé + id stable).
function extractQuestionJson(stdout) {
    var q = extractJsonObject(stdout);
    if (!q || !validate(q)) return null;
    if (!q.id) q.id = "ai-" + hashString(q.question);
    return q;
}

// --- nudges (messages d'accroche façon Duolingo, affichés sur la pastille) ---

var LOCAL_NUDGES = [
    "Coucou 👋",
    "Clique-moi 👀",
    "Apprenons un truc !",
    "Trop facile pour toi ? 😏",
    "T'as peur d'un quiz ? 😎",
    "Petit génie, par ici 🧠",
    "Allez, juste une 🙃",
    "On parie que tu sèches ? 🤭",
    "Hop, un quiz fun ! 🎉",
    "Réveille ce cerveau 🧠⚡",
    "Même pas cap 😜",
    "Une pause maligne ?",
    "Psst… par ici 🤫",
    "Le savoir t'attend 📚",
    "Tu vas adorer (ou pas) 😈",
    "Prouve que t'es chaud 🔥"
];

function randomNudge(rng) {
    rng = rng || Math.random;
    var idx = Math.floor(rng() * LOCAL_NUDGES.length);
    if (idx < 0) idx = 0;
    if (idx >= LOCAL_NUDGES.length) idx = LOCAL_NUDGES.length - 1;
    return LOCAL_NUDGES[idx];
}

// Emoji expressif en tête de pastille (varie à chaque message).
var NUDGE_EMOJIS = ["🦉", "🧠", "✨", "🤓", "💡", "🎯", "🔥", "🚀", "📚", "⚡", "🌟", "🎓", "👀", "💫", "🤔"];

function randomEmoji(rng) {
    rng = rng || Math.random;
    var idx = Math.floor(rng() * NUDGE_EMOJIS.length);
    if (idx < 0) idx = 0;
    if (idx >= NUDGE_EMOJIS.length) idx = NUDGE_EMOJIS.length - 1;
    return NUDGE_EMOJIS[idx];
}

// Styles/tons de communication — variété demandée : cool, sarcasme, blague, clash, fun…
var NUDGE_ANGLES = [
    "cool et décontracté",
    "un petit sarcasme taquin",
    "une mini-blague ou un jeu de mots",
    "un petit clash amical / une provoc joueuse",
    "fun et déjanté",
    "complice, entre potes",
    "une salutation chaleureuse",
    "piquer la curiosité",
    "un défi joueur (« même pas cap »)",
    "un encouragement bienveillant",
    "un brin d'humour absurde",
    "façon coach survolté",
    "faussement blasé / ironique",
    "mystérieux et intrigant"
];

function randomNudgeAngle(rng) {
    rng = rng || Math.random;
    var idx = Math.floor(rng() * NUDGE_ANGLES.length);
    if (idx < 0) idx = 0;
    if (idx >= NUDGE_ANGLES.length) idx = NUDGE_ANGLES.length - 1;
    return NUDGE_ANGLES[idx];
}

// Prompt pour `claude -p` : une accroche courte, le style/ton aléatoire force la variété.
// Noms des animations d'attention de la pastille. L'ORDRE = l'index `animIndex` de QuizOverlay
// (0 bounce … 13 metronome) — ne pas réordonner sans aligner QuizOverlay.qml.
var NUDGE_ANIMATIONS = [
    "bounce", "shake", "pulse", "swing", "tada", "heartbeat", "rubber",
    "float", "headshake", "wobble", "pop", "tilt", "jump", "metronome"
];

function animationIndex(name) {
    if (typeof name !== "string") return -1;
    return NUDGE_ANIMATIONS.indexOf(name.trim().toLowerCase());
}

// Prompt `claude -p` : renvoie un JSON {message, emoji, animation} — claude choisit AUSSI
// l'animation qui colle le mieux à l'émotion du message.
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

// Parse la sortie JSON du nudge → { message, emoji, animIndex }. animIndex = -1 si animation
// inconnue (l'appelant choisit alors une animation aléatoire). null si message inexploitable.
function parseNudge(stdout) {
    var n = extractJsonObject(stdout);
    if (!n) return null;
    var message = cleanNudge(typeof n.message === "string" ? n.message : "");
    if (!message) return null;
    var emoji = (typeof n.emoji === "string" && n.emoji.trim() !== "") ? n.emoji.trim() : "";
    var animIndex = animationIndex(typeof n.animation === "string" ? n.animation : "");
    return { message: message, emoji: emoji, animIndex: animIndex };
}

// --- mode apprentissage (prof IA organique) ---

// Format des leçons : texte à délimiteurs (PAS de JSON). Le contenu markdown libre (guillemets,
// antislashs, code) casse trop souvent le JSON généré par le LLM — le format ligne est robuste.
var LESSON_FORMAT =
    "Pour une LEÇON, réponds EXACTEMENT (aucun autre texte, PAS de JSON, PAS de balises ```) :\n"
    + "TYPE: lesson\n"
    + "TITRE: <titre court avec un emoji au début>\n"
    + "RESUME: <résumé en ~8 mots>\n"
    + "CONTENU:\n"
    + "<contenu de la leçon en markdown, plusieurs lignes autorisées, **gras**/`code` libres>\n";
var QUIZ_FORMAT =
    "Pour un QUIZ, réponds EXACTEMENT (aucun autre texte, PAS de JSON) :\n"
    + "TYPE: quiz\n"
    + "QUESTION: <la question, un emoji au début>\n"
    + "A: <choix>\nB: <choix>\nC: <choix>\nD: <choix>\n"
    + "REPONSE: <A, B, C ou D>\n"
    + "EXPLICATION: <courte explication, une seule ligne>\n"
    + "RESUME: <résumé en ~8 mots>\n";

// Prompt « enseigne la suite » : une leçon OU un quiz, en format texte, selon l'historique.
function buildLessonPrompt(subject, history) {
    var covered = (history && history.length) ? history.join(" ; ") : "rien encore";
    return "Tu es un prof cool, concis et bienveillant de « " + subject + " ». "
        + "TOUJOURS répondre EN FRANÇAIS. "
        + "Déjà couvert par l'apprenant : " + covered + ". "
        + "Donne LA PROCHAINE étape d'apprentissage, en construisant logiquement sur l'acquis, sans répéter. "
        + "La plupart du temps : une LEÇON courte et digeste (UNE notion à la fois, un exemple concret). "
        + "De temps en temps seulement, si plusieurs notions ont déjà été vues et qu'une vérification est pertinente : "
        + "un QUIZ à choix unique sur ce qui a été couvert.\n\n"
        + "IMPORTANT : commence ta réponse DIRECTEMENT par « TYPE: » — aucune salutation, aucune phrase avant ou après.\n\n"
        + LESSON_FORMAT + "\n" + QUIZ_FORMAT;
}

// Ré-explication : l'apprenant n'a pas validé une notion → la ré-enseigner AUTREMENT (sans avancer).
function buildRelearnPrompt(subject, notion, history) {
    var covered = (history && history.length) ? history.join(" ; ") : "rien encore";
    return "Tu es un prof cool de « " + subject + " ». TOUJOURS répondre EN FRANÇAIS. "
        + "L'apprenant n'a PAS encore validé la notion : « " + notion + " ». "
        + "Ré-explique-la AUTREMENT (autre angle, autre exemple, analogie ou astuce mnémo) pour l'aider à la saisir — "
        + "NE PASSE PAS à une nouvelle notion, reste exactement sur celle-ci. "
        + "Déjà couvert avant : " + covered + ".\n\n"
        + "IMPORTANT : commence ta réponse DIRECTEMENT par « TYPE: » — aucune salutation, aucune phrase avant ou après.\n\n"
        + LESSON_FORMAT;
}

// Lit la valeur d'un champ « CLE: valeur » (insensible à la casse) dans un tableau de lignes.
function _field(lines, name) {
    var re = new RegExp("^\\s*" + name + "\\s*:\\s*(.*)$", "i");
    for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(re);
        if (m) return m[1].trim();
    }
    return "";
}

// Parse une étape au format texte → leçon {type,title,content,summary} ou quiz {type,...,id,summary}.
function parseLearningStep(stdout) {
    if (typeof stdout !== "string") return null;
    var text = stdout.trim();
    // retire un éventuel fence ENVELOPPANT uniquement (préserve les blocs ``` internes du contenu)
    if (text.indexOf("```") === 0) {
        text = text.replace(/^```[a-zA-Z]*[ \t]*\r?\n?/, "");
        text = text.replace(/\r?\n?```[ \t]*$/, "");
    }
    var lines = text.split(/\r?\n/);
    var type = _field(lines, "TYPE").toLowerCase();

    if (type === "lesson") {
        var title = _field(lines, "TITRE");
        var summary = _field(lines, "RESUME");
        var ci = -1;
        for (var j = 0; j < lines.length; j++) {
            if (/^\s*CONTENU\s*:/i.test(lines[j])) { ci = j; break; }
        }
        var content = "";
        if (ci !== -1) {
            var head = lines[ci].replace(/^\s*CONTENU\s*:\s?/i, "");
            var rest = lines.slice(ci + 1).join("\n");
            content = (head + (head && rest ? "\n" : "") + rest).trim();
        }
        if (!title || !content) return null;
        if (!summary) summary = title;
        return { type: "lesson", title: title, content: content, summary: summary };
    }

    if (type === "quiz") {
        var q = _field(lines, "QUESTION");
        var choices = [_field(lines, "A"), _field(lines, "B"), _field(lines, "C"), _field(lines, "D")];
        var rep = _field(lines, "REPONSE").toUpperCase();
        var map = { A: 0, B: 1, C: 2, D: 3 };
        var answer = (map[rep] !== undefined) ? map[rep] : parseInt(rep, 10);
        var explanation = _field(lines, "EXPLICATION");
        var obj = { question: q, choices: choices, answer: answer, explanation: explanation };
        if (!validate(obj)) return null;
        var qsum = _field(lines, "RESUME") || ("Quiz : " + q);
        if (qsum.length > 60) qsum = qsum.slice(0, 60);
        obj.id = "ai-" + hashString(q);
        obj.type = "quiz";
        obj.summary = qsum;
        return obj;
    }

    return null;
}

// Résumé court d'une étape à ajouter à l'historique de progression.
function summarizeStep(step) {
    return (step && typeof step.summary === "string") ? step.summary : "";
}

// Nettoie la sortie de `claude -p` : première ligne non vide, sans guillemets, plafonnée.
function cleanNudge(stdout, max) {
    max = max || 40;
    if (typeof stdout !== "string") return "";
    var line = "";
    var parts = stdout.split("\n");
    for (var i = 0; i < parts.length; i++) {
        var t = parts[i].trim();
        if (t) { line = t; break; }
    }
    line = line.replace(/^["'«»\s]+/, "").replace(/["'«»\s]+$/, "");
    if (line.length > max) line = line.slice(0, max);
    return line;
}
