.pragma library

// Minimal, themeable Markdown → Qt RichText (HTML subset) renderer.
// Tuned for short assistant answers (the island Ask panel). Uses only tags the
// Qt rich-text engine renders: <h3>/<h4>, <b>/<i>, <pre>, <span style>, <ul>/<li>,
// <ol>/<li>, <a>, <br>. Colors/mono family are passed in so it tracks the theme.
// Code spans are extracted to distinctive placeholders before escaping/formatting,
// then restored last (the token can't collide with text, markdown, or escaping).

function _escape(s) {
    return String(s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
}

// opts: { codeColor, codeBg, mono, linkColor }
function toRichText(md, opts) {
    if (typeof md !== "string")
        return "";
    opts = opts || {};
    var cc = opts.codeColor || "#cbb6ff";
    var cb = opts.codeBg || "#2a2a33";
    var mono = opts.mono || "monospace";
    var link = opts.linkColor || cc;

    var codeStyle = "font-family:'" + mono + "',monospace; color:" + cc + "; background-color:" + cb;
    var ph = [];
    var s = md.replace(/\r\n/g, "\n");

    function stash(html) {
        ph.push(html);
        return "@@MDPH" + (ph.length - 1) + "@@";
    }

    // fenced code blocks ```lang\n ... ``` → styled <pre> panel (proven to render
    // text + background in Qt's rich-text engine; nested tables drop the content)
    s = s.replace(/```[a-zA-Z0-9+#.\-]*\n?([\s\S]*?)```/g, function (m, code) {
        var body = _escape(code.replace(/\s+$/, ""));
        return stash('<pre style="' + codeStyle + '; padding:6px">' + body + '</pre>');
    });
    // inline code `...`
    s = s.replace(/`([^`\n]+)`/g, function (m, code) {
        return stash('<span style="' + codeStyle + '">&nbsp;' + _escape(code) + '&nbsp;</span>');
    });

    s = _escape(s);

    // headings → real hierarchy (cap at h3/h4 for a compact panel)
    s = s.replace(/^[ \t]*#{1,2}[ \t]+(.+)$/gm, '<h3>$1</h3>');
    s = s.replace(/^[ \t]*#{3,6}[ \t]+(.+)$/gm, '<h4>$1</h4>');

    // bold / italic
    s = s.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
    s = s.replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<i>$2</i>');

    // bare URLs → links
    s = s.replace(/(https?:\/\/[^\s<]+)/g, function (m, url) {
        return '<a href="' + url + '" style="color:' + link + '">' + url + '</a>';
    });

    // group contiguous list lines into <ul>/<ol>
    var lines = s.split("\n");
    var out = [];
    var i = 0;
    while (i < lines.length) {
        if (/^[ \t]*[-*][ \t]+(.+)$/.test(lines[i])) {
            var u = [];
            while (i < lines.length && /^[ \t]*[-*][ \t]+(.+)$/.test(lines[i])) {
                u.push('<li>' + lines[i].replace(/^[ \t]*[-*][ \t]+/, '') + '</li>');
                i++;
            }
            out.push('<ul style="margin:4px 0">' + u.join("") + '</ul>');
        } else if (/^[ \t]*\d+\.[ \t]+(.+)$/.test(lines[i])) {
            var o = [];
            while (i < lines.length && /^[ \t]*\d+\.[ \t]+(.+)$/.test(lines[i])) {
                o.push('<li>' + lines[i].replace(/^[ \t]*\d+\.[ \t]+/, '') + '</li>');
                i++;
            }
            out.push('<ol style="margin:4px 0">' + o.join("") + '</ol>');
        } else {
            out.push(lines[i]);
            i++;
        }
    }
    s = out.join("\n");

    s = s.replace(/\n/g, '<br>');
    // drop the <br> the engine would otherwise stack against block elements
    s = s.replace(/<br>\s*(<(?:h3|h4|ul|ol|table))/g, '$1');
    s = s.replace(/(<\/(?:h3|h4|ul|ol|table)>)\s*<br>/g, '$1');

    // restore code placeholders
    s = s.replace(/@@MDPH(\d+)@@/g, function (m, n) { return ph[+n]; });
    return s;
}
