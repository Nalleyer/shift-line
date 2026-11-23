#!/usr/bin/env bash
# ---------------------------------------------------------------
#  SHIFTLINE launcher
#    ./run.sh              play the game
#    ./run.sh --test       run the headless test suite
#    ./run.sh --assets     regenerate sprites / font map / audio
#    ./run.sh --fonts      rebuild the Chinese pixel-font subset
#    ./run.sh --package    build dist/shift-line.love
# ---------------------------------------------------------------
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HERE/.cache}"

need_love() {
  echo "Love2D 11.x not found and nix is unavailable." >&2
  echo "Install love (https://love2d.org) or nix, then run this script again." >&2
  exit 1
}

run_tool() { # run_tool <nixpkgs-pkg> <cmd...>
  local pkg="$1"; shift
  if command -v "$1" >/dev/null 2>&1; then
    "$@"
  elif command -v nix >/dev/null 2>&1; then
    nix shell "nixpkgs#$pkg" -c "$@"
  else
    return 127
  fi
}

case "${1:-}" in
  --test)
    shift
    run_tool luajit luajit tests/run_all.lua "$@" || { echo "(tests failed; LuaJIT or nix is required)" >&2; exit 1; }
    ;;
  --assets)
    command -v node >/dev/null 2>&1 || { echo "node is required to regenerate assets" >&2; exit 1; }
    node tools/gen_assets.js
    node tools/gen_audio.js
    ;;
  --fonts)
    command -v node >/dev/null 2>&1 || { echo "node is required to extract the character set" >&2; exit 1; }
    ./tools/gen_cjk_font.sh
    ;;
  --package)
    mkdir -p dist
    rm -f dist/shift-line.love
    run_tool zip zip -9 -r dist/shift-line.love conf.lua main.lua src assets || { echo "(zip or nix is required)" >&2; exit 1; }
    echo "Built dist/shift-line.love"
    ;;
  --help|-h)
    sed -n "2,7p" "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    run_tool love love . "$@" || need_love
    ;;
esac
