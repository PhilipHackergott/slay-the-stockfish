---
description: Phase 5 – playtest loop: turn the designer's feedback into classified, decided, knob-backed work
argument-hint: <feedback text or file>
---
Read `docs/VISION.md` (decisions), `docs/FEEDBACK.md`, the latest release notes, and the feedback: $ARGUMENTS.

1. **Log.** Append every remark to `docs/FEEDBACK.md`: date, build, seed, the designer's words (quoted, untranslated),
   and a class:
   - `bug`: the game breaks its own rules;
   - `tuning`: a number;
   - `convention`: a genre standard we lack; also add it to the conventions checklist in `VISION.md`;
   - `look`: needs a target, reference or anti-reference;
   - `vision`: changes a pillar, the loop or a locked decision.
2. **Decide.**
   - `tuning` and `bug` get a fix plan.
   - `vision` gets a new or changed row in the `VISION.md` decisions table, with old and new default, and the designer
     confirms it before any track starts. Never let a vision change reach a track without a decision row.
3. **Look feedback first gets a picture.** Before any code: a target still or reference and an anti-reference (the
   current shot) under `art/targets/<topic>/`, approved by the designer. Then the change is judged against it.
4. **Group** the work into the next feature wave (`docs/kit/templates/FEATURE_PLAN.md`) or a small fix branch.
   Tuning goes into data (`data/…`) with a balance sim run (`--sim`) and before/after numbers.
5. **Answer** the designer with a short table: remark → class → decision → where it lands.

Never reverse an earlier decision without naming it (id, date, why it changes now).
