#!/usr/bin/env node
// Reference docs-bundle exporter (docs/contracts/docs-bundle.md, v1).
//
// Node >= 22, zero dependencies, no network. Reads an existing docs-as-code site
// (`<repo>/docs/site` with nav.mjs, versions.mjs, content/**.html, assets/) and
// writes `docs-bundle-<product>-<version>.tar.gz` + `.sha256` into --out.
// The source repository is only READ (its build.mjs is not run: it writes dist/).
//
//   node tools/export-docs-bundle.mjs --site <repo>/docs/site --product ios-sdk \
//        --group "Mobile SDKs" --title "iOS SDK" --out ./out [--strict]
//
// See tools/README.md.

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';

const PRODUCTS = new Set(['ios-sdk', 'ios-map', 'android-sdk', 'android-map', 'js-library', 'react-native',
  'react-native-map', 'api-core', 'api-geo', 'api-audit', 'api-routing', 'api-relay', 'mcp']);

const { values: args } = parseArgs({
  options: {
    site: { type: 'string' }, product: { type: 'string' }, group: { type: 'string' }, title: { type: 'string' },
    out: { type: 'string', default: './out' }, repo: { type: 'string' }, commit: { type: 'string' },
    install: { type: 'string' }, version: { type: 'string' }, changelog: { type: 'string' }, strict: { type: 'boolean', default: false }, help: { type: 'boolean', short: 'h' },
  },
});
if (args.help || !args.site || !args.product || !args.group || !args.title) {
  console.error('usage: export-docs-bundle.mjs --site <docs/site dir> --product <id> --group <group> --title <title>\n' +
    '         [--out <dir>] [--repo owner/name] [--commit sha] [--install \'{"spm":"…"}\']\n' +
    '         [--version <v>] [--changelog <path>] [--strict]');
  process.exit(args.help ? 0 : 2);
}
if (!PRODUCTS.has(args.product)) fail(`unknown product id "${args.product}" (contract §1)`);

const SITE_DIR = path.resolve(args.site);
const CONTENT_DIR = path.join(SITE_DIR, 'content');
const ASSETS_DIR = path.join(SITE_DIR, 'assets');
const REPO_ROOT = path.resolve(SITE_DIR, '..', '..');
const warnings = [];
const warn = (m) => warnings.push(m);
function fail(m) { console.error(`export-docs-bundle: ${m}`); process.exit(1); }

/* ── site sources ─────────────────────────────────────────────────────── */

const { NAV, SITE = {} } = await import(pathToFileURL(path.join(SITE_DIR, 'nav.mjs')).href);
// versions.mjs is optional (the Android sites have none). Version precedence:
// --version, versions.mjs `version`, newest dated CHANGELOG heading.
const versionsPath = path.join(SITE_DIR, 'versions.mjs');
const versions = fs.existsSync(versionsPath) ? await import(pathToFileURL(versionsPath).href) : {};
const PLACEHOLDERS = versions.PLACEHOLDERS ?? {};
// --changelog: docs living in another repo than the library (Android Map docs sit in the SDK repo).
const changelogPath = path.resolve(args.changelog ?? path.join(REPO_ROOT, 'CHANGELOG.md'));
const changelogText = fs.existsSync(changelogPath) ? fs.readFileSync(changelogPath, 'utf8') : null;
const newestDated = changelogText
  ? /^## \[(?!Unreleased\])([^\]]+)\][^\n]*?\d{4}-\d{2}-\d{2}/m.exec(changelogText)?.[1] ?? null
  : null;
const version = args.version ?? versions.version ?? newestDated
  ?? fail('no version: pass --version, export `version` from versions.mjs, or add a dated CHANGELOG entry');
if (!/^[0-9A-Za-z][0-9A-Za-z.+-]*$/.test(version)) fail(`unsafe version string "${version}"`);
const generation = `v${String(versions.generation ?? (/^v\d+$/.test(SITE.version ?? '') ? SITE.version : version.split('.')[0])).replace(/^v/, '')}`;

