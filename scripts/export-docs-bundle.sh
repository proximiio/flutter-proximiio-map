#!/usr/bin/env bash
#
# export-docs-bundle.sh — build, checksum and sign the Partner Zone docs bundle
# for one release (contract: proximiio-partner-zone/docs/contracts/docs-bundle.md).
#
# Runs Partner Zone's reference exporter (tools/export-docs-bundle.mjs) PINNED BY
# COMMIT with --strict, so a draft page, a page-relative link or a missing dated
# CHANGELOG entry fails the release instead of shipping. Copied from
# proximiio-android-sdk-v6 (same exporter pin); this repo holds one site:
#
#   flutter-map  docs/site  CHANGELOG.md of this repo  pub package flutter_proximiio_map
#
# The site has no versions.mjs, so the version is passed explicitly (--version)
# and the install block carries the package and its git source (--install).
#
# Output (default build/docs-bundle):
#   docs-bundle-<product>-<version>.tar.gz
#   docs-bundle-<product>-<version>.tar.gz.sha256
#   docs-bundle-<product>-<version>.tar.gz.minisig   (unless --no-sign)
#
# WHO SIGNS: only .github/workflows/docs-bundle.yml, on the medina self-hosted
# runner, with the fleet R4 key that lives there. The key is never on a laptop.
# On a laptop, run this with --no-sign as a preflight before tagging: a docs site
# that is not strict-clean then fails before the release instead of in CI.
#
# Usage:
#   scripts/export-docs-bundle.sh <product> <version> [--out <dir>] [--no-sign]
#                                 [--source <checkout>] [--changelog <file>]
#   scripts/export-docs-bundle.sh --refresh-exporter
#
# <product>           flutter-map
# <version>           the release version (= the git tag), e.g. 6.0.0-beta.1
# --no-sign           export + checksum only (preflight, dry runs). No .minisig.
# --source <dir>      export the docs of ANOTHER checkout of this repo (default:
#                     the one this script lives in). The workflow uses it to run
#                     today's tooling against an older tag's docs, which predate
#                     the vendored exporter (backfills).
# --changelog <file>  the CHANGELOG that dates the release (default <source>/CHANGELOG.md).
# --refresh-exporter  re-vendor scripts/vendor/export-docs-bundle.mjs from
#                     EXPORTER_PIN and rewrite EXPORTER_SHA256 below, then exit.
#
# THE EXPORTER IS VENDORED. scripts/vendor/export-docs-bundle.mjs is a byte copy
# of $EXPORTER_REPO:$EXPORTER_PATH at $EXPORTER_PIN, checked against
# EXPORTER_SHA256 before every run. It is vendored because the runner's
# GITHUB_TOKEN cannot read the private Partner Zone repo. To move the pin: bump
# EXPORTER_PIN, run --refresh-exporter (reads a local partner-zone checkout, or
# `gh api` with your own token), and commit the script + the .mjs together.
#
# Environment:
#   PARTNER_ZONE_DIR     --refresh-exporter only: a local proximiio-partner-zone
#                        checkout containing the pin (default /Volumes/ExtremeSSD/
#                        proximiio/proximiio-partner-zone); else `gh api`.
#   MINISIGN_SECRET_KEY  the R4 minisign secret key (default: minisign's own
#                        default, ~/.minisign/minisign.key). The fleet key is
#                        passwordless; when stdin is not a terminal minisign gets
#                        /dev/null, so a key that wants a password fails fast
#                        instead of hanging the runner.
#   MINISIGN_PUBLIC_KEY  optional; when set, the fresh signature is verified
#                        against it (`minisign -Vm`) before the script succeeds.
#                        The fleet pubkey is committed at deploy/minisign.pub.
#
set -euo pipefail

GROUP="Mobile SDKs"

