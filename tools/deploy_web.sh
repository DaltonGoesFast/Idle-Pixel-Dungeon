#!/usr/bin/env bash
# DECISIONS #196: export the browser build and publish it to the gh-pages branch (GitHub Pages).
# Usage: tools/deploy_web.sh [--no-push]   (run from a clean checkout of the commit to publish)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SRC_SHA="$(git rev-parse --short HEAD)"
VER="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
OUT="builds/web"
rm -rf "$OUT"; mkdir -p "$OUT"
"$GODOT" --headless --path . --export-release Web "$OUT/index.html"
test -s "$OUT/index.wasm" && test -s "$OUT/index.pck"
touch "$OUT/.nojekyll"
[ "${1:-}" = "--no-push" ] && { echo "Exported to $OUT"; exit 0; }
REMOTE="$(git remote get-url origin)"
TMP="$(mktemp -d)"
if git ls-remote --exit-code --heads origin gh-pages >/dev/null; then
  git clone -q --depth 1 --branch gh-pages "$REMOTE" "$TMP"
else
  git init -q "$TMP" && git -C "$TMP" checkout -q --orphan gh-pages && git -C "$TMP" remote add origin "$REMOTE"
fi
find "$TMP" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -a "$OUT"/. "$TMP"/
git -C "$TMP" add -A
git -C "$TMP" commit -q -m "Publish web build v$VER ($SRC_SHA)" || { echo "No changes"; exit 0; }
git -C "$TMP" push -q origin gh-pages
echo "Published v$VER ($SRC_SHA) to gh-pages"
