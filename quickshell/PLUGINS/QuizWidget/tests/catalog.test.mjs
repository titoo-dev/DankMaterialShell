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
        src + "\n;globalThis.__api = { CATALOG, CATEGORIES, allCategories, topicById, topicsByCategory, categoriesWithTopics, addCustom, buildTopicPool, categoryEmoji };",
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

test("addCustom ajoute un sujet trimmé", () => {
    assert.deepEqual(Array.from(C.addCustom([], "  WebSockets  ")), ["WebSockets"]);
});
test("addCustom ignore une entrée vide ou en espaces", () => {
    assert.equal(C.addCustom(["a"], "   ").length, 1);
    assert.equal(C.addCustom(["a"], null).length, 1);
});
test("addCustom dédoublonne (insensible à la casse)", () => {
    const r = C.addCustom(["Rust"], "rust");
    assert.equal(r.length, 1);
    assert.equal(r[0], "Rust"); // garde la casse existante
});
test("addCustom ne mute pas la liste d'entrée", () => {
    const orig = ["a"];
    C.addCustom(orig, "b");
    assert.equal(orig.length, 1);
});
test("buildTopicPool fusionne catalogue résolu + customs", () => {
    const pool = C.buildTopicPool(["python", "inconnu"], ["WebSockets"]);
    assert.equal(pool.length, 2); // inconnu ignoré
    assert.equal(pool[0].label, "Python");
    assert.equal(pool[0].category, "Technologies");
    assert.equal(pool[1].id, "custom:WebSockets");
    assert.equal(pool[1].label, "WebSockets");
    assert.equal(pool[1].category, "Sujet libre");
});
test("buildTopicPool ignore les customs vides", () => {
    assert.equal(C.buildTopicPool([], ["", "  "]).length, 0);
});
test("buildTopicPool gère des arguments absents", () => {
    assert.equal(C.buildTopicPool(null, null).length, 0);
});
test("categoryEmoji renvoie un emoji par catégorie + un défaut", () => {
    assert.ok(C.categoryEmoji("Technologies").length > 0);
    assert.ok(C.categoryEmoji("Concepts").length > 0);
    assert.ok(C.categoryEmoji("Méthodologies").length > 0);
    assert.ok(C.categoryEmoji("Sujet libre").length > 0); // défaut
    assert.ok(C.categoryEmoji("n'importe quoi").length > 0);
});
