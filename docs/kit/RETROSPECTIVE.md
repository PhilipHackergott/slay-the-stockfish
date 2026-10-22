# Felsenburg retrospective: what to keep, what to change

Evidence base: branch `origin/v09/main` (tip `327bc8d4`, 2026-10-21). Every path below is on that branch; open it with
`git worktree add --detach /tmp/fb09 origin/v09/main`. Lesson ids (`K*` = keep, `L*` = lesson) are referenced by
`PLAYBOOK.md`, `ART_PIPELINE.md` and the templates.

## The project in numbers

| What | Value |
|---|---|
| Span | 2026-10-02 (prototype baseline) to 2026-10-21 (v0.8.11), 19 days |
| Commits | 1573 (302 on day two alone) |
| Release notes | 22 (`docs/releases/`) |
| GDScript in `src/` | ~123.6k lines; test files: 310 (`tests/**/test_*.gd`); ~980 GUT tests at v0.5 |
| Models / concept files | 259 `models/*.glb` / 372 files under `art/concepts/` |
| Contract requests | 126 sections in 19 files (`docs/contract-requests/`) |
| Commits by prefix | terrain 299, integration 209, ui 162, art 107, buildings 104, combat 66, perf 35 |
| Topics in commit subjects | water/river/lake 159, cliff 113, mountain 92, perf/fps 91, path/road 91, sky/night/cloud 86 |

Read the last two rows together: about a fifth of all commits went into making the ground look right and agree with
the game rules, more than combat, economy and population combined.

## What worked: keep it

- **K1 Foundation first, then parallel tracks.** Contracts in `src/core/contracts/`, core stubs picked by file path
  (`src/core/service_locator.gd`), hard folder ownership (`scripts/check_ownership.sh`). The M1 and M3 merges had no
  merge conflicts (`docs/handoff/integration.md`, `integration-m3.md`).
- **K2 Layered, mechanical gates.** Parse gate (`scripts/check_parse.gd`, rc = broken scripts), boot smoke
  (`FB BOOT OK`), GUT with a test-count check (`scripts/test.sh`), ownership check, handoff. They caught the
  engine-level pitfalls in `docs/FOUNDATION_REVIEW.md` before eight tracks hit them.
- **K3 Data-driven content, determinism, devtools.** `.tres` defs plus `Modifiers.resolve`, seeded `RNG` streams, and
  `DevConsole` commands in every system made balance sims (`docs/balancing/*.csv`) and bug repros cheap.
- **K4 A living pitfalls file.** `docs/FOUNDATION_REVIEW.md` saved more time than the 3800-line design doc did.
- **K5 Briefs that are tables.** The v0.8 briefs (`.claude/commands/v08-track-*.md`) give owned paths, item →
  approach → proof slug, a perf budget, the tests to run, the judge target and the gates. Agents invented far less
  than with the prose briefs of the vertical slice (`vs-track-*.md`).
- **K6 Asset contract in metres plus an automated GLB check.** `check_glb`/`enforce` in `tools/asset_pipeline.py`
  verify the voxel grid, the triangle budget, the footprint and named parts. A broken model can never ship, whatever it
  looks like, and the pipeline keeps the best pass, not the last.
- **K7 Scripted builds plus an independent judge** (v0.8 and v0.9). Claude wrote one voxkit script per asset
  (`tools/v08_models/<id>.py`) and Gemini Argon judged the render. 39 of 50 (v0.8) and 17 of 22 (v0.9) assets shipped
  at 8/10 or better, against 3 of 12 in v0.5 with the self-judging loop (`docs/handoff/art-v05.md`).
- **K8 A measured perf program.** Clock, then shared navigation, then batching and shadows, then event-driven UI,
  then tick staggering, each with paired A/B numbers (`docs/PERF_ARCHITECTURE.md`, `docs/perf/`).
- **K9 Decision tables in feature plans.** "Decisions (Philip can overrule; each switch is data or one constant)" in
  `docs/V08_BIOMES_PLAN.md`: design calls get an id, a default, and a single knob.

## What cost the most, and why

### A. The visual target was not locked before systems were built

- **L1 Cliffs were rebuilt at least five times** (v0.6, v0.6.2, v0.7.1, v0.7.2, v0.8.11; `docs/handoff/v06-cliffs.md`,
  `v062-cliffs.md`, `v071-cliffs.md`, `v072-cliffs.md`). Designer feedback: "we are simply putting a rock facade on
  grey polygons", "cliffs are still too rounded and not natural enough". v0.7.1 painted every slope over 32° as stone
  ("soft cliffs are very annoying to build on"), and v0.7.2 reversed it: "Cliffs are what they look like". Root cause:
  look, walkability and buildability were three different rules computed in three places. References and
  anti-references (`art/concepts/cliff_reference_manor_lords.png`, `cliff_antireference.png`,
  `cliff_current_rejected.png`) arrived only after several rejected rounds.
