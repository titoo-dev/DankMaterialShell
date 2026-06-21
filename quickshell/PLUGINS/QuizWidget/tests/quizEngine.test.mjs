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
        src + "\n;globalThis.__api = {"
        + " validate: typeof validate !== 'undefined' ? validate : undefined,"
        + " pickQuestion: typeof pickQuestion !== 'undefined' ? pickQuestion : undefined,"
        + " buildQuestionPrompt: typeof buildQuestionPrompt !== 'undefined' ? buildQuestionPrompt : undefined,"
        + " extractQuestionJson: typeof extractQuestionJson !== 'undefined' ? extractQuestionJson : undefined,"
        + " claudeBinary: typeof claudeBinary !== 'undefined' ? claudeBinary : undefined,"
        + " randomNudge: typeof randomNudge !== 'undefined' ? randomNudge : undefined,"
        + " randomEmoji: typeof randomEmoji !== 'undefined' ? randomEmoji : undefined,"
        + " randomNudgeAngle: typeof randomNudgeAngle !== 'undefined' ? randomNudgeAngle : undefined,"
        + " buildNudgePrompt: typeof buildNudgePrompt !== 'undefined' ? buildNudgePrompt : undefined,"
        + " parseNudge: typeof parseNudge !== 'undefined' ? parseNudge : undefined,"
        + " animationIndex: typeof animationIndex !== 'undefined' ? animationIndex : undefined,"
        + " buildLessonPrompt: typeof buildLessonPrompt !== 'undefined' ? buildLessonPrompt : undefined,"
        + " buildRelearnPrompt: typeof buildRelearnPrompt !== 'undefined' ? buildRelearnPrompt : undefined,"
        + " parseLearningStep: typeof parseLearningStep !== 'undefined' ? parseLearningStep : undefined,"
        + " summarizeStep: typeof summarizeStep !== 'undefined' ? summarizeStep : undefined,"
        + " buildAnswerPrompt: typeof buildAnswerPrompt !== 'undefined' ? buildAnswerPrompt : undefined,"
        + " mdToHtml: typeof mdToHtml !== 'undefined' ? mdToHtml : undefined,"
        + " cleanNudge: typeof cleanNudge !== 'undefined' ? cleanNudge : undefined };",
        ctx
    );
    return ctx.__api;
}
const E = loadEngine();

// Normalise les tableaux renvoyés par le contexte vm (realm différent) avant comparaison.
const arrEq = (actual, expected) => assert.deepEqual(Array.from(actual), expected);

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

const bank = [
    { id: "a", question: "Qa ?", choices: ["1", "2"], answer: 0, explanation: "ea" },
    { id: "b", question: "Qb ?", choices: ["1", "2"], answer: 1, explanation: "eb" }
];

test("pickQuestion choisit la première du pool avec rng=0", () => {
    const r = E.pickQuestion(bank, [], () => 0);
    assert.equal(r.question.id, "a");
    arrEq(r.seen, ["a"]);
});
test("pickQuestion évite les déjà-vues", () => {
    const r = E.pickQuestion(bank, ["a"], () => 0);
    assert.equal(r.question.id, "b");
    arrEq(r.seen, ["a", "b"]);
});
test("pickQuestion recycle quand tout est vu", () => {
    const r = E.pickQuestion(bank, ["a", "b"], () => 0);
    assert.equal(r.question.id, "a");
    arrEq(r.seen, ["a"]);
});
test("pickQuestion ignore les questions invalides", () => {
    const mixed = [{ id: "bad", question: "", choices: ["1"], answer: 9, explanation: "" }, bank[0]];
    const r = E.pickQuestion(mixed, [], () => 0);
    assert.equal(r.question.id, "a");
});
test("pickQuestion retourne null sur banque vide/invalide", () => {
    assert.equal(E.pickQuestion([], [], () => 0), null);
});

