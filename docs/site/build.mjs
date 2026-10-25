#!/usr/bin/env node
/* Proximi.io Android SDK v6 — documentation site builder.
 *
 * Zero dependencies, Node >= 18, no network. Reads `nav.mjs` plus the body
 * fragments under `content/` and writes a complete static site to `dist/`.
 *
 *   node docs/site/build.mjs
 *   node docs/site/build.mjs --assistant http://127.0.0.1:8787   (docs assistant panel on)
 *
 * Design notes
 * ------------
 * · Every URL emitted is RELATIVE (`../` depth computed per page) so `dist/`
 *   works unchanged from a web root, from a subpath, and from `file://`.
 * · The search index is a JS file that assigns `window.DOCS_INDEX` rather than
 *   JSON fetched at runtime — `fetch()` of a sibling file is blocked under
 *   `file://`, a `<script src>` is not.
 * · Syntax highlighting happens here, at build time. The tokenizers below
 *   consume the *unescaped* source (fragments arrive HTML-escaped) and
 *   re-escape each token as it is emitted, so nothing is ever double-escaped
 *   and no half-formed entity can be split by a keyword match.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CONTENT_DIR = path.join(HERE, "content");
const ASSETS_DIR = path.join(HERE, "assets");
const DIST_DIR = path.join(HERE, "dist");

const { NAV, SITE } = await import(pathToFileURL(path.join(HERE, "nav.mjs")).href);

const warnings = [];

// The only argument is --assistant. An unrecognised argument is loud, so a typo
// does not silently build without the panel.
const args = process.argv.slice(2);
let assistantArg = null;
const unknown = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--assistant" && args[i + 1] && !args[i + 1].startsWith("--")) assistantArg = args[++i];
  else if (a.startsWith("--assistant=")) assistantArg = a.slice("--assistant=".length);
  else unknown.push(a);
}
if (unknown.length) {
  console.error(`build.mjs: unknown argument${unknown.length === 1 ? "" : "s"} ${unknown.join(", ")}`);
  console.error("usage: node docs/site/build.mjs [--assistant <url>]");
  process.exit(2);
}

/* Docs assistant panel — OFF unless an endpoint is given, by `--assistant <url>`
 * or DOCS_ASSISTANT_URL (the flag wins). Ported from the iOS builder. Off, the
 * output is byte-identical to a build without this feature: no tag is emitted
 * and assets/assistant.* is not copied to dist/. On, every page links
 * assets/assistant.css + .js (the same two files in docs/site and
 * docs/map-site) and gets a config object.
 *
 * The assistant server answers Android questions on its /android route, so an
 * endpoint given without a path gets "/android" appended
 * (http://127.0.0.1:8787 -> http://127.0.0.1:8787/android). An endpoint with a
 * path is used as given.
 *
 * Citations of the other docs site need that site's dist/ root as an absolute
 * URL: DOCS_ASSISTANT_SDK_BASE / DOCS_ASSISTANT_MAP_BASE. For a local endpoint
 * (127.0.0.1 / localhost) they default to the paths the assistant server
 * serves both Android sites at. Citations of this site always stay relative. */
const ASSISTANT_SITE = "sdk";
const ASSISTANT_URL = (assistantArg ?? process.env.DOCS_ASSISTANT_URL ?? "").trim().replace(/\/+$/, "");
const ASSISTANT_FILES = ["assistant.js", "assistant.css"];
let ASSISTANT = null;
if (ASSISTANT_URL) {
  const m = /^(https?:\/\/[^\s/]+)(\/\S*)?$/i.exec(ASSISTANT_URL);
  if (!m) {
    console.error(`build.mjs: assistant endpoint must be an http(s) URL, got "${ASSISTANT_URL}"`);
    process.exit(2);
  }
  const origin = m[1];
  const local = /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/i.test(origin);
  const baseFor = (envName, siteDir) => {
    const v = (process.env[envName] || "").trim();
    if (v) return v.endsWith("/") ? v : `${v}/`;
    return local ? `${origin}/proximiio-android-sdk-v6/docs/${siteDir}/dist/` : null;
  };
  ASSISTANT = {
    endpoint: m[2] ? ASSISTANT_URL : `${ASSISTANT_URL}/android`,
    site: ASSISTANT_SITE,
    bases: {
      sdk: baseFor("DOCS_ASSISTANT_SDK_BASE", "site"),
      map: baseFor("DOCS_ASSISTANT_MAP_BASE", "map-site"),
    },
  };
}

/** `<link>` for the head and `<script>`s for the end of body; "" when off. */
function assistantTags(slug, base) {
  if (!ASSISTANT) return { head: "", body: "" };
  const cfg = JSON.stringify({ ...ASSISTANT, page: slug }).replace(/</g, "\\u003c");
  return {
    head: `\n<link rel="stylesheet" href="${base}assets/assistant.css">`,
    body: `\n<script>window.DOCS_ASSISTANT=${cfg};</script>\n<script src="${base}assets/assistant.js"></script>`,
  };
}

/* ===================================================================== */
/* Small HTML helpers                                                     */
/* ===================================================================== */

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

const ENTITIES = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
  hellip: "…", mdash: "—", ndash: "–", rsquo: "’",
  lsquo: "‘", ldquo: "“", rdquo: "”", times: "×",
  rarr: "→", larr: "←", middot: "·", deg: "°",
};

