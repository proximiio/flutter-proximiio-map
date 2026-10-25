/* Docs assistant panel — "Ask the docs".
 *
 * ANDROID COPY: copied from the iOS widget (proximiio-ios-sdk-v6
 * docs/site/assets/assistant.js) with Android text only: the subtitle, input
 * hint, intro and example questions. Everything else is identical to iOS, so a
 * diff against the iOS file shows only that text. docs/site/assets and
 * docs/map-site/assets in this repository hold identical copies. The Android
 * build points the endpoint at the server's /android route.
 *
 * SHARED FILE: this file is identical in proximiio-ios-sdk-v6 and
 * proximiio-ios-map-v6 (docs/site/assets/assistant.js). Change both copies
 * together; `cmp` the two files before committing.
 *
 * Emitted only when the site is built with an assistant endpoint
 * (DOCS_ASSISTANT_URL=… or --assistant <url>). The build writes the config
 * before this script:
 *
 *   window.DOCS_ASSISTANT = {
 *     endpoint: "http://127.0.0.1:8787",   // POST {endpoint}/ask, SSE reply
 *     site: "sdk" | "map",                 // this site
 *     page: "guides/background",           // this page's slug ("" = index)
 *     bases: { sdk: "…/dist/" | null, map: "…/dist/" | null }  // other site
 *   };
 *
 * Citations arrive as "sdk/<path>#anchor" or "map/<path>#anchor". A citation
 * of this site resolves against window.DOCS_BASE (relative, works over file://
 * and from any subpath); a citation of the other site resolves against
 * bases[site]. With no base for that site the citation is shown as text.
 *
 * No dependencies. Model output is never inserted as HTML: the markdown
 * renderer below escapes every character it does not itself emit.
 */
