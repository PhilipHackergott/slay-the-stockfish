# Playbook: the next game, built right the first time

The process that built Felsenburg (audit → foundation → parallel tracks → integrate → playtest), reordered so that the
expensive questions are answered first. Lesson ids point to `RETROSPECTIVE.md`. Phase briefs for Claude Code are in
`commands/`, and the documents they produce start from `templates/`.

```
0 Vision lock ─► 1 Look-dev (golden scene) ─► 2 Foundation ─► 3 Slice tracks (parallel) ─► 4 Integrate ─► 5 Playtest
                                                                     ▲                                        │
                                                                     └──────── 6 Feature waves (A contracts, B tracks + art batch) ◄┘
```

Felsenburg went straight from the GDD to the foundation and found its look in v0.6 to v0.8.11 (L1 to L4). Phases 0
and 1 are new. They are short, but no system code is written until both have passed their gates.

## Phase 0: Vision lock (`commands/ng-00-vision.md` → `docs/VISION.md`)

Decide everything that Felsenburg decided mid-flight (L5, L6, L9). Output: `templates/VISION.md`, filled in.

- **Three pillars** and the **core loop with numbers**: phase lengths, round count, resource list, start stock.
  Felsenburg changed its build phase from 5 to 10 minutes and its food model four times.
- **One reference game per dimension**: camera, selection and controls, HUD, look, economy. Freeze them for the
  slice. Felsenburg went from an Anno strip to an SC2 command card within days.
- **The genre conventions checklist** taken from those references, with each line marked "slice", "later" or "never".
  Every item Felsenburg added piecemeal is on it: camera tilt, edge pan, double-click and triple-click select, control
  groups, attack-move, queues, stop production, range ring off by default, fixed-size UI boxes, key profiles, tutorial.
- **The fantasy-critical system** (Felsenburg: villagers who haul and build). Put it in the slice or defer it
  explicitly; don't half-add it.
- **Target machine and budgets**: fps, frame ms, tick ms, GPU ms, draw calls, triangles, entity counts (heavy scene =
  twice the largest planned wave), map size. Name a physical target machine that the team can run builds on.
  Felsenburg's 30 fps goal arrived in v0.9, and its "average PC" was never measured (`PERFORMANCE.md`).
- **Decisions table** (K9): id, question, default, knob (data field or constant), owner. No open question may remain
  for a slice feature.

Gate: the human (designer) approves `VISION.md`.

## Phase 1: Art bible and look-dev (`commands/ng-01-lookdev.md` → `docs/ART_BIBLE.md` + golden scene)

Felsenburg's biggest cost was matching the concept art after the systems existed (L1 to L4, L15, L21). Here the look
is proven in the engine before any system is built.

1. **Key art plus three target stills** at the gameplay camera distances (near, mid, far), painted from the key art.
   These are the judge's targets for the scene.
2. **References and anti-references** for every risky surface: landform, cliffs, water, sky, vegetation. Felsenburg's
   `cliff_antireference.png` and `cliff_current_rejected.png` came after five rounds; here they come before the first.
3. **The truth table** ("look == rule"): for every ground class or surface, how it looks, whether it is walkable,
   whether it is buildable, and which single mask or function decides it. One function feeds the renderer, the
   navmesh and placement (L1, L7). Paths: either draw the nav's real route or draw nothing.
4. **Palette and materials in game light.** A palette board rendered in the golden scene at day, dusk and night, and
   approved there, not on a grey background (L15). Roughness and metal rules are part of the palette.
5. **Scale chart and asset classes**: voxel edge per class, triangle budget per class (derived from the Phase 0
   budgets), footprint grid. These numbers live in one file, `art/assets.json` (L13, L14).
6. **The golden scene in Godot**: the hardest visual problem first (for Felsenburg, the terrain with cliffs,
   mountains and coast), final lighting, sky, fog and post-processing, plus 5 to 8 hero assets through the art pipeline
   (`ART_PIPELINE.md`). Organic forms get the most iterations here (L2).
7. **Measure the golden scene** on the target machine against the Phase 0 budgets. That tells you early whether the
   look can afford 400 trees and 150 enemies.

Gate: the scene judge rates the golden scene at least 8/10 against the target stills at all three distances. The
human signs off on the stills, the in-game shots side by side and the perf numbers. The golden shots (fixed cameras,
fixed seed) become the visual regression set for every later phase.

## Phase 2: Foundation (`commands/ng-02-foundation.md`)

Keep what worked (K1 to K4, K6) and close the gaps that showed up later (L9, L17 to L20, L22, L23).

- **Rules file**: start from `templates/CLAUDE.md`. It already contains every engine and harness pitfall Felsenburg hit
  (L23), so no new probe pass is needed. Re-run the probes only when the Godot version changes.
- **Contracts only for the slice.** One file per service in `src/core/contracts/`, documented in the code. No
  3800-line design doc: the foundation doc indexes the contracts and the decisions, and stays under about 400 lines
  (L20). Add a field to a contract only when a second track needs it; until then use `def.extra`.
- **Stubs that keep the hard seams.** The stub map is the golden-scene terrain baked to a file, not a flat plane, so
  slopes, cliffs, chokepoints and wall seams exist from day one (L17). Stubs pass the same contract suites as the real
  implementations, also with `CONTRACT_STUBS=1` once real ones exist.
