.pragma library

// Sanitizer for notification bodies rendered with Text.StyledText.
//
// The freedesktop notification spec allows a small markup subset in bodies
// (<b> <i> <u> <a> <img>), but real-world senders (browsers, Electron apps,
// phone-notification bridges) emit anything from entity-encoded HTML to full
// documents. Qt's StyledText parser silently falls back to PlainText on
// malformed or unsupported markup, which renders the raw HTML as visible
// text. Everything returned by sanitize() is therefore guaranteed to be
// well-formed markup using only tags StyledText understands.

const INLINE_TAGS = {
    "b": "b",
    "strong": "b",
    "i": "i",
    "em": "i",
    "u": "u",
    "s": "s",
    "strike": "s",
    "del": "s"
};

// Tags whose boundaries become line breaks; their content is kept.
const BLOCK_TAGS = {
    "p": true,
    "div": true,
    "ul": true,
    "ol": true,
    "blockquote": true,
    "pre": true,
    "table": true,
    "tr": true,
    "section": true,
    "article": true,
    "header": true,
    "footer": true,
    "html": true,
    "body": true
};

// h1-h6 render as bold with surrounding breaks.
const HEADING_TAGS = {
    "h1": true,
    "h2": true,
    "h3": true,
    "h4": true,
    "h5": true,
    "h6": true
};

const ALLOWED_HREF_SCHEMES = /^(https?|file|mailto|tel|sms|geo):/i;

const NAMED_ENTITIES = {
    "amp": "&",
    "lt": "<",
    "gt": ">",
    "quot": "\"",
    "apos": "'",
    "nbsp": " ",
    "ndash": "–",
    "mdash": "—",
    "lsquo": "‘",
    "rsquo": "’",
    "ldquo": "“",
    "rdquo": "”",
    "bull": "•",
    "hellip": "…",
    "trade": "™",
    "copy": "©",
    "reg": "®",
    "deg": "°",
    "plusmn": "±",
    "times": "×",
    "divide": "÷",
    "micro": "µ",
    "middot": "·",
    "laquo": "«",
    "raquo": "»",
    "larr": "←",
    "rarr": "→",
    "uarr": "↑",
    "darr": "↓",
    "euro": "€",
    "pound": "£",
    "yen": "¥",
    "cent": "¢",
    "sect": "§",
    "para": "¶",
    "dagger": "†",
    "Dagger": "‡",
    "permil": "‰",
    "prime": "′",
    "Prime": "″",
    "frasl": "⁄",
    "minus": "−",
    "lowast": "∗",
    "ne": "≠",
    "le": "≤",
    "ge": "≥",
    "infin": "∞",
    "sum": "∑",
    "prod": "∏",
    "radic": "√",
    "asymp": "≈",
    "equiv": "≡",
    "oplus": "⊕",
    "otimes": "⊗",
    "perp": "⊥",
    "sdot": "⋅",
    "alpha": "α",
    "beta": "β",
    "gamma": "γ",
    "delta": "δ",
    "pi": "π",
    "sigma": "σ",
    "omega": "ω",
    "Omega": "Ω",
    "mu": "μ",
    "lambda": "λ",
    "shy": "",
    "zwnj": "",
    "zwj": "",
    "ensp": " ",
    "emsp": " ",
    "thinsp": " ",
    "iexcl": "¡",
    "curren": "¤",
    "brvbar": "¦",
    "uml": "¨",
    "ordf": "ª",
    "not": "¬",
    "macr": "¯",
    "sup1": "¹",
    "sup2": "²",
    "sup3": "³",
    "acute": "´",
    "cedil": "¸",
    "ordm": "º",
    "frac14": "¼",
    "frac12": "½",
    "frac34": "¾",
    "iquest": "¿",
    "Agrave": "À",
    "Aacute": "Á",
    "Acirc": "Â",
    "Atilde": "Ã",
    "Auml": "Ä",
    "Aring": "Å",
    "AElig": "Æ",
    "Ccedil": "Ç",
    "Egrave": "È",
    "Eacute": "É",
    "Ecirc": "Ê",
    "Euml": "Ë",
    "Igrave": "Ì",
    "Iacute": "Í",
    "Icirc": "Î",
    "Iuml": "Ï",
    "ETH": "Ð",
    "Ntilde": "Ñ",
    "Ograve": "Ò",
    "Oacute": "Ó",
    "Ocirc": "Ô",
    "Otilde": "Õ",
    "Ouml": "Ö",
    "Oslash": "Ø",
    "Ugrave": "Ù",
    "Uacute": "Ú",
    "Ucirc": "Û",
    "Uuml": "Ü",
    "Yacute": "Ý",
    "THORN": "Þ",
    "szlig": "ß",
    "agrave": "à",
    "aacute": "á",
    "acirc": "â",
    "atilde": "ã",
    "auml": "ä",
    "aring": "å",
    "aelig": "æ",
    "ccedil": "ç",
    "egrave": "è",
    "eacute": "é",
    "ecirc": "ê",
    "euml": "ë",
    "igrave": "ì",
    "iacute": "í",
    "icirc": "î",
    "iuml": "ï",
    "eth": "ð",
    "ntilde": "ñ",
    "ograve": "ò",
    "oacute": "ó",
    "ocirc": "ô",
    "otilde": "õ",
    "ouml": "ö",
    "oslash": "ø",
    "ugrave": "ù",
    "uacute": "ú",
    "ucirc": "û",
    "uuml": "ü",
    "yacute": "ý",
    "thorn": "þ",
    "yuml": "ÿ",
    "oelig": "œ",
    "OElig": "Œ",
    "scaron": "š",
    "Scaron": "Š",
    "fnof": "ƒ",
    "sbquo": "‚",
    "bdquo": "„"
};

