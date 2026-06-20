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
