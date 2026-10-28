# Handover: Slay the Stockfish v0.3 (for Claude Code)

Start a session with: *"Read CLAUDE.md, HANDOVER.md and docs/DECISIONS.md, then continue with the open items."*
`CLAUDE.md` has the tech rules and every check command; `docs/DECISIONS.md` is the source of truth for design
decisions (mirrored in Notion: Project Slay the Stockfish → Build decisions → v0.3 decision log).

## Where things stand

- Repo `~/slay-the-stockfish`, GitHub `philipheider-libra/slay-the-stockfish`, branch `main`, remote name
  **`github`** (not `origin`). Push straight to main; merging PRs is allowed. Commit and push after every
  finished feature.
- Never `git add -A`: `art/concepts/*.png` are untracked on purpose. Add the `.uid` file of every new script.
- Released: v0.2 (tag `slay-the-stockfish/v0.2`). v0.3 is finished on main but **not tagged or released**.
  Local builds of the current main: `dist/slay-the-stockfish/v0.3/` (mac universal `.app` zip + Windows zip,
  from `tools/package/package.sh v0.3`). The Windows smoke workflow has not run for v0.3.
- Checks on `7b29ae9`: `scripts/test.sh` rc 0 (pytest 15, parse gate 69 scripts, GUT 141/141 including
  `test_walling_arenas_shut_the_pocket`); seed-7 autoplay wins the whole run with no warnings.

## v0.3 commits (newest first)

| Commit | What |
| --- | --- |
| `ed6ce2d` | DECISIONS: muster, small early enemies, board stage, walling vs drops |
| `25d55ce` | Walling arenas (Burning Stakes, The Crow) shut the pocket for the fight instead of failing to load |
| `c0aece9` | Board stage: places slam onto the board; muster and formation edited on the 3D board |
| `6849d1a` | Run starts with the king and a 7-point draft; act-1 enemies start small and grow by row |
| `71025af` | Map node badges explain themselves on hover |
| `a3687f3` | Graft at the Bone Surgeon, autoplay grafts, affixes raise elite gold |
| `194b48e` / `7e21635` | Fusion (Graft); unlock keys for arenas and events |
| `9865329` | Lich's Phylactery (a run-ending fight starts over once) |
| `df776b5` / `8df7080` | Elite affixes; guardian signature arenas |
| `df9b167` | Ten arenas in all, walls that change per move, core raises on engine rejection, dev runs muted |
| `f2d2250` / `b061a91` / `3554f04` | Scarce gold; clock gold; readability (hover tooltip, nameplates) |

## The newest systems (read before touching them)

### Muster (run-start draft)
- `RunConfig`: `starting_army = [king]`, `draft_budget` 7, `draft_basics` (pawn, knight, bishop, rook, any
  number), `draft_specials` 2 one-of specials from `draft_special_tiers` [1, 2], `draft_leftover_gold` 3 per point.
- `RunState.draft` holds `points`, `specials`, `rolled`, `bought`. API: `draft_open`, `draft_points`,
  `draft_offers`, `can_draft`, `draft_buy`, `draft_refund`, `finish_draft`, `auto_draft` (autoplay, dev jumps).
  Difficulty removals lower the budget.
- Flow (`src/main.gd`): relic pick → `_show_draft()` → act intro → map. `_jump` auto-drafts for every
  `--screen` except `relic`/`draft`.
- Tests use `RunFixture.classic(seed, difficulty)` (`tests/run_fixture.gd`): a new run plus the old classic
  army with the draft closed. Use it instead of `Run.new_run` unless the test is about the draft.

### Small early enemies
- `ActDef.enemy_material_start` (act 1: 6): the material the encounter ratios apply to at row 0, rising
  linearly to Command at the guardian (`RunState.enemy_material`). Guardians and the boss always use Command.
- Act-1 layouts are small cores; `reinforcements` fill up to the target. Reinforcement squares next to the
  enemy king are skipped, so don't put entries there.

### Board stage (every recurring place happens over the board)
- `CameraRig.set_mode("stage")`: board on the left, panel docked right. `UiModal.docked()`: right-edge
  panel, no backdrop, clicks outside the panel reach the board.
- `BoardView.slam_place(kind)` / `lift_place()`: the prop `models/props/place_<kind>.glb` (shop, campfire,
  chest, shrine) drops onto the engine's half at `PLACE_AT` (0, 0, -2.6). Expo drop, squash and bounce, Fx
  `slam` dust ring + `debris`, flash, `impact` signal → camera shake, pieces hop (`_quake`), flickering
  OmniLights at the glb's `light_*` empties, `Fx.embers` over the campfire, sound `place_slam`.
