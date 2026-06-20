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
        + " buildAiRequestBody: typeof buildAiRequestBody !== 'undefined' ? buildAiRequestBody : undefined,"
        + " parseAiQuestion: typeof parseAiQuestion !== 'undefined' ? parseAiQuestion : undefined };",
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
