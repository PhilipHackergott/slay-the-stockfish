# Slay the Stockfish

A 3D gothic chess roguelike. Build an army of bone and ivory pieces across one act, then beat Fairy-Stockfish at
full strength. Status: v0.1 MVP (one act, standard upgrade ladder, four relics).

## Play

1. Build the engine once: `chesscore/build_engine.sh`
2. Python sidecar: `uv venv chesscore/.venv -p 3.12 && uv pip install -p chesscore/.venv pyffish==0.0.90 pytest`
3. Open the folder in Godot 4.7.1 and press Play (or `godot --path .`).

Controls: left click selects and moves, right click cancels, right drag orbits, wheel zooms, F1 dev panel,
F12 screenshot.

## Develop

Rules for agents and all checks: `CLAUDE.md`. The next-game kit distilled from Felsenburg: `docs/kit/`.
