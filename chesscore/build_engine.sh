#!/usr/bin/env bash
# Builds the Fairy-Stockfish binary at a pinned commit into chesscore/bin/fairy-stockfish.
# Same build flags as the pyffish wheels (largeboards + all variants), so rules and engine agree.
set -euo pipefail
FSF_REPO="https://github.com/fairy-stockfish/Fairy-Stockfish.git"
FSF_COMMIT="${FSF_COMMIT:-9f778da667f6e07dae1e85d3e2ea204fc6dee94d}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/.engine-src"
ARCH="${ARCH:-apple-silicon}"

if [ ! -d "$SRC/.git" ]; then
  git clone --quiet "$FSF_REPO" "$SRC"
fi
cd "$SRC"
if [ -n "$FSF_COMMIT" ]; then
  git fetch --quiet origin
  git checkout --quiet "$FSF_COMMIT"
fi
echo "fairy-stockfish commit: $(git rev-parse HEAD)"
cd src
make -j8 build ARCH="$ARCH" largeboards=yes all=yes >/dev/null
mkdir -p "$HERE/bin"
cp stockfish "$HERE/bin/fairy-stockfish"
echo "built $HERE/bin/fairy-stockfish"
