# Decision log: v0.1 (post-MVP ticket)

Every assumption made while building the rest of the handover ticket without asking. Each line
names the default chosen and where to change it. Data lives in `.tres` resources, so most of these
are a one-file edit. Mirrored to Notion: Project Slay the Stockfish → Build decisions.

## Promotion trees (the upgrade path)

- **All children shown at level-up.** The appendix lists candidate trees; a level-up offers every
  child of the current piece, not a random subset. Deterministic and player-driven. Change in
  `Run.upgrade_options`.
- **Children are per node, not per lineage.** A piece's children are the same however it was
  reached (Chancellor → Amazon or Aiwok, whether it came from Knight, Rook or Kniroo).
- **Trees as built** (`data/pieces/*.tres`, field `upgrades`):
  - Pawn → Knight, Bishop, Shieldbearer, Skirmisher, Spearman. Shieldbearer → Sergeant → Rook;
    Skirmisher → Outrider → Centaur; Spearman → Pikeman → Rook.
  - Knight → Rook, Centaur, Archbishop, Chancellor. Centaur, Archbishop → Amazon. Chancellor →
    Amazon, Aiwok.
  - Bishop → Rook, Dragon Horse, Archbishop. Dragon Horse → Queen.
  - Rook → Queen, Dragon King, Chancellor. Dragon King → Aiwok.
  - Queen → Leaping Queen → Maharani; Queen → Siege Queen → Bombard.
  - King → Warlord → Conqueror; King → Regent. Kings stay royal; the engine plays them as the
    pseudo-royal `w` with the tree piece's Betza.
  - Reward-only roots (uncommon): Wazir → Commoner → Centaur; Knibis → Archbishop; Kniroo →
    Chancellor; Cannon → Banner.
  - Legendary rewards with no children: Amazon, Aiwok, Nightmare.
- **XP thresholds** 3 / 8 / 15 / 24 / 35 per level (5 levels, the 5th added so the deepest trees can
  finish). `run_config.tres → xp_thresholds`.
- **Final forms convert XP to gold**: 2 gold per XP a maxed piece earns. `overflow_gold_per_xp`.
- **Custom pawns** (Shieldbearer, Skirmisher, Spearman, Outrider, Pikeman) promote like pawns:
  they join `promotionPawnTypes` and may not stand on rank 1 in formations or edits. Sergeant
  moves backwards, so it is not pawn-like.
- **Regent**: a second royal piece (the "twin") stands on the first free square of
  `twin_squares`. You lose only when both fall (engine: the last extinction piece is royal). The
  twin exists for one fight and is not a run unit; it earns no XP.
- **Letters per fight.** Non-standard pieces get letters from a 19-letter pool per fight, both
  sides combined. An army with more than 19 distinct fairy types cannot start a fight (logged
  warning, the node is skipped). Judged too rare to design around for v0.1.

## Rewards, gold and XP

- **Rarity tiers per act and node kind** (`data/acts/act*.tres → reward_rarity`). Act 1 fights:
  85 % common / 15 % uncommon. Guardians: uncommon or legendary only.
- **Legendaries are gated by unlocks**: Amazon after the first guardian, Aiwok after the second,
  Nightmare after a win.
- **Gold per win** rolled per act and kind (`gold`), e.g. act 1 fight 14–22, elite 35–50,
  guardian 60–80. Starting gold 30.
- **Relic choices**: start 1 of 4, elite 1 of 2, guardian 1 of 3.

## Acts, guardians, enemies

- **Three acts**: The Ossuary Stair, The Drowned Nave, The Engine's Throne. Each has its own map
  rows, encounter tiers, gold and shop odds. Act 1 and 2 end in a guardian (Choir Engine, Abbot
  Engine); act 3 ends in Stockfish at full strength.
- **Guardian reward**: gold, a piece reward, a relic, then the next act. A guardian also records
  an unlock.
- **Draw against a guardian or the boss ends the run** (you did not get past it). Draws in normal
  fights still count as survival, as in the MVP.
- **Enemy fairy pieces** appear from act 1 elites onwards and in most act 2/3 fights. No
  encounter may allow a mate in one on move 1 (tested against two reference armies).
- **Engine strength** rises through act tiers via `skill` and `movetime_ms` per encounter.

## Shop and events

- **Shop**: 3 pieces, 2 relics, restore a fallen piece. Piece price = 10 + 8 × value, +25 for
  legendaries; restore 45. Stock is rolled once per node, so leaving and saving does not reroll.
- **Events** may cost gold, a pawn or a random piece, and may give gold, a piece of a given rarity
  or transform a random piece. Options you cannot afford are shown but disabled.

## Relics (new)

- **Held Breath**: pass a turn (engine `pass` rule). The pass is the king moving to its own square.
- **Sanctuary Banner** (unlock: finish a run): your king reaching rank 8 wins.
- **Mercy Denied**: stalemating the engine wins (`stalemateValue = loss`).
- **Reliquary Knight**, **Ossuary Urn** (two pawns): pocket pieces like the Reliquary Bishop.
  Pocket drops only on ranks 1–4.