function decodeEntities(s) {
  return String(s).replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);/g, (m, body) => {
    if (body[0] === "#") {
      const code = body[1] === "x" || body[1] === "X"
        ? parseInt(body.slice(2), 16)
        : parseInt(body.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : m;
    }
    return Object.prototype.hasOwnProperty.call(ENTITIES, body) ? ENTITIES[body] : m;
  });
}

function stripTags(html) {
  return decodeEntities(
    String(html)
      .replace(/<!--[\s\S]*?-->/g, " ")
      .replace(/<(script|style)\b[\s\S]*?<\/\1>/gi, " ")
      .replace(/<[^>]+>/g, " ")
  ).replace(/\s+/g, " ").trim();
}

function slugify(text) {
  return String(text)
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "section";
}

/* ===================================================================== */
/* Syntax highlighting                                                    */
/* ===================================================================== */

const SWIFT_KEYWORDS = new Set(`
actor any as associatedtype async await break case catch class continue convenience default
defer deinit didSet do else enum extension fallthrough fileprivate final for func get guard if
import in indirect infix init inout internal is isolated lazy let mutating nonisolated
nonmutating open operator override postfix precedencegroup prefix private protocol public repeat
required rethrows return set some static struct subscript super switch throw throws try
typealias unowned var weak where while willSet
`.trim().split(/\s+/));

const SWIFT_LITERALS = new Set(["true", "false", "nil", "self", "Self", "super"]);

const KOTLIN_KEYWORDS = new Set(`
abstract actual annotation as break by catch class companion const constructor continue
crossinline data do else enum expect external final finally for fun if import in infix init
inline inner interface internal is lateinit noinline object open operator out override private
protected public reified return sealed suspend tailrec this throw try typealias val var vararg
when where while
`.trim().split(/\s+/));
const KOTLIN_LITERALS = new Set(["true", "false", "null", "this", "super"]);

const JAVA_KEYWORDS = new Set(`
abstract assert boolean break byte case catch char class const continue default do double else
enum extends final finally float for goto if implements import instanceof int interface long
native new package private protected public return short static strictfp super switch synchronized
this throw throws transient try void volatile while var record sealed permits yield
`.trim().split(/\s+/));
const JAVA_LITERALS = new Set(["true", "false", "null", "this", "super"]);

