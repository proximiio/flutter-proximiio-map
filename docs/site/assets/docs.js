/* Proximi.io iOS SDK v6 docs — client behaviour.
 *
 * Vanilla ES2017, no framework, no CDN, no fetch: every page ships its own
 * `search-index.js` (a global assignment) so the site works identically from
 * a web root, a subpath, or a bare `file://` open.
 *
 * Owns: theme cycling, ⌘K search, TOC scrollspy, code copy buttons, the
 * mobile sidebar drawer and per-section collapse persistence.
 */
(function () {
  "use strict";

  var LS = {
    theme: "proximiio-docs-theme",
    nav: "proximiio-docs-nav",
  };

  function lsGet(key) {
    try { return window.localStorage.getItem(key); } catch (e) { return null; }
  }
  function lsSet(key, value) {
    try { window.localStorage.setItem(key, value); } catch (e) { /* private mode */ }
  }
  function lsRemove(key) {
    try { window.localStorage.removeItem(key); } catch (e) { /* private mode */ }
  }

  var root = document.documentElement;
  var base = window.DOCS_BASE || "";

  /* ── Theme: light → dark → system ────────────────────────────────────── */
  var THEME_ORDER = ["light", "dark", "system"];

  function currentTheme() {
    var t = root.getAttribute("data-theme");
    return t === "light" || t === "dark" ? t : "system";
  }

  function applyTheme(theme) {
    if (theme === "light" || theme === "dark") {
      root.setAttribute("data-theme", theme);
      lsSet(LS.theme, theme);
    } else {
      root.removeAttribute("data-theme");
      lsRemove(LS.theme);
    }
    var btn = document.querySelector(".docs-theme-toggle");
    if (btn) {
      var label =
        theme === "light" ? "Theme: light (switch to dark)" :
        theme === "dark" ? "Theme: dark (switch to system)" :
        "Theme: follow system (switch to light)";
      btn.setAttribute("aria-label", label);
      btn.setAttribute("title", label);
    }
  }

  function initTheme() {
    applyTheme(currentTheme());
    var btn = document.querySelector(".docs-theme-toggle");
    if (!btn) return;
    btn.addEventListener("click", function () {
      var next = THEME_ORDER[(THEME_ORDER.indexOf(currentTheme()) + 1) % THEME_ORDER.length];
      applyTheme(next);
    });
  }

  /* ── Sidebar: drawer + collapsible sections ──────────────────────────── */
  function initSidebar() {
    var shell = document.querySelector(".docs-root");
    var toggle = document.querySelector(".docs-nav-toggle");
    var scrim = document.querySelector(".docs-nav-scrim");
    var sidebar = document.querySelector(".docs-sidebar");

    function setOpen(open) {
      if (!shell || !toggle) return;
      shell.classList.toggle("nav-open", open);
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
      if (open && sidebar) {
        var first = sidebar.querySelector("a, button");
        if (first) first.focus();
      }
    }

    if (toggle) toggle.addEventListener("click", function () { setOpen(!shell.classList.contains("nav-open")); });
    if (scrim) scrim.addEventListener("click", function () { setOpen(false); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && shell && shell.classList.contains("nav-open")) setOpen(false);
    });

    // Collapse state, keyed by section label. The section holding the current
    // page is always forced open by the build; a stored value overrides only
    // the sections that do not.
    var stored = {};
    try { stored = JSON.parse(lsGet(LS.nav) || "{}") || {}; } catch (e) { stored = {}; }

    var heads = document.querySelectorAll(".docs-side-head");
    Array.prototype.forEach.call(heads, function (head) {
      var key = head.getAttribute("data-section") || "";
      var hasCurrent = head.parentNode.querySelector('[aria-current="page"]') != null;
      if (!hasCurrent && Object.prototype.hasOwnProperty.call(stored, key)) {
        head.setAttribute("aria-expanded", stored[key] ? "true" : "false");
      }
      head.addEventListener("click", function () {
        var open = head.getAttribute("aria-expanded") !== "true";
        head.setAttribute("aria-expanded", open ? "true" : "false");
        stored[key] = open;
        lsSet(LS.nav, JSON.stringify(stored));
      });
    });

    // Keep the active nav row in view on load.
    var active = document.querySelector('.docs-side-item[aria-current="page"]');
    if (active && sidebar) {
      var top = active.offsetTop;
      var nav = sidebar.querySelector(".docs-side-nav");
      if (nav && top > nav.clientHeight - 80) nav.scrollTop = top - nav.clientHeight / 2;
    }
  }

  /* ── Copy buttons ────────────────────────────────────────────────────── */
  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text).catch(function () { return legacyCopy(text); });
    }
    return Promise.resolve(legacyCopy(text));
  }

  function legacyCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.top = "-1000px";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); } catch (e) { /* ignore */ }
    document.body.removeChild(ta);
  }

  function initCopyButtons() {
    var buttons = document.querySelectorAll(".doc-code-copy");
    Array.prototype.forEach.call(buttons, function (btn) {
      btn.addEventListener("click", function () {
        var block = btn.closest(".doc-code");
        var code = block && block.querySelector("pre code");
        if (!code) return;
        copyText(code.textContent);
        btn.classList.add("copied");
        btn.setAttribute("aria-label", "Copied");
        window.setTimeout(function () {
          btn.classList.remove("copied");
          btn.setAttribute("aria-label", "Copy code");
        }, 1400);
      });
    });
  }

  /* ── TOC scrollspy ───────────────────────────────────────────────────── */
  function initScrollspy() {
    var links = document.querySelectorAll(".doc-toc-link");
    if (!links.length || !("IntersectionObserver" in window)) return;
    var main = document.querySelector(".docs-main");
    var ids = [];
    var byId = {};
    Array.prototype.forEach.call(links, function (link) {
      var id = decodeURIComponent((link.getAttribute("href") || "").slice(1));
      if (!id) return;
      ids.push(id);
      byId[id] = link;
    });
    var targets = ids.map(function (id) { return document.getElementById(id); })
                     .filter(function (el) { return el != null; });
    if (!targets.length) return;

    var visible = Object.create(null);
    function setActive(id) {
      Array.prototype.forEach.call(links, function (l) { l.classList.remove("active"); });
      if (byId[id]) byId[id].classList.add("active");
    }

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) visible[e.target.id] = true;
        else delete visible[e.target.id];
      });
      for (var i = 0; i < ids.length; i++) {
        if (visible[ids[i]]) { setActive(ids[i]); return; }
      }
    }, { root: main || null, rootMargin: "0px 0px -70% 0px", threshold: [0, 1] });

    targets.forEach(function (el) { observer.observe(el); });

    var hash = decodeURIComponent(window.location.hash.slice(1));
    setActive(hash && ids.indexOf(hash) >= 0 ? hash : ids[0]);

    Array.prototype.forEach.call(links, function (link) {
      link.addEventListener("click", function () {
        var id = decodeURIComponent((link.getAttribute("href") || "").slice(1));
        if (id) setActive(id);
      });
    });
  }

  /* ── Search ──────────────────────────────────────────────────────────── */
  var search = {
    scrim: null,
    input: null,
    list: null,
    hits: [],
    index: -1,
    lastFocus: null,
  };

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function highlight(text, query) {
    var escaped = escapeHtml(text);
    if (!query) return escaped;
    var needle = escapeHtml(query);
    var i = escaped.toLowerCase().indexOf(needle.toLowerCase());
    if (i < 0) return escaped;
    return escaped.slice(0, i) + "<mark>" + escaped.slice(i, i + needle.length) + "</mark>" + escaped.slice(i + needle.length);
  }

  function snippetAround(plain, needle) {
    var i = plain.toLowerCase().indexOf(needle);
    if (i < 0) return "";
    var start = Math.max(0, i - 40);
    var end = Math.min(plain.length, i + needle.length + 70);
    return (start > 0 ? "…" : "") + plain.slice(start, end).trim() + (end < plain.length ? "…" : "");
  }

  // Weighted substring scorer over the build-time index. The corpus is a few
  // dozen pages, so exact ranking beats a fuzzy-search dependency.
  function runSearch(query, limit) {
    var docs = window.DOCS_INDEX || [];
    var q = String(query).trim().toLowerCase();
    if (!q) return [];
    var tokens = q.split(/\s+/).filter(function (t) { return t.length >= 2; });
    if (!tokens.length) return [];

    var hits = [];
    for (var d = 0; d < docs.length; d++) {
      var doc = docs[d];
      var title = (doc.title || "").toLowerCase();
      var section = (doc.section || "").toLowerCase();
      var desc = (doc.description || "").toLowerCase();
      var plain = (doc.text || "").toLowerCase();
      var score = 0;
      var bestHeading = null;

      if (title === q) score += 120;
      else if (title.indexOf(q) >= 0) score += 60;
      if (desc.indexOf(q) >= 0) score += 18;
      if (plain.indexOf(q) >= 0) score += 12;
      if (section.indexOf(q) >= 0) score += 8;

      var covered = 0;
      for (var t = 0; t < tokens.length; t++) {
        var tok = tokens[t];
        var hit = false;
        if (title.indexOf(tok) >= 0) { score += title.indexOf(tok) === 0 ? 14 : 10; hit = true; }
        if (section.indexOf(tok) >= 0) { score += 4; hit = true; }
        for (var h = 0; h < (doc.headings || []).length; h++) {
          if (doc.headings[h].text.toLowerCase().indexOf(tok) >= 0) {
            score += 6;
            if (!bestHeading) bestHeading = doc.headings[h];
            hit = true;
            break;
          }
        }
        if (desc.indexOf(tok) >= 0) { score += 3; hit = true; }
        if (plain.indexOf(tok) >= 0) { score += 2; hit = true; }
        if (hit) covered++;
      }
      if (covered < tokens.length || score <= 0) continue;

      hits.push({
        doc: doc,
        score: score,
        heading: bestHeading,
        snippet: snippetAround(doc.text || "", q) || snippetAround(doc.text || "", tokens[0]),
      });
    }

    hits.sort(function (a, b) { return b.score - a.score || a.doc.title.localeCompare(b.doc.title); });
    return hits.slice(0, limit || 8);
  }

  function buildSearchUI() {
    if (search.scrim) return;
    var scrim = document.createElement("div");
    scrim.className = "doc-search-scrim";
    scrim.hidden = true;
    scrim.innerHTML =
      '<div class="doc-search-panel" role="dialog" aria-modal="true" aria-label="Search documentation">' +
        '<div class="doc-search-input-row">' +
          '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.2-3.2"/></svg>' +
          '<input class="doc-search-input" type="search" autocomplete="off" spellcheck="false" placeholder="Search the docs…" aria-label="Search documentation" aria-controls="doc-search-results" />' +
        '</div>' +
        '<ul class="doc-search-results scroll" id="doc-search-results" role="listbox"></ul>' +
        '<div class="doc-search-foot">' +
          '<span><kbd class="kbd">↑</kbd><kbd class="kbd">↓</kbd> navigate</span>' +
          '<span><kbd class="kbd">↵</kbd> open</span>' +
          '<span><kbd class="kbd">esc</kbd> close</span>' +
        '</div>' +
      '</div>';
    document.body.appendChild(scrim);

    search.scrim = scrim;
    search.input = scrim.querySelector(".doc-search-input");
    search.list = scrim.querySelector(".doc-search-results");

    scrim.addEventListener("mousedown", function (e) {
      if (e.target === scrim) closeSearch();
    });
    search.input.addEventListener("input", function () { render(search.input.value); });
    search.input.addEventListener("keydown", onSearchKey);
    search.list.addEventListener("click", function (e) {
      var row = e.target.closest("[data-href]");
      if (row) { window.location.href = row.getAttribute("data-href"); }
    });
  }

  function hrefFor(hit) {
    var slug = hit.doc.slug;
    var path = base + (slug === "" ? "index.html" : slug + ".html");
    if (hit.heading && hit.heading.id) path += "#" + hit.heading.id;
    return path;
  }

  function render(query) {
    search.hits = runSearch(query, 8);
    search.index = search.hits.length ? 0 : -1;
    if (!query.trim()) {
      search.list.innerHTML = '<li class="doc-search-empty">Type to search the documentation.</li>';
      return;
    }
    if (!search.hits.length) {
      search.list.innerHTML = '<li class="doc-search-empty">No results for “' + escapeHtml(query) + '”.</li>';
      return;
    }
    var q = query.trim().toLowerCase();
    search.list.innerHTML = search.hits.map(function (hit, i) {
      var heading = hit.heading ? ' <span class="doc-search-row-heading">› ' + escapeHtml(hit.heading.text) + "</span>" : "";
      var snippet = hit.snippet ? '<span class="doc-search-row-snippet">' + highlight(hit.snippet, q) + "</span>" : "";
      var section = hit.doc.section ? '<span class="doc-search-row-section">' + escapeHtml(hit.doc.section) + "</span>" : "";
      return '<li class="doc-search-row' + (i === 0 ? " active" : "") + '" role="option" aria-selected="' + (i === 0) + '" data-href="' + escapeHtml(hrefFor(hit)) + '">' +
        '<span class="doc-search-row-main">' +
          '<span class="doc-search-row-title">' + highlight(hit.doc.title, q) + heading + "</span>" +
          snippet +
        "</span>" + section +
      "</li>";
    }).join("");
  }

  function moveSelection(delta) {
    if (!search.hits.length) return;
    search.index = (search.index + delta + search.hits.length) % search.hits.length;
    var rows = search.list.querySelectorAll(".doc-search-row");
    Array.prototype.forEach.call(rows, function (row, i) {
      var on = i === search.index;
      row.classList.toggle("active", on);
      row.setAttribute("aria-selected", on ? "true" : "false");
      if (on && row.scrollIntoView) row.scrollIntoView({ block: "nearest" });
    });
  }

  function onSearchKey(e) {
    if (e.key === "ArrowDown") { e.preventDefault(); moveSelection(1); }
    else if (e.key === "ArrowUp") { e.preventDefault(); moveSelection(-1); }
    else if (e.key === "Enter") {
      var hit = search.hits[search.index];
      if (hit) { e.preventDefault(); window.location.href = hrefFor(hit); }
    } else if (e.key === "Escape") { e.preventDefault(); closeSearch(); }
  }

  function openSearch() {
    buildSearchUI();
    search.lastFocus = document.activeElement;
    search.scrim.hidden = false;
    search.input.value = "";
    render("");
    search.input.focus();
  }

  function closeSearch() {
    if (!search.scrim || search.scrim.hidden) return;
    search.scrim.hidden = true;
    if (search.lastFocus && search.lastFocus.focus) search.lastFocus.focus();
  }

  function isTypingTarget(el) {
    if (!el) return false;
    var tag = el.tagName;
    return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable;
  }

  function initSearch() {
    var trigger = document.querySelector(".docs-search-trigger");
    if (trigger) trigger.addEventListener("click", openSearch);
    document.addEventListener("keydown", function (e) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        openSearch();
        return;
      }
      if (e.key === "/" && !e.metaKey && !e.ctrlKey && !e.altKey && !isTypingTarget(document.activeElement)) {
        e.preventDefault();
        openSearch();
      }
    });
  }

  /* ── Boot ────────────────────────────────────────────────────────────── */
  function boot() {
    initTheme();
    initSidebar();
    initCopyButtons();
    initScrollspy();
    initSearch();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