// Same placeholder rule as build.mjs: known names are filled, documented brace
// tokens (`{{ts}}`) and `{{root}}` are left for later, anything else is a warning.
const PLACEHOLDER_RE = /\{\{([A-Za-z][\w]*)\}\}/g;
const DOCUMENTED_BRACE_TOKENS = new Set(['ts']);
function applyPlaceholders(text, slug) {
  return text.replace(PLACEHOLDER_RE, (m, name) => {
    if (Object.prototype.hasOwnProperty.call(PLACEHOLDERS, name)) return String(PLACEHOLDERS[name]);
    if (name !== 'root' && !DOCUMENTED_BRACE_TOKENS.has(name)) warn(`${slug || 'index'}: unknown placeholder {{${name}}}`);
    return m;
  });
}

// build.mjs slugify + processHeadings (ids only; Partner Zone renders its own anchors).
function slugify(text) {
  return String(text).toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'section';
}
const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', mdash: '—', ndash: '–', hellip: '…',
  rarr: '→', larr: '←', times: '×', minus: '−', le: '≤', ge: '≥', middot: '·', lsquo: '‘', rsquo: '’', ldquo: '“',
  rdquo: '”', deg: '°', plusmn: '±' };
function decode(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') return String.fromCodePoint(e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10));
    return ENT[e.toLowerCase()] ?? m;
  });
}
const strip = (s) => decode(s.replace(/<[^>]+>/g, '')).replace(/[ \t\r\n]+/g, ' ').trim();
const escAttr = (s) => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');

function addHeadingIds(html) {
  const blocks = [];
  html = html.replace(/<pre\b[^>]*>[\s\S]*?<\/pre>/gi, (m) => { blocks.push(m); return `\u0000${blocks.length - 1}\u0000`; });
  const used = new Set();
  html = html.replace(/<(h[234])\b([^>]*)>([\s\S]*?)<\/\1>/gi, (m, tag, attrs, inner) => {
    const idAttr = /\bid\s*=\s*"([^"]*)"/i.exec(attrs) || /\bid\s*=\s*'([^']*)'/i.exec(attrs);
    let id = idAttr ? idAttr[1] : slugify(strip(inner));
    if (used.has(id)) { let n = 2; while (used.has(`${id}-${n}`)) n++; id = `${id}-${n}`; }
    used.add(id);
    const rest = attrs.replace(/\s*\bid\s*=\s*("[^"]*"|'[^']*')/i, '');
    return `<${tag} id="${escAttr(id)}"${rest}>${inner}</${tag}>`;
  });
  html = html.replace(/\u0000(\d+)\u0000/g, (m, i) => blocks[Number(i)]);
  return { html, ids: used };
}

// `{{root}}x/y.html#a` -> `x/y#a`, `{{root}}index.html` -> `./`, `{{root}}assets/p` -> `assets/p`.
function rewriteRootLinks(html, slug, assets) {
  return html.replace(/\b(href|src)\s*=\s*"\{\{root\}\}([^"]*)"/gi, (m, attr, target) => {
    const [p, frag] = target.split('#', 2);
    const hash = frag !== undefined ? `#${frag}` : '';
    if (p.startsWith('assets/')) { assets.add(p); return `${attr}="${p}${hash}"`; }
    if (p === '' || p === 'index.html') return `${attr}="./${hash}"`;
    if (p.endsWith('.html')) return `${attr}="${p.slice(0, -5)}${hash}"`;
    warn(`${slug || 'index'}: {{root}} link to non-page "${p}" kept as relative`);
    return `${attr}="${p}${hash}"`;
  });
}

