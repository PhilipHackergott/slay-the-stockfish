#!/bin/sh
# Rebuild board, candelabra and environment glbs, verify the contract, render the previews.
# Usage: tools/blender/world/build_all.sh [--fast]   (--fast = half-res previews without fog)
# Logs: build/blender/world/<script>.log; stops at the first failing step.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
LOGS="$HERE/../../../build/blender/world"
FAST="$1"

step() {
    label="$1"; shift
    log="$LOGS/$(basename "$1" .py).log"
    echo "== $label"
    if ! "$HERE/run.sh" "$@" > "$log" 2>&1; then
        tail -40 "$log"
        echo "== FAILED: $label (log: $log)"
        exit 1
    fi
}

step "board.glb" board.py 900;              grep '^\[world\]' "$LOGS/board.log"
step "candelabra.glb" candelabra.py 600;    grep '^\[world\]' "$LOGS/candelabra.log"
step "environment.glb" environment.py 1500; grep '^\[world\]' "$LOGS/environment.log"
step "verify" verify.py 600;                sed -n '/^=== /,$p' "$LOGS/verify.log" | grep -v ' | INFO: ' | grep -v '^Blender'
step "previews" preview.py 900 -- game orbit close back side under $FAST; grep '^\[world\]' "$LOGS/preview.log"
step "props" props.py 600 -- $FAST;         grep '^\[world\]' "$LOGS/props.log"
echo "== done"