// Dart: added for the Flutter site (the rest of this file is the Android copy).
const DART_KEYWORDS = new Set(`
abstract as assert async await base break case catch class const continue covariant default deferred
do dynamic else enum export extends extension external factory final finally for get hide if implements
import in interface is late library mixin new on operator part required rethrow return sealed set show
static super switch sync throw try type typedef var void when while with yield
`.trim().split(/\s+/));
const DART_LITERALS = new Set(["true", "false", "null", "this", "super"]);
const YAML_KEY_RE = /^[ \t]*-?[ \t]*[A-Za-z0-9_.\-"']+(?=:(\s|$))/;

const PROPERTIES_KEY_RE = /^[A-Za-z_][\w.\-]*(?=\s*[=:])/;
const TOML_KEY_RE = /^[A-Za-z_][\w.\-]*(?=\s*=)/;

const SH_KEYWORDS = new Set(`
if then elif else fi for while until do done case esac in function select time coproc
return break continue local export readonly declare typeset set unset shift eval exec trap source
`.trim().split(/\s+/));
const SH_BUILTINS = new Set(`
echo printf cd pwd read test true false exit sleep mkdir rm mv cp ls cat sed awk grep find
xargs curl git gradle gradlew adb sdkmanager keytool apksigner java javac npm node brew open
`.trim().split(/\s+/));

const RUBY_KEYWORDS = new Set(`
alias and begin break case class def defined? do else elsif end ensure false for if in module
next nil not or redo rescue retry return self super then true undef unless until when while yield
require require_relative attr_accessor attr_reader attr_writer include extend lambda proc raise
`.trim().split(/\s+/));
const RUBY_LITERALS = new Set(["true", "false", "nil", "self"]);

const IDENT_RE = /^[A-Za-z_$][A-Za-z0-9_$]*/;
const NUMBER_RE = /^(0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(\.\d[\d_]*)?([eE][+-]?\d+)?)/;

/** Consume a line comment starting with `prefix`. */
function lineComment(prefix) {
  return (s, i) => {
    if (!s.startsWith(prefix, i)) return null;
    const nl = s.indexOf("\n", i);
    return { cls: "hljs-comment", len: (nl < 0 ? s.length : nl) - i };
  };
}

/** Consume a `/* … *\/` comment; Kotlin allows nesting, Java does not. */
function blockComment(open, close, nested) {
  return (s, i) => {
    if (!s.startsWith(open, i)) return null;
    let j = i + open.length;
    let depth = 1;
    while (j < s.length) {
      if (nested && s.startsWith(open, j)) { depth++; j += open.length; continue; }
      if (s.startsWith(close, j)) { depth--; j += close.length; if (depth === 0) break; continue; }
      j++;
    }
    return { cls: "hljs-comment", len: j - i };
  };
}

/** Consume a delimited string. `esc` enables backslash escapes. */
function quoted(delim, esc) {
  return (s, i) => {
    if (!s.startsWith(delim, i)) return null;
    let j = i + delim.length;
    while (j < s.length) {
      if (esc && s[j] === "\\") { j += 2; continue; }
      if (s.startsWith(delim, j)) { j += delim.length; break; }
      if (delim.length === 1 && s[j] === "\n") break; // unterminated single-line string
      j++;
    }
    return { cls: "hljs-string", len: j - i };
  };
}

/** Swift raw string: #"…"# / ##"…"##. */
function swiftRawString(s, i) {
  const m = /^(#+)"/.exec(s.slice(i));
  if (!m) return null;
  const hashes = m[1];
  const closer = '"' + hashes;
  const end = s.indexOf(closer, i + m[0].length);
  return { cls: "hljs-string", len: (end < 0 ? s.length : end + closer.length) - i };
}

/**
 * Generic left-to-right scanner. Matchers are tried in order at every
 * position; comments and strings come first so a keyword inside a string or a
 * comment is never re-tokenized.
 */
function scan(code, matchers, identify) {
  const tokens = [];
  let plain = "";
  let i = 0;
  let prevSignificant = "";

  const flush = () => { if (plain) { tokens.push([null, plain]); plain = ""; } };

  while (i < code.length) {
    let hit = null;
    for (const m of matchers) {
      hit = m(code, i);
      if (hit) break;
    }
    if (hit && hit.len > 0) {
      flush();
      tokens.push([hit.cls, code.slice(i, i + hit.len)]);
      i += hit.len;
      prevSignificant = "";
      continue;
    }
    const idm = IDENT_RE.exec(code.slice(i));
    if (idm && identify) {
      const word = idm[0];
      const rest = code.slice(i + word.length);
      const cls = identify(word, rest, prevSignificant);
      flush();
      tokens.push([cls, word]);
      i += word.length;
      prevSignificant = word;
      continue;
    }
    const ch = code[i];
    if (!/\s/.test(ch)) prevSignificant = ch;
    plain += ch;
    i++;
  }
  flush();
  return tokens;
}

function renderTokens(tokens) {
  let out = "";
  for (const [cls, text] of tokens) {
    out += cls ? `<span class="${cls}">${escapeHtml(text)}</span>` : escapeHtml(text);
  }
  return out;
}

/** `label:` in a call / literal position reads as a Swift argument label. */
function isLabelPosition(rest, prev) {
  return /^\s*:/.test(rest) && !/^\s*::/.test(rest) && (prev === "(" || prev === "," || prev === "[");
}

const LANGUAGES = {
  swift: {
    matchers: [
      blockComment("/*", "*/", true),
      lineComment("//"),
      quoted('"""', true),
      swiftRawString,
      quoted('"', true),
      (s, i) => (/^@[A-Za-z_]/.test(s.slice(i)) ? { cls: "hljs-keyword", len: /^@[A-Za-z_][A-Za-z0-9_]*/.exec(s.slice(i))[0].length } : null),
      (s, i) => (/^#[A-Za-z_]/.test(s.slice(i)) ? { cls: "hljs-meta", len: /^#[A-Za-z_][A-Za-z0-9_]*/.exec(s.slice(i))[0].length } : null),
      (s, i) => { const m = NUMBER_RE.exec(s.slice(i)); return m ? { cls: "hljs-number", len: m[0].length } : null; },
    ],
    identify(word, rest, prev) {
      if (SWIFT_LITERALS.has(word)) return "hljs-literal";
      if (SWIFT_KEYWORDS.has(word)) return "hljs-keyword";
      if (isLabelPosition(rest, prev)) return "hljs-attr";
      if (/^[A-Z]/.test(word)) return "hljs-type";
      if (/^\s*\(/.test(rest)) return "hljs-title";
      return null;
    },
  },

  kotlin: {
    matchers: [
      blockComment("/*", "*/", true),
      lineComment("//"),
      quoted('"""', true),
      quoted('"', true),
      (s, i) => (/^@[A-Za-z_]/.test(s.slice(i)) ? { cls: "hljs-keyword", len: /^@[A-Za-z_][A-Za-z0-9_]*/.exec(s.slice(i))[0].length } : null),
      (s, i) => { const m = NUMBER_RE.exec(s.slice(i)); return m ? { cls: "hljs-number", len: m[0].length } : null; },
    ],
    identify(word, rest, prev) {
      if (KOTLIN_LITERALS.has(word)) return "hljs-literal";
      if (KOTLIN_KEYWORDS.has(word)) return "hljs-keyword";
      if (isLabelPosition(rest, prev)) return "hljs-attr";
      if (/^[A-Z]/.test(word)) return "hljs-type";
      if (/^\s*\(/.test(rest)) return "hljs-title";
      return null;
    },
  },

  java: {
    matchers: [
      blockComment("/*", "*/", false),
      lineComment("//"),
      quoted('"""', true),
      quoted('"', true),
      quoted("'", true),
      (s, i) => (/^@[A-Za-z_]/.test(s.slice(i)) ? { cls: "hljs-keyword", len: /^@[A-Za-z_][A-Za-z0-9_]*/.exec(s.slice(i))[0].length } : null),
      (s, i) => { const m = NUMBER_RE.exec(s.slice(i)); return m ? { cls: "hljs-number", len: m[0].length } : null; },
    ],
    identify(word, rest, prev) {
      if (JAVA_LITERALS.has(word)) return "hljs-literal";
      if (JAVA_KEYWORDS.has(word)) return "hljs-keyword";
      if (/^[A-Z]/.test(word)) return "hljs-type";
      if (/^\s*\(/.test(rest)) return "hljs-title";
      return null;
    },
  },

  dart: {
    matchers: [
      blockComment("/*", "*/", true),
      lineComment("//"),
      quoted("'''", true),
      quoted('"""', true),
      quoted('"', true),
      quoted("'", true),
      (s, i) => (/^@[A-Za-z_]/.test(s.slice(i)) ? { cls: "hljs-meta", len: /^@[A-Za-z_][A-Za-z0-9_]*/.exec(s.slice(i))[0].length } : null),
      (s, i) => { const m = NUMBER_RE.exec(s.slice(i)); return m ? { cls: "hljs-number", len: m[0].length } : null; },
    ],
    identify(word, rest, prev) {
      if (DART_LITERALS.has(word)) return "hljs-literal";
      if (DART_KEYWORDS.has(word)) return "hljs-keyword";
      if (isLabelPosition(rest, prev)) return "hljs-attr";
      if (/^[A-Z]/.test(word)) return "hljs-type";
      if (/^\s*\(/.test(rest)) return "hljs-title";
      return null;
    },
  },

  yaml: {
    matchers: [
      lineComment("#"),
      (s, i) => {
        if (i !== 0 && s[i - 1] !== "\n") return null;
        const m = YAML_KEY_RE.exec(s.slice(i));
        return m ? { cls: "hljs-attr", len: m[0].length } : null;
      },
      quoted('"', true),
      quoted("'", false),
      (s, i) => { const m = NUMBER_RE.exec(s.slice(i)); return m ? { cls: "hljs-number", len: m[0].length } : null; },
    ],
    identify(word) {
      if (word === "true" || word === "false" || word === "null") return "hljs-literal";
      return null;
    },
  },

  properties: {
    matchers: [
      lineComment("#"),
      (s, i) => {
        if (i !== 0 && s[i - 1] !== "\n") return null;
        const m = PROPERTIES_KEY_RE.exec(s.slice(i));
        return m ? { cls: "hljs-attr", len: m[0].length } : null;
      },
      (s, i) => { const m = NUMBER_RE.exec(s.slice(i)); return m ? { cls: "hljs-number", len: m[0].length } : null; },
    ],
    identify() { return null; },
  },

  toml: {
    matchers: [
      lineComment("#"),
      (s, i) => {
        if (i !== 0 && s[i - 1] !== "\n") return null;
        const m = /^\[[^\]\n]*\]/.exec(s.slice(i));
        return m ? { cls: "hljs-section", len: m[0].length } : null;
      },
      (s, i) => {
        if (i !== 0 && s[i - 1] !== "\n") return null;
        const m = TOML_KEY_RE.exec(s.slice(i));
        return m ? { cls: "hljs-attr", len: m[0].length } : null;
      },
      quoted('"', true),
      quoted("'", false),
      (s, i) => { const m = NUMBER_RE.exec(s.slice(i)); return m ? { cls: "hljs-number", len: m[0].length } : null; },
    ],
    identify(word) {
      if (word === "true" || word === "false") return "hljs-literal";
      return null;
    },
  },

  sh: {
    matchers: [
      lineComment("#"),
      quoted('"', true),
      quoted("'", false),
      (s, i) => {
        const m = /^\$(\{[^}]*\}|[A-Za-z_][A-Za-z0-9_]*|[0-9@*#?])/.exec(s.slice(i));
        return m ? { cls: "hljs-variable", len: m[0].length } : null;
      },
      (s, i) => { const m = NUMBER_RE.exec(s.slice(i)); return m ? { cls: "hljs-number", len: m[0].length } : null; },
    ],
    identify(word) {
      if (SH_KEYWORDS.has(word)) return "hljs-keyword";
      if (SH_BUILTINS.has(word)) return "hljs-built_in";
      return null;
    },
  },

  ruby: {
    matchers: [
      lineComment("#"),
      quoted('"', true),
      quoted("'", false),
      (s, i) => {
        const m = /^:[A-Za-z_][A-Za-z0-9_]*[?!]?/.exec(s.slice(i));
        return m ? { cls: "hljs-symbol", len: m[0].length } : null;
      },
      (s, i) => {
        const m = /^@@?[A-Za-z_][A-Za-z0-9_]*/.exec(s.slice(i));
        return m ? { cls: "hljs-variable", len: m[0].length } : null;
      },
      (s, i) => { const m = NUMBER_RE.exec(s.slice(i)); return m ? { cls: "hljs-number", len: m[0].length } : null; },
    ],
    identify(word, rest) {
      if (RUBY_LITERALS.has(word)) return "hljs-literal";
      if (RUBY_KEYWORDS.has(word)) return "hljs-keyword";
      if (/^[A-Z]/.test(word)) return "hljs-type";
      if (/^\s*\(/.test(rest)) return "hljs-title";
      return null;
    },
  },

  json: {
    matchers: [
      (s, i) => {
        if (s[i] !== '"') return null;
        const r = quoted('"', true)(s, i);
        if (!r) return null;
        const after = s.slice(i + r.len);
        return { cls: /^\s*:/.test(after) ? "hljs-attr" : "hljs-string", len: r.len };
      },
      (s, i) => { const m = /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/.exec(s.slice(i)); return m && m[0] ? { cls: "hljs-number", len: m[0].length } : null; },
    ],
    identify(word) {
      return word === "true" || word === "false" || word === "null" ? "hljs-literal" : null;
    },
  },
};

/** XML / plist needs tag-vs-text state, so it gets its own scanner. */
function highlightXml(code) {
  const tokens = [];
  let i = 0;
  let plain = "";
  let inTag = false;
  const flush = () => { if (plain) { tokens.push([null, plain]); plain = ""; } };

  while (i < code.length) {
    if (!inTag) {
      if (code.startsWith("<!--", i)) {
        const end = code.indexOf("-->", i);
        const len = (end < 0 ? code.length : end + 3) - i;
        flush(); tokens.push(["hljs-comment", code.substr(i, len)]); i += len; continue;
      }
      if (code.startsWith("<?", i) || code.startsWith("<!", i)) {
        const end = code.indexOf(">", i);
        const len = (end < 0 ? code.length : end + 1) - i;
        flush(); tokens.push(["hljs-meta", code.substr(i, len)]); i += len; continue;
      }
      const open = /^<\/?([A-Za-z_][\w:.-]*)/.exec(code.slice(i));
      if (open) {
        flush();
        const lead = open[0].length - open[1].length;
        tokens.push([null, code.substr(i, lead)]);
        tokens.push(["hljs-name", open[1]]);
        i += open[0].length;
        inTag = true;
        continue;
      }
      plain += code[i]; i++;
      continue;
    }
    // inside a tag
    if (code[i] === ">") { flush(); tokens.push([null, ">"]); i++; inTag = false; continue; }
    if (code.startsWith("/>", i)) { flush(); tokens.push([null, "/>"]); i += 2; inTag = false; continue; }
    if (code[i] === '"' || code[i] === "'") {
      const r = quoted(code[i], false)(code, i);
      flush(); tokens.push(["hljs-string", code.substr(i, r.len)]); i += r.len; continue;
    }
    const attr = /^[A-Za-z_][\w:.-]*(?=\s*=)/.exec(code.slice(i));
    if (attr) { flush(); tokens.push(["hljs-attr", attr[0]]); i += attr[0].length; continue; }
    plain += code[i]; i++;
  }
  flush();
  return tokens;
}

const LANG_ALIAS = {
  swift: "swift",
  dart: "dart",
  yaml: "yaml", yml: "yaml",
  kotlin: "kotlin", kt: "kotlin", kts: "kotlin", gradle: "kotlin", groovy: "kotlin",
  java: "java",
  properties: "properties", ini: "properties", proguard: "properties",
  toml: "toml",
  sh: "sh", bash: "sh", shell: "sh", zsh: "sh", console: "sh",
  ruby: "ruby", rb: "ruby",
  json: "json", jsonc: "json",
  xml: "xml", plist: "xml", html: "xml", svg: "xml",
};

/** Highlight already-escaped fence content; returns escaped HTML. */
function highlight(escapedCode, lang) {
  const raw = decodeEntities(escapedCode);
  const key = LANG_ALIAS[String(lang || "").toLowerCase()];
  if (!key) return escapeHtml(raw);
  if (key === "xml") return renderTokens(highlightXml(raw));
  const spec = LANGUAGES[key];
  return renderTokens(scan(raw, spec.matchers, spec.identify));
}

/* ===================================================================== */
/* Fragment processing                                                    */
/* ===================================================================== */

const COPY_ICON =
  '<svg class="i-copy" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
  '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>' +
  '<svg class="i-check" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m20 6-11 11-5-5"/></svg>';

const PLACEHOLDER = " CODE";

function extractCodeBlocks(html) {
  const blocks = [];
  const replaced = html.replace(/<pre\b[^>]*>[\s\S]*?<\/pre>/gi, (match) => {
    blocks.push(match);
    return `${PLACEHOLDER}${blocks.length - 1} `;
  });
  return { html: replaced, blocks };
}

function renderCodeBlock(preHtml, slug) {
  const codeMatch = /<code\b([^>]*)>([\s\S]*?)<\/code>/i.exec(preHtml);
  let lang = "";
  let body;
  if (codeMatch) {
    const attrs = codeMatch[1] || "";
    const cls = /class\s*=\s*"([^"]*)"/i.exec(attrs) || /class\s*=\s*'([^']*)'/i.exec(attrs);
    if (cls) {
      const found = cls[1].split(/\s+/).find((c) => c.startsWith("language-") || c.startsWith("lang-"));
      if (found) lang = found.replace(/^(language-|lang-)/, "");
    }
    body = codeMatch[2];
  } else {
    body = /<pre\b[^>]*>([\s\S]*?)<\/pre>/i.exec(preHtml)?.[1] ?? "";
  }
  if (lang && !LANG_ALIAS[lang.toLowerCase()]) {
    warnings.push(`${slug || "index"}: unknown code fence language "${lang}" — rendered unhighlighted`);
  }
  // Trim a single leading newline (authors often start the fence on its own line).
  const trimmed = body.replace(/^\n/, "").replace(/\s+$/, "");
  const highlighted = highlight(trimmed, lang);
  const langClass = lang ? ` language-${escapeHtml(lang)}` : "";
  return (
    `<div class="doc-code"${lang ? ` data-lang="${escapeHtml(lang)}"` : ""}>` +
    `<button type="button" class="doc-code-copy" aria-label="Copy code" title="Copy code">${COPY_ICON}</button>` +
    `<pre><code class="hljs${langClass}">${highlighted}</code></pre>` +
    "</div>"
  );
}

function processHeadings(html) {
  const headings = [];
  const used = new Set();

  const out = html.replace(/<(h[234])\b([^>]*)>([\s\S]*?)<\/\1>/gi, (match, tag, attrs, inner) => {
    const depth = Number(tag[1]);
    const text = stripTags(inner);
    const idAttr = /\bid\s*=\s*"([^"]*)"/i.exec(attrs) || /\bid\s*=\s*'([^']*)'/i.exec(attrs);
    let id = idAttr ? idAttr[1] : slugify(text);
    if (used.has(id)) {
      let n = 2;
      while (used.has(`${id}-${n}`)) n++;
      id = `${id}-${n}`;
    }
    used.add(id);
    const cleanedAttrs = attrs.replace(/\s*\bid\s*=\s*("[^"]*"|'[^']*')/i, "");
    if (depth <= 3) headings.push({ id, text, depth });
    return `<${tag} id="${escapeHtml(id)}"${cleanedAttrs}>` +
      `<a class="doc-anchor" href="#${escapeHtml(id)}">${inner}</a></${tag}>`;
  });

  return { html: out, headings };
}

function wrapTables(html) {
  return html.replace(/<table\b[\s\S]*?<\/table>/gi, (match, offset, whole) => {
    const before = whole.slice(Math.max(0, offset - 120), offset);
    if (/doc-table-wrap[^>]*>\s*$/.test(before)) return match; // author wrapped it already
    return `<div class="doc-table-wrap">${match}</div>`;
  });
}

function parseFragment(raw, slug) {
  const metaMatch = /^\s*<!--([\s\S]*?)-->/.exec(raw);
  const meta = {};
  let body = raw;
  if (metaMatch) {
    for (const line of metaMatch[1].split("\n")) {
      const kv = /^\s*([A-Za-z][\w-]*)\s*:\s*(.*?)\s*$/.exec(line);
      if (kv) meta[kv[1].toLowerCase()] = kv[2];
    }
    body = raw.slice(metaMatch[0].length);
  } else {
    warnings.push(`${slug || "index"}: fragment has no metadata comment (title/description)`);
  }
  if (/<\s*(html|head|body)\b/i.test(body)) {
    warnings.push(`${slug || "index"}: fragment contains an <html>/<head>/<body> tag — fragments must be body-only`);
  }
  return { meta, body: body.trim() };
}

function renderFragment(body, slug, rootPrefix) {
  const extracted = extractCodeBlocks(body);
  let html = extracted.html;
  const headed = processHeadings(html);
  html = wrapTables(headed.html);
  html = html.replace(new RegExp("\\u0000CODE(\\d+)\\u0000", "g"), (m, n) =>
    renderCodeBlock(extracted.blocks[Number(n)], slug)
  );
  html = html.split("{{root}}").join(rootPrefix);
  return { html, headings: headed.headings };
}

/* ===================================================================== */
/* Nav model                                                              */
/* ===================================================================== */

const pages = [];
for (const section of NAV) {
  for (const item of section.items) {
    pages.push({ slug: item.slug, label: item.label, section: section.label });
  }
}

const slugSet = new Set(pages.map((p) => p.slug));

function fragmentPathFor(slug) {
  return slug === ""
    ? path.join(CONTENT_DIR, "index.html")
    : path.join(CONTENT_DIR, `${slug}.html`);
}

function outputPathFor(slug) {
  return slug === ""
    ? path.join(DIST_DIR, "index.html")
    : path.join(DIST_DIR, `${slug}.html`);
}

function rootPrefixFor(slug) {
  if (slug === "") return "";
  return "../".repeat(slug.split("/").length - 1);
}

function hrefFor(fromSlug, toSlug) {
  const prefix = rootPrefixFor(fromSlug);
  return prefix + (toSlug === "" ? "index.html" : `${toSlug}.html`);
}

/* ===================================================================== */
/* Shell                                                                  */
/* ===================================================================== */

const ICONS = {
  menu: '<svg class="i-menu" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M3 6h18M3 12h18M3 18h18"/></svg>',
  close: '<svg class="i-close" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"/></svg>',
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.2-3.2"/></svg>',
  sun: '<svg class="i-theme i-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
  moon: '<svg class="i-theme i-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/></svg>',
  system: '<svg class="i-theme i-system" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/></svg>',
  chevron: '<svg class="docs-side-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>',
  arrowLeft: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 12H5m7-7-7 7 7 7"/></svg>',
  arrowRight: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14m-7-7 7 7-7 7"/></svg>',
  github: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .5a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2c-3.3.7-4-1.6-4-1.6-.6-1.4-1.4-1.8-1.4-1.8-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.7-1.6-2.7-.3-5.5-1.3-5.5-5.9 0-1.3.5-2.4 1.2-3.2-.1-.3-.5-1.5.1-3.2 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.7 18.3 5 18.3 5c.6 1.7.2 2.9.1 3.2.8.8 1.2 1.9 1.2 3.2 0 4.6-2.8 5.6-5.5 5.9.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A12 12 0 0 0 12 .5Z"/></svg>',
};

const NO_FLASH = `(function(){try{var t=localStorage.getItem('proximiio-docs-theme');if(t==='dark'||t==='light'){document.documentElement.setAttribute('data-theme',t);}}catch(e){}})();`;

function renderSidebar(currentSlug) {
  return NAV.map((section) => {
    const hasCurrent = section.items.some((i) => i.slug === currentSlug);
    const open = hasCurrent || !section.collapsed;
    const items = section.items.map((item) => {
      const active = item.slug === currentSlug;
      return `<a class="docs-side-item" href="${escapeHtml(hrefFor(currentSlug, item.slug))}"` +
        `${active ? ' aria-current="page"' : ""}><span class="lbl">${escapeHtml(item.label)}</span></a>`;
    }).join("");
    const id = `side-${slugify(section.label)}`;
    return `<div class="docs-side-section">` +
      `<button type="button" class="docs-side-head" data-section="${escapeHtml(section.label)}" ` +
      `aria-expanded="${open ? "true" : "false"}" aria-controls="${id}">` +
      `${ICONS.chevron}<span class="lbl">${escapeHtml(section.label)}</span></button>` +
      `<div class="docs-side-items" id="${id}">${items}</div></div>`;
  }).join("");
}

function renderToc(headings) {
  if (!headings.length) return "";
  const items = headings.map((h) =>
    `<li data-depth="${h.depth}"><a class="doc-toc-link" href="#${escapeHtml(h.id)}">${escapeHtml(h.text)}</a></li>`
  ).join("");
  return `<nav class="doc-toc" aria-label="On this page">` +
    `<div class="doc-toc-title">On this page</div><ul>${items}</ul></nav>`;
}

function renderPager(currentSlug) {
  const idx = pages.findIndex((p) => p.slug === currentSlug);
  const prev = idx > 0 ? pages[idx - 1] : null;
  const next = idx >= 0 && idx < pages.length - 1 ? pages[idx + 1] : null;
  if (!prev && !next) return "";
  const left = prev
    ? `<a class="docs-pager-link prev" href="${escapeHtml(hrefFor(currentSlug, prev.slug))}">${ICONS.arrowLeft}` +
      `<span class="docs-pager-meta"><span class="docs-pager-dir">Previous</span>` +
      `<span class="docs-pager-title">${escapeHtml(prev.label)}</span></span></a>`
    : "<span></span>";
  const right = next
    ? `<a class="docs-pager-link next" href="${escapeHtml(hrefFor(currentSlug, next.slug))}">` +
      `<span class="docs-pager-meta"><span class="docs-pager-dir">Next</span>` +
      `<span class="docs-pager-title">${escapeHtml(next.label)}</span></span>${ICONS.arrowRight}</a>`
    : "<span></span>";
  return `<nav class="docs-pager" aria-label="Pagination">${left}${right}</nav>`;
}

function renderShell({ slug, title, description, section, bodyHtml, headings, layout }) {
  const base = rootPrefixFor(slug);
  const assistant = assistantTags(slug, base);
  const pageTitle = slug === "" ? `${SITE.titleSuffix} documentation` : `${title} · ${SITE.titleSuffix}`;

  const crumbs = layout === "landing" ? "" :
    `<nav class="docs-crumbs" aria-label="Breadcrumb">` +
    `<a href="${escapeHtml(hrefFor(slug, ""))}">Docs</a>` +
    (section ? `<span class="docs-crumb-sep" aria-hidden="true">/</span><span>${escapeHtml(section)}</span>` : "") +
    `</nav>`;

  const head = layout === "landing" ? "" :
    `<header class="docs-page-head"><h1>${escapeHtml(title)}</h1>` +
    (description ? `<p class="docs-page-lede">${escapeHtml(description)}</p>` : "") +
    `</header>`;

  const main = layout === "landing"
    ? `<div class="docs-landing">${bodyHtml}</div>`
    : `<div class="docs-content-wrap"><article class="docs-content">${crumbs}${head}` +
      `<div class="doc-prose">${bodyHtml}</div>${renderPager(slug)}</article>` +
      `<aside class="docs-toc-col">${renderToc(headings)}</aside></div>`;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(pageTitle)}</title>
<meta name="description" content="${escapeHtml(description || `${SITE.name} ${SITE.version} documentation.`)}">
<meta name="generator" content="proximiio-docs-site">
<link rel="icon" type="image/svg+xml" href="${base}assets/favicon.svg">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;450;500;600;700&amp;family=JetBrains+Mono:wght@400;500&amp;display=swap">
<link rel="stylesheet" href="${base}assets/styles.css">${assistant.head}
<script>${NO_FLASH}</script>
</head>
<body>
<a class="skip-link" href="#doc-content">Skip to content</a>
<div class="docs-root">
  <header class="docs-header">
    <button type="button" class="docs-nav-toggle" aria-label="Toggle navigation" aria-expanded="false" aria-controls="docs-sidebar">${ICONS.menu}${ICONS.close}</button>
    <a class="docs-brand" href="${escapeHtml(hrefFor(slug, ""))}" aria-label="${escapeHtml(SITE.name)} ${escapeHtml(SITE.version)} documentation home">
      <span class="docs-logo-plate"><img class="docs-logo" src="${base}assets/proximi-logo.png" width="2082" height="532" alt="Proximi.io"></span>
      <span class="docs-brand-sep" aria-hidden="true"></span>
      <span class="docs-brand-lockup">
        <span class="docs-brand-name">${escapeHtml(SITE.name)}</span>
        <span class="docs-brand-eyebrow">${escapeHtml(SITE.version)}</span>
      </span>
    </a>
    <div class="docs-header-spacer"></div>
    <button type="button" class="docs-search-trigger" aria-label="Search documentation">
      ${ICONS.search}<span class="docs-search-trigger-label">Search</span><kbd class="kbd">⌘K</kbd>
    </button>
    <button type="button" class="docs-icon-btn docs-theme-toggle" aria-label="Toggle theme" title="Toggle theme">${ICONS.sun}${ICONS.moon}${ICONS.system}</button>
    <a class="docs-icon-btn" href="${escapeHtml(SITE.repoUrl)}" target="_blank" rel="noreferrer noopener" aria-label="Source on GitHub" title="Source on GitHub">${ICONS.github}</a>
  </header>
  <div class="docs-body">
    <aside class="docs-sidebar" id="docs-sidebar">
      <nav class="docs-side-nav scroll" aria-label="Documentation">${renderSidebar(slug)}</nav>
    </aside>
    <div class="docs-nav-scrim" role="presentation"></div>
    <main class="docs-main scroll" id="doc-content" tabindex="-1">${main}</main>
  </div>
</div>
<script src="${base}assets/search-index.js"></script>
<script>window.DOCS_BASE=${JSON.stringify(base)};</script>
<script src="${base}assets/docs.js"></script>${assistant.body}
</body>
</html>
`;
}

/* ===================================================================== */
/* Build                                                                  */
/* ===================================================================== */

function rmrf(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
}

function copyDir(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    const src = path.join(from, entry.name);
    const dst = path.join(to, entry.name);
    if (entry.isDirectory()) copyDir(src, dst);
    else fs.copyFileSync(src, dst);
  }
}

function listFragments(dir, prefix = "") {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) out.push(...listFragments(path.join(dir, entry.name), rel));
    else if (entry.name.endsWith(".html")) out.push(rel.replace(/\.html$/, ""));
  }
  return out;
}

function placeholderBody(label) {
  return `<div class="docs-placeholder"><strong>This page is being written.</strong>` +
    `<p>“${escapeHtml(label)}” is part of the ${escapeHtml(SITE.name)} ${escapeHtml(SITE.version)} ` +
    `documentation outline but has no content yet. It will land in a later pass.</p></div>`;
}

rmrf(DIST_DIR);
fs.mkdirSync(DIST_DIR, { recursive: true });
copyDir(ASSETS_DIR, path.join(DIST_DIR, "assets"));
if (!ASSISTANT) for (const f of ASSISTANT_FILES) fs.rmSync(path.join(DIST_DIR, "assets", f), { force: true });
if (ASSISTANT) console.log(`docs assistant: on → ${ASSISTANT.endpoint} (sdk base ${ASSISTANT.bases.sdk ?? "none"}, map base ${ASSISTANT.bases.map ?? "none"})`);

const fragmentSlugs = listFragments(CONTENT_DIR).map((s) => (s === "index" ? "" : s));
for (const s of fragmentSlugs) {
  if (!slugSet.has(s)) warnings.push(`content/${s || "index"}.html exists but no nav entry references it`);
}

const index = [];
let placeholders = 0;

for (const page of pages) {
  const fragPath = fragmentPathFor(page.slug);
  const rootPrefix = rootPrefixFor(page.slug);
  let title = page.label;
  let description = "";
  let layout = "doc";
  let bodyHtml;
  let headings = [];
  let plain = "";

  if (fs.existsSync(fragPath)) {
    const raw = fs.readFileSync(fragPath, "utf8");
    const { meta, body } = parseFragment(raw, page.slug);
    title = meta.title || page.label;
    description = meta.description || "";
    layout = meta.layout === "landing" ? "landing" : "doc";
    const rendered = renderFragment(body, page.slug, rootPrefix);
    bodyHtml = rendered.html;
    headings = rendered.headings;
    plain = stripTags(body).slice(0, 2400);
    if (meta.title && meta.title !== page.label) {
      // Nav label stays the short form; that's intentional, not a warning.
    }
  } else {
    warnings.push(`no fragment for nav slug "${page.slug || "(index)"}" — placeholder emitted`);
    placeholders++;
    bodyHtml = placeholderBody(page.label);
    description = `${page.label} — documentation in progress.`;
    plain = "This page is being written.";
  }

  const html = renderShell({
    slug: page.slug,
    title,
    description,
    section: page.section,
    bodyHtml,
    headings,
    layout,
  });

  const outPath = outputPathFor(page.slug);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, html, "utf8");

  index.push({
    slug: page.slug,
    title,
    description,
    section: page.section,
    headings: headings.map((h) => ({ id: h.id, text: h.text, depth: h.depth })),
    text: plain,
  });
}

const indexJs =
  "/* Generated by build.mjs — do not edit. Assigned to a global (not fetched)\n" +
  "   so search works when the site is opened straight from disk. */\n" +
  `window.DOCS_INDEX = ${JSON.stringify(index)};\n`;
fs.writeFileSync(path.join(DIST_DIR, "assets", "search-index.js"), indexJs, "utf8");

/* ── Summary ───────────────────────────────────────────────────────────── */
const indexBytes = Buffer.byteLength(indexJs, "utf8");
console.log(`proximiio-docs · built ${pages.length} pages ` +
  `(${pages.length - placeholders} authored, ${placeholders} placeholder) → ${path.relative(process.cwd(), DIST_DIR)}`);
console.log(`  search index: ${index.length} entries, ${(indexBytes / 1024).toFixed(1)} KB`);
if (warnings.length) {
  console.log(`  warnings (${warnings.length}):`);
  const shown = warnings.filter((w) => !/placeholder emitted$/.test(w));
  for (const w of shown) console.log(`    · ${w}`);
  const hidden = warnings.length - shown.length;
  if (hidden) console.log(`    · ${hidden} nav slug${hidden === 1 ? "" : "s"} still awaiting a fragment`);
} else {
  console.log("  no warnings");
}