// Page-relative `../x/y.html#a` (works on the static site, not in Partner Zone)
// -> product-relative `x/y#a`. Reported, so authors can switch to {{root}}.
function rewritePageRelativeLinks(html, slug) {
  const dir = path.posix.dirname(slug || 'index');
  return html.replace(/\bhref\s*=\s*"([^"]*)"/gi, (m, href) => {
    const [p, frag] = href.split('#', 2);
    if (!p.endsWith('.html') || /^[a-z][a-z0-9+.-]*:/i.test(p) || p.startsWith('/') || p.includes('{{')) return m;
    const hash = frag !== undefined ? `#${frag}` : '';
    const resolved = path.posix.normalize(path.posix.join(dir, p));
    if (resolved.startsWith('../')) { warn(`${slug || 'index'}: link "${href}" escapes the product`); return m; }
    const target = resolved === 'index.html' ? './' : resolved.slice(0, -5);
    warn(`${slug || 'index'}: page-relative link "${href}" normalised to "${target}${hash}" (use {{root}})`);
    return `href="${target}${hash}"`;
  });
}

function parseMeta(raw) {
  const meta = {};
  const mm = /^\s*<!--([\s\S]*?)-->/.exec(raw);
  if (mm) for (const line of mm[1].split('\n')) {
    const kv = /^\s*([A-Za-z][\w-]*)\s*:\s*(.*?)\s*$/.exec(line);
    if (kv) meta[kv[1].toLowerCase()] = kv[2];
  }
  return meta;
}

/* ── assistant corpus (port of docs-assistant-prototype/corpus.mjs toText) ── */

function toText(html) {
  const blocks = [];
  html = html.replace(/<pre\b[^>]*>([\s\S]*?)<\/pre>/gi, (m, inner) => {
    const lang = /class="[^"]*language-([\w-]+)/i.exec(inner)?.[1] ?? '';
    const code = decode(inner.replace(/<[^>]+>/g, '')).replace(/^\n+|\s+$/g, '');
    blocks.push('\n```' + lang + '\n' + code + '\n```\n');
    return `\u0000${blocks.length - 1}\u0000`;
  });
  html = html.replace(/\s+/g, ' ');
  const used = new Set();
  const anchors = [];
  html = html.replace(/<(h[234])\b([^>]*)>([\s\S]*?)<\/\1>/gi, (m, tag, attrs, inner) => {
    const text = strip(inner);
    let id = /\bid\s*=\s*"([^"]*)"/i.exec(attrs)?.[1] ?? slugify(text);
    if (used.has(id)) { let n = 2; while (used.has(`${id}-${n}`)) n++; id = `${id}-${n}`; }
    used.add(id); anchors.push({ id, text, depth: Number(tag[1]) });
    return `\n\n${'#'.repeat(Number(tag[1]))} ${text} {#${id}}\n\n`;
  });
  html = html.replace(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi, (m, inner) => {
    const cells = [...inner.matchAll(/<t[hd]\b[^>]*>([\s\S]*?)<\/t[hd]>/gi)]
      .map((c) => strip(c[1].replace(/<code\b[^>]*>([\s\S]*?)<\/code>/gi, '`$1`')).replace(/\|/g, '\\|'));
    return `\n${cells.join(' | ')}\n`;
  });
  html = html.replace(/<li\b[^>]*>/gi, '\n- ')
    .replace(/<\/(p|div|ul|ol|table|thead|tbody|blockquote|dl|dd|dt|section|aside|figure)>/gi, '\n')
    .replace(/<br\s*\/?>/gi, '\n').replace(/<(p|div|dt|dd|blockquote)\b[^>]*>/gi, '\n');
  html = html.replace(/<code\b[^>]*>([\s\S]*?)<\/code>/gi, (m, i) => '`' + decode(i.replace(/<[^>]+>/g, '')) + '`');
  let text = decode(html.replace(/<!--[\s\S]*?-->/g, '').replace(/<[^>]+>/g, ''));
  text = text.split('\n').map((l) => l.replace(/[ \t]+/g, ' ').trim()).join('\n')
    .replace(/^-\s*\n+/gm, '- ').replace(/\n{3,}/g, '\n\n').trim();
  for (let k = 0; k < 2; k++) text = text.replace(/^([^\n]* \| [^\n]*)\n\n(?=[^\n]* \| )/gm, '$1\n');
  text = text.replace(/\u0000(\d+)\u0000/g, (m, i) => blocks[Number(i)]).replace(/\n{3,}/g, '\n\n');
  return { text, anchors };
}