# ── exporter pin (proximiio/proximiio-partner-zone) ───────────────────────
EXPORTER_PIN="0d269ee384b90308b3576af432d988adc356f32a"
EXPORTER_REPO="proximiio/proximiio-partner-zone"
EXPORTER_PATH="tools/export-docs-bundle.mjs"
EXPORTER_SHA256="0692c53a9cbf62b4092f1da85ad0de4763a32bc707fbf13d22ec40b59721650f"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -t 1 ]]; then C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RED=$'\033[31m'; C_BLU=$'\033[34m'; C_RST=$'\033[0m'
else C_GRN=; C_YEL=; C_RED=; C_BLU=; C_RST=; fi
step() { printf '%s==>%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '%s ok %s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YEL" "$C_RST" "$*"; }
die()  { printf '%serror%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }
# sha256sum on Linux (the runner), shasum on macOS.
sha256_of() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
sha256_check() {  # $1 = dir, $2 = .sha256 file ("<hex>  <name>")
  if command -v sha256sum >/dev/null; then ( cd "$1" && sha256sum -c --status "$2" )
  else ( cd "$1" && shasum -a 256 -c "$2" >/dev/null ); fi
}

VENDORED_EXPORTER="$SCRIPT_DIR/vendor/export-docs-bundle.mjs"

refresh_exporter() {
  local pz="${PARTNER_ZONE_DIR:-/Volumes/ExtremeSSD/proximiio/proximiio-partner-zone}"
  local tmp="$VENDORED_EXPORTER.tmp"
  mkdir -p "$(dirname "$VENDORED_EXPORTER")"
  step "Re-vendor $EXPORTER_REPO:$EXPORTER_PATH @ ${EXPORTER_PIN:0:7}"
  if [[ -d "$pz" ]] && git -C "$pz" cat-file -e "$EXPORTER_PIN^{commit}" 2>/dev/null; then
    git -C "$pz" show "$EXPORTER_PIN:$EXPORTER_PATH" > "$tmp"
    ok "read from local checkout $pz"
  else
    command -v gh >/dev/null || die "pin not in $pz and gh CLI not found — set PARTNER_ZONE_DIR to a checkout containing $EXPORTER_PIN"
    gh api -H 'Accept: application/vnd.github.raw' \
      "repos/$EXPORTER_REPO/contents/$EXPORTER_PATH?ref=$EXPORTER_PIN" > "$tmp" \
      || { rm -f "$tmp"; die "could not fetch $EXPORTER_PATH@$EXPORTER_PIN from $EXPORTER_REPO (gh auth status?)"; }
    ok "fetched from GitHub"
  fi
  [[ -s "$tmp" ]] || { rm -f "$tmp"; die "exporter is empty"; }
  mv "$tmp" "$VENDORED_EXPORTER"
  local sum; sum="$(sha256_of "$VENDORED_EXPORTER")"
  sed -i.bak -E "s/^EXPORTER_SHA256=\"[0-9a-f]*\"/EXPORTER_SHA256=\"$sum\"/" "$SCRIPT_DIR/export-docs-bundle.sh"
  rm -f "$SCRIPT_DIR/export-docs-bundle.sh.bak"
  ok "$VENDORED_EXPORTER sha256 $sum (EXPORTER_SHA256 updated) — commit both files together"
}

PRODUCT=""
VERSION=""
OUT=""
CHANGELOG=""
SIGN=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)       OUT="${2:?--out needs a value}"; shift 2 ;;
    --no-sign)   SIGN=0; shift ;;
    --source)    ROOT="$(cd "${2:?--source needs a value}" && pwd)"; shift 2 ;;
    --changelog) CHANGELOG="${2:?--changelog needs a value}"; shift 2 ;;
    --refresh-exporter) refresh_exporter; exit 0 ;;
    -h|--help)   grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          die "unknown flag: $1" ;;
    *)
      if   [[ -z "$PRODUCT" ]]; then PRODUCT="$1"
      elif [[ -z "$VERSION" ]]; then VERSION="$1"
      else die "unexpected extra argument: $1"; fi
      shift ;;
  esac