function decodeEntities(s) {
    if (!s)
        return "";
    s = s.replace(/&#(\d+);/g, (m, n) => {
        const code = parseInt(n, 10);
        return code >= 0 && code <= 0x10FFFF ? String.fromCodePoint(code) : m;
    });
    s = s.replace(/&#x([0-9a-fA-F]+);/g, (m, n) => {
        const code = parseInt(n, 16);
        return code >= 0 && code <= 0x10FFFF ? String.fromCodePoint(code) : m;
    });
    return s.replace(/&([a-zA-Z][a-zA-Z0-9]*);/g, (m, name) => {
        if (Object.prototype.hasOwnProperty.call(NAMED_ENTITIES, name))
            return NAMED_ENTITIES[name];
        return m;
    });
}

function hasMarkup(s) {
    return /<\/?[a-zA-Z][^>]*>/.test(s || "");
}

function hasEntities(s) {
    return /&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);/.test(s || "");
}

function escapeText(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function escapeAttr(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// Escape a decoded text segment, turning bare URLs into anchors.
function escapeAndLink(text, allowLinks) {
    if (!allowLinks)
        return escapeText(text);
    const urlRe = /\bhttps?:\/\/[^\s<>"']+/g;
    let out = "";
    let last = 0;
    let m;
    while ((m = urlRe.exec(text)) !== null) {
        out += escapeText(text.slice(last, m.index));
        // Trim trailing punctuation that's almost never part of the URL.
        let url = m[0].replace(/[.,;:!?)\]]+$/, "");
        out += "<a href=\"" + escapeAttr(url) + "\">" + escapeText(url) + "</a>";
        last = m.index + url.length;
    }
    out += escapeText(text.slice(last));
    return out;
}

function extractHref(attrs) {
    const m = /href\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(attrs || "");
    if (!m)
        return "";
    const raw = m[2] !== undefined ? m[2] : (m[3] !== undefined ? m[3] : m[4]);
    const href = decodeEntities(raw).trim();
    if (!ALLOWED_HREF_SCHEMES.test(href))
        return "";
    return href;
}

const TOKEN_RE = /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<![^>]*>|<\?[^>]*>|<\s*(\/?)\s*([a-zA-Z][a-zA-Z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*)>/g;

// Sanitize markup (or plain text) into well-formed StyledText markup.
// Unknown tags are dropped, their content kept. <img> is dropped entirely
// (notification bodies must not trigger network fetches).
function sanitize(input) {
    if (!input)
        return "";

    const BR = "\x00BR\x00";
    const parts = [];
    const stack = [];

    function openTag(mapped) {
        stack.push(mapped);
        parts.push("<" + mapped + ">");
    }

    function closeTag(mapped) {
        const idx = stack.lastIndexOf(mapped);
        if (idx === -1)
            return;
        // Close inner tags too so the output stays properly nested.
        for (let i = stack.length - 1; i >= idx; i--)
            parts.push("</" + stack[i] + ">");
        stack.length = idx;
    }

    function inLink() {
        return stack.indexOf("a") !== -1;
    }

    let last = 0;
    let m;
    TOKEN_RE.lastIndex = 0;
    while ((m = TOKEN_RE.exec(input)) !== null) {
        if (m.index > last)
            parts.push(escapeAndLink(decodeEntities(input.slice(last, m.index)), !inLink()));
        last = TOKEN_RE.lastIndex;

        if (m[2] === undefined)
            continue; // comment / doctype / processing instruction

        const closing = m[1] === "/";
        const name = m[2].toLowerCase();
        const attrs = m[3] || "";

        if (name === "br") {
            if (!closing)
                parts.push(BR);
            continue;
        }
        if (name === "img")
            continue;

        if (Object.prototype.hasOwnProperty.call(INLINE_TAGS, name)) {
            const mapped = INLINE_TAGS[name];
            if (closing)
                closeTag(mapped);
            else
                openTag(mapped);
            continue;
        }

        if (name === "a") {
            if (closing) {
                closeTag("a");
            } else {
                const href = extractHref(attrs);
                if (href) {
                    stack.push("a");
                    parts.push("<a href=\"" + escapeAttr(href) + "\">");
                }
            }
            continue;
        }

        if (Object.prototype.hasOwnProperty.call(HEADING_TAGS, name)) {
            if (closing) {
                closeTag("b");
                parts.push(BR);
            } else {
                parts.push(BR);
                openTag("b");
            }
            continue;
        }

        if (name === "li") {
            if (!closing)
                parts.push(BR + "• ");
            continue;
        }

        if (Object.prototype.hasOwnProperty.call(BLOCK_TAGS, name)) {
            parts.push(BR);
            continue;
        }
        // Unknown tag: dropped, content kept.
    }
    if (last < input.length)
        parts.push(escapeAndLink(decodeEntities(input.slice(last)), !inLink()));

    for (let i = stack.length - 1; i >= 0; i--)
        parts.push("</" + stack[i] + ">");

    let html = parts.join("");

    // Newlines in the original text are line breaks too.
    html = html.replace(/\r\n?/g, "\n").replace(/\n/g, BR);
    // Collapse runs of breaks (with optional whitespace between) to at most two.
    const brRun = new RegExp("(?:" + BR + "[ \\t]*){3,}", "g");
    html = html.replace(brRun, BR + BR);
    // Trim leading/trailing breaks and whitespace.
    const edge = new RegExp("^(?:" + BR + "|[ \\t])+|(?:" + BR + "|[ \\t])+$", "g");
    html = html.replace(edge, "");
    html = html.split(BR).join("<br/>");

    return html;
}

// Strip all markup and decode entities, for single-line plain-text contexts
// (summaries, previews, dedup keys).
function toPlainText(s) {
    if (!s)
        return "";
    let text = s.toString();
    text = text.replace(TOKEN_RE, " ");
    text = decodeEntities(text);
    text = text.replace(/\s+/g, " ").trim();
    return text;
}
