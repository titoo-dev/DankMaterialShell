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
    return "Génère UNE question de quiz à choix unique, en français, de niveau intermédiaire, "
        + "sur le sujet suivant (catégorie « " + category + " ») : " + topicLabel + ". "
        + "La question doit être claire et factuelle, avec EXACTEMENT 4 propositions dont une seule correcte, "
        + "et une explication courte de la bonne réponse. "
        + "Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour, sans balises Markdown, de la forme : "
        + '{"question": "...", "choices": ["...", "...", "...", "..."], "answer": 0, "explanation": "..."} '
        + "où \"answer\" est l'index (0 à 3) de la bonne proposition dans \"choices\".";
}

// Parse la sortie de `claude -p` : retire les fences markdown, isole le premier objet {…}
// équilibré (en ignorant les accolades à l'intérieur des chaînes), valide, assigne un id.
function extractQuestionJson(stdout) {
    if (typeof stdout !== "string") return null;
    var text = stdout;
    var fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
    if (fence) text = fence[1];
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
function nudgePrompt(angle) {
    var a = angle || randomNudgeAngle();
    return "Génère UN court message en français (max 7 mots, un emoji bienvenu) "
         + "pour inciter l'utilisateur à cliquer sur un mini-quiz qui vient d'apparaître. "
         + "Style/ton de communication à adopter : " + a + ". "
         + "Tu peux être cool, taquin, drôle, légèrement sarcastique ou lancer un petit clash amical "
         + "— mais reste bienveillant, jamais blessant ni vulgaire. "
         + "Réponds UNIQUEMENT le message, sans guillemets ni ponctuation finale superflue.";
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
