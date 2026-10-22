# Next-game kit: what Felsenburg taught us

A starter kit for the next 3D Godot game built with the same pipeline (concept art → Blender → Godot → judge model,
parallel coding agents in tracks). The goal is much better quality on the first try. It is distilled from Felsenburg's
full history on `origin/v09/main`: 1573 commits, 22 releases, about 90 handoffs and the v0.8.10 performance pass.

| File | What it is |
|---|---|
| `RETROSPECTIVE.md` | What worked (K1 to K9) and what cost the most (L1 to L23), with numbers and paths |
| `PLAYBOOK.md` | The process for the next game: phases 0 to 6, each with an exit gate |
| `PERFORMANCE.md` | The first big perf pass: 14 mistakes not to repeat and the day-one runtime spec |
| `ART_PIPELINE.md` | Art pipeline v2: roles, one spec file, sheet check, context judging, stop rules, failure library |
| `templates/` | `CLAUDE.md`, `VISION.md`, `ART_BIBLE.md`, `FEATURE_PLAN.md`, `TRACK_BRIEF.md`, `assets.example.json`, `budgets.example.json` |
| `commands/` | Phase briefs for Claude Code: `ng-00-vision`, `ng-01-lookdev`, `ng-02-foundation`, `ng-03-integrate`, `ng-04-playtest`, `ng-art-batch` |

## The twelve rules that matter most

1. **Lock the vision before code.** Pillars, loop numbers, one reference game per dimension, the conventions
   checklist, target machine and budgets, and a decisions table with defaults. (Felsenburg flipped gold, food, phase
   length and the HUD paradigm mid-flight.)
2. **Prove the look in Godot before systems.** A golden scene at the three gameplay cameras, judged ≥ 8 against target
   stills, with final light, sky and fog, and the hardest landform first. (Cliffs were rebuilt five times; the sky came
   last.)
3. **References and anti-references for every risky surface**, from the start. (Felsenburg's cliff anti-references
   arrived after five rounds.)
4. **Look == rule.** One function decides how ground looks, whether it is walkable and whether it is buildable. Paths
   shown are the nav's real paths. (Stone slopes in v0.7.1, reversed in v0.7.2; "0 of 107 beaches followed their
   road".)
5. **Runtime architecture from day one:**
   - a 20 Hz tick with a scheduler and buckets;
   - a shared path service;
   - one loop per entity kind and a rig driver;
   - an event-driven UI;
   - single-material exports and MultiMesh;
   - shader variants;
   - workers for bakes.

   (Felsenburg retrofitted all of it at about 116k lines.)
6. **Profile per stage before choosing an architecture; stop tuning when over 1.5× budget.** (The perf plan was wrong
   in four places; four tuning rounds gained a few fps, one structural pass cut wave-start frames from 103 to 26.6 ms.)
7. **Real target hardware and a quiet, locked perf runner, with budgets as a merge gate.** (The "average PC" was a
   formula; the measurements were made on a machine shared with six agents.)
8. **The builder never judges itself.** Committed build scripts, an independent judge, a sheet check before building,
   context shots at gameplay distance in game light. (The self-judge gave 8 where Argon gave 5; props that scored 8 in
   isolation scored 3 in the game.)
9. **Fix inputs, not pass counts.** Stop after two passes without improvement and fix the contract, sheet, rule or
   budget. One spec file (`art/assets.json`) holds every asset number. (First passes averaged 5.8; `bridge_gate` took
   9 passes to reach 7.)
10. **Stubs keep the hard seams.** The stub map is the golden terrain, not a flat plane. Boot with stubs and boot real;
    run a composition smoke on three seeds. (Enemies froze on cliffs and walked through wall seams only on the real
    island.)
11. **Small contracts, small files, green main.** Contracts only for the slice, documented in code; split files at 1500
    lines; known failures have owners. (A 3800-line design doc, a 6.6k-line combat file, 8 to 27 suites red on main
    during the perf pass.)
12. **Feedback becomes decisions.** Every designer remark is logged with a class, a decision id and a knob, and every
    feature wave has an interaction matrix. (The "why" behind Felsenburg's reversals was scattered across handoffs.)

## Starting the next game

1. Create the new repo. Copy `docs/next-game/` into it as `docs/kit/`, and `docs/next-game/commands/*.md` into
   `.claude/commands/`.
2. Run `/ng-00-vision <pitch>` with the designer, until `docs/VISION.md` is approved.
3. Run `/ng-01-lookdev`, until the golden scene passes its gate and the designer signs off.
4. Run `/ng-02-foundation`. It reuses Felsenburg's proven core pieces (listed in the brief) and adds the runtime spec,
   the harnesses and the art pipeline v2.
5. Plan the slice with `templates/FEATURE_PLAN.md`, write the track briefs from `templates/TRACK_BRIEF.md`, start the
   worktrees (`scripts/vs-worktrees.sh`) and the tracks in parallel, with `/ng-art-batch` for content.
6. Run `/ng-03-integrate`, then `/ng-04-playtest <feedback>` after each designer session. Repeat with feature waves.

Felsenburg itself is not changed by this kit. Evidence paths in these documents refer to `origin/v09/main`; open it
with `git worktree add --detach /tmp/fb09 origin/v09/main`.