- **Puppeteer's String** (unlock: two runs): once per fight, move one of your pieces to an empty
  square in your half instead of moving. Not the king; pawns not on rank 1 or the promotion rank.
- **Soul Lantern** (unlock: first guardian): once per fight, lift a piece into your pocket as a
  free action, then drop it later as a move. The dropped piece keeps its unit identity and XP.
  Not the king; not if lifting exposes the king.
- **Candle of Patience** (+2 s increment), **Tithe Bowl** (+50 % fight gold).

## Meta-progression and difficulty

- **Profile** in `user://profile.json`: runs, wins, best act, highest difficulty unlocked, unlock
  keys, settings. Unlocks: finish 1 run, finish 2 runs, beat each guardian, beat Stockfish.
- **Difficulty tiers stack** (Slay the Spire ascension style): Mortal, Penitent (+2 enemy skill),
  Haunted (−60 s clock), Forsaken (−20 % gold, +20 % prices), Damned (one pawn fewer),
  Abyssal (elites +3 skill, engines think 1.5× longer, no early resigns). Winning on the highest
  unlocked tier unlocks the next.
- **Settings** (volumes, fullscreen) live in the profile; "Erase all progress" keeps settings.

## Save and continue

- **One run save** (`user://run.json`), written whenever the map is shown. Quitting mid-fight
  loses only that fight's progress: you restart the node. Save-scumming a fight is possible and
  accepted for a single-player roguelike.
- The run RNG state is saved, so a continued run rolls the same as an uninterrupted one.
- Starting a new descent with a save present asks before abandoning it.
- Autoplay, screenshots and tests use isolated profile and save files, so they never touch your
  real progress.

## Formation

- **Formation editor** on the map ("Arrange"): an 8×2 grid plus reserve, click to swap. Pawn-like
  pieces cannot stand on rank 1. Preferences persist per unit; new units fill free squares.

## Fight UI and flow

- **Pause** (Esc) stops the fight clock and the engine's turn presentation.
- **Hold Breath** has its own button; edits (swap, move, lift) are modes with a hint line and a
  cancel.

## UI design system

- **Textured kit, not vector UI**: Blender-rendered frames (iron, bone, stone) and
  Gemini-generated textures, nine-sliced in Godot (`assets/ui/kit/`, `kit.json` holds margins). Every
  element falls back to a flat style if a texture is missing, so the game never breaks on art.
- **One modal component** (`UiModal`) for every dialog: blurred backdrop, plaque title, crest,
  close button, footer. Screens build into its `body` and `footer`.
- Palette: bone text, ember accents, soul-blue for XP, gold for currency, blood for danger.

## Art

- **Fairy pieces are kit-bashed** from the existing piece parts in Blender (e.g. Chancellor =
  rook tower + knight head), so all 27 new pieces share the MVP's material language. Until a model
  exists the game shows the base family's model with a glowing halo.
- **Portraits** are rendered from the same models.
- **Relic and node icons** from Gemini, cut to the existing icon style.

## Audio

- Procedurally synthesised SFX and music (no licensed samples), generated by `tools/audio`.
  Buses Music and Sfx. Details in that folder's README.

## Packaging

- **Bundled Python, not a rewrite.** The chess core stays a Python sidecar (pyffish +
  Fairy-Stockfish). Each build ships a standalone CPython 3.12 with pyffish and the engine:
  `Contents/Resources/chesscore` on macOS, `chesscore/` next to the exe on Windows. It runs with
  `-E -s -B`, so the player's Python setup never interferes and nothing is written into the bundle.
- **macOS: one universal app** (arm64 + x86_64), because the official 4.7.1 template is universal.
  Python, pyffish and the engine are merged per architecture with lipo. Ad-hoc signed, not
  notarized: players need "Open Anyway" once.
- **Windows: x86-64 only.** Engine cross-compiled with mingw-w64 at the pinned commit (static).
  `msvcp140.dll` ships next to `python.exe` because pyffish needs it and CPython does not include
  it. Unsigned: SmartScreen shows "Run anyway". No console window (Godot starts the sidecar with
  `CREATE_NO_WINDOW`).
- **Verified**: both exports boot with `STS BOOT OK core=ok` from the bundled runtime only (Mac
  native and under Rosetta; Windows on a GitHub `windows-latest` runner).
- **Licences**: Fairy-Stockfish and pyffish are GPL-3.0; their licences, source URL and commit ship
  in `chesscore/licenses/` and `RUNTIME.txt`.
- Build: `tools/package/package.sh v0.1` → `dist/slay-the-stockfish/v0.1/` (zips + SHA256SUMS).

## Known gaps in v0.1

- An army with more than 19 distinct fairy piece types cannot fight (letter budget).
- Save points are map-only (no mid-fight save).
- No controller support; mouse only.
- Builds are not notarized (macOS) or Authenticode-signed (Windows).
- Windows usernames outside the system code page may break variant loading (temp path). Untested.
