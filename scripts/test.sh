#!/usr/bin/env bash
# usage: scripts/test.sh [extra GUT args, e.g. -gselect=test_unit_map]
# green = pytest rc 0 AND parse gate rc 0 AND GUT rc 0 AND the JUnit report counts > 0 tests
# (GUT exits 0 with zero tests).
set -euo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(git rev-parse --show-toplevel)"
chesscore/.venv/bin/python -m pytest -q chesscore/tests || { echo "PYTEST FAILED"; exit 1; }
"$GODOT" --headless --path . --import --quit-after 600 >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://scripts/check_parse.gd --quit-after 300 || { echo "PARSE GATE FAILED"; exit 1; }
mkdir -p build/test-results
xml="build/test-results/gut.xml"; rm -f "$xml"
rc=0
"$GODOT" --headless --path . --fixed-fps 60 --quit-after 5000000 -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file="res://$xml" "$@" || rc=$?
n="$(grep -o 'tests="[0-9]*"' "$xml" 2>/dev/null | head -1 | tr -dc 0-9 || true)"
echo "TESTS rc=$rc count=${n:-0}"
[[ $rc -eq 0 && "${n:-0}" -gt 0 ]]
