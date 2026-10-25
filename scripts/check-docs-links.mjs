#!/usr/bin/env node
// Link checker for the customer docs site (docs/site).
//
// build.mjs warns about a nav slug with no fragment and a fragment no nav entry
// references, but it never resolves the links the fragments write by hand. A
// renamed page therefore builds clean and ships a dead link. This walks the
// generated site instead of the sources: every internal href in dist/ has to
// resolve to a file that exists, and every #fragment to an id that exists on
// the page it points at.
//
//   node docs/site/build.mjs && node scripts/check-docs-links.mjs
//
// Exits 1 listing every problem, 0 with a one-line summary.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
// `--site docs/map-site` checks the other site in this repository; default is docs/site.
const siteArg = (() => { const i = process.argv.indexOf("--site"); return i >= 0 ? process.argv[i + 1] : "docs/site"; })();
const DIST = path.join(REPO, siteArg, "dist");

if (!fs.existsSync(DIST)) {
  console.error(`no built site at ${path.relative(REPO, DIST)} — run "node ${siteArg}/build.mjs" first`);
  process.exit(1);
}

function listHtml(dir, prefix = "") {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) out.push(...listHtml(path.join(dir, entry.name), rel));
    else if (entry.name.endsWith(".html")) out.push(rel);
  }
  return out;
}

// Resolve "a/b/../c" without letting it escape the site root.
function normalizeRel(p) {
  const segments = [];
  for (const seg of p.split("/")) {
    if (!seg || seg === ".") continue;
    if (seg === "..") segments.pop();
    else segments.push(seg);
  }
  return segments.join("/");
}

const pages = listHtml(DIST);
const html = new Map(pages.map((rel) => [rel, fs.readFileSync(path.join(DIST, rel), "utf8")]));
const idsByPage = new Map(
  pages.map((rel) => [rel, new Set([...html.get(rel).matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]))]),
);

const errors = [];
for (const rel of pages) {
  for (const [, raw] of html.get(rel).matchAll(/href="([^"]+)"/g)) {
    // The theme query string docs.js appends at runtime never appears in the
    // generated markup, so a "?" here would be hand-written — still worth
    // resolving the path half rather than reporting the whole href missing.
    const href = raw.replace(/&amp;/g, "&");
    if (/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(href)) continue; // http(s), mailto, tel, data, protocol-relative

    if (href.startsWith("#")) {
      const fragment = href.slice(1);
      if (fragment && !idsByPage.get(rel).has(fragment)) {
        errors.push(`${rel}: missing anchor #${fragment}`);
      }
      continue;
    }

    const [withQuery, fragment] = href.split("#");
    const pathPart = withQuery.split("?")[0];
    if (!pathPart) continue;

    const target = normalizeRel(path.posix.join(path.posix.dirname(rel), pathPart));
    if (!target || !fs.existsSync(path.join(DIST, target))) {
      errors.push(`${rel}: broken link -> ${href} (resolved ${target || "outside dist/"})`);
      continue;
    }
    if (fragment && idsByPage.has(target) && !idsByPage.get(target).has(fragment)) {
      errors.push(`${rel}: broken anchor -> ${href}`);
    }
  }
}

if (errors.length) {
  console.error(`LINK CHECK FAILED — ${errors.length} problem(s):`);
  for (const e of errors) console.error(`  x ${e}`);
  process.exit(1);
}
console.log(`Link check: OK — ${pages.length} pages, all internal links and anchors resolve.`);
