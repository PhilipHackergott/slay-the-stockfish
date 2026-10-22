---
description: Phase 1 – art bible and golden scene: prove the final look in Godot before any system is built
argument-hint: [optional focus, e.g. terrain only]
---
Read `docs/VISION.md`, `docs/kit/PLAYBOOK.md` § Phase 1, `docs/kit/ART_PIPELINE.md`,
`docs/kit/PERFORMANCE.md` § Rendering, and `docs/kit/RETROSPECTIVE.md` (A and D).

Produce `docs/ART_BIBLE.md` from `docs/kit/templates/ART_BIBLE.md`, plus:

1. **Targets.** `art/keyart.png` and `art/targets/{near,mid,far}.png` at the gameplay cameras from `VISION.md`
   (painter: `GenerateImage` with the key art as reference). For each risky surface (landform, cliffs, water, sky,
   vegetation), references and **anti-references** under `art/targets/ref/` and `art/targets/anti/`. The designer
   approves them before step 3.
2. **Truth table, palette, scale.**
   - The truth table: class → look, walkable, buildable, cost, deciding function.
   - `art/palette.json`.
   - The asset classes and budgets in `art/assets.json`, split out of `perf/budgets.json`.
3. **Golden scene** (`scenes/golden.tscn` + `tests/proof/golden_shots.gd`, fixed seed):
   - Build the hardest visual problem first: the landform with its cliffs, mountains and coast as a procedural Blender
     kit or generator. Use the truth-table function for looks, nav and placement from the start.
   - Then final lighting, sky, fog and post per preset (`#if` variants).
   - Then the palette board at day, dusk and night.
   - Then 5 to 8 hero assets through the art pipeline (`docs/kit/commands/ng-art-batch.md`).
4. **Judge and iterate.**
   - Render the three golden cameras windowed.
   - Run the scene judge (independent model, `Task` subagent with `file_attachments: [target, shot]`) against each
     target still.
   - Fix the three biggest gaps per round, and read every PNG yourself.
   - At most 5 rounds per camera. If two rounds in a row don't improve the score, change the approach (kit, shader or
     reference), not the parameters.
5. **Measure.** Run the golden scene in the perf harness (or a minimal one: frame, GPU proxy, draws, primitives) on the
   target machine against `perf/budgets.json`.

Gate:
- All three cameras at ≥ 8 against their targets, with side-by-side sheets `build/proof/golden/<cam>-vs-target.png`.
- The palette board approved.
- Perf numbers within budget, or a written plan to get there.
- The designer signs off.

Commit the targets, bible, palette, `assets.json`, golden scene and proof scripts.

Focus: $ARGUMENTS
