#!/bin/sh
# Run one world script headless with a hard timeout: run.sh <script.py> [timeout_s] [-- args]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
SCRIPT="$1"; shift
LIMIT="${1:-900}"; [ $# -gt 0 ] && shift
mkdir -p "$HERE/../../../build/blender/world"
exec perl -e 'alarm shift; exec @ARGV' "$LIMIT" \
  "$BLENDER" --background --factory-startup --python "$HERE/$SCRIPT" "$@"
