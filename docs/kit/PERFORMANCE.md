# Performance from day one

Read this before the foundation is written. It distils Felsenburg's first big performance pass: the architecture plan
`docs/PERF_ARCHITECTURE.md` (2026-10-19), its phases 0 to 6 plus tick staggering (all on 2026-10-20, reports in
`docs/perf/phase{3,4,5}_result.md`), and the four tuning rounds before it (`docs/handoff/v09-perf.md`). Paths are on
`origin/v09/main`.

## What happened

- **Rounds 1 to 4 tuned around the architecture.** They added presets, FSR, compile-time shader variants, a LOD bias,
  a deer threat pre-filter and path-query budgets. Each gained a few fps, and the goal ("run on an average computer on
  at least 30 fps locked") stayed out of reach: the round-10 wave was estimated at 15 to 25 fps on the average PC.
- **The plan named the real cause:** "No single bug causes this. Several early choices that are fine at small scale
  multiply with agent count and map size." By then the game had about 116k lines of GDScript, with combat at 6.5k and
  buildings at 5.3k lines in one file each.
- **Phases 0 to 6 changed those choices**, on the riverlands map, real clock, seed 7:
  - wave start: 103 ms average and 529 ms worst frame before, 26.6 ms and 171 ms after;
  - main CPU: 95 ms before, 18 ms after;
  - physics ticks per frame: 4.84 before, 0.54 after.
- **Still not met at the end:**
  - "No frame over 25 ms": a 20 Hz tick lands its whole cost in one frame of three.
  - The triangle budget: 4.3 to 4.5 M against 3 M.
  - The Mittel GPU budget: 14.5 ms against 7 ms.
  - Any measurement on a real average PC: the estimate was a formula.

Retrofitting cost a dedicated perf track (four rounds), then a day of parallel perf branches (clock, navigation,
animation, geometry, UI), and cross-track edits in the biggest files. Every item below is cheap if it is in the
foundation, and expensive later.

## The mistakes not to repeat

| # | Mistake | What it cost in Felsenburg | Day one instead |
|---|---|---|---|
| P1 | **The simulation clock was the physics clock**: 60 Hz, up to 8 catch-up steps per frame | Waves went into catch-up: 4.84 ticks per frame on average, 8 at worst, so wave start ran at about 10 fps. Moving to 20 Hz meant hunting every per-frame constant and every test that counted frames | A 20 Hz gameplay tick (try 15 Hz) with physics interpolation; `max_physics_steps_per_frame` 2 to 3; every rate and budget stated per second and converted with `Engine.physics_ticks_per_second`; tests wait in game seconds |
| P2 | **Per-agent path queries on the main thread** (`NavigationAgent3D` per walker), "fixed" with query budgets | Combat AI was about 60% of a 16 to 28 ms tick. The budgets (`THINK_QUERY_BUDGET`, `RESTEER_QUERY_BUDGET`) "delay decisions instead of removing the cost". Every navmesh rebake re-planned every walker: 84% of queries were target changes | A core **path service**: paths cached per nav map; walkers reuse a cached path that passes within 1 m and join one within 4 m with a short query. Short queries stay region-local, accepted only when equal to the whole-map path. Re-plans are batched at the end of the tick on `WorkerThreadPool`. A rebake invalidates only the paths that cross the changed region. Groups (escorts) share one path. One path follower node with no per-agent server state |
| P3 | **Whole-map engine queries inside per-agent loops** | `map_get_closest_point` scans every polygon: the muster spread cost 14.2 of 19.1 ms per tick. `query_path` resets the whole map: about 0.43 ms for a 1 m query, about 10 ms from beach to keep. With `included_regions`, nav links are rejected | The path service owns a region grid and offers `closest_near` and local queries. Never call a whole-map query per agent per tick. Engine-cost facts go in the rules file |
| P4 | **Every entity was a full scene tree with its own `_process`**, and every rig animated every frame | 243 to 569 rigs advanced per frame, 558 in a wave; per-person scripts each frame | One update loop per entity kind inside its service. A central rig driver (`src/core/rig_driver.gd` pattern): manual `AnimationPlayer` callbacks, every frame within 60 m, every 2nd within 120 m, every 4th beyond, frozen off screen, 4 buckets. Crowds later get vertex-animation `MultiMesh` |
| P5 | **Periodic jobs ran whole in one tick**, and timers started together ran in lockstep | The water class batch took 18 to 32 ms in one tick; all wildlife threat checks landed in the same tick, each scanning every enemy (5 to 15 ms) | A tick scheduler from day one (the plan's §3.7; Felsenburg only staggered these two jobs by hand, §5h). Each system registers rate, offset, budget and metric. Periodic work runs in slices with a per-tick budget; per-entity checks run in turns (frame + index) |
| P6 | **A 20 Hz tick does three ticks' work in one frame** | Every third frame paid the whole tick plus the render, so "no frame over 25 ms" could not be met without a cross-track change | Bucket entity updates across render frames from the start (a third of the enemies each frame, interpolated), or budget the tick against one frame, not three |
| P7 | **UI and helpers polled**: periodic scans built `Inspect` data for every inspectable | The danger overlay took 25 to 55 ms every 0.25 s, the hidden marker 42 ms every 0.5 s, work-area peers about 30 ms per frame while a card was open, the HUD refresh 47 ms at wave start. The profiler booked it to buildings and combat | An event-driven HUD (EventBus dirty flags); per-node caches keyed by instance id; an index for inspectables; inspect data built on demand, never in a scan; theme overrides only on change |
| P8 | **Asset export decided draw calls**: one surface per palette colour per prop, and each 48 m MultiMesh cell paid one draw per colour | 2,380 draws at the default camera (budget 1,500); merging colour surfaces cut 45%. Colour jitter keeps triangles high (790k for all voxel glbs, 419k if colour did not split faces). LOD1 and LOD2 were drawn twice where a LOD switch overlapped a shadow band. About 1,350 shadow draws on Niedrig. Static building pieces were never merged | voxkit exports **one material** per model: vertex colours already remove the per-colour draws, and a palette texture atlas also lets greedy meshing merge across colours (419k instead of 790k triangles). Systems that read colour (night lights, motion, rock family) read `COLOR` or the atlas, not the surface. Static building pieces merge per building. Shadow policy by size (nothing under 1.5 m casts). LOD bands are designed together with shadow bands. Triangle and draw budgets per asset class in `art/assets.json`, checked by the GLB check |
| P9 | **Big shaders had runtime quality branches**, and the terrain fragment shader carried every layer | Runtime `uniform int` quality branches cost Hoch about 9 ms (register pressure). The Mittel GPU stayed at 14.5 ms against 7 ms, mostly terrain fragment and tree MultiMeshes. Instance uniforms ran out (grass floated) | Compile-time `#define` variants per preset from the first shader. Bake static colour layers into a texture per map. No instance uniforms on mass-instanced meshes. Every optional layer is guarded by its fade weight |
| P10 | **Heavy work on the main thread, threads added later** | Nav rebakes hitched 1 to 2.7 s; water took 2 ms per tick. The first threaded water task ran at normal priority behind the nav bakes and stalled a frame for 0.57 s | Map generation, nav bakes and splits, and grid sims run on workers from the first version, and publish on the main thread. Per-tick tasks run at high priority. A bit-identical test (hash per tick) proves threaded equals synchronous |
| P11 | **No budget was enforced**, and metrics were attributed wrongly | The harness was "run by hand, so regressions land unnoticed". The "6.5 ms of UI" was mostly `AnimationPlayer`s. The GDScript profiler samples one frame per second and misses the 20 Hz tick frames. The path-watch devtool cost 2 ms per tick inside perf runs | Harness and budgets JSON exist before the first track merges. Every system reports `<system>_ms`. Temporary stage timers are the profiling tool for tick code. Dev watchers are off in perf runs and exports. A regression over 10% blocks the merge |
| P12 | **Measurements on a shared dev machine, and no target hardware** | Load averages of 13 to 20 from other agents moved single numbers by 2 to 4 ms. Metal has no GPU timestamps. An occluded window throttled to about 1 fps (a false night-time alarm). Headless nav timings read 130 to 490 ms against 1 to 5 ms windowed. Two checkouts side by side showed their own offset. The "average PC" was `×4 GPU, ÷0.6 CPU`, never measured | One machine-wide heavy lock and a quiet runner (pause other builds). Interleaved A/B in one checkout, medians of paired runs. GPU numbers windowed with the screen on. Release numbers from an exported build. **Real target hardware (Windows/Vulkan with GPU timestamps) from day one** |
| P13 | **Main was not green during the perf work** | 8 to 27 suites already failed on `v09/main`, so every perf phase had to prove it "fails exactly where `v09/main` fails" | Main stays green. A known-failures list with owners and dates; perf branches A/B against a green base |
| P14 | **God files** | Each perf phase edited `combat_service_impl.gd` (6.6k lines) or `building_service_impl.gd` (5.4k), which made them cross-track changes | Services are façades over components (movement, decisions, sight, spawning, projectiles), so a perf fix stays inside one component |

## Diagnose before you build (the plan was wrong in four places)

The plan was well argued and still wrong in four places. Measurement corrected it each time:

- **Flow fields** (§3.2): once paths were shared, path work was about 7% of combat's tick. The rest was per-enemy
  decisions and sight scans. A grid flow field would also have created a second route truth beside the navmesh
  (bridges, fords, gates, lanes, agent sizes), exactly what the detour and breaching tests guard.
- **Greedy meshing** (§3.4) was already done; the draws came from per-colour surfaces in MultiMesh cells.
- **Animation LOD** saved 1.1 to 1.4 ms, not "several ms": a rig costs about 2 to 2.5 µs per frame.
- **Native kernels** (§3.6) were never needed: no kernel stayed hot after the algorithmic fixes.

The rule that follows: **profile per stage before changing the architecture.** Add temporary stage timers in the tick,
take the top three costs, fix those, and measure again.

The other half of the rule: **when a scene misses its budget by more than 1.5× after the obvious fixes, stop tuning.**
Rounds 1 to 4 kept tuning; phases 0 to 6 changed the structure and got four times more.

## Day-one runtime spec (for the foundation)

- **Clock and scheduler** (core):
  - A 20 Hz tick with interpolation on moved visuals (`reset_physics_interpolation()` on snaps and spawns; set it off
    on each `SubViewport`).
  - `TickScheduler.register(owner, rate_hz, offset, budget_ms, metric)`.
  - Entity buckets spread over frames.
  - Determinism unchanged: same seed, same tick sequence.
- **Entities**: services own entity data and run one loop per kind. Visual nodes are thin and own no gameplay
  callbacks. Gameplay never reads animation timing or bone poses.
- **Navigation** (core contract `PathService`):
  - path cache per nav map, with reuse, join and local queries;
  - a batch at the end of the tick on workers;
  - region invalidation on rebake;
  - group paths;
  - `closest_near`;
  - a per-tick spatial grid for neighbour and target search;
  - sight and range modifiers resolved once per tick.
- **Rendering**:
  - vertex-colour, single-material voxel exports;
  - a MultiMesh per cell for anything with more than about 20 copies;
  - merged static building meshes;
  - a shadow policy by size;
  - LOD bands planned together with shadow bands;
  - compile-time shader variants;
  - graphics presets (Low, Medium, High plus custom) with render scale (FSR), shadow cascades and SSAO per preset;
  - first-start detection;
  - a frame cap.
- **UI**: EventBus-driven refresh with dirty flags, an indexed Inspect with per-node caches, redraw only on change.
- **Threads**: generation, bakes and sims on workers with a main-thread publish; high priority for per-tick tasks; a
  bit-identical determinism test for each threaded system.

## Budgets (fill in from `VISION.md`; Felsenburg's for scale)

Felsenburg's targets for its stated average PC (about 60% of the dev Mac's single-thread speed, about a quarter of its
GPU, 1080p, 30 fps), measured on the dev Mac:

- main thread in the heaviest wave: at most 14 ms;
- simulation tick: at most 6 ms;
- GPU on the default preset: at most 7 ms;
- no frame over 25 ms outside loading;
- at the default camera: at most 1,500 draw calls and 3 M triangles.

Store yours as `perf/budgets.json`, per scene: frame avg, p95 and max; spikes over 25 ms per 20 s; main CPU;
tick ms; per-system ms; draws and primitives (view and shadow); render-only frame; entity, rig and path-query counts.
The heavy scene is twice the largest planned wave on the biggest map. Split the per-asset-class triangle budgets in
`art/assets.json` out of the scene triangle budget.

## Harness and gate

- Scenes: default camera, built base, heavy wave start, heavy wave, night; two maps; fixed seed; both pinned clock and
  real clock.
- Output: JSON next to the harness, compared against the stored reference, with paired A/B mode
  (`--perf-anim-ab` pattern).
- Gate: tracks that touch hot paths run it before handoff; integration runs it before every release; a regression over
  10% blocks the merge until explained.
- On screen: an FPS readout and frame graph with per-system costs (`src/ui/perf_readout.gd` pattern), so the designer
  sees spikes while playing.

## Rules for every new feature (copy into `CLAUDE.md`)

1. Register with the tick scheduler: rate, offset, budget, and a `<name>_ms` metric listed in the harness.
2. No per-entity `_process` or `_physics_process`, and no per-entity visual callbacks.
3. Path work goes through the path service only: no `find_path`, no `map_get_closest_point` and no re-target per
   agent per tick.
4. No `get_nodes_in_group` or Inspect scans per frame; keep an index fed by EventBus.
5. More than about 20 copies of a model means a MultiMesh per cell with `visibility_range_end`; shadows only on the
   near band, and nothing under 1.5 m casts.
6. No runtime quality branches or new full-screen passes in big shaders; use preset `#if` variants; read the graphics
   caps signal (glow, particles, wildlife share). Fire and lights use emissive materials or the light pool, never a
   shadowed light per flame.
7. Anything over about 2 ms goes into slices or onto a worker; only the publish runs on the main thread.
8. Measure before merging any visual-heavy or AI-heavy feature: harness A/B against the reference, numbers in the
   handoff.
