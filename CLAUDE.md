# Slay the Stockfish – project rules for coding agents

Slay the Stockfish is a 3D chess roguelike: build an army across one act (9 nodes: fights, an elite, campfires,
events), then beat Fairy-Stockfish at full strength. The army is the deck; every piece is a unit with id, XP, level,
lineage and losses for the whole run. Lose any fight (or your king) and the run ends.
Scope: v0.1 MVP per the "Chess Roguelike — MVP Handover". Decisions and their reasons: Notion "Project Slay the
Stockfish" → Build decisions (private to Philip). Kit and lessons from Felsenburg: `docs/kit/`.

## Tech
- Godot 4.7.1 (read `project.godot`, never guess), Forward+, GDScript with static types.
- Method parameters and signal arguments: untyped `Array`/`Dictionary` or `Packed*Array` (typed containers as
  parameters throw in 4.7). Inferred Variant types are errors here: annotate (`var x: String = d["k"]`).
- Expected problems: `push_warning` or a return value, never `push_error` (GUT fails on it and on engine warnings).
- **Chess rules live only in the chess core**, never in GDScript: `chesscore/server.py` (pyffish + Fairy-Stockfish,
  JSON lines over a pipe) via the `ChessCore` autoload (`await ChessCore.legal(...)` etc.). GDScript only tracks units
  per square (`UnitMap`) and presentation.
- **The engine plays fair:** every lasting rule (relics, custom pieces) goes into the fight's variant ini built by
  `VariantGen`. The player's king is the custom pseudo-royal `w:K` with `pieceValue w:1` (0 means "no override").
- Data-driven: pieces, encounters, relics, events and the run config are `.tres` under `data/`, loaded by `Content`.
- Run state (army, relics, map, seed) lives in the `Run` autoload; randomness only from `Run.rng` (seeded).

## Layout
- `src/core/` chess core client, FEN, unit map, variant generator, position edits.
- `src/data/` resource classes and the `Content` loader. `src/run/` run state, map, units.
- `src/fight/` `FightController` (rules flow, clock, XP, resign), `BoardView` (picking, markers, presenter
  coroutines), `PieceView` (glb + side materials + clips, procedural fallback).
- `src/world/` world (sky, lights, fog, candelabras, ruin), materials (`Mats`, swap by slot name), camera, fx.
- `src/ui/` all screens built in code with `UiKit`. `src/main.gd` is the game flow.
- `shaders/` bone, obsidian, board stone, glow, highlight, sky, round UI mask.
- `models/` glbs from Blender scripts in `tools/blender/` (pieces; world). Asset contract in those scripts' headers:
  metres, 1 m squares, a1 at (-3.5, -3.5), white at Blender -Y, origin at the base centre, slots `piece_body`,
  `piece_trim`, `piece_glow`; clips `move`, `leap`, `capture`, `drop`, `spawn`. Never rescale in the game.

## Setup
- Engine: `chesscore/build_engine.sh` (pinned commit). Python: `uv venv chesscore/.venv -p 3.12` then
  `uv pip install -p chesscore/.venv pyffish==0.0.90 pytest`.
- `$GODOT` = `/Applications/Godot.app/Contents/MacOS/Godot`.

## Checks (all before a commit)
- `scripts/test.sh` = pytest, import, parse gate, GUT. Green = rc 0 and GUT count > 0.
- Boot smoke: `$GODOT --headless --path . --quit-after 100000 -- --quit-after-boot` prints `STS BOOT OK core=ok`.
- Full run: `$GODOT --headless --path . --quit-after 50000000 -- --seed=7 --autoplay --speed=8 --quit-on-end` prints
  one `STS FIGHT` line per fight and `STS RUN END`, with no ERROR or WARNING lines.
- Screens (windowed only): `$GODOT --path . -- --screen=fight --seed=7 --relics=reliquary_bishop --shot=res://build/shots/x.png --quit-after-shot`
  (`--screen=title|relic|map|fight|elite|boss|reward|campfire|event|end`, `--autoplay` to play moves). Read the PNG.
 Dev runs (`--screen`, `--autoplay`, `--isolated`) are muted; add `--sound` to hear them.
- Input (windowed): `--click=e2,e4,b1` sends real mouse clicks to those squares 2.5 s apart (picking, selection, moves);
  pair it with `--shot-delay=12`.
- Headless runs frames uncapped: use `--quit-after-boot`/`--quit-on-end`, not small `--quit-after` values.
- Never grep for `ERROR` to judge a run; the engine prints leak lines at exit.
- Release: `tools/package/package.sh vX.Y`, upload the zips to a (draft) release tagged `slay-the-stockfish/vX.Y`,
  then `gh workflow run windows-smoke -f tag=slay-the-stockfish/vX.Y` on a clean Windows runner.

## Working style
- Small commits. Record every new design or build decision in Notion → Build decisions.
- Unclear design question: take the handover's proposal; if there is none, build the simplest data-switchable variant
  and record it.
