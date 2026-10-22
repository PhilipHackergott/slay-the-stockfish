#!/usr/bin/env bash
# Rebuilds every sound in assets/audio/ (see make_audio.py for options).
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x .venv/bin/python ]; then
	uv venv .venv --python 3.12
	uv pip install --python .venv/bin/python -r requirements.txt
fi
exec .venv/bin/python make_audio.py "$@"
