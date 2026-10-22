#!/usr/bin/env bash
# Builds the self-contained chess core runtimes that ship with the exported game (no installed Python needed):
#   build/runtime/macos-arm64/chesscore/      python/ (CPython 3.12 + pyffish), server.py, core.py, bin/fairy-stockfish
#   build/runtime/macos-x86_64/chesscore/     same for Intel Macs
#   build/runtime/macos-universal/chesscore/  both merged with lipo (what package.sh ships: the Godot template is universal)
#   build/runtime/windows-x64/chesscore/      python/ (python.exe + pyffish + MSVC C++ runtime), server.py, core.py,
#                                             bin/fairy-stockfish.exe (cross-compiled with mingw-w64)
# usage: tools/package/build_runtime.sh [macos-arm64|macos-x86_64|macos-universal|windows-x64 ...]
#        (default: macos-universal windows-x64)
# Needs Xcode command line tools, git, curl; macos-x86_64 smoke needs Rosetta; windows-x64 needs `brew install mingw-w64`.
# Every download is pinned by URL + sha256 (cache: build/runtime/_cache); engine builds live in build/runtime/_work.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$REPO/build/runtime"
CACHE="$OUT/_cache"
WORK="$OUT/_work"
SMOKE="$REPO/tools/package/smoke_core.py"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

PY_VERSION="3.12.15"
PBS="https://github.com/astral-sh/python-build-standalone/releases/download/20261021"
PY_arm64="$PBS/cpython-3.12.15%2B20261021-aarch64-apple-darwin-install_only_stripped.tar.gz"
PY_arm64_SHA="7b8d00b751db21cea87dc551a8f8165147c5fbc5251d5537d7e5497dde00a219"
PY_x86_64="$PBS/cpython-3.12.15%2B20261021-x86_64-apple-darwin-install_only_stripped.tar.gz"
PY_x86_64_SHA="f12e0504397683d6be0745ffd4c39ef45a455cec169adf35c628840d06133773"
PY_WINDOWS="$PBS/cpython-3.12.15%2B20261021-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"
PY_WINDOWS_SHA="aac5d331fc3307343f95928fdbea4583f0d53973d08c7e1d081884fbd229a0e1"

PYPI="https://files.pythonhosted.org/packages"
PYFFISH_VERSION="0.0.90"
PYFFISH_arm64="$PYPI/58/81/995b0b7ba4c5889a1c45d95c007881b0b8808730271438c8b3277c7f6f7b/pyffish-0.0.90-cp312-cp312-macosx_11_0_arm64.whl"
PYFFISH_arm64_SHA="8158829fec276102016dc81b5083b161bd566b13d0c3b4f04929ff242ed99885"
PYFFISH_x86_64="$PYPI/d3/2d/3cf385901be6438fae0c9fb7141fcb615f339e15075678108cd2c867face/pyffish-0.0.90-cp312-cp312-macosx_10_14_x86_64.whl"
PYFFISH_x86_64_SHA="ab222af699467d1729369a9aa5e1162fa2ef24c86ba4460e3b3d4bc5e601cf3b"
PYFFISH_WINDOWS="$PYPI/5c/11/d5e82ef34784d11eb0d5e2de09a101391390ebd507b70e47ba387925bc51/pyffish-0.0.90-cp312-cp312-win_amd64.whl"
PYFFISH_WINDOWS_SHA="53e6e77e654ef6b0518ded6b67cb55d9b64cc6b5173c8b74612a7a9f0faea5f5"
# pyffish's .pyd imports MSVCP140.dll, which CPython does not ship. These are Microsoft's signed redistributable
# DLLs (VC++ 14.51), packaged as a wheel by Christoph Gohlke; we only copy the DLLs next to python.exe.
MSVC_RUNTIME="$PYPI/98/33/be9ef68901200813fc174a06758b4ae48ca4eb58fa783280dd879d5fd048/msvc_runtime-14.51.36231-cp312-cp312-win_amd64.whl"
MSVC_RUNTIME_SHA="89f70d1a37bb64164cdb09d02dd82d6b1400e1310be2995b4ed5a9f23efe2222"

FSF_REPO="https://github.com/fairy-stockfish/Fairy-Stockfish.git"
FSF_COMMIT="$(sed -n 's/^FSF_COMMIT="\${FSF_COMMIT:-\([0-9a-f]\{40\}\)}"$/\1/p' "$REPO/chesscore/build_engine.sh")"
[ -n "$FSF_COMMIT" ] || { echo "could not read the pinned FSF_COMMIT from chesscore/build_engine.sh" >&2; exit 1; }
FSF_FLAGS="largeboards=yes all=yes"
ENGINE_arm64="ARCH=apple-silicon"
ENGINE_x86_64="ARCH=x86-64-modern"

log() { printf '== %s\n' "$*"; }
die() { printf 'RUNTIME FAILED: %s\n' "$*" >&2; exit 1; }

