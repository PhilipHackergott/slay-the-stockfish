---
description: Art batch – build a set of assets with the v2 pipeline (spec, sheet check, voxkit script, contract check, isolation and context shots, independent judge)
argument-hint: <asset ids or set name>
---
Read `docs/ART_BIBLE.md`, `docs/kit/ART_PIPELINE.md` (all of it), `art/assets.json`, `art/palette.json`, and the
failure library rules named by the assets: $ARGUMENTS.

Owned: `art/assets.json` entries for these ids, `art/concepts/<id>.png`, `tools/models/<id>.py`, `models/<id>.glb`
(no `.import`), `art/scores.json` rows, `docs/handoff/art-<batch>.md`.

1. **Calibrate.** Run the judge on the 6 anchor pairs. If it is off by more than 1 point on average, fix the prompt
   first.
2. **Spec.** Complete each entry: class, height, fit, desc, contract in metres, set, style_ref, refs, anti_refs, rules,
   parts, host, context, views. Check the budget against the class.
3. **Sheet.**
   - Paint from the key art, the set's approved style sheet, the references and the contract (painter: `GenerateImage`
     with reference images).
   - **Sheet check:** the judge compares the sheet with the contract (orientation, size, joints, below-ground parts).
     Repaint before building if it fails.
   - The designer approves one sheet per new set.
4. **Build.** `tools/models/<id>.py` on `_kit.py` and voxkit. Measure first: print the plan in voxels. Use palette
   names only (at most 3 new colours, listed in the handoff). Run headless until it prints `CHECK <id> ok`, with one
   material.
5. **Shots.** All windowed, under the heavy lock, with a 900 s cap:
   - prop viewer views;
   - the **context shot** in the golden scene at every `seen_at_m`;
   - a pose strip for rigs;
   - a host compose for attachments.
6. **Judge.** The independent model, with sheet or target, render and pose or host image. Ship at isolation ≥ 8 and
   context ≥ 8. Send only feasible issues to the next pass; use a pairwise A/B on ties. Read every PNG yourself.
7. **Iterate.**
   - Budget: 3 passes + 1 rescue.
   - If two passes in a row don't improve, fix the input (contract, sheet, rule, budget) and restart the count.
   - Below 8 at the end: ship the best pass to the under-bar list with a reopen reason.
   - Add a failure-library rule when a complaint repeats across two assets.
8. **Record and hand off.**
   - `art/scores.json` rows.
   - A contact sheet per set (`build/proof/art-<batch>/<set>.png`).
   - Handoff with a table: id, passes, isolation and context scores per pass, shipped pass, size, triangles, new
     colours, rules added, gaps.

Report the batch metrics: first-pass mean, share ≥ 8, passes per asset, isolation-vs-context gaps.
