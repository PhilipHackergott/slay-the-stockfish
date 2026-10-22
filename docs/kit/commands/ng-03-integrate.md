---
description: Phase 4 – integrate the track branches: ordered merges, gates after each, composition smoke, interaction matrix, golden and perf regression
---
Read `CLAUDE.md`, every `docs/handoff/<track>.md` and `docs/contract-requests/<track>.md`, and
`docs/kit/PLAYBOOK.md` § Phase 4. You are the only agent allowed to edit `src/core/`, and only through accepted
contract requests.

1. **Order.** Merge in the order of the dependency graph (map → buildings → economy/population → combat → rounds → ui
   → devtools, or this game's equivalent). Before each merge run `scripts/check_ownership.sh <track> <base>` on the
   branch.
2. **After each merge** re-run parse, boot (stubs and real), `scripts/test.sh` all, and
   `CONTRACT_STUBS=1` contract suites.
   Fix integration breaks in `tests/integration/` or through a contract change, never by editing a track's code
   without writing it down in `docs/handoff/integration.md`.
3. **Contract requests.** Accept or reject each one with a reason. Land the accepted ones in core and remove the track
   adapters they replace.
4. **Composition smoke** on the real map with three seeds:
   - a scripted run through the slice (build, produce, recruit, defend, a boss, a loss);
   - it must end without deadlocks and without frozen, stacked or wall-walking units;
   - log the resource curve.
5. **Interaction matrix.** Turn every pending matrix check from the plan green, or record why not.
6. **Golden and perf regression.**
   - The golden shots through the scene judge must not drop more than 1 point against the last accepted ones.
   - The perf harness must stay within 10% of the reference, or the regression is explained and accepted by the
     designer.
7. **Release notes** `docs/releases/<version>.md`: what changed, why (decision ids), known issues, the gates and their
   results.

Gate: all of the above green on the integration branch. Then hand the build to the designer
(`docs/kit/commands/ng-04-playtest.md`).
