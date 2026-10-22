#!/usr/bin/env bash
# Builds the release: Godot exports (presets "macOS", "Windows Desktop" in export_presets.cfg) plus the bundled
# chess core runtime (tools/package/build_runtime.sh), zipped into dist/slay-the-stockfish/<version>/:
#   slay-the-stockfish-<version>-macos.zip    Slay the Stockfish.app (universal, ad-hoc signed, core in Contents/Resources)
#   slay-the-stockfish-<version>-windows.zip  Slay the Stockfish/ (exe, pck, chesscore/ next to the exe)
# Then unzips the mac build into a temp dir and boots it headless from /tmp with a clean environment (no source tree,
# no STS_* overrides), natively and under Rosetta: each must print "STS BOOT OK core=ok".
# Needs rendering/textures/vram_compression/import_etc2_astc=true in project.godot (Godot refuses arm64 exports
# without it) and the chess core resolver in src/core/chess_core.gd (core_command()).
# usage: tools/package/package.sh <version, e.g. v0.1> [--no-smoke]
# env:   GODOT (default /Applications/Godot.app/Contents/MacOS/Godot), PROJECT_DIR (default: this repo)
set -euo pipefail

VERSION="${1:?usage: tools/package/package.sh <version, e.g. v0.1> [--no-smoke]}"
SMOKE=1; [ "${2:-}" = "--no-smoke" ] && SMOKE=0
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="$(cd "${PROJECT_DIR:-$REPO}" && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
GODOT_VERSION="4.7.1.stable"
NAME="Slay the Stockfish"
EXPORT="$REPO/build/export"
RUNTIME="$REPO/build/runtime"
DIST="$REPO/dist/slay-the-stockfish/$VERSION"
APP="$EXPORT/macos/$NAME.app"
WIN="$EXPORT/windows/$NAME"
MAC_ZIP="$DIST/slay-the-stockfish-$VERSION-macos.zip"
WIN_ZIP="$DIST/slay-the-stockfish-$VERSION-windows.zip"

log() { printf '== %s\n' "$*"; }
die() { printf 'PACKAGE FAILED: %s\n' "$*" >&2; exit 1; }

case "$("$GODOT" --version)" in "$GODOT_VERSION".*) ;; *) die "need Godot $GODOT_VERSION at $GODOT" ;; esac
TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/$GODOT_VERSION"
[ -f "$TEMPLATES/macos.zip" ] && [ -f "$TEMPLATES/windows_release_x86_64.exe" ] || die "export templates missing: $TEMPLATES"
[ "$PROJECT_DIR" = "$REPO" ] || cp "$REPO/export_presets.cfg" "$PROJECT_DIR/export_presets.cfg"

log "runtime"
"$REPO/tools/package/build_runtime.sh" macos-universal windows-x64

export_preset() { # export_preset <preset> <path>
  log "export $1 -> ${2#"$REPO"/}"
  "$GODOT" --headless --path "$PROJECT_DIR" --export-release "$1" "$2" >"$EXPORT/export-${1// /_}.log" 2>&1 \
    || { tail -30 "$EXPORT/export-${1// /_}.log" >&2; die "Godot export '$1' failed (log: $EXPORT/export-${1// /_}.log)"; }
}

rm -rf "$EXPORT/macos" "$EXPORT/windows" && mkdir -p "$EXPORT/macos" "$WIN"
log "import"
"$GODOT" --headless --path "$PROJECT_DIR" --import >"$EXPORT/import.log" 2>&1 || true
export_preset "macOS" "$APP"
export_preset "Windows Desktop" "$WIN/$NAME.exe"
[ -x "$APP/Contents/MacOS/$NAME" ] || die "no mac binary in $APP"
[ -f "$WIN/$NAME.exe" ] && [ -f "$WIN/$NAME.pck" ] || die "no Windows exe/pck in $WIN"

log "mac: runtime -> Contents/Resources/chesscore, ad-hoc signing"
ditto "$RUNTIME/macos-universal/chesscore" "$APP/Contents/Resources/chesscore"
xattr -cr "$APP"
find "$APP/Contents/Resources/chesscore" -type f -print0 | while IFS= read -r -d '' f; do
  case "$(file -b "$f")" in Mach-O*) codesign --force -s - "$f" 2>/dev/null || die "codesign $f" ;; esac
done
codesign --force --deep -s - "$APP" 2>/dev/null || die "codesign $APP"
codesign --verify --deep --strict "$APP" || die "codesign verification failed"

log "windows: runtime -> chesscore/ next to the exe"
cp -R "$RUNTIME/windows-x64/chesscore" "$WIN/chesscore"

log "zip -> ${DIST#"$REPO"/}"
mkdir -p "$DIST"
[ -f "$REPO/dist/.gitignore" ] || echo "*" >"$REPO/dist/.gitignore"
rm -f "$MAC_ZIP" "$WIN_ZIP"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$MAC_ZIP"
(cd "$EXPORT/windows" && zip -qry -X "$WIN_ZIP" "$NAME")
(cd "$DIST" && shasum -a 256 "$(basename "$MAC_ZIP")" "$(basename "$WIN_ZIP")" >SHA256SUMS)

if [ "$SMOKE" = 1 ]; then
  tmp="$(mktemp -d /tmp/sts-smoke.XXXXXX)"
  ditto -x -k "$MAC_ZIP" "$tmp"
  archs="arm64"; arch -x86_64 /usr/bin/true 2>/dev/null && archs="arm64 x86_64"
  for a in $archs; do
    log "smoke ($a): unzipped mac build, clean env, run from /tmp"
    out="$(cd /tmp && env -i HOME="$HOME" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" perl -e 'alarm 180; exec @ARGV' \
      arch "-$a" "$tmp/$NAME.app/Contents/MacOS/$NAME" --headless -- --quit-after-boot 2>&1 || true)"
    echo "$out" | grep "STS BOOT" || true
    echo "$out" | grep -q "STS BOOT OK core=ok" || { echo "$out" | tail -20 >&2; die "mac boot smoke $a (build kept in $tmp)"; }
  done
  rm -rf "$tmp"
fi

log "done"
(cd "$DIST" && ls -lh ./*.zip | awk '{print "   " $5 "  " $NF}' && cat SHA256SUMS)
