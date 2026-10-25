# Proximi.io Flutter map — documentation site

Partner-facing docs for `flutter_proximiio_map`, published only to Partner Zone as a docs bundle
(`coordination/conventions/docs-changelog.md`). The site is a port of the iOS and Android SDK sites
(`proximiio-android-sdk-v6/docs/map-site` and the iOS map docs): same builder, same design
tokens, same fragment contract, same section order. The page set and wording mirror those sites; the
platform facts are Flutter's.

## Layout

| Path | What |
|---|---|
| `nav.mjs` | Sidebar order and titles; the single source of which pages exist |
| `content/<slug>.html` | One HTML fragment per page (`""` → `content/index.html`) |
| `assets/` | Styles and scripts, byte copies of the Android site |
| `build.mjs` | Zero-dependency builder (Node ≥ 18), the Android copy plus `dart` and `yaml` highlighting |
| `ANNINA-RULES.md` | Writing rules |
| `dist/` | Build output (git-ignored) |

## Fragment contract

- No `<html>`, `<head>`, `<body>`, no `<h1>`; prose starts at `<h2>`.
- First thing in the file: a metadata comment with `title` and `description` (≤ 160 characters).
  `layout: landing` only on `index.html`.
- Links: `{{root}}path.html#anchor`.
- Code: `<pre><code class="language-dart">`, unindented, HTML-escaped.
- Callouts: `<div class="doc-aside doc-aside-note|tip|caution|warning|danger"><p>…</p></div>`.
- Every symbol must exist in the Dart API (`lib/`); every claim must hold on both platforms or name the platform.

## Commands

```sh
node docs/site/build.mjs                   # build into docs/site/dist
node scripts/check-docs-links.mjs          # every internal link and anchor resolves
scripts/export-docs-bundle.sh flutter-map 6.0.0-beta.1 --no-sign   # Partner Zone bundle preflight
```

The bundle export needs Node ≥ 22 and a dated CHANGELOG entry for the version. Signing happens only in
the release workflow, never on a laptop.