done

# ── per-product identity ──────────────────────────────────────────────────
case "$PRODUCT" in
  flutter-map)
    SITE="docs/site"; TITLE="Flutter Map"; PACKAGE="flutter_proximiio_map"
    GIT_URL="https://github.com/proximiio/flutter-proximiio-map"
    CHANGELOG="${CHANGELOG:-$ROOT/CHANGELOG.md}" ;;
  "") die "usage: $0 flutter-map <version> [--out <dir>] [--no-sign] [--source <checkout>] [--changelog <file>]" ;;
  *)  die "unknown product '$PRODUCT' (flutter-map)" ;;
esac
[[ -n "$VERSION" ]] || die "version required, e.g. $0 $PRODUCT 6.0.0-beta.1"
VERSION="${VERSION#v}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "'$VERSION' is not a version"
[[ -d "$ROOT/$SITE" ]] || die "no $SITE in $ROOT"
[[ -f "$CHANGELOG" ]] || die "no CHANGELOG at $CHANGELOG"
CHANGELOG="$(cd "$(dirname "$CHANGELOG")" && pwd)/$(basename "$CHANGELOG")"
OUT="${OUT:-$ROOT/build/docs-bundle}"

# ── toolchain ─────────────────────────────────────────────────────────────
command -v node >/dev/null || die "node not found (the exporter needs Node >= 22)"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
(( NODE_MAJOR >= 22 )) || die "node $(node --version) is too old — the exporter needs Node >= 22"
if [[ $SIGN -eq 1 ]]; then
  command -v minisign >/dev/null || die "minisign not found — or pass --no-sign for an unsigned export"
  if [[ -n "${MINISIGN_SECRET_KEY:-}" ]]; then
    [[ -f "$MINISIGN_SECRET_KEY" ]] || die "MINISIGN_SECRET_KEY=$MINISIGN_SECRET_KEY does not exist"
  else
    DEFAULT_KEY="${MINISIGN_CONFIG_DIR:-$HOME/.minisign}/minisign.key"
    [[ -f "$DEFAULT_KEY" ]] || die "no minisign key: set MINISIGN_SECRET_KEY to the R4 secret key (minisign's default $DEFAULT_KEY does not exist)"
  fi
fi

WORKTMP="$(mktemp -d "${TMPDIR:-/tmp}/export-docs-bundle.XXXXXX")"
trap 'rm -rf "$WORKTMP"' EXIT

# ── 1. the vendored exporter, checked against its pin ─────────────────────
step "Exporter $EXPORTER_REPO@${EXPORTER_PIN:0:7} (vendored)"
[[ -s "$VENDORED_EXPORTER" ]] || die "missing $VENDORED_EXPORTER — run $0 --refresh-exporter"
GOT_SHA="$(sha256_of "$VENDORED_EXPORTER")"
[[ "$GOT_SHA" == "$EXPORTER_SHA256" ]] \
  || die "$VENDORED_EXPORTER sha256 $GOT_SHA != EXPORTER_SHA256 $EXPORTER_SHA256 — it was edited by hand; run $0 --refresh-exporter"
ok "sha256 $GOT_SHA"

# ── 2. export, strict ─────────────────────────────────────────────────────
# bundle.json records the commit the docs came from: the release tag's commit
# when the tag exists, otherwise HEAD of the source checkout.
step "Export docs bundle $PRODUCT $VERSION from $SITE (--strict)"
COMMIT_ARGS=()
if TAG_COMMIT="$(git -C "$ROOT" rev-parse --verify --quiet "refs/tags/$VERSION^{commit}")"; then
  HEAD_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
  [[ "$TAG_COMMIT" == "$HEAD_COMMIT" ]] \
    || warn "HEAD (${HEAD_COMMIT:0:8}) is not tag $VERSION (${TAG_COMMIT:0:8}) — the docs are read from the working tree, not from the tag"
  COMMIT_ARGS=(--commit "$TAG_COMMIT")
