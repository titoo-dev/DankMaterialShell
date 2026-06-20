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

// --- nudges (messages d'accroche façon Duolingo, affichés sur la pastille) ---

var LOCAL_NUDGES = [
    "Coucou 👋",
    "Je suis là !",
    "Clique-moi 👀",
    "Apprenons un truc !",
    "Petit quiz ? 🧠",
    "On révise ?",
    "Hé, par ici !",
    "Une question pour toi !"
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

var NUDGE_ANGLES = [
    "une salutation chaleureuse",
    "« je suis là, ne m'oublie pas »",
    "« clique-moi »",
    "« apprenons un truc ensemble »",
    "piquer la curiosité",
    "un défi joueur",
    "un encouragement bienveillant",
    "un brin d'humour"
];

function randomNudgeAngle(rng) {
    rng = rng || Math.random;
    var idx = Math.floor(rng() * NUDGE_ANGLES.length);
    if (idx < 0) idx = 0;
    if (idx >= NUDGE_ANGLES.length) idx = NUDGE_ANGLES.length - 1;
    return NUDGE_ANGLES[idx];
}

// Prompt pour `claude -p` : une accroche courte et variée. L'angle aléatoire force la variété.
function nudgePrompt(angle) {
    var a = angle || randomNudgeAngle();
    return "Génère UN court message ludique en français (max 5 mots, style Duolingo, "
         + "un emoji bienvenu) pour inciter à cliquer sur un mini-quiz qui vient d'apparaître. "
         + "Angle à adopter : " + a + ". "
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