fetch() { # fetch <url> <sha256>: prints the verified cached file
  local file="$CACHE/$(basename "$1")"
  mkdir -p "$CACHE"
  if [ ! -f "$file" ] || ! echo "$2  $file" | shasum -a 256 -c - >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$file.part" "$1"
    echo "$2  $file.part" | shasum -a 256 -c - >/dev/null || { rm -f "$file.part"; die "sha256 mismatch: $1"; }
    mv "$file.part" "$file"
  fi
  echo "$file"
}

engine() { # engine <name> <make args...>: builds the pinned commit once per target, prints the binary path
  local name="$1"; shift
  local src="$WORK/fsf-$name" bin="$WORK/out/$name" stamp="$FSF_COMMIT $FSF_FLAGS $*"
  if [ -f "$bin" ] && [ "$(cat "$bin.stamp" 2>/dev/null)" = "$stamp" ]; then echo "$bin"; return; fi
  if [ ! -d "$src/.git" ]; then
    local origin="$FSF_REPO"
    [ -d "$REPO/chesscore/.engine-src/.git" ] && origin="$REPO/chesscore/.engine-src"
    git clone --quiet "$origin" "$src" >&2
  fi
  if ! git -C "$src" checkout --quiet "$FSF_COMMIT" 2>/dev/null; then
    git -C "$src" fetch --quiet "$FSF_REPO" "$FSF_COMMIT" >&2
    git -C "$src" checkout --quiet "$FSF_COMMIT"
  fi
  [ "$(git -C "$src" rev-parse HEAD)" = "$FSF_COMMIT" ] || die "engine checkout is not $FSF_COMMIT"
  make -C "$src/src" clean >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  make -C "$src/src" -j"$JOBS" build $FSF_FLAGS "$@" >"$WORK/$name.build.log" 2>&1 \
    || { tail -20 "$WORK/$name.build.log" >&2; die "engine build failed, see $WORK/$name.build.log"; }
  mkdir -p "$WORK/out"
  local exe="$src/src/stockfish"; [ -f "$exe.exe" ] && exe="$exe.exe"
  cp "$exe" "$bin"
  echo "$stamp" >"$bin.stamp"
  echo "$bin"
}

prune_python() { # prune_python <python dir> <stdlib dir>: drops tests, GUI, pip, headers, caches; empties site-packages
  local py="$1" lib="$2"
  rm -rf "$lib"/{test,idlelib,tkinter,turtledemo,ensurepip,lib2to3,pydoc_data,turtle.py}
  rm -rf "$lib/site-packages" && mkdir -p "$lib/site-packages"
  find "$py" -type d -name __pycache__ -prune -exec rm -rf {} +
  find "$py" -type f \( -name '_test*.so' -o -name '_test*.pyd' -o -name '_ctypes_test*' -o -name 'xxlimited*' \
    -o -name '_xxtestfuzz*' -o -name '_tkinter*' -o -name '*.pdb' \) -delete
}

common_files() { # common_files <chesscore dir> <engine name>
  cp "$REPO/chesscore/server.py" "$REPO/chesscore/core.py" "$1/"
  mkdir -p "$1/licenses"
  cp "$WORK/fsf-$2/Copying.txt" "$1/licenses/fairy-stockfish-COPYING.txt"
}

manifest() { # manifest <chesscore dir> <target> <python urls> <pyffish urls> [extra lines]
  local dir="$1" target="$2" py="$3" wheel="$4"; shift 4
  {
    echo "Slay the Stockfish chess core runtime ($target), built $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "python      CPython $PY_VERSION (python-build-standalone, PSF license) $py"
    echo "pyffish     $PYFFISH_VERSION (GPL-3.0) $wheel"
    echo "engine      Fairy-Stockfish $FSF_COMMIT $FSF_FLAGS (GPL-3.0, source: $FSF_REPO)"
    for line in "$@"; do echo "$line"; done
  } >"$dir/RUNTIME.txt"
}

build_macos() { # build_macos <arm64|x86_64>
  local a="$1" dir="$OUT/macos-$1/chesscore" py lib
  local py_url="PY_$a" py_sha="PY_${a}_SHA" whl_url="PYFFISH_$a" whl_sha="PYFFISH_${a}_SHA" make_args="ENGINE_$a"
  log "macos-$a: python $PY_VERSION"
  rm -rf "$OUT/macos-$a" && mkdir -p "$dir/bin"
  tar -xzf "$(fetch "${!py_url}" "${!py_sha}")" -C "$dir"
  py="$dir/python"; lib="$py/lib/python3.12"
  prune_python "$py" "$lib"
  # python3.12 is statically linked; nothing loads libpython3.12.dylib (it is only for embedding).
  rm -rf "$py/include" "$py/share" "$py/lib/pkgconfig" "$py/lib"/{itcl,tcl,tk,thread}* "$py/lib"/libtcl* \
    "$py/lib/libpython3.12.dylib" "$lib"/config-3.12-*
  find "$py/bin" -mindepth 1 ! -name python ! -name python3 ! -name python3.12 -exec rm -f {} +
  log "macos-$a: pyffish $PYFFISH_VERSION"
  unzip -q "$(fetch "${!whl_url}" "${!whl_sha}")" -d "$lib/site-packages"
  log "macos-$a: fairy-stockfish $FSF_COMMIT"
  cp "$(engine "macos-$a" "${!make_args}")" "$dir/bin/fairy-stockfish"
  common_files "$dir" "macos-$a"
  manifest "$dir" "macos-$a" "${!py_url}" "${!whl_url}"
  arch "-$a" "$py/bin/python3" -E -s -B "$SMOKE" "$dir"
}