test("buildQuestionPrompt inclut le label et la catégorie et exige du JSON", () => {
    const p = E.buildQuestionPrompt("Docker", "Technologies");
    assert.match(p, /Docker/);
    assert.match(p, /Technologies/);
    assert.match(p, /JSON/);
    assert.match(p, /4 propositions/);
    assert.match(p, /emoji/i);
    assert.match(p, /markdown/i);
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

test("claudeBinary construit le chemin absolu depuis HOME", () => {
    assert.equal(E.claudeBinary("/home/x"), "/home/x/.local/bin/claude");
});
test("claudeBinary retombe sur 'claude' si HOME absent", () => {
    assert.equal(E.claudeBinary(""), "claude");
    assert.equal(E.claudeBinary(null), "claude");
});

test("randomNudge renvoie le premier preset avec rng=0", () => {
    const n = E.randomNudge(() => 0);
    assert.equal(typeof n, "string");
    assert.ok(n.length > 0);
});
test("randomNudge renvoie toujours un preset non vide", () => {
    for (let r = 0; r < 1; r += 0.1) {
        const n = E.randomNudge(() => r);
        assert.ok(typeof n === "string" && n.length > 0);
    }
});
test("cleanNudge prend la première ligne non vide et retire les guillemets", () => {
    assert.equal(E.cleanNudge('\n  "Clique-moi 👀"  \nautre ligne'), "Clique-moi 👀");
});
test("cleanNudge plafonne la longueur", () => {
    const long = "x".repeat(100);
    assert.ok(E.cleanNudge(long, 40).length <= 40);
});
test("cleanNudge gère une entrée non-string", () => {
    assert.equal(E.cleanNudge(null), "");
});
test("randomNudgeAngle renvoie un angle non vide", () => {
    const a = E.randomNudgeAngle(() => 0);
    assert.ok(typeof a === "string" && a.length > 0);
});
test("buildNudgePrompt demande un JSON message/emoji/animation et liste les animations", () => {
    const p = E.buildNudgePrompt("MON_ANGLE_TEST");
    assert.match(p, /MON_ANGLE_TEST/);
    assert.match(p, /JSON/);
    assert.match(p, /message/);
    assert.match(p, /emoji/);
    assert.match(p, /animation/);
    assert.match(p, /tada/); // un nom d'animation présent dans la liste
});
test("animationIndex mappe un nom vers l'index de l'overlay", () => {
    assert.equal(E.animationIndex("bounce"), 0);
    assert.equal(E.animationIndex("tada"), 4);
    assert.equal(E.animationIndex("metronome"), 13);
    assert.equal(E.animationIndex("  POP  "), 10); // trim + casse
});
test("animationIndex renvoie -1 pour un nom inconnu", () => {
    assert.equal(E.animationIndex("inexistante"), -1);
    assert.equal(E.animationIndex(null), -1);
});
test("parseNudge extrait message/emoji/animIndex", () => {
    const n = E.parseNudge('{"message": "Allez go", "emoji": "🔥", "animation": "pop"}');
    assert.equal(n.message, "Allez go");
    assert.equal(n.emoji, "🔥");
    assert.equal(n.animIndex, 10);
});
test("parseNudge gère les fences markdown", () => {
    const n = E.parseNudge('```json\n{"message":"Coucou","emoji":"👋","animation":"wobble"}\n```');
    assert.equal(n.message, "Coucou");
    assert.equal(n.animIndex, 9);
});
test("parseNudge -> animIndex -1 si animation inconnue", () => {
    const n = E.parseNudge('{"message":"Hop","emoji":"✨","animation":"zzz"}');
    assert.equal(n.animIndex, -1);
});
test("parseNudge renvoie null sur sortie non-JSON", () => {
    assert.equal(E.parseNudge("désolé, pas de json"), null);
});
test("parseNudge renvoie null si message vide", () => {
    assert.equal(E.parseNudge('{"message":"  ","emoji":"✨","animation":"pop"}'), null);
});
test("randomEmoji renvoie un emoji non vide", () => {
    const e = E.randomEmoji(() => 0);
    assert.ok(typeof e === "string" && e.length > 0);
});

test("buildLessonPrompt inclut le sujet, l'historique, leçon/quiz et le format TYPE", () => {
    const p = E.buildLessonPrompt("Vim", ["modes", "dd/yy"]);
    assert.match(p, /Vim/);
    assert.match(p, /modes/);
    assert.match(p, /le[çc]on/i);
    assert.match(p, /quiz/i);
    assert.match(p, /TYPE:/);
});
test("buildLessonPrompt gère un historique vide", () => {
    const p = E.buildLessonPrompt("Vim", []);
    assert.match(p, /rien encore/);
});
const lessonTxt = "TYPE: lesson\nTITRE: Les modes\nRESUME: modes de base\nCONTENU:\n**Normal** et `i`\nplusieurs lignes \"avec guillemets\" et \\d antislash";
test("parseLearningStep — leçon (format texte) avec contenu libre", () => {
    const s = E.parseLearningStep(lessonTxt);
    assert.equal(s.type, "lesson");
    assert.equal(s.title, "Les modes");
    assert.match(s.content, /Normal/);
    assert.match(s.content, /plusieurs lignes/); // multi-ligne préservé
    assert.match(s.content, /guillemets/);       // guillemets bruts OK (impossible en JSON)
    assert.match(s.content, /\\d/);               // antislash brut OK
    assert.equal(s.summary, "modes de base");
});
test("parseLearningStep — leçon sans RESUME -> summary = titre", () => {
    const s = E.parseLearningStep("TYPE: lesson\nTITRE: Le registre\nCONTENU:\ndu contenu");
    assert.equal(s.summary, "Le registre");
});
test("parseLearningStep — leçon sans contenu -> null", () => {
    assert.equal(E.parseLearningStep("TYPE: lesson\nTITRE: X\nCONTENU:\n   "), null);
});
test("parseLearningStep — quiz (format texte) valide, avec ':' dans un choix", () => {
    const s = E.parseLearningStep("TYPE: quiz\nQUESTION: Quitter Vim ?\nA: :q\nB: :w\nC: :x\nD: :e\nREPONSE: A\nEXPLICATION: ok\nRESUME: sortie");
    assert.equal(s.type, "quiz");
    assert.equal(s.answer, 0);
    assert.equal(s.choices.length, 4);
    assert.equal(s.choices[0], ":q");
    assert.ok(s.id.startsWith("ai-"));
    assert.equal(s.summary, "sortie");
});
test("parseLearningStep — quiz REPONSE numérique acceptée", () => {
    const s = E.parseLearningStep("TYPE: quiz\nQUESTION: Q ?\nA: a\nB: b\nC: c\nD: d\nREPONSE: 2\nEXPLICATION: ok\nRESUME: s");
    assert.equal(s.answer, 2);
});
test("parseLearningStep — quiz incomplet (validate) -> null", () => {
    assert.equal(E.parseLearningStep("TYPE: quiz\nQUESTION: Q ?\nA: a\nB: \nC: \nD: \nREPONSE: A\nEXPLICATION: \nRESUME: s"), null);
});
test("parseLearningStep — type inconnu / vide -> null", () => {
    assert.equal(E.parseLearningStep("TYPE: autre\nTITRE: x"), null);
    assert.equal(E.parseLearningStep("désolé, rien d'utile"), null);
});
test("parseLearningStep gère les fences markdown", () => {
    const s = E.parseLearningStep("```\nTYPE: lesson\nTITRE: T\nCONTENU:\nC\n```");
    assert.equal(s.type, "lesson");
    assert.equal(s.title, "T");
});
test("summarizeStep renvoie le summary", () => {
    assert.equal(E.summarizeStep({ type: "lesson", summary: "abc" }), "abc");
});
test("buildNudgePrompt inclut le context fourni et garde le défaut", () => {
    assert.match(E.buildNudgePrompt("a", "une nouvelle leçon de Vim"), /nouvelle leçon de Vim/);
    assert.match(E.buildNudgePrompt("a"), /mini-quiz/);
});

test("buildRelearnPrompt ré-explique la même notion autrement (format texte)", () => {
    const p = E.buildRelearnPrompt("Vim", "les modes Normal/Insertion", ["x"]);
    assert.match(p, /Vim/);
    assert.match(p, /les modes Normal\/Insertion/);
    assert.match(p, /AUTREMENT|autre/i);
    assert.match(p, /TYPE: lesson/);
});

test("extractQuestionJson tolère un retour-ligne brut dans une chaîne", () => {
    const raw = '{"question":"Ligne1\nLigne2 ?","choices":["1","2","3","4"],"answer":0,"explanation":"ok"}';
    const q = E.extractQuestionJson(raw);
    assert.ok(q);
    assert.match(q.question, /Ligne1/);
});

test("extractJsonObject répare une séquence d'échappement invalide (ex. backslash-d de regex)", () => {
    // claude écrit parfois \d (antislash brut) dans le JSON → invalide ; on le répare en littéral.
    const raw = '{"question":"Regex \\d trouve un chiffre ?","choices":["1","2","3","4"],"answer":0,"explanation":"ok"}';
    const q = E.extractQuestionJson(raw);
    assert.ok(q, "doit parser malgré l'échappement invalide");
    assert.match(q.question, /Regex/);
});

test("parseLearningStep — contenu avec bloc de code ``` interne préservé", () => {
    const txt = "TYPE: lesson\nTITRE: T\nRESUME: s\nCONTENU:\nExemple :\n```vim\n:wq\n```\nVoilà !";
    const s = E.parseLearningStep(txt);
    assert.ok(s, "doit parser malgré le bloc de code interne");
    assert.match(s.content, /:wq/);
    assert.match(s.content, /```vim/); // bloc de code conservé
});
test("parseLearningStep — réponse entière enveloppée dans un fence", () => {
    const txt = "```\nTYPE: lesson\nTITRE: T\nRESUME: s\nCONTENU:\nhello\n```";
    const s = E.parseLearningStep(txt);
    assert.ok(s);
    assert.equal(s.title, "T");
    assert.match(s.content, /hello/);
});

test("mdToHtml — gras / italique / code inline en HTML stylé", () => {
    const h = E.mdToHtml("Tape `:wq` pour **sauver** et *quitter*", "#fff", "#222");
    assert.match(h, /<span[^>]*font-family:monospace[^>]*>[^<]*:wq[^<]*<\/span>/);
    assert.match(h, /<b>sauver<\/b>/);
    assert.match(h, /<i>quitter<\/i>/);
});
test("mdToHtml — bloc de code ``` en <pre>", () => {
    const h = E.mdToHtml("Exemple:\n```vim\n:wq\n```", "#fff", "#222");
    assert.match(h, /<pre[^>]*>:wq<\/pre>/);
});
test("mdToHtml — échappe le HTML", () => {
    const h = E.mdToHtml("a < b & c > d", "#fff", "#222");
    assert.match(h, /a &lt; b &amp; c &gt; d/);
});
test("mdToHtml — le contenu du code est échappé et non re-formatté", () => {
    const h = E.mdToHtml("`a < b **x**`", "#fff", "#222");
    assert.match(h, /a &lt; b/);
    assert.ok(!/<b>/.test(h), "pas de gras à l'intérieur du code");
});
test("mdToHtml — retours-ligne en <br>", () => {
    assert.match(E.mdToHtml("l1\nl2", "#fff", "#222"), /l1<br>l2/);
});
test("mdToHtml — entrée non-string -> chaîne vide", () => {
    assert.equal(E.mdToHtml(null, "#fff", "#222"), "");
});

test("buildAnswerPrompt — réponse brève sur le sujet, inclut la question", () => {
    const p = E.buildAnswerPrompt("Vim", "comment quitter ?");
    assert.match(p, /Vim/);
    assert.match(p, /comment quitter \?/);
    assert.match(p, /bri[eè]vement|bref|concis/i);
    assert.match(p, /backtick|markdown/i);
});