else
  warn "bundle.json records HEAD of $ROOT as the source commit"
fi

# The exporter rejects a product id Partner Zone does not know before it reads the docs; say so
# here, so that failure is not taken for a docs problem.
grep -q "'$PRODUCT'" "$VENDORED_EXPORTER" \
  || die "product id \"$PRODUCT\" is not in the vendored exporter's product list yet — Partner Zone has to add it (coordination/inbox/proximiio-partner-zone), then re-vendor the exporter; the docs are not the problem"

BASE="docs-bundle-$PRODUCT-$VERSION.tar.gz"
mkdir -p "$OUT"
rm -f "$OUT/$BASE" "$OUT/$BASE.sha256" "$OUT/$BASE.minisig"
STAGE="$WORKTMP/out"
mkdir -p "$STAGE"
# The exporter writes the tarball BEFORE it applies --strict, so it always
# writes into a scratch dir and only a clean run is moved into $OUT.
if ! node "$VENDORED_EXPORTER" --site "$ROOT/$SITE" \
      --product "$PRODUCT" --group "$GROUP" --title "$TITLE" \
      --version "$VERSION" --changelog "$CHANGELOG" \
      --install "{\"pub\":\"$PACKAGE\",\"git\":\"$GIT_URL\",\"pin\":\"$VERSION\"}" \
      --out "$STAGE" --strict ${COMMIT_ARGS[@]+"${COMMIT_ARGS[@]}"}; then
  die "the docs bundle is not strict-clean (warnings above) — fix the docs"
fi
[[ -f "$STAGE/$BASE" ]] || die "exporter did not produce $BASE (got: $(ls "$STAGE" | tr '\n' ' '))"
[[ -f "$STAGE/$BASE.sha256" ]] || die "exporter did not produce $BASE.sha256"
mv "$STAGE/$BASE" "$STAGE/$BASE.sha256" "$OUT/"
sha256_check "$OUT" "$BASE.sha256" || die "$BASE does not match its .sha256"
ok "$OUT/$BASE"
ok "$OUT/$BASE.sha256"

# ── 3. sign (R4) ──────────────────────────────────────────────────────────
if [[ $SIGN -eq 0 ]]; then
  warn "--no-sign: no .minisig produced — this bundle cannot be ingested by Partner Zone"
  exit 0
fi
step "Sign with minisign${MINISIGN_SECRET_KEY:+ ($MINISIGN_SECRET_KEY)}"
SIGN_ARGS=(-S -m "$OUT/$BASE" -t "$BASE $PRODUCT $VERSION")
[[ -n "${MINISIGN_SECRET_KEY:-}" ]] && SIGN_ARGS+=(-s "$MINISIGN_SECRET_KEY")
# Non-interactive (the runner): a passwordless key signs; a key that asks for a
# password reads EOF and fails at once instead of hanging the job.
if [[ -t 0 ]]; then
  minisign "${SIGN_ARGS[@]}" || { rm -f "$OUT/$BASE.minisig"; die "minisign failed"; }
else
  minisign "${SIGN_ARGS[@]}" </dev/null || { rm -f "$OUT/$BASE.minisig"; die "minisign failed (a password-protected key cannot sign unattended)"; }
fi
[[ -s "$OUT/$BASE.minisig" ]] || die "minisign produced no $BASE.minisig"
if [[ -n "${MINISIGN_PUBLIC_KEY:-}" ]]; then
  minisign -V -q -m "$OUT/$BASE" -p "$MINISIGN_PUBLIC_KEY" || die "the fresh signature does not verify against $MINISIGN_PUBLIC_KEY"
  ok "signature verifies against $MINISIGN_PUBLIC_KEY"
fi
ok "$OUT/$BASE.minisig"
