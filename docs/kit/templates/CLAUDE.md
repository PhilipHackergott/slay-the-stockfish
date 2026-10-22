# <GAME> – project rules for coding agents

<GAME> is <one-paragraph pitch: core loop with numbers, win/lose condition>. Vision, pillars, references and the
decisions table: `docs/VISION.md`. Look: `docs/ART_BIBLE.md`. Current goal: <milestone> per `docs/<PLAN>.md`.
Contracts: `src/core/contracts/*.gd` (documented in code). Ids, tags, stats, streams, commands: `docs/CONVENTIONS.md`.
Known pitfalls: `docs/PITFALLS.md` (append, don't rewrite).

## Tech
- Real 3D world. Godot 4.x (read the version from `project.godot`, never guess). GDScript with static types.
- Method parameters and signal arguments: untyped `Array`/`Dictionary` or `Packed*Array` (typed containers as
  parameters throw runtime errors in 4.7). Return types and exported fields may be typed; write typed fields with
  `.assign()`.
- Expected problems: `push_warning` or a return value, never `push_error`. GUT fails a test on `push_error` **and on
  any engine ERROR or WARNING** (navigation, physics). Navmesh edge-merge warnings are off in `project.godot`.
- Never call `Input.get_joy_guid`/`get_joy_name` on a pad that `get_connected_joypads()` doesn't list (engine error).
- Register dev commands as methods, not as lambdas that don't capture `self` (`unregister_owner` can't remove them).
- Identifiers, files, signals: English. Comments and docs: short.
- **Data-driven:** all content is a custom Resource (`.tres`) under `data/`. No gameplay numbers in code except defaults.
- **Tags and modifiers:** defs carry `tags: Array[StringName]`; stats are read through `Modifiers.resolve(def, &"stat")`.
- **Determinism:** randomness only from seeded streams (`RNG.stream(&"<system>")`); same seed, same map, same waves.
- **Input:** game logic reads `Players.get_player(id).input`, never `Input.*`.
- **Services:** systems talk through `Services.*`, EventBus, GameState, ContentDB, Modifiers, Players, Inspect,
  DevConsole and DevOverlays only. ui and devtools never call `Services.*`.
- **DevTools are mandatory:** every system registers its debug commands and metrics and is testable headless.

## Runtime and performance (`docs/PERFORMANCE.md`)
- Gameplay runs only in the 20 Hz tick (`_physics_process` or physics timers `create_timer(t, false, true)`), never
  `Time.get_ticks*`. State every rate and budget per second; convert with `Engine.physics_ticks_per_second`. Tests
  wait in game seconds (`wait_game_seconds`). Moved visuals use physics interpolation; snaps call
  `reset_physics_interpolation()`; set it off on each `SubViewport`.
- Register every periodic system with `TickScheduler` (rate, offset, budget, metric `<name>_ms`).
- No per-entity `_process`/`_physics_process` and no per-entity visual callbacks: one loop per kind in its service;
  rigs through the rig driver.
- Paths only through `Services.paths` (cache, local queries, batch). Never `map_get_closest_point`, `find_path` or a
  re-target per agent per tick.
- No group or Inspect scans per frame; keep an index fed by EventBus.
- More than about 20 copies of a model: MultiMesh per cell with `visibility_range_end`; shadows only near; nothing
  under 1.5 m casts shadows. No instance uniforms on mass-instanced meshes.
- Shaders: preset `#if` variants, never runtime quality uniforms in big shaders; no new full-screen passes on low presets.
- More than about 2 ms of work goes into slices or onto a worker thread (high priority if per tick); publish on the
  main thread.
- Visual-heavy or AI-heavy change: run the perf harness A/B against the reference and put the numbers in the handoff.

## Look and rules (`docs/ART_BIBLE.md`)
- **Truth table:** what a surface looks like, whether it is walkable and whether it is buildable all come from one
  function (`<MaskOwner>.class_at`). Never add a second slope or ground rule in a shader, the nav or placement.
- Paths shown to the player are the navigation's real routes, or nothing.
- Asset numbers (voxel edge, budget, footprint, parts) live only in `art/assets.json`. Models are used exactly as
  authored: metres, origin = ground point under the centre, front = Godot +Z, voxels below k = 0 are foundation.
  Never rescale in the game.
- New or changed art goes through `docs/ART_PIPELINE.md` (build script + independent judge). Tracks request art in
  their handoff; they never draw their own.

## Folders and ownership
<table: path → owner; core/scenes/project.godot = foundation; one folder set per track; tests/<track>/,
docs/handoff/<track>.md, docs/contract-requests/<track>.md per track; tests/integration/ = integration>

1. **Ownership is enforced:** write only your folders; run `scripts/check_ownership.sh <track>` before every commit.
2. **Never commit editor side effects:** `project.godot`, `scenes/main.tscn`, `*.import`, `.godot/`, `override.cfg`.
   Commit the `.gd.uid` files of your own scripts.
3. **Names:** entry files at fixed paths have no `class_name`; every other `class_name` starts with the track prefix.
   Never reuse a core or engine name.
4. **Frozen:** `src/core/**`, `scenes/`, `project.godot`, `scripts/`, `tests/core/**`, `addons/gut/`, this file. For
   a change, write a contract request and use a local adapter in `src/<track>/adapters/`. For a missing def field,
   use `def.extra[&"key"]` or a subclass.
5. **No new globals** without a prefix (signals, autoloads, actions, layers, groups). A missing global signal is
   declared on your own service node plus a contract request.
6. **Register only your own** commands, overlays, streams and metrics; unregister in `_exit_tree`.
7. **Data:** don't edit another track's `data/`; tests build variant defs in code.
8. **Size:** a file over 1500 lines gets split into components (the gate warns at 1500 and fails at 2500).
9. **Main stays green.** A known failure goes into `docs/KNOWN_FAILURES.md` with owner and date, or gets fixed.
10. **Done gate:**
    - parse gate, boot smoke with stubs **and** with real implementations;
    - `scripts/test.sh <track>` green with your own tests counted (> 0 in `tests/<track>/`);
    - perf A/B within budget where the brief asks;
    - proof shots judged at or above the brief's target and read by you;
    - ownership check OK;
    - `docs/handoff/<track>.md` written.

## Tests and checks (`docs/HOW_TO_TEST.md`)
- GUT 9.x, base class `<Prefix>Test`. Green = exit code 0 **and** test count > 0 (GUT exits 0 with 0 tests).
- Never grep for `ERROR`: every run ends with engine leak lines.
- Always pass `--quit-after N`; `godot --headless --quit` is not a parse check (use `scripts/check_parse.gd`; rc =
  broken scripts).
- Headless has no pixels and wrong nav timings. Screenshots and GPU numbers are windowed only, with the screen on (an
  occluded window throttles). Heavy Godot runs go through the machine-wide lock: `lockf -k /tmp/<game>-heavy.lock …`.

## Working style
- Small commits with the track prefix (`terrain: ...`).
- Unclear design question: don't invent. Take the default from the decisions table; if there is none, build the
  simplest data-switchable variant and list it under assumptions in the handoff.
