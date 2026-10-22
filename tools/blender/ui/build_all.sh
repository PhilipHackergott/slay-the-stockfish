#!/usr/bin/env bash
# Rebuilds the UI texture kit: Blender renders (build/ui/raw) -> post (assets/ui/kit + kit.json) -> previews.
#   tools/blender/ui/build_all.sh [group ...]     (no args = everything; groups are the @group names in build_ui.py)
# Env: BLENDER (default /Applications/Blender.app/Contents/MacOS/Blender), UI_TIMEOUT (seconds, default 1200).
set -euo pipefail
cd "$(dirname "$0")/../../.."
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
VENV=build/ui/.venv
LOG=build/ui/build_ui.log
mkdir -p build/ui/raw assets/ui/kit
t0=$(date +%s)

if [ ! -x "$VENV/bin/python" ]; then
  uv venv "$VENV" -p 3.12 -q
  uv pip install -q -p "$VENV" pillow numpy
fi

echo "[ui] blender render -> $LOG"
if ! perl -e 'alarm shift; exec @ARGV' "${UI_TIMEOUT:-1200}" "$BLENDER" --background --factory-startup \
    --python-exit-code 1 --python tools/blender/ui/build_ui.py -- "$@" >"$LOG" 2>&1; then
  tail -30 "$LOG"
  echo "[ui] blender FAILED (see $LOG)"
  exit 1
fi
grep '^\[ui\]' "$LOG" | tail -1

# post: groups render several files, so always rebuild every kit file from the raws
"$VENV/bin/python" tools/blender/ui/post.py | tail -1
"$VENV/bin/python" tools/blender/ui/compose.py
echo "[ui] done in $(( $(date +%s) - t0 ))s"