- **L2 Organic forms are where code-built art is weakest.** Mountains went from heightfield to Blender kit to eroded
  kit (`tools/mountainkit.py`, `tools/erodekit.py`): "still a bit too pointy, every mountain a cone", "still too low
  poly, blocky". Voxel props converged in 2 to 3 passes; free-form rock and terrain took many rounds.
- **L3 Atmosphere came last.** Sky, clouds and the far world were built in v0.8.11: "the clouds and fog are not as in
  the concept arts. those were much more painterly and detailed". Lighting and grading change how every asset reads,
  so they belong at the start.
- **L4 A good score in isolation does not mean a good look in the game.** The perched crow scored 8 as a prop and 3 on
  its roost; `woodcutter_l2` 8 as a model and 3 in the forestry view; the alders 3 in the swamp (all later 8 after
  rebuilding at real scale and in game light, `docs/handoff/v08-art.md` § v0.8.1 polish). Biome views stayed at 5 to 7
  while single props hit 8 (`docs/releases/v0.8.md`).

### B. Product decisions were made late, or flipped

- **L5 Economy identity.** Gold was the bootstrap resource in the M3 Notion pass (`docs/NOTION_PLAN.md`) and was removed
  in v0.3 the next day (`docs/V03_PLAN.md`). Food went from round upkeep to a move-in cost to continuous eating (v0.5) and
  back to a move-in cost (v0.5.2). The build phase went from 5 to 10 minutes (`docs/releases/m1.md`, `v0.5.md`).
- **L6 Genre conventions arrived one request at a time.** The HUD went from TV-sized to an Anno 117 strip
  (`docs/handoff/ui.md`) to an SC2 command card (v0.5.6) to lenses (v0.8.5). Camera tilt, double-click select, control
  groups, attack-move, stop production, unit queues, the range ring off by default and fixed-size UI boxes each became a
  separate request (`docs/handoff/fix-v03f-camera.md`, `v06-boxes.md`, `v072-*.md`). Every one of them is standard in the
  reference games; a checklist on day one would have covered them.
- **L7 Two sources of truth for paths.** Drawn roads were planned separately from the navmesh: "Before: 0 of 107
  beaches followed their road" (`docs/handoff/v056-paths.md`). Roads were shown, hidden, re-added and hidden again.
- **L8 Feature stacking without an interaction matrix.** In v0.8.10 the new mountain shapes moved a spring by 40 m
  (no rivers on crescent seed 7), shifted start ravines and pushed fishery sites onto wet or steep ground
  (`docs/releases/v0.8.10.md` § Known issues). Each macro feature (cliffs, mountains, rivers, biomes) touched the
  others, and the conflicts surfaced as failing suites after the merge.

### C. Performance was a late feature