build_macos_universal() {
  local arm="$OUT/macos-arm64/chesscore" x64="$OUT/macos-x86_64/chesscore" dir="$OUT/macos-universal/chesscore"
  build_macos arm64
  build_macos x86_64
  log "macos-universal: lipo arm64 + x86_64"
  diff <(cd "$arm" && find . ! -name RUNTIME.txt | sort) <(cd "$x64" && find . ! -name RUNTIME.txt | sort) >&2 \
    || die "arm64 and x86_64 trees differ"
  rm -rf "$OUT/macos-universal" && mkdir -p "$OUT/macos-universal" && ditto "$arm" "$dir"
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    case "$(file -b "$f")" in Mach-O*) lipo -create "$arm/$rel" "$x64/$rel" -output "$f" ;; esac
  done < <(find "$dir" -type f -print0)
  manifest "$dir" macos-universal "$PY_arm64 $PY_x86_64" "$PYFFISH_arm64 $PYFFISH_x86_64"
  for a in arm64 x86_64; do arch "-$a" "$dir/python/bin/python3" -E -s -B "$SMOKE" "$dir"; done
}

build_windows_x64() {
  local dir="$OUT/windows-x64/chesscore" py lib tmp deps
  command -v x86_64-w64-mingw32-c++ >/dev/null || die "windows-x64 needs mingw-w64: brew install mingw-w64"
  log "windows-x64: python $PY_VERSION"
  rm -rf "$OUT/windows-x64" && mkdir -p "$dir/bin"
  tar -xzf "$(fetch "$PY_WINDOWS" "$PY_WINDOWS_SHA")" -C "$dir"
  py="$dir/python"; lib="$py/Lib"
  prune_python "$py" "$lib"
  rm -rf "$py/tcl" "$py/include" "$py/libs" "$py/Scripts" "$py/DLLs"/{tcl,tk}86t.dll
  log "windows-x64: pyffish $PYFFISH_VERSION + MSVC C++ runtime"
  unzip -q "$(fetch "$PYFFISH_WINDOWS" "$PYFFISH_WINDOWS_SHA")" -d "$lib/site-packages"
  tmp="$WORK/msvc-runtime" && rm -rf "$tmp" && mkdir -p "$tmp"
  unzip -q "$(fetch "$MSVC_RUNTIME" "$MSVC_RUNTIME_SHA")" -d "$tmp"
  cp "$tmp"/msvc_runtime-*.data/data/msvcp140.dll "$tmp"/msvc_runtime-*.data/data/Scripts/vcruntime140.dll \
    "$tmp"/msvc_runtime-*.data/data/Scripts/vcruntime140_1.dll "$py/"
  log "windows-x64: fairy-stockfish $FSF_COMMIT (mingw-w64, x86-64-modern, static)"
  # KERNEL=Linux selects the Makefile's mingw cross-compile branch (x86_64-w64-mingw32-c++, -static, LTO).
  cp "$(engine windows-x64 ARCH=x86-64-modern COMP=mingw KERNEL=Linux)" "$dir/bin/fairy-stockfish.exe"
  x86_64-w64-mingw32-strip "$dir/bin/fairy-stockfish.exe"
  common_files "$dir" windows-x64
  cp "$tmp"/msvc_runtime-*.dist-info/licenses/LICENSE "$dir/licenses/msvc-runtime-LICENSE.txt"
  manifest "$dir" windows-x64 "$PY_WINDOWS" "$PYFFISH_WINDOWS" \
    "msvc        msvcp140.dll + vcruntime140*.dll 14.51.36231 (Microsoft redistributable) $MSVC_RUNTIME"
  deps="$(x86_64-w64-mingw32-objdump -p "$dir/bin/fairy-stockfish.exe" | sed -n 's/.*DLL Name: //p' | tr '\n' ' ')"
  log "windows-x64: fairy-stockfish.exe imports: $deps"
  case "$deps" in *libstdc++*|*libgcc*|*libwinpthread*) die "engine is not static: $deps" ;; esac
}

for t in ${*:-macos-universal windows-x64}; do
  case "$t" in
    macos-arm64) build_macos arm64 ;;
    macos-x86_64) build_macos x86_64 ;;
    macos-universal) build_macos_universal ;;
    windows-x64) build_windows_x64 ;;
    *) die "unknown target $t (macos-arm64, macos-x86_64, macos-universal, windows-x64)" ;;
  esac
  log "$t: $(du -sh "$OUT/$t/chesscore" | cut -f1) in build/runtime/$t/chesscore"
done
