---
description: <version> track <name> – <one line of items>
argument-hint: [optional focus]
---
Read first: `CLAUDE.md`, `docs/<PLAN>.md` (your row, decisions <D…>, the interaction matrix, "Visual verification"),
`docs/PITFALLS.md`, `docs/PERFORMANCE.md` § Rules for every new feature, the contracts you use
(`src/core/contracts/<…>.gd`), the stubs that stand in for your peers (`src/core/stubs/<…>.gd`), and your targets
`art/targets/<…>` plus the references and anti-references.

Own worktree `../<game>-<track>` (branch `<version>/<track>` from <commit>). Change **only**: <exact paths and file
prefixes>, tests `tests/<track>/test_<version>_*.gd`, proof scripts `tests/<track>/proof/*`, `docs/handoff/<track>.md`,
`docs/contract-requests/<track>.md`.

| # | Item | Approach | Truth-table rows | Perf budget | Proof slug (target) |
|---|---|---|---|---|---|
| T1 | <item> | <files, functions, data knobs> | <rows or —> | <ms / draws> | `<slug>` (vs `art/targets/<…>`, ≥ 8) |

Determinism: <stream names>. Threads: <what runs on workers, what publishes on main>.
Tests (fast and targeted, ≤ <n>): <list the behaviours>. Run only `lockf -k /tmp/<game>-heavy.lock scripts/targeted.sh
<track> <suites>`.
Perf: `tests/perf/run_perf.sh <label> <map>` A/B against the reference; numbers in the handoff.
Visual verification: windowed shots, an independent judge per `docs/<PLAN>.md`, at most 3 rounds per item; READ every
PNG yourself.
Gates:
- parse gate;
- boot smokes `--stubs=all` and with your real implementation → `<GAME> BOOT OK`;
- the targeted run with your own tests counted;
- the perf A/B;
- `scripts/check_ownership.sh <track> <base>`.

Handoff `docs/handoff/<track>.md` (template `docs/handoff/README.md`):
- state per item;
- dev commands;
- tests;
- judge scores with shot paths;
- perf numbers;
- known gaps;
- open requests;
- assumptions.

Focus: $ARGUMENTS
