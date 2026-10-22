# Art pipeline v2: concept art → Blender → Godot → judge

The same loop that built Felsenburg's 259 models, set up in the shape it reached in v0.8 and v0.9 (scripted builds,
independent judge) instead of the shape it started in (one model painting, building and judging its own work). Lesson
ids point to `RETROSPECTIVE.md`, perf ids (`P*`) to `PERFORMANCE.md`.

Targets for the next game (Felsenburg in brackets, `docs/handoff/v08-art.md`, `v09-models.md`):

| Metric | Target | Felsenburg |
|---|---|---|
| Mean score of the first independent judge pass | ≥ 7.0 | 5.8 (v0.8, n = 50), 5.7 (v0.9, n = 22) |
| Share shipped at ≥ 8 | ≥ 90% | 78% (39/50), 77% (17/22); 25% in v0.5 |
| Judged passes per asset | ≤ 2 | 2.1 (v0.8), 3.0 (v0.9) |
| Assets 8 or more in isolation but under 7 in game context | 0 | crow, woodcutter_l2, alders, hen_yard (L4) |

First-try quality comes from better inputs: contract, sheet, references, failure rules, scale and light. Extra passes
add little (L12).

## Roles

| Role | Model | Felsenburg evidence |
|---|---|---|
| Painter | an image model: Cursor `GenerateImage`, or codex imagegen (`paint()` in `tools/asset_pipeline.py`) | key art, 372 concept files |
| Builder | the coding agent writes `tools/models/<id>.py`, a voxkit script run headless in Blender | v0.8/v0.9 `tools/v0{8,9}_models/<id>.py`: 39/50 and 17/22 at ≥ 8 |
| Judge | **a different model family from the builder**: Gemini Argon via a `Task` subagent with `file_attachments` (`docs/V08_BIOMES_PLAN.md` § Visual verification) | self-judge 8 against Argon 5 on `flowers_white` (L10) |
| Human | the designer: approves the key art, the set style sheets and the palette board; breaks ties; signs off on contact sheets per set | the v0.5 hand-picks (`art-v05.md`) |

The pipeline talks to each role through a small adapter: `paint(refs, prompt)`, `build(id)`, `judge(images, prompt,
schema)`. When one provider hits a spend cap, another can take its place (L11: Codex stopped at its cap in v0.8).

## One spec file: `art/assets.json`

All numbers live here, and nothing restates them. `CLAUDE.md`, briefs and handoffs refer to the file (L14). Example
(`templates/assets.example.json`):

```json
{
  "classes": {
    "structure": {"vox": 0.125, "tris": 12000, "shadow": true},
    "prop_small": {"vox": 0.0625, "tris": 2500, "shadow": false},
    "unit": {"vox": 0.05, "tris": 4000, "rig": "vox_humanoid"}
  },
  "assets": {
    "watchtower": {
      "class": "structure", "h": 9.0, "fit": [4.0, 4.0, "max"],
      "desc": "a timber watchtower on stone footings",
      "contract": "Platform floor at 7.0 m ... front faces -Y ... foundation to -1.0 m.",
      "set": "defences", "style_ref": "palisade_section",
      "host": null, "parts": {},
      "views": ["iso", "front", "gameplay_mid"],
      "context": "golden_base", "seen_at_m": [25, 60, 120],
      "rules": ["masonry_blocks", "timber_joints"]
    }
  }
}
```

Class budgets are split out of the scene budgets in `perf/budgets.json` (P8). A judge request the budget cannot
satisfy is invalid by definition (L13).

## Stages

| # | Stage | Output | Gate |
|---|---|---|---|
| 1 | Spec | an entry in `art/assets.json` | fields complete; budget fits the class |
| 2 | Sheet | `art/concepts/<id>.png`: hero view plus orthographic views, from key art, set style sheet, references, anti-references | **sheet check**: the judge compares the sheet with the contract *before* any build (orientation, size, joints, below-ground parts). Felsenburg's `bridge_wood_end` sheet ramped the wrong way and cost passes |
| 3 | Build | `tools/models/<id>.py` → `models/<id>.glb` | the script runs headless (`Blender -b --factory-startup --python ...`) and prints `CHECK <id> ok` |
| 4 | Contract check | GLB stats | grid, triangles, footprint, named parts, rig check, **one material** (P8). A failure caps the score at 2 and the pass can never ship (`check_glb` / `enforce`, K6) |
| 5 | Shots | (a) prop viewer, 3 fixed views, scale figure placed where it does not hide the model; (b) **context shot**: the asset placed in the golden scene at its `seen_at_m` distances in game light; (c) pose strip for rigs (`tools/rig_shots.gd`); (d) host compose for attachments (`tools/v09_models/compose.py`) | windowed render under the heavy lock, hard timeout (`tools/v08_models/render.py` pattern) |
| 6 | Judge | `build/pipeline/<id>/pass-N.json` | ship when isolation ≥ 8 **and** context ≥ 8 |
| 7 | Iterate | the next script edit fixes the top 3 gaps | stop rules below |
| 8 | Ship | `models/<id>.glb` + script + a row in `art/scores.json` | best contract-passing pass, never the last by default |

## Judge protocol

- **Inputs:** image 1 is the sheet (or the golden still for a context shot), image 2 is the render, image 3 is the pose
  strip or host shot. The prompt carries the contract, the class budget and the asset's rules, and the instruction to
  ignore what the model cannot change (lighting, camera, background). The `judge()` wording in
  `tools/asset_pipeline.py` is the starting point.