(function () {
  "use strict";

  var CFG = window.DOCS_ASSISTANT;
  if (!CFG || !CFG.endpoint || !window.fetch || !document.querySelector) return;

  var SITE = CFG.site === "map" ? "map" : "sdk";
  var BASE = window.DOCS_BASE || "";
  var BASES = CFG.bases || {};
  var STORE_KEY = "proximiio-docs-assistant";
  var HISTORY_TURNS = 3;            // turns sent as `history`
  var MAX_TURNS_KEPT = 20;          // turns kept in the panel
  var NARROW = 860;                 // matches the sidebar breakpoint in styles.css

  var turns = [];                   // { q, a, cites:[{url,label}], status: "" | "stopped" | "error", note, done }
  var busy = null;                  // AbortController of the request in flight

  /* ------------------------------------------------------------------ */
  /* Storage (per-viewer convenience only; every access may throw)       */
  /* ------------------------------------------------------------------ */

  function load() {
    try { var s = JSON.parse(window.sessionStorage.getItem(STORE_KEY) || "null"); return s && Array.isArray(s.turns) ? s : null; }
    catch (e) { return null; }
  }
  function save(open) {
    try {
      window.sessionStorage.setItem(STORE_KEY, JSON.stringify({
        open: open === undefined ? isOpen() : open,
        turns: turns.slice(-MAX_TURNS_KEPT)
      }));
    } catch (e) { /* storage blocked */ }
  }

  /* ------------------------------------------------------------------ */
  /* Escaping and links                                                  */
  /* ------------------------------------------------------------------ */

  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // "sdk/guides/x.html#a" -> { href, external } or null when it cannot be linked.
  function resolveDocUrl(url) {
    var m = /^(sdk|map)\/([^\s]*)$/.exec(url);
    if (!m) return null;
    if (m[1] === SITE) return { href: BASE + m[2], external: false };
    var b = BASES[m[1]];
    return b ? { href: b + m[2], external: true } : null;
  }

  function linkHtml(url, labelHtml) {
    var u = url.replace(/^<|>$/g, "");
    var r = resolveDocUrl(u);
    if (r) {
      return '<a href="' + esc(r.href) + '"' + (r.external ? ' target="_blank" rel="noopener"' : "") +
        ' data-da-cite>' + labelHtml + "</a>";
    }
    if (/^https?:\/\//i.test(u)) return '<a href="' + esc(u) + '" target="_blank" rel="noopener noreferrer">' + labelHtml + "</a>";
    return labelHtml;
  }

  /* ------------------------------------------------------------------ */
  /* Markdown: fences, headings, lists, tables, paragraphs; inline code, */
  /* links, bold, italic. Everything else is escaped text.               */
  /* ------------------------------------------------------------------ */

  function emph(escaped) {
    return escaped
      .replace(/\*\*([^*\n]+?)\*\*/g, "<strong>$1</strong>")
      .replace(/(^|[^*\w])\*([^*\s][^*\n]*?)\*(?![*\w])/g, "$1<em>$2</em>");
  }

  // Code spans and emphasis, no links.
  function spans(raw) {
    var out = "", re = /`([^`\n]+)`/g, last = 0, m;
    while ((m = re.exec(raw))) {
      // <wbr> after punctuation: long API names wrap at "." "(" ":" "," "/" instead of mid-word.
      out += emph(esc(raw.slice(last, m.index))) + "<code>" + esc(m[1]).replace(/([.(:,\/])(?=[^\s])/g, "$1<wbr>") + "</code>";
      last = re.lastIndex;
    }
    return out + emph(esc(raw.slice(last)));
  }

  /* Citations. Doc links ("sdk/…", "map/…") that the model uses as citations
   * collapse into numbered markers [n]; n is the page's position in order of
   * first citation in the answer, which is also the Sources numbering.
   * A link collapses when it is wrapped in parentheses, follows sentence
   * punctuation ("…configuration. [A](u)"), or sits in a run of two or more
   * links. A single link inside a sentence ("See [Permissions](u).") stays a
   * prose link. */
  var RE_LINK = /\[([^\]\n]+)\]\(\s*(<[^>\s]+>|[^)\s]+)\s*\)/g;
  var citePages = [];
  function isDoc(url) { return /^(sdk|map)\//.test(url); }
  function pageOf(url) { return url.split("#")[0]; }
  function citeOrder(text) {
    var pages = [], m, re = new RegExp(RE_LINK.source, "g");
    while ((m = re.exec(String(text || "")))) {
      var u = m[2].replace(/^<|>$/g, "");
      if (isDoc(u) && pages.indexOf(pageOf(u)) < 0) pages.push(pageOf(u));
    }
    return pages;
  }
  function refNumber(page) {
    var i = citePages.indexOf(page);
    if (i < 0) { citePages.push(page); i = citePages.length - 1; }
    return i + 1;
  }
  function refsHtml(run) {
    var keys = [], refs = {};
    run.forEach(function (lk) {
      var page = pageOf(lk.url);
      if (refs[page]) { refs[page].titles.push(lk.label); return; }
      keys.push(page);
      refs[page] = { url: lk.url, titles: [lk.label], n: refNumber(page) };
    });
    return '<span class="da-refs">' + keys.map(function (page) {
      var r = refs[page], label = r.titles.join("; ").replace(/`/g, ""), res = resolveDocUrl(r.url);
      var attrs = ' class="da-ref" title="' + esc(label) + '" aria-label="Source ' + r.n + ": " + esc(label) + '"';
      return res
        ? "<a" + attrs + ' href="' + esc(res.href) + '"' + (res.external ? ' target="_blank" rel="noopener"' : "") + " data-da-cite>" + r.n + "</a>"
        : "<span" + attrs + ">" + r.n + "</span>";
    }).join("") + "</span>";
  }

  function inline(raw) {
    var ms = [], m, re = new RegExp(RE_LINK.source, "g");
    while ((m = re.exec(raw))) ms.push({ s: m.index, e: re.lastIndex, label: m[1], url: m[2].replace(/^<|>$/g, "") });
    var out = "", pos = 0, i = 0;
    while (i < ms.length) {
      var run = [ms[i]], j = i + 1;
      if (isDoc(ms[i].url)) {
        while (j < ms.length && isDoc(ms[j].url) && /^[\s,;]*$/.test(raw.slice(ms[j - 1].e, ms[j].s))) { run.push(ms[j]); j++; }
      }
      var before = raw.slice(pos, run[0].s), after = raw.slice(run[run.length - 1].e), end = run[run.length - 1].e;
      var collapse = false;
      if (isDoc(run[0].url)) {
        if (/\(\s*$/.test(before) && /^\s*\)/.test(after)) {
          collapse = true; before = before.replace(/\s*\(\s*$/, ""); end += /^\s*\)/.exec(after)[0].length;
        } else if (run.length > 1 || /[.!?:;]\s*$/.test(before)) {
          collapse = true; before = before.replace(/\s+$/, "");
        }
      }
      if (collapse) out += spans(before) + refsHtml(run);
      else { out += spans(before) + linkHtml(run[0].url, spans(run[0].label)); end = run[0].e; j = i + 1; }
      pos = end; i = j;
    }
    return out + spans(raw.slice(pos));
  }

  var RE_FENCE = /^\s*(```|~~~)\s*([\w+-]*)\s*$/;
  var RE_ITEM = /^(\s*)([-*+]|\d{1,3}[.)])\s+(.*)$/;
  var RE_HEAD = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/;
  var RE_ROW = /^\s*\|.*\|\s*$/;
  var RE_SEP = /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/;

  function renderList(items) {
    var html = "", stack = [];
    items.forEach(function (it) {
      var tag = it.ordered ? "ol" : "ul";
      while (stack.length && it.indent < stack[stack.length - 1].indent) {
        html += "</li></" + stack.pop().tag + ">";
      }
      var top = stack[stack.length - 1];
      if (top && it.indent === top.indent && top.tag === tag) {
        html += "</li>";
      } else {
        if (top && it.indent === top.indent) html += "</li></" + stack.pop().tag + ">";
        html += "<" + tag + (it.ordered && it.start !== 1 ? ' start="' + it.start + '"' : "") + ">";
        stack.push({ indent: it.indent, tag: tag });
      }
      html += "<li>" + inline(it.text);
    });
    while (stack.length) html += "</li></" + stack.pop().tag + ">";
    return html;
  }

  function cells(line) {
    return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(function (c) { return c.trim(); });
  }

  function md(src) {
    citePages = citeOrder(src);
    var lines = String(src).replace(/\r\n?/g, "\n").split("\n");
    var out = "", para = [], items = [], i = 0, m;

    function flushPara() { if (para.length) { out += "<p>" + inline(para.join("\n")).replace(/\n/g, "<br>") + "</p>"; para = []; } }
    function flushList() { if (items.length) { out += renderList(items); items = []; } }

    while (i < lines.length) {
      var line = lines[i];

      if ((m = RE_FENCE.exec(line))) {
        flushPara(); flushList();
        var fence = m[1], lang = m[2], code = [];
        i++;
        while (i < lines.length && lines[i].trim() !== fence) { code.push(lines[i]); i++; }
        i++; // closing fence (or end of a still-streaming block)
        var indent = /^\s*/.exec(line)[0].length;
        if (indent) code = code.map(function (l) { return l.slice(Math.min(indent, /^\s*/.exec(l)[0].length)); });
        out += '<div class="da-codewrap"><pre class="da-code"' + (lang ? ' data-lang="' + esc(lang) + '"' : "") + "><code>" + esc(code.join("\n")) + "</code></pre>" +
          '<button type="button" class="da-icon-btn da-copy" aria-label="Copy code" title="Copy code">' + I.copy + "</button></div>";
        continue;
      }
      if (!line.trim()) {
        flushPara();
        // A blank line ends a list unless the list continues after it.
        var next = lines[i + 1];
        if (items.length && !(next && (RE_ITEM.test(next) || /^\s{2,}\S/.test(next)) && !RE_FENCE.test(next))) flushList();
        i++; continue;
      }
      if ((m = RE_HEAD.exec(line))) {
        flushPara(); flushList();
        out += '<p class="da-h">' + inline(m[2]) + "</p>";
        i++; continue;
      }
      if (RE_ROW.test(line) && lines[i + 1] && RE_SEP.test(lines[i + 1])) {
        flushPara(); flushList();
        var head = cells(line), body = [];
        i += 2;
        while (i < lines.length && RE_ROW.test(lines[i])) { body.push(cells(lines[i])); i++; }
        out += '<div class="da-table"><table><thead><tr>' + head.map(function (c) { return "<th>" + inline(c) + "</th>"; }).join("") +
          "</tr></thead><tbody>" + body.map(function (r) { return "<tr>" + r.map(function (c) { return "<td" + (/^`[^`]+`$/.test(c) ? ' class="da-td-code"' : "") + ">" + inline(c) + "</td>"; }).join("") + "</tr>"; }).join("") +
          "</tbody></table></div>";
        continue;
      }
      if ((m = RE_ITEM.exec(line))) {
        flushPara();
        var ordered = /\d/.test(m[2]);
        items.push({ indent: m[1].replace(/\t/g, "    ").length, ordered: ordered, start: ordered ? parseInt(m[2], 10) : 1, text: m[3] });
        i++; continue;
      }
      if (items.length && /^\s+\S/.test(line)) {
        items[items.length - 1].text += " " + line.trim();
        i++; continue;
      }
      flushList();
      para.push(line.trim());
      i++;
    }
    flushPara(); flushList();
    return out;
  }

  /* ------------------------------------------------------------------ */
  /* DOM                                                                 */
  /* ------------------------------------------------------------------ */

  // Stroke icons in the header's style: 24-unit viewBox, 2px stroke, currentColor.
  function icon(paths, extra) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"' + (extra || "") + ">" + paths + "</svg>";
  }
  var I = {
    chat: icon('<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12Z"/>'),
    close: icon('<path d="M18 6 6 18M6 6l12 12"/>'),
    newChat: icon('<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/>'),
    send: icon('<path d="M12 19V5M5 12l7-7 7 7"/>'),
    stop: '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><rect x="7" y="7" width="10" height="10" rx="2" fill="currentColor"/></svg>',
    retry: icon('<path d="M3 12a9 9 0 0 1 15.5-6.2L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-15.5 6.2L3 16"/><path d="M3 21v-5h5"/>'),
    copy: icon('<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"/>'),
    check: icon('<path d="M20 6 9 17l-5-5"/>'),
    arrow: icon('<path d="M5 12h14M13 6l6 6-6 6"/>'),
    // The Proximi.io pin from the favicon, as the product mark.
    mark: '<svg viewBox="0 0 32 32" aria-hidden="true" focusable="false"><path fill="currentColor" d="M16 2.5c-5.247 0-9.5 4.253-9.5 9.5 0 6.9 8.34 16.44 8.695 16.842a1.07 1.07 0 0 0 1.61 0C17.16 28.44 25.5 18.9 25.5 12c0-5.247-4.253-9.5-9.5-9.5Zm0 14.1a4.6 4.6 0 1 1 0-9.2 4.6 4.6 0 0 1 0 9.2Z"/></svg>'
  };

  var COPY = SITE === "map" ? {
    subtitle: "Android map documentation",
    placeholder: "Ask about the Android map",
    examples: [
      "How do I show the route on the map?",
      "How do I add the map to a Compose screen?",
      "How do I make the map follow the user's position?"
    ]
  } : {
    subtitle: "Android SDK documentation",
    placeholder: "Ask about the Android SDK",
    examples: [
      "Which Bluetooth permissions does Android 12 and later need?",
      "How do I keep positioning running in the background?",
      "How do I receive geofence enter and exit events?"
    ]
  };

  function el(tag, attrs, html) {
    var n = document.createElement(tag);
    for (var k in attrs) if (Object.prototype.hasOwnProperty.call(attrs, k)) n.setAttribute(k, attrs[k]);
    if (html) n.innerHTML = html;
    return n;
  }

  var trigger = el("button", { type: "button", "class": "da-trigger", "aria-controls": "docs-assistant", "aria-expanded": "false", "aria-label": "Ask the docs", title: "Ask the docs" },
    I.chat + '<span class="da-trigger-label">Ask the docs</span>');

  var panel = el("aside", { id: "docs-assistant", "class": "da-panel", role: "dialog", "aria-modal": "false", "aria-labelledby": "da-title", "aria-describedby": "da-sub", hidden: "" },
    '<div class="da-head">' +
      '<span class="da-mark">' + I.mark + "</span>" +
      '<div class="da-titles"><h2 class="da-title" id="da-title">Ask the docs</h2><p class="da-sub" id="da-sub">' + esc(COPY.subtitle) + "</p></div>" +
      '<button type="button" class="da-icon-btn da-clear" aria-label="New chat" title="New chat">' + I.newChat + "</button>" +
      '<button type="button" class="da-icon-btn da-close" aria-label="Close" title="Close (Esc)">' + I.close + "</button>" +
    "</div>" +
    '<div class="da-log scroll" aria-live="polite" aria-busy="false" aria-relevant="additions text"></div>' +
    '<form class="da-form">' +
      '<div class="da-composer">' +
        '<label class="da-sr" for="da-input">Question</label>' +
        '<textarea id="da-input" class="da-input" rows="1" placeholder="' + esc(COPY.placeholder) + '" autocomplete="off" enterkeyhint="send"></textarea>' +
        '<button type="submit" class="da-send" aria-label="Send" title="Send (Enter)" disabled>' +
          '<span class="da-send-i da-i-send">' + I.send + '</span><span class="da-send-i da-i-stop">' + I.stop + "</span>" +
        "</button>" +
      "</div>" +
      '<p class="da-note">Answers are generated from these docs and may be incomplete. Each answer links to the pages it cites.</p>' +
    "</form>");

  var log = panel.querySelector(".da-log");
  var input = panel.querySelector(".da-input");
  var sendBtn = panel.querySelector(".da-send");
  var form = panel.querySelector(".da-form");

  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var closeTimer = 0;

  function isOpen() { return !panel.hasAttribute("hidden"); }

  function setOpen(open, opts) {
    opts = opts || {};
    clearTimeout(closeTimer);
    if (open) {
      panel.removeAttribute("hidden");
      // Next frame, so the transition runs from the closed state.
      (window.requestAnimationFrame || setTimeout)(function () { panel.classList.add("is-open"); });
      document.documentElement.classList.add("da-open");
      trigger.setAttribute("aria-expanded", "true");
      if (opts.focus !== false) input.focus({ preventScroll: true });
      scrollToEnd(true);
    } else {
      panel.classList.remove("is-open");
      closeTimer = setTimeout(function () { panel.setAttribute("hidden", ""); }, reduceMotion ? 0 : 220);
      document.documentElement.classList.remove("da-open");
      trigger.setAttribute("aria-expanded", "false");
      if (opts.focus !== false) trigger.focus();
    }
    if (opts.persist !== false) save(open);
  }

  function nearEnd() { return log.scrollHeight - log.scrollTop - log.clientHeight < 80; }
  function scrollToEnd(force) { if (force || nearEnd()) log.scrollTop = log.scrollHeight; }

  var SOURCES_SHOWN = 4;

  // One chip per page, numbered like the [n] markers; sections in the tooltip.
  function citesHtml(t) {
    var cites = t.cites;
    if (!cites || !cites.length) return "";
    var order = citeOrder(t.a), groups = {};
    cites.forEach(function (c) {
      var page = pageOf(c.url);
      var parts = String(c.label || "").split(" › ");
      var title = c.title || parts[0] || page;
      var heading = c.title ? c.heading : parts[1];
      var g = groups[page] || (groups[page] = { page: page, title: title, urls: [], sections: [] });
      g.urls.push(c.url);
      if (heading && g.sections.indexOf(heading) < 0) g.sections.push(heading);
      if (order.indexOf(page) < 0) order.push(page);
    });
    var list = order.filter(function (p) { return groups[p]; }).map(function (p) { return groups[p]; });
    var items = list.map(function (g, i) {
      var n = order.indexOf(g.page) + 1;
      var s = g.page.slice(0, 3);
      var tag = s !== SITE ? '<span class="da-site">' + (s === "sdk" ? "SDK" : "Map") + "</span>" : "";
      var tip = g.title + (g.sections.length ? ": " + g.sections.join("; ") : "");
      var r = resolveDocUrl(g.urls.length === 1 ? g.urls[0] : g.page);
      var inner = '<span class="da-chip-n">' + n + '</span><span class="da-chip-label">' + esc(g.title) + "</span>" + tag;
      var chip = r
        ? '<a class="da-chip" href="' + esc(r.href) + '"' + (r.external ? ' target="_blank" rel="noopener"' : "") + ' data-da-cite title="' + esc(tip) + '">' + inner + "</a>"
        : '<span class="da-chip da-chip-text" title="' + esc(tip) + '">' + inner + "</span>";
      return "<li" + (i >= SOURCES_SHOWN ? ' class="da-chip-extra" hidden' : "") + ">" + chip + "</li>";
    }).join("");
    var extra = list.length - SOURCES_SHOWN;
    var more = extra > 0
      ? '<li><button type="button" class="da-more" aria-expanded="false" data-more="' + extra + '">+' + extra + " more</button></li>"
      : "";
    return '<div class="da-cites"><p class="da-cites-label">Sources</p><ul class="da-chips">' + items + more + "</ul></div>";
  }

  // Caret inside the innermost trailing element, so it sits after the last word.
  function withCaret(html) {
    var caret = '<span class="da-caret" aria-hidden="true"></span>';
    return /(?:<\/[a-z0-9]+>)+$/.test(html) ? html.replace(/((?:<\/[a-z0-9]+>)+)$/, caret + "$1") : html + caret;
  }

  function botHtml(t, streaming) {
    var body;
    if (t.a) body = '<div class="da-a doc-prose">' + (streaming ? withCaret(md(t.a)) : md(t.a)) + "</div>";
    else if (streaming) body = '<div class="da-typing" role="status" aria-label="Generating an answer"><span></span><span></span><span></span></div>';
    else body = "";
    var status = "";
    if (t.status === "stopped" || t.status === "error") {
      status = '<div class="da-status' + (t.status === "error" ? " da-error" : "") + '">' +
        "<span>" + esc(t.status === "error" ? (t.note || "The answer could not be generated.") : "Stopped.") + "</span>" +
        '<button type="button" class="da-icon-btn da-retry" aria-label="Retry" title="Retry">' + I.retry + "</button></div>";
    }
    return '<div class="da-bot-head"><span class="da-avatar">' + I.mark + '</span><span class="da-bot-name">Docs</span></div>' +
      body + status + citesHtml(t);
  }

  function turnNode(t, i, animate) {
    var streaming = !!busy && i === turns.length - 1 && !t.status && !t.done;
    return el("div", { "class": "da-turn" + (animate ? " da-enter" : "") },
      '<div class="da-user"><div class="da-bubble">' + esc(t.q) + "</div></div>" +
      '<div class="da-bot">' + botHtml(t, streaming) + "</div>");
  }

  function emptyHtml() {
    return '<div class="da-empty">' +
      '<p class="da-empty-intro">Ask a question about the Android SDK or the Android map. Answers cite the pages they come from.</p>' +
      '<ul class="da-suggest">' + COPY.examples.map(function (q) {
        return '<li><button type="button" class="da-suggest-btn" data-q="' + esc(q) + '"><span>' + esc(q) + "</span>" + I.arrow + "</button></li>";
      }).join("") + "</ul></div>";
  }

  function renderAll() {
    log.innerHTML = "";
    if (!turns.length) { log.innerHTML = emptyHtml(); return; }
    turns.forEach(function (t, i) { log.appendChild(turnNode(t, i, false)); });
  }

  function appendTurn(t) {
    if (log.querySelector(".da-empty") || log.children.length !== turns.length - 1) { renderAll(); log.lastElementChild.classList.add("da-enter"); return; }
    log.appendChild(turnNode(t, turns.length - 1, true));
  }

  function renderLast() {
    var node = log.lastElementChild;
    var t = turns[turns.length - 1];
    if (!node || !t || !node.querySelector(".da-bot")) { renderAll(); return; }
    var stick = nearEnd();
    node.querySelector(".da-bot").innerHTML = botHtml(t, !!busy && !t.status && !t.done);
    if (stick) scrollToEnd(true);
  }

  var frame = 0;
  function scheduleRender() {
    if (frame) return;
    frame = (window.requestAnimationFrame || setTimeout)(function () { frame = 0; renderLast(); });
  }

  function syncSend() {
    sendBtn.disabled = !busy && !input.value.trim();
  }

  function setBusy(ctrl) {
    busy = ctrl;
    sendBtn.classList.toggle("is-busy", !!ctrl);
    sendBtn.setAttribute("aria-label", ctrl ? "Stop" : "Send");
    sendBtn.setAttribute("title", ctrl ? "Stop" : "Send (Enter)");
    log.setAttribute("aria-busy", ctrl ? "true" : "false");
    syncSend();
  }

  // Auto-grow between one and six lines.
  function autosize() {
    input.style.height = "auto";
    var cs = window.getComputedStyle(input);
    var line = parseFloat(cs.lineHeight) || 21;
    var pad = parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom);
    var max = line * 6 + pad;
    input.style.height = Math.min(input.scrollHeight, max) + "px";
    input.style.overflowY = input.scrollHeight > max ? "auto" : "hidden";
  }

  /* ------------------------------------------------------------------ */
  /* Request                                                             */
  /* ------------------------------------------------------------------ */

  function historyFor(prior) {
    var h = [];
    prior.filter(function (t) { return t.a; }).slice(-HISTORY_TURNS).forEach(function (t) {
      h.push({ role: "user", content: t.q.slice(0, 2000) }, { role: "assistant", content: t.a.slice(0, 6000) });
    });
    return h;
  }

  // Label per cited URL: "Page title › Heading" from the server's citation
  // fields; else the retrieved chunk's heading path; else the page path.
  function labelCites(citations, chunks) {
    var byUrl = {}, byPage = {};
    (chunks || []).forEach(function (c) {
      byUrl[c.url] = c.heading;
      var page = c.url.split("#")[0];
      if (!byPage[page]) byPage[page] = String(c.heading || "").split(" > ")[0];
    });
    var seen = {};
    return (citations || []).filter(function (c) { return c && c.url; }).map(function (c) {
      var url = c.ok === false ? c.url.split("#")[0] : c.url;   // a bad anchor still reaches the page
      if (seen[url]) return null;
      seen[url] = 1;
      var page = url.split("#")[0];
      var fallback = String(byUrl[url] || byPage[page] || page.replace(/^(sdk|map)\//, "").replace(/\.html$/, "")).split(" > ");
      return {
        url: url,
        title: c.title || fallback[0],
        heading: c.title ? (c.ok !== false && c.heading) || "" : fallback.slice(1).join(" › ")
      };
    }).filter(Boolean);
  }

  function ask(question) {
    var prior = turns.slice();
    var turn = { q: question, a: "", cites: [], status: "", done: false };
    turns.push(turn);
    if (turns.length > MAX_TURNS_KEPT) turns.shift();

    var ctrl = new AbortController();
    setBusy(ctrl);
    appendTurn(turn);
    scrollToEnd(true);

    fetch(CFG.endpoint.replace(/\/+$/, "") + "/ask", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question: question, history: historyFor(prior), site: SITE, page: CFG.page || "" }),
      signal: ctrl.signal
    }).then(function (r) {
      if (!r.ok || !r.body) throw { user: "The assistant returned an error (HTTP " + r.status + ")." };
      var reader = r.body.getReader(), dec = new TextDecoder(), buf = "";
      function pump() {
        return reader.read().then(function (res) {
          if (res.done) return;
          buf += dec.decode(res.value, { stream: true }).replace(/\r\n/g, "\n");
          var i;
          while ((i = buf.indexOf("\n\n")) >= 0) {
            var raw = buf.slice(0, i); buf = buf.slice(i + 2);
            var ev = (/^event: ?(.*)$/m.exec(raw) || [])[1];
            var dm = /^data: ?(.*)$/m.exec(raw);
            var data = null;
            try { data = dm ? JSON.parse(dm[1]) : null; } catch (e) { data = null; }
            if (ev === "token" && data) { turn.a += data.t || ""; scheduleRender(); }
            else if (ev === "done" && data) { turn.done = true; turn.cites = labelCites(data.citations, data.chunks); }
            else if (ev === "error") { turn.status = "error"; turn.note = "The answer could not be generated."; }
          }
          return pump();
        });
      }
      return pump();
    }).catch(function (err) {
      if (err && err.name === "AbortError") { turn.status = "stopped"; return; }
      turn.status = "error";
      turn.note = err && err.user ? err.user : "The assistant is not reachable.";
    }).then(function () {
      if (!turn.done && !turn.status) { turn.status = "error"; turn.note = "The answer was cut off."; }
      if (busy === ctrl) setBusy(null);
      if (turns.indexOf(turn) >= 0) { renderLast(); save(); }
    });
  }

  function submitQuestion(q) {
    q = String(q || "").trim();
    if (!q || busy) return;
    input.value = "";
    autosize();
    ask(q.slice(0, 4000));
  }

  /* ------------------------------------------------------------------ */
  /* Copy                                                                */
  /* ------------------------------------------------------------------ */

  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    return new Promise(function (resolve, reject) {
      var ta = el("textarea", { readonly: "", "aria-hidden": "true" });
      ta.value = text;
      ta.style.cssText = "position:fixed;top:-1000px;opacity:0";
      document.body.appendChild(ta);
      ta.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
      document.body.removeChild(ta);
      if (ok) resolve(); else reject(new Error("copy failed"));
    });
  }

  /* ------------------------------------------------------------------ */
  /* Wiring                                                              */
  /* ------------------------------------------------------------------ */

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    if (busy) { busy.abort(); input.focus(); return; }
    if (!input.value.trim()) { input.focus(); return; }
    submitQuestion(input.value);
  });

  input.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      if (!busy) submitQuestion(input.value);
    }
  });
  input.addEventListener("input", function () { autosize(); syncSend(); });

  panel.querySelector(".da-close").addEventListener("click", function () { setOpen(false); });
  panel.querySelector(".da-clear").addEventListener("click", function () {
    if (busy) busy.abort();
    setBusy(null);
    turns = [];
    renderAll();
    save();
    input.focus();
  });

  trigger.addEventListener("click", function () { setOpen(!isOpen()); });

  panel.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); setOpen(false); }
  });
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape" || !isOpen() || panel.contains(e.target)) return;
    var scrim = document.querySelector(".doc-search-scrim");
    if (scrim && !scrim.hidden && scrim.offsetParent !== null) return;   // search dialog closes first
    setOpen(false, { focus: false });
  });

  log.addEventListener("click", function (e) {
    var t = e.target;
    if (!t.closest) return;

    var suggest = t.closest(".da-suggest-btn");
    if (suggest) { submitQuestion(suggest.getAttribute("data-q")); input.focus(); return; }

    var retry = t.closest(".da-retry");
    if (retry) {
      var idx = Array.prototype.indexOf.call(log.children, retry.closest(".da-turn"));
      if (idx < 0 || busy) return;
      var q = turns[idx].q;
      turns.splice(idx, 1);
      renderAll();
      ask(q);
      input.focus();
      return;
    }

    var more = t.closest(".da-more");
    if (more) {
      var open = more.getAttribute("aria-expanded") !== "true";
      Array.prototype.forEach.call(more.closest(".da-chips").querySelectorAll(".da-chip-extra"), function (li) { li.hidden = !open; });
      more.setAttribute("aria-expanded", open ? "true" : "false");
      more.textContent = open ? "Show less" : "+" + more.getAttribute("data-more") + " more";
      return;
    }

    var copy = t.closest(".da-copy");
    if (copy) {
      var pre = copy.parentNode.querySelector("pre");
      copyText(pre ? pre.textContent : "").then(function () {
        copy.classList.add("is-copied");
        copy.innerHTML = I.check;
        copy.setAttribute("aria-label", "Copied");
        copy.setAttribute("title", "Copied");
        setTimeout(function () {
          copy.classList.remove("is-copied");
          copy.innerHTML = I.copy;
          copy.setAttribute("aria-label", "Copy code");
          copy.setAttribute("title", "Copy code");
        }, 1600);
      }, function () { copy.setAttribute("title", "Copy failed"); });
      return;
    }

    // On a narrow screen the panel covers the page: following a citation of
    // this site closes it, so the cited page is what the reader lands on.
    var a = t.closest("a[data-da-cite]");
    if (a && !a.target && window.innerWidth <= NARROW) save(false);
  });

  var header = document.querySelector(".docs-header");
  var anchor = header && header.querySelector(".docs-theme-toggle");
  if (anchor) header.insertBefore(trigger, anchor);
  else if (header) header.appendChild(trigger);
  else { trigger.classList.add("da-trigger-float"); document.body.appendChild(trigger); }
  document.body.appendChild(panel);

  var saved = load();
  if (saved) {
    turns = saved.turns.filter(function (t) { return t && typeof t.q === "string"; }).map(function (t) {
      return { q: t.q, a: typeof t.a === "string" ? t.a : "", cites: Array.isArray(t.cites) ? t.cites : [], status: t.status || "", note: t.note, done: !!t.done };
    });
  }
  // A request cut off by navigation reads as stopped, not as still running.
  turns.forEach(function (t) { if (!t.status && !t.done) t.status = "stopped"; });
  renderAll();
  if (saved && saved.open && window.innerWidth > NARROW) setOpen(true, { focus: false, persist: false });

  // Exposed for tests only.
  window.DOCS_ASSISTANT_MD = md;
})();
