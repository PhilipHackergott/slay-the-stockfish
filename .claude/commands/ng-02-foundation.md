---
description: Phase 2 – foundation for parallel tracks: rules, minimal contracts, seam-faithful stubs, runtime architecture, gates and harnesses
---
Read `docs/VISION.md`, `docs/ART_BIBLE.md`, `docs/kit/PLAYBOOK.md` § Phase 2, `docs/kit/PERFORMANCE.md`
(all of it), `docs/kit/ART_PIPELINE.md`, `docs/kit/RETROSPECTIVE.md` § E. This runs alone on main
before any track.

Reuse from Felsenburg (`origin/v09/main`) where it fits, and adapt names and prefixes:
- `scripts/check_parse.gd`, `test.sh`, `targeted.sh`, `check_ownership.sh`, `vs-worktrees.sh`;
- `tests/fb_test.gd`, `tests/contract_check.gd`, `addons/gut/`;
- `src/core/service_locator.gd` (file-path stubs), `dev_console.gd`, `dev_overlays.gd`, `rng.gd`, `modifiers.gd`,
  `content_db.gd`, `model_library.gd`, `rig_driver.gd`, `character_rig.gd`;
- `tools/voxkit.py`, `rigkit.py`, `rig_shots.gd`, `tools/v08_models/{_kit,render}.py`, `tools/v09_models/compose.py`;
- `tests/perf/{run_perf.sh,perf_scenes.gd,mesh_breakdown.gd}`, `src/ui/perf_readout.gd`,
  `src/ui/graphics_detail.gd`.

Never copy game logic.

Build:
1. **Rules.** `CLAUDE.md` from `docs/kit/templates/CLAUDE.md`; `docs/PITFALLS.md` seeded with
   `RETROSPECTIVE.md` L23 and the engine findings in `PERFORMANCE.md`; `docs/CONVENTIONS.md`; `docs/HOW_TO_TEST.md`.
2. **Contracts only for the slice**, one documented file per service in `src/core/contracts/`, including
   `PathService` and `TickScheduler`. Keep `docs/FOUNDATION.md` as an index under ~400 lines.
3. **Stubs that keep the hard seams.**
   - The stub map loads the golden-scene terrain (a baked file), not a flat plane.
   - Stubs pass the same contract suites as real implementations.
   - Stub inputs support two players.
   - Stub units are inspectable.
   - Stub walls have real seams.
4. **Runtime architecture** per `PERFORMANCE.md` § Day-one runtime spec:
   - the 20 Hz tick with interpolation;
   - the scheduler with buckets;
   - the path service with cache, local queries, batch, region invalidation and `closest_near`;
   - the spatial grid;
   - the rig driver;
   - an event-driven Inspect index;
   - single-material voxel export (voxkit);
   - MultiMesh, LOD and shadow policies;
   - presets with `#if` shader variants and detection;
   - worker bakes with a main-thread publish and a bit-identical test.
5. **Gates and harnesses.**
   - Parse, boot with stubs and boot real, GUT count > 0 per track, ownership.
   - A file-size gate: warn at 1500 lines, fail at 2500.
   - The perf harness with `perf/budgets.json` and stored reference JSON, plus a 10% regression check.
   - The windowed proof harness: fixed cameras, `force_draw`, a check that fails when the window is occluded or
     throttled, golden shots.
   - The art pipeline v2: `art/assets.json` loader, contract check, shots, judge adapter, `art/scores.json`.
6. Placeholder content: one def per type. `docs/contract-requests/` and `docs/handoff/` with READMEs. An empty
   `docs/KNOWN_FAILURES.md`.

Gate:
- parse rc 0, both boots OK, all tests green with count > 0;
- the perf harness runs the golden scene within budget;
- the proof harness reproduces the golden shots;
- one asset through the full art pipeline.

Commit in steps (`core: …`), list the contracts briefly, and say when the tracks can start
(`scripts/vs-worktrees.sh`).