const isPlaceholderText = (text) => text.replace(/\s/g, '').length < 200 || /This page is being written/i.test(text);

/* ── build the bundle tree in memory ──────────────────────────────────── */

const files = new Map(); // tar path -> Buffer
const put = (p, data) => files.set(p, Buffer.isBuffer(data) ? data : Buffer.from(data, 'utf8'));
const nav = [];
const corpusPages = [];
const corpusExcluded = [];
const assetRefs = new Set();
const pageIds = new Map(); // slug -> Set(anchor ids)
const linkChecks = []; // { from, slug, anchor }

for (const section of NAV) {
  const sectionInternal = /internal/i.test(section.label) || section.internal;
  const items = [];
  for (const item of section.items) {
    if (sectionInternal || item.internal) { warn(`${item.slug || 'index'}: nav marks internal — not exported`); continue; }
    const rel = `${item.slug || 'index'}.html`;
    const file = path.join(CONTENT_DIR, rel);
    let raw;
    let draft = false;
    if (fs.existsSync(file)) {
      raw = fs.readFileSync(file, 'utf8');
      const meta = parseMeta(raw);
      if (/^internal|true$/i.test(meta.internal ?? meta.audience ?? '')) {
        warn(`${item.slug || 'index'}: metadata marks internal — not exported`); continue;
      }
    } else {
      draft = true;
      raw = `<!--\ntitle: ${item.label}\n-->\n<p>This page is being written.</p>\n`;
    }
    if (/<script\b/i.test(raw)) fail(`${rel}: contains <script> (contract §5)`);
    let html = applyPlaceholders(raw, item.slug);
    html = rewriteRootLinks(html, item.slug, assetRefs);
    html = rewritePageRelativeLinks(html, item.slug);
    const headed = addHeadingIds(html);
    html = headed.html;
    pageIds.set(item.slug, headed.ids);
    for (const m of html.matchAll(/\bhref\s*=\s*"([^"]*)"/gi)) {
      const href = m[1];
      if (/^[a-z][a-z0-9+.-]*:/i.test(href) || href.startsWith('/') || href.startsWith('assets/')) continue;
      const [p, anchor] = href.split('#', 2);
      const slug = p === '' ? item.slug : p === './' ? '' : p.replace(/^\.\//, '');
      linkChecks.push({ from: item.slug, slug, anchor, href });
    }
    const meta = parseMeta(html);
    const { text, anchors } = toText(html.replace(/^\s*<!--[\s\S]*?-->/, ''));
    if (!draft && isPlaceholderText(text)) draft = true;
    if (draft) corpusExcluded.push(item.slug);
    else corpusPages.push({ slug: item.slug, title: meta.title || item.label, section: section.label,
      description: decode(meta.description || ''), anchors, text });
    put(`pages/${rel}`, html);
    items.push({ slug: item.slug, label: item.label, ...(draft ? { draft: true } : {}) });
  }
  if (items.length) nav.push({ label: section.label, collapsed: Boolean(section.collapsed), items });
}

for (const l of linkChecks) {
  if (!pageIds.has(l.slug)) warn(`${l.from || 'index'}: internal link "${l.href}" points to a page not in the bundle`);
  else if (l.anchor && !pageIds.get(l.slug).has(l.anchor)) warn(`${l.from || 'index'}: internal link "${l.href}" points to a missing anchor`);
}

for (const a of assetRefs) {
  const src = path.join(ASSETS_DIR, a.slice('assets/'.length));
  if (!src.startsWith(ASSETS_DIR + path.sep) || !fs.existsSync(src)) { warn(`asset "${a}" referenced but not found`); continue; }
  put(a, fs.readFileSync(src));
}

let releasedAt = null;
if (changelogText !== null) {
  const changelog = changelogText;
  put('changelog.md', changelog);
  const esc = version.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  releasedAt = new RegExp(`^## \\[${esc}\\][^\\n]*?(\\d{4}-\\d{2}-\\d{2})`, 'm').exec(changelog)?.[1] ?? null;
} else warn(`no CHANGELOG.md at ${changelogPath}`);
if (!releasedAt) { releasedAt = new Date().toISOString().slice(0, 10); warn(`no CHANGELOG date for ${version}; released_at = today`); }