- **Schema:** Felsenburg's `JUDGE_SCHEMA` (match, score 0 to 10, summary, issues with aspect, concept_shows,
  render_shows and fix), extended with `context_score` and a `feasible` flag on each issue. An issue the budget or
  contract forbids is marked not feasible and is never sent to the builder.
- **Calibration:** at the start of every batch, run the judge on 6 anchor pairs with agreed scores (two shipped 8s,
  two 6s, two rejects from Felsenburg's `build/pipeline/`). If it is off by more than 1 point on average, fix the
  prompt before judging the batch. Self-scores are smoke tests, never ship gates (L10).
- **Pairwise tie-break:** when a pass ties or moves within ±1, ask the judge "A or B, and why", instead of trusting
  noisy absolute scores (`pitch_works` scores moved 6, 7, 6, 6).
- **The agent reads every PNG itself.** Judges miss floating props and z-fighting (`V08_BIOMES_PLAN.md`).

## Iteration policy

- Budget: 3 judged passes plus 1 rescue pass.
- **Stop rule:** if two passes in a row do not raise the score, more passes will not help (`bridge_gate` took 9
  passes to reach 7). Fix the input instead: the contract, the sheet, the budget or the rule. Then restart the count.
- Below 8 after the budget, ship the best pass to an "under bar" list with a reopen reason, so it doesn't block
  content.
- Keep the best pass. `kelp` scored 7 on pass 1 and 3 to 6 later.

## Failure library: rules learned once and applied to every build

Each rule has an id, and assets name the rules they use. Starting set, from the prompt constants in
`tools/asset_pipeline.py` and the handoffs:

| id | Rule | Origin |
|---|---|---|
| `masonry_blocks` | Stone faces built from blocks of 2 × 2 or 4 × 2 cubes in a running bond, one colour per block, one-cube inset darker mortar; no per-cube noise, no checkerboard | `wall_section` contract, `_STONE` |
| `natural_rock` | Rock never reads as a box, tower or slab with a flat front; terraced lopsided mass of large offset blocks; connected moss caps, not isolated green cubes | `_NATURAL` (springs stuck at 6) |
| `rock_family` | Rock props use the terrain's rock colours exactly (Felsenburg: a cool neutral grey) | `_MTN_ROCK`, `rock_family.gdshaderinc` |
| `rest_pose` | Rigged figures in rest pose: arms straight down, tool upright in the right fist through the grip cell; skirts as an A-line envelope on the torso | `docs/CHARACTERS.md`, `tools/rigkit.py` |
| `no_ground` | No terrain slab, water or figures in the model: the game's ground surrounds it | `_NO_GROUND` |
| `shared_frame` | Kit pieces that join share one frame (deck height, post depth, flush joint faces) | `_DECK` (boardwalks) |
| `real_scale` | Animals and small props at real size; the strategy camera does not get exaggerated sizes unless the class says so | crow 0.20 → 0.14 m: in game 3 → 8 |
| `game_light` | Colours chosen on the palette board in game light; dark accents darker than they look on grey; no gloss on dark materials (it mirrors the sky) | `steel_dark`, pitch roughness 0.55 (L15) |
| `attachment_view` | Wall attachments are judged on their host from a second camera | `murder_hole` (L16) |

Add a rule whenever a judge complaint repeats across two assets.

## Organic forms (terrain, cliffs, mountains, big rocks)

These took the most rounds in Felsenburg (L1, L2): `tools/rockkit.py`, `mountainkit.py` and `erodekit.py` against "every
mountain a cone", "rock facade on grey polygons" and "too low poly, blocky". For the next game:

- They are built in Phase 1 look-dev, before systems, against references *and* anti-references, judged at the
  gameplay distances in the golden scene.
- They use the truth table: the rendered rock is exactly the unwalkable and unbuildable mask (L1).
- They are procedural kits (Blender scripts with erosion and LODs) with fixed seeds, so a rejected look is a parameter
  change, not a rebuild.

## Regression lock

- When the palette, lighting, post-processing, LOD or camera changes, re-render the context shots of the affected
  classes and the golden shots. A drop of more than 1 point blocks the change.
- `art/scores.json` (committed) keeps, per asset: pass, isolation score, context score, judge model, date, script hash.
  Handoff tables and contact sheets are generated from it (`tools/v08_models/handoff.py` pattern).

## Infrastructure (keep from Felsenburg)

- One headless Blender per job; Godot renders queued through one machine-wide lock (`FB_HEAVY_LOCK`, `lockf -k`)
  with a hard 900 s cap per run.
- A timeout fails one asset, never the batch (`_worker` in `tools/asset_pipeline.py`).
- `models/*.glb` ship as authored; LODs are baked and committed, so a fresh checkout doesn't fall back to raw
  `GLTFDocument` loads.

## What changes against `tools/asset_pipeline.py`

| Felsenburg v0.2 loop | v2 |
|---|---|
| Builder and judge are the same model (`codex exec`) | different model families; adapters per role |
| Interactive Blender session over MCP; only the glb survives | committed build script per asset |
| `ASSETS` Python dict, numbers also in `CLAUDE.md` | `art/assets.json`, the only place |
| Prop viewer on a grey slab | prop viewer plus context shot in the golden scene at gameplay distances |
| One `WORLD` style string | `ART_BIBLE.md`: key art, target stills, palette board, references, anti-references |
| No sheet check | the sheet is judged against the contract before building |
| Ties keep the first pass | pairwise judge, human on close calls |
| One material per palette colour | one material per model (P8) |
| Fixed 3-pass budget | 3 + 1, stop rule, fix the input |
| `FB_HEAVY_LOCK` optional | lock on by default |
