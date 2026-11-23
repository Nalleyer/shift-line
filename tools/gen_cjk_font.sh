#!/usr/bin/env bash
# ---------------------------------------------------------------
#  SHIFTLINE — build the embedded Chinese pixel font subset
#
#  Regenerates assets/fonts/shiftline-cjk.ttf from the open-source
#  Fusion Pixel Font (SIL OFL 1.1), plus tests/cjk_glyphs.lua used by
#  the i18n regression test. Run this after editing src/i18n/zh.lua.
#
#    ./run.sh --fonts            # via the launcher
#    tools/gen_cjk_font.sh       # directly
#
#  Set FONT_SRC=/path/to/fusion-pixel-12px-monospaced-zh_hans.ttf to
#  skip the 50 MB release download.
# ---------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

if [ "${1:-}" = "--subset-only" ]; then
  pyftsubset "$2" --text-file="$3" --output-file="$4.tmp" \
    --layout-features='' --no-ignore-missing-unicodes
  mv "$4.tmp" "$4"
  exit 0
fi

VERSION="2026.10.25"
ZIP_NAME="fusion-pixel-font-12px-monospaced-ttf-v${VERSION}.zip"
ZIP_URL="https://github.com/TakWolf/fusion-pixel-font/releases/download/${VERSION}/${ZIP_NAME}"

CACHE_ROOT="${XDG_CACHE_HOME:-$ROOT/.cache}"
CACHE="$CACHE_ROOT/fonts"
DEST="$ROOT/assets/fonts"
OUT="$DEST/shiftline-cjk.ttf"
CHARS="$CACHE/shiftline-chars.txt"
CHARS_LUA="$CACHE/cjk_glyphs.lua"
mkdir -p "$CACHE" "$DEST"

command -v node >/dev/null 2>&1 || { echo "node is required" >&2; exit 1; }

# 1. Every character the Chinese interface can draw.
node "$HERE/extract_i18n_chars.js" "$ROOT/src/i18n/zh.lua" "$CHARS" "$CHARS_LUA"

# 2. Locate the source face.
SRC="${FONT_SRC:-$CACHE/fusion-pixel-12px-monospaced-zh_hans.ttf}"
if [ ! -f "$SRC" ]; then
  ZIP="$CACHE/$ZIP_NAME"
  if [ ! -f "$ZIP" ]; then
    echo "[fonts] downloading Fusion Pixel 12px ..."
    command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
    curl -fL --retry 3 -o "$ZIP.part" "$ZIP_URL"
    mv "$ZIP.part" "$ZIP"
  fi
  command -v unzip >/dev/null 2>&1 || { echo "unzip is required" >&2; exit 1; }
  unzip -o -j "$ZIP" 'fusion-pixel-12px-monospaced-zh_hans.ttf' -d "$CACHE" >/dev/null
  SRC="$CACHE/fusion-pixel-12px-monospaced-zh_hans.ttf"
  unzip -o -j "$ZIP" 'OFL.txt' -d "$DEST" >/dev/null
  unzip -o "$ZIP" 'LICENSES/*' -d "$DEST" >/dev/null
fi
[ -f "$SRC" ] || { echo "[fonts] missing source font; set FONT_SRC" >&2; exit 1; }

# 3. Subset. Use an already-installed fonttools, or borrow it from nix.
if command -v pyftsubset >/dev/null 2>&1; then
  echo "[fonts] subsetting $SRC"
  pyftsubset "$SRC" --text-file="$CHARS" --output-file="$OUT.tmp" \
    --layout-features='' --no-ignore-missing-unicodes
  mv "$OUT.tmp" "$OUT"
elif command -v nix >/dev/null 2>&1; then
  echo "[fonts] subsetting via nix fonttools"
  XDG_CACHE_HOME="$CACHE_ROOT" nix shell nixpkgs#python3Packages.fonttools -c \
    bash "$HERE/gen_cjk_font.sh" --subset-only "$SRC" "$CHARS" "$OUT"
else
  echo "[fonts] pyftsubset not found (install fonttools, or nix)" >&2
  exit 1
fi

cp "$CHARS_LUA" "$ROOT/tests/cjk_glyphs.lua"
echo "[fonts] $(wc -c < "$OUT") bytes -> ${OUT#$ROOT/}"
