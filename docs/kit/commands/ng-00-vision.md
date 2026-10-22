---
description: Phase 0 – vision lock with the designer (pillars, loop numbers, references, conventions, budgets, decisions)
argument-hint: [pitch or GDD path]
---
Read `docs/kit/PLAYBOOK.md` § Phase 0, `docs/kit/RETROSPECTIVE.md` (B and C) and the pitch or GDD:
$ARGUMENTS. Write no code in this phase.

Produce `docs/VISION.md` from `docs/kit/templates/VISION.md`:

1. **Pillars and loop.** Three pillars with a slice test each, and the core loop with numbers (phase lengths, resources,
   start stock, run length). Name the fantasy-critical system and say whether it is in the slice.
2. **References.** One reference game per dimension (camera, selection and orders, HUD, look, economy feel), with what
   we copy and what we don't. For each one, write down its concrete conventions.
3. **Conventions checklist.** Fill in every row of the template's list, marked slice, later or never, and add the
   reference games' own conventions.
4. **Budgets.** The target machine (an exact model the team can run builds on), the fps target, the frame, tick and GPU
   budgets, draw and triangle budgets, and entity counts (heavy scene = twice the largest planned wave). Copy them into
   `perf/budgets.json` (`templates/budgets.example.json`).
5. **Decisions.** Every open design question for the slice becomes a row: id, question, proposed default, knob, owner.

Ask the designer about every decision row whose default you cannot derive from the pitch. Present the questions in one
batch, with your proposed default for each.

Gate: the designer approves `docs/VISION.md`, and no decision row for a slice feature is open. Commit
`docs: vision lock`.