- **Runtime architecture from day one**, as specified in `PERFORMANCE.md` § Day-one runtime spec (L9, K8, mistakes
  P1 to P14). Felsenburg retrofitted all of it in one perf pass at about 116k lines:
  - a 20 Hz tick with interpolation and a tick scheduler (rate, offset, budget, metric);
  - entity updates bucketed across frames;
  - one loop per entity kind and a central rig driver with distance LOD;
  - a core path service (cache, reuse, join, local queries, batch on workers, region invalidation, `closest_near`)
    instead of per-agent `NavigationAgent3D`. Query budgets only delay the cost;
  - an event-driven HUD with an indexed Inspect;
  - single-material voxel exports and MultiMesh per cell, with shadow and LOD bands planned together;
  - compile-time shader variants and graphics presets;
  - workers for bakes and sims, with a main-thread publish.
- **Real target hardware** (a Windows/Vulkan machine with GPU timestamps) and a quiet, locked perf runner exist before
  the first track merges (P12).
- **Component services.** Each service is a thin façade over components (for combat: spawning, movement, targeting,
  projectiles, morale). A gate warns at 1500 lines per file and fails at 2500 (L19).
- **Harnesses as gates**:
  - Parse, boot, GUT with count > 0, and ownership checks (K2).
  - A per-track test-count check, so a track with no tests of its own cannot pass.
  - A boot with stubs and a boot with real implementations.
  - A perf harness with budgets in JSON; a regression of more than 10% fails.
  - A windowed proof harness that renders the golden shots (fixed cameras, `force_draw`, occlusion detection;
    headless renders no pixels, L22).
  - The art pipeline set up end to end (`ART_PIPELINE.md`).
- **Ownership and worktrees** exactly as in Felsenburg (`scripts/check_ownership.sh`, prefixes, frozen core,
  contract requests, handoffs).

Gate:
- Parse, boot and tests pass.
- The perf harness runs the golden scene within budget.
- The proof harness reproduces the golden shots.
- One asset has gone through the whole pipeline (spec, sheet, script, check, shots, judge, ship).

## Phase 3: Vertical-slice tracks (parallel; `templates/TRACK_BRIEF.md`)

Every brief is a table in the v0.8 format (K5): read first, owned paths, item → approach → proof slug, determinism,
perf budget, tests to run, visual verification, gates, handoff. The done gate in `templates/CLAUDE.md` (rule 10)
extends Felsenburg's: a track must also show:

- **In-game proof shots** for every visual item, judged by an independent model at or above the brief's target against
  its reference or golden still, and read by the agent itself. Judges miss floating props and z-fighting.
- **Its own perf numbers** from the harness against the brief's budget.
- **Its own tests** (count > 0 in `tests/<track>/`) and a **real-implementation boot**, not only `--stubs=all`.
- **Truth-table compliance** for anything that changes ground, walkability or placement.

## Phase 4: Integrate (`commands/ng-03-integrate.md`)

- Merge in the order of the dependency graph and re-run every gate after each merge (K2).
- **Composition smoke on the real map with three seeds**: a scripted run through the slice (build, produce, fight, win,
  lose) must end without deadlocks and without frozen or stacked units (L17, L18).
- **The interaction matrix** for every feature pair that shares ground, routes or resources (L8), as cheap checks.
- **Golden-shot regression**: the scene judge on the golden cameras may not drop more than 1 point against the last
  accepted shots.

## Phase 5: Playtest loop (`commands/ng-04-playtest.md`)

- The designer plays a build with a known seed. Every remark goes into `docs/FEEDBACK.md` as a quote with a class
  (bug, tuning, convention, look, vision change), a decision id and the knob that implements it.
- Look feedback first gets a picture: a target or reference and an anti-reference (the current shot), approved by the
  designer. Only then does the work start, judged against that picture. Felsenburg's cliffs and mountains were
  described in words ("too rounded", "a cone") for several rounds before reference and anti-reference images existed
  (L1, L2).
- Vision changes go through the `VISION.md` decisions table, never straight into a track. Felsenburg's richest "why"
  lived in scattered handoffs (`docs/BALANCING_NOTES.md`), so later reversals were expensive (L5, L7).
- Release notes state what changed, why (with a link to the decision), and the known issues.

## Phase 6: Feature waves

Same shape as Felsenburg's later milestones:
- **Wave A** on the integration branch: contracts, art specs and the interaction-matrix rows.
- **Wave B**: parallel tracks plus an art batch (`commands/ng-art-batch.md`).

Plan each wave with `templates/FEATURE_PLAN.md`: decisions table, visual verification, proof slugs, perf budget and the
interaction matrix. Every new macro feature (rivers, biomes, weather) gets its own look-dev mini-pass, with references,
anti-references and a golden still, before the wave B track starts.

## Single sources of truth

| Truth | One place | Felsenburg had |
|---|---|---|
| Asset contract (edge, budget, footprint, parts, refs) | `art/assets.json` | `ASSETS` in Python plus `CLAUDE.md` plus script overrides (L14) |
| Palette | `art/palette.json`, read by voxkit and the shaders | `voxkit.PALETTE` plus per-script additions |
| Walk, build and look classes | one mask function (truth table) | separate slope rules for renderer, nav and placement (L1) |
| Paths shown to the player | the navigation's real route | a second road planner (L7) |
| Budgets | `perf/budgets.json` | prose in handoffs (L9) |
| Design decisions | `VISION.md` and the feature-plan decision tables | quotes across handoffs (L5) |
| Visual targets | `art/targets/` (stills, references, anti-references) plus the golden shots | concept sheets only, references added late |

## Roles

| Role | Who | Never |
|---|---|---|
| Designer | the human: approves vision, golden scene, slice, each release | is asked to judge single props |
| Integration / foundation | one agent on the integration branch | builds features |
| Tracks | one agent per worktree | edits another track's folders or the core |
| Painter | image model (`GenerateImage`, or codex imagegen) | judges |
| Builder | coding agent writing Blender build scripts | judges its own work as a ship gate |
| Judge | a different model family (Felsenburg: Gemini Argon via a Task subagent) | builds |
