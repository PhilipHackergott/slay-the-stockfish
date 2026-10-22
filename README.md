# Slay the Stockfish

Spike: a roguelike chess game. Status: Phase 0 (vision), no code yet.

## Kit

`docs/kit/` is the next-game kit distilled from Felsenburg (retrospective, playbook, performance from day one, art
pipeline v2, templates). The phase briefs are in `.claude/commands/`:

1. `/ng-00-vision <pitch>` until `docs/VISION.md` is approved
2. `/ng-01-lookdev` until the golden scene passes its gate
3. `/ng-02-foundation`, then tracks, `/ng-03-integrate`, `/ng-04-playtest <feedback>`

Kit evidence paths (`origin/v09/main`) refer to Felsenburg in `~/felsenburg`, where the remote is named `github`:
`git -C ~/felsenburg worktree add --detach /tmp/fb09 github/v09/main`.