- `main.gd`: `_stage(place)` / `_unstage()`. Shop and muster use `shop`, campfire `campfire`, treasure
  `chest`, events (and event-fight results) `shrine`. The map, fights, title, act intro and end lift it.
- Props: `tools/blender/world/places.py` (run `tools/blender/world/run.sh places.py 900`), materials by slot
  name; `wood`, `cloth`, `gold`, `fire` were added to `Mats.world` and to Blender `common.PALETTE`.
- Sound: `tools/audio/make_audio.py` `place_slam`; rebuild one sound with `tools/audio/build.sh --only place_slam`.

### Formation on the 3D board
- `src/ui/board_stage.gd` (`BoardStage`) replaced the 2D FormationModal. Click a piece, then a square on
  ranks 1-2 (move or swap; pawns stay off rank 1); bench and deploy in the panel. Every change goes straight
  to `Run.set_formation` / `Run.set_benched`. Draft mode (`setup(board, true)`) is the muster: offers in the
  panel, buys drop onto the board (`BoardView.present_drop`), a selected bought piece can be returned.
- Opened by the map's **Arrange** button (`MapScreen.arrange` → `_show_formation`) and `--screen=formation`.
- `--click=d1,c2` also works on `--screen=draft|formation` (squares only, not panel buttons).
- Tests: `tests/test_board_stage.gd`; `test_ui_fit.gd` checks the formation and muster panels.

### Walling arenas vs drops
- The engine rejects `wallingRule` together with `pieceDrops`. `FightController.setup` turns the pocket off
  for that fight on a walling arena and shows `_sealed_note` at `begin()`. Test: `test_walling_arenas_shut_the_pocket`.

## Open items (suggested next steps)

1. **Release v0.3:** run `scripts/test.sh`, the autoplay run and a few screenshots, then
   `tools/package/package.sh v0.3`, a draft release tagged `slay-the-stockfish/v0.3` with both zips, and
   `gh workflow run windows-smoke -f tag=slay-the-stockfish/v0.3`.
2. **Merchant stall silhouette:** from the stage camera it reads as a dark box with a red awning. Make it
   taller and more open (hanging wares, a sign, a lantern) in `places.py`, re-export, `--import`.
3. **Muster polish:** no hover tooltip on the board pieces outside fights; offers could show the move
   diagram like the shop cards; the act intro after the muster still uses the orbit camera.
4. **Reward screen** still uses the map camera and a centred modal (it isn't a recurring place, so this was
   left alone on purpose).
5. **Waiting on Philip:** ratings on the Notion arena review page (proposals: tweak The Ascent, which overlaps
   the Sanctuary Banner relic, and Burning Stakes, whose board fills too fast) and a real playtest (run length
   against 60 ± 15 min, scarce gold, the 7-point muster, act-1 difficulty). Autoplay is not balance data.

## Gotchas

- `G=/Applications/Godot.app/Contents/MacOS/Godot`. Run `$G --headless --path . --import` after adding
  assets or a new `class_name` script, or the parse gate and GUT won't find it.
- One GUT file: `$G --headless --path . --fixed-fps 60 --quit-after 500000000 -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gselect=test_board_stage.gd -gexit`.
- Don't edit files while `scripts/test.sh` runs; the run goes red for unrelated reasons.
- Fight-edit tests (Soul Exchange, Puppeteer's String, Soul Lantern) can fail when the machine is under heavy
  load; the same committed code passes on an idle machine.
- Inferred Variant types are parse errors (`var x := d["k"]` fails; write `var x: String = d["k"]`), also
  inside lambdas.
- The engine can silently reject a variant; the core raises `CoreError` now. If a rule "does nothing", probe
  the engine binary over UCI.
- Duck walling (The Crow) can't use a normal king: the arena sets `king = -`, `commoner = k`,
  `extinctionPieceTypes = kw`.
- pyffish costs about 2.7 ms per call; walling variants have about 640 legal moves at the start, so group by
  piece move when looping.
- `FightController._rebase` does not reset `walls`; tests set them by hand.
- Hover and click probes need window coordinates: `get_viewport().get_final_transform() * pos`.
- Dev runs are muted unless `--sound`. Never grep for `ERROR` to judge a run; exit leak lines are normal.
- `--shot-delay` counts from boot; the place slam lands about 1 s after boot on `--screen=shop`.