- **L9** The 30 fps target ("run on an average computer on at least 30 fps locked", `docs/handoff/v09-perf.md`) came
  after forests, night, water and biomes were in. The prototype defaults then had to be rebuilt:
  - The 60 Hz physics clock fell into catch-up: wave start took 103 ms per frame on average, with a 529 ms worst frame
    and 4.84 ticks per frame.
  - Every walker queried its own path; 558 rigs were animated every frame.
  - The inspect and danger scans took 25 to 55 ms every 0.25 s.
  - The default view drew 2380 draw calls.

  Four tuning rounds (presets, shader variants, query budgets) gained a few fps each. Only the architecture plan
  (`docs/PERF_ARCHITECTURE.md`: "Several early choices that are fine at small scale multiply with agent count and map
  size") changed the structure: a 20 Hz tick, shared paths, an animation LOD driver, merged MultiMesh surfaces, an
  event-driven HUD and staggered jobs. Wave start fell from 103 to 26.6 ms per frame. The plan itself was wrong in four
  places (flow fields, greedy meshing, the animation saving, native code), and stage timers corrected it. At the end
  the GPU was still 2× over budget and triangles at 4.3 to 4.5 M against 3 M, and no real average PC had been
  measured. The full list of mistakes is in `PERFORMANCE.md`.

### D. Art pipeline

- **L10 The builder judged itself.** The original loop had GPT Astra paint the sheet, build the model and judge the
  render against its own sheet (`tools/asset_pipeline.py` docstring). The self-judge was too lenient: `flowers_white`
  scored 8 from the self-judge and 5 from Argon, the boardwalks 7 and 4 to 5 (`docs/handoff/v08-art.md`).
- **L11 Interactive Blender sessions over MCP were not a durable artifact.** When Codex hit its spend cap, the pipeline
  stopped (`docs/V08_BIOMES_PLAN.md` § Visual verification). A committed build script per asset could be re-run, diffed,
  reviewed and fixed by any agent.
- **L12 The first pass is usually mediocre.** In v0.8, 50 assets averaged 5.8/10 on their first Argon pass, and 9 reached
  8. In v0.9, 22 assets averaged 5.7, and 2 reached 8. The typical asset needed 2 to 3 judged passes, and some never
  converged (`bridge_gate`: 9 passes, best 7). First-try quality has to come from better inputs; extra passes do not fix
  it.
- **L13 The rubric and the budget disagreed.** The judge asked for 16 to 20 crown puffs on `oak_lone`, which a
  14000-triangle budget cannot hold, and the alders were capped by the 4 m width (`v08-art.md` § Bekannte Lücken). Every
  pass spent on that request was wasted.
- **L14 The asset contract drifted between documents.** `CLAUDE.md` still states 0.25 m / 0.1 m voxels, but the game
  ships 0.125 m / 0.05 m. The `ASSETS` text still describes the old crow, which its script overrides in memory
  (`v08-art.md`).
- **L15 The palette was judged on a grey background, not in game light.** `steel_dark` reads light grey in the game, cool
  grey boulders wash out to cream, glossy pitch mirrors the sky as navy (`v08-art.md`, `docs/handoff/v09-models.md`).
- **L16 The camera hid parts of models.** Wall attachments were hidden by the parapet at the default pitch, and the scale
  soldier occluded small props. Both were fixed with a second camera and host compose shots (`v09-models.md`).

### E. Engineering process

- **L17 Stubs hid the hard seams.** On the flat stub map, enemies never froze on steep slopes and never walked through
  wall seams. Keep housing of 0 combined with hauled construction deadlocked only with the real population
  (`docs/handoff/integration.md`, contract requests). Several bugs appeared only on the real island.
- **L18 Tests stayed green while the game was broken.** Archers stacked on the keep, the HUD ignored weapon and queue
  signals, and grass floated in the air because the shader instance-uniform buffer ran out of slots
  (`docs/handoff/integration.md`, `docs/handoff/v09-perf.md`). Unit tests do not see composition or pixels.
- **L19 God files.** `combat_service_impl.gd` grew to 6629 lines, `building_service_impl.gd` 5371, `tier_gen.gd` 4464.
  They are also the top churn files, so every feature and every perf fix collided in them.
- **L20 The contract surface kept growing.** `FOUNDATION_DESIGN.md` gained §11 to §16 (one per milestone), reached about
  3800 lines and collected 126 request sections. Each new agent paid for reading it.
- **L21 Generator tests became threshold tuning.** Map-generator suites assert percentages (cliff coverage, thin
  ledges, straightness). When a merge shifted the map, the fix was often to loosen the threshold
  (`MIN_CASE_STRAIGHT` 0.25 → 0.23, `docs/handoff/v072-terrain-fix.md`), because no picture said what "right" looks
  like. Metrics without a visual target drift.
- **L22 Headless runs lie about pixels and timing.** Headless navigation timings read 130 to 490 ms against 1 to 5 ms
  windowed. Metal has no GPU timestamps, and an occluded window throttles to about 1 fps (`docs/handoff/v09-perf.md`).
- **L23 Engine and test-harness pitfalls** (all now rules in `CLAUDE.md`):
  - Typed `Array`/`Dictionary` method parameters throw runtime errors in 4.7.
  - `push_error` and any engine ERROR or WARNING fail a GUT test.
  - GUT exits 0 with 0 tests.
  - `--quit` is not a parse check.
  - Editor side-effect files get committed.
  - Self-less lambdas survive `unregister_owner`.
  - Joypad GUIDs on simulated pads raise engine errors.

## The short version

Felsenburg's engineering process (K1 to K5) scaled well. The rework came from three gaps:

1. Visual and physical targets that no one had fixed before content was built (L1 to L4, L7).
2. Product and genre decisions taken mid-flight (L5, L6, L8).
3. Prototype-grade runtime defaults kept until the end (L9).

The art pipeline got good once builder and judge were separate models, builds were scripts, and judging happened in
game context (K7, L10 to L16). The next game should start with those three gaps closed, and with the art pipeline in
its v0.9 shape rather than its v0.2 shape.
