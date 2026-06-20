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
        + " nudgePrompt: typeof nudgePrompt !== 'undefined' ? nudgePrompt : undefined,"
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
test("nudgePrompt inclut l'angle fourni", () => {
    assert.match(E.nudgePrompt("MON_ANGLE_TEST"), /MON_ANGLE_TEST/);
});
test("randomEmoji renvoie un emoji non vide", () => {
    const e = E.randomEmoji(() => 0);
    assert.ok(typeof e === "string" && e.length > 0);
});