function git(...a) {
  try { return execFileSync('git', ['-C', REPO_ROOT, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); }
  catch { return null; }
}
const remote = git('remote', 'get-url', 'origin');
const repo = args.repo ?? (remote ? /github\.com[:/](.+?)(?:\.git)?$/.exec(remote)?.[1] ?? remote : null);
const commit = args.commit ?? git('rev-parse', 'HEAD');
if (git('status', '--porcelain', '--', path.relative(REPO_ROOT, SITE_DIR), 'CHANGELOG.md')) warn('source repo has uncommitted docs changes; commit id is approximate');

let install = { spm: SITE.repoUrl, pin: version };
if (args.install) { try { install = JSON.parse(args.install); } catch (e) { fail(`--install is not JSON: ${e.message}`); } }

const bundle = { schema: 1, product: args.product, title: args.title, group: args.group, version, generation,
  released_at: releasedAt, source: { repo, commit }, install };
put('bundle.json', JSON.stringify(bundle, null, 2) + '\n');
put('nav.json', JSON.stringify(nav, null, 2) + '\n');
put('assistant-corpus.json', JSON.stringify({ generated: new Date().toISOString(), pages: corpusPages, excluded: corpusExcluded }, null, 2) + '\n');

/* ── tar (ustar) + gzip, deterministic ────────────────────────────────── */

function tarHeader(name, size, mtime) {
  const h = Buffer.alloc(512);
  let prefix = '';
  if (Buffer.byteLength(name) > 100) {
    const cut = name.lastIndexOf('/', 155);
    if (cut <= 0 || Buffer.byteLength(name.slice(cut + 1)) > 100) fail(`path too long for ustar: ${name}`);
    prefix = name.slice(0, cut); name = name.slice(cut + 1);
  }
  const field = (off, len, val) => h.write(val, off, len, 'utf8');
  const octal = (off, len, n) => field(off, len, n.toString(8).padStart(len - 1, '0') + '\0');
  field(0, 100, name); octal(100, 8, 0o644); octal(108, 8, 0); octal(116, 8, 0); octal(124, 12, size);
  octal(136, 12, mtime); h.fill(' ', 148, 156); field(156, 1, '0'); field(257, 6, 'ustar\0'); field(263, 2, '00');
  field(345, 155, prefix);
  let sum = 0; for (const b of h) sum += b;
  field(148, 8, sum.toString(8).padStart(6, '0') + '\0 ');
  return h;
}
const mtime = Math.floor(Date.parse(`${releasedAt}T00:00:00Z`) / 1000) || 0;
const chunks = [];
for (const name of [...files.keys()].sort()) {
  const data = files.get(name);
  chunks.push(tarHeader(name, data.length, mtime), data, Buffer.alloc((512 - (data.length % 512)) % 512));
}
chunks.push(Buffer.alloc(1024));
const gz = zlib.gzipSync(Buffer.concat(chunks), { level: 9 });

const outDir = path.resolve(args.out);
fs.mkdirSync(outDir, { recursive: true });
const base = `docs-bundle-${args.product}-${version}.tar.gz`;
fs.writeFileSync(path.join(outDir, base), gz);
const sha = crypto.createHash('sha256').update(gz).digest('hex');
fs.writeFileSync(path.join(outDir, `${base}.sha256`), `${sha}  ${base}\n`);

const navPages = nav.reduce((n, s) => n + s.items.length, 0);
console.log(`${base}: ${navPages} pages (${corpusExcluded.length} draft), ${assetRefs.size} assets, ` +
  `${(gz.length / 1024).toFixed(1)} KiB, sha256 ${sha}`);
for (const w of warnings) console.warn(`  warning: ${w}`);
// TODO(R4): minisign signature (.minisig) is produced by the release CI, not here.
if (args.strict && warnings.length) process.exit(1);
