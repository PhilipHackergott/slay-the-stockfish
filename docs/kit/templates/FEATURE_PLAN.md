# <version> <feature> – plan

Modelled on Felsenburg's `docs/V08_BIOMES_PLAN.md` (decisions, visual verification, proof slugs), plus the interaction
matrix, perf budget and look-dev pass that version lacked.

## Goal and player-facing result
<what the player sees and does differently; link the designer's request in `docs/FEEDBACK.md`>

## Look-dev mini-pass (before wave B)
- References and anti-references: `art/targets/<feature>/`.
- Golden still(s) at the near, mid and far cameras: `art/targets/<feature>/{near,mid,far}.png`.
- Truth-table rows added or changed: <rows>.
- Accepted by the designer on: <date>.

## Waves
| Wave | Where | What | Parallel |
|---|---|---|---|
| A | integration branch | contracts (`src/core/contracts/…`), stubs that model the new seams, `art/assets.json` entries, interaction-matrix checks as pending tests, briefs | no |
| B | worktrees | tracks below + art batch | yes |
| C | integration | merge, composition smoke (3 seeds), golden-shot regression, perf A/B, release notes | no |

## Tracks
| Track | Owned paths | Items | Proof slugs |
|---|---|---|---|
| <track> | <paths> | <items> | <slugs> |

## Decisions (the designer can overrule; each switch is data or one constant)
| id | Question | Default | Knob | Owner |
|---|---|---|---|---|

## Interaction matrix
Every pair that shares ground, routes, resources or the screen. Each cell is a cheap check (test or probe) that wave A
lands as pending and wave B turns green.

| | terrain | water | paths | buildings | combat | economy | ui |
|---|---|---|---|---|---|---|---|
| <feature> | e.g. never on cliffs | | routes still reach the goal from every spawn | placement rules | | | readable at far zoom |

## Perf budget
- Added cost at the default camera: ≤ <x> ms frame, ≤ <d> draws, ≤ <t> k triangles.
- Added cost per tick in the heavy scene: ≤ <y> ms. Metric names: `<name>_ms`.
- Measured with `tests/perf/run_perf.sh` A/B against the reference; numbers in each handoff.

## Visual verification
Windowed proof shots under `build/proof/<version>-<track>/<slug>.png`, judged by an independent model (`Task`
subagent, `file_attachments: [<target>, <shot>]`). Prompt: "Image 1 is the TARGET look, image 2 the game. Judge only
<items>. Score 0–10, list the three biggest visual gaps with concrete fixes. Answer JSON {score, match, gaps[]}."
Save the answer as `judge-<slug>-N.json`. At most 3 rounds per item; ship at ≥ 8 or keep the best and list it. The
agent reads every PNG itself.

## Assumptions
<listed by tracks in their handoffs, switchable by data>

## Proof slugs
<list>
