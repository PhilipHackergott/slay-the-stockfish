# Decision log: v0.2 (playtest fixes)

Built from the v0.1 playtest: text overflowed with no scrolling, upgrade trees felt wonky, rewards
were "always pick the highest value", too few relics. Chosen core fix: a Command cap plus
value-banded offers. Slices: a readable, b choices, c reliquary and campfire, d randomness and
events. Mirrored to Notion: Build decisions → v0.2 decision log.

## a: Readable

- **Cards grow to their text** (`UiKit.fit_to_content`); option buttons take a fixed width when
  they sit in a row (`option_button(..., width)`), so labels never collapse to a sliver.
- **Modals fit the viewport and scroll** past it (`UiModal`); the HUD left column, relic icon grid
  and event options wrap instead of overflowing.
- **Overflow test** (`tests/test_ui_fit.gd`) walks every screen at 1920×1080 and fails on clipped or
  collapsed labels.
- **Unlocks apply from the next run**, so a run never changes its own pools mid-way.

## b: Choices (tiers, Command, rewards)

- **Tier ladder 1–5 plus legends** (`piece_def.tier`). Every promotion goes exactly one tier up,
  at most three options (`Run.upgrade_options`). Replaces v0.1's "all children shown".
  Value step per promotion: +1–2 at tiers 1–2, +2–4 at tiers 3–4.
- **XP thresholds** 3 / 9 / 18 / 30 / 45 / 65.
- **Perks instead of a promotion**: Veteran (+50 % XP), Bulwark (gets up after a won fight),
  Vanguard (−1 Command), Bounty (5 gold per capture). One perk per level-up, fixed per unit and
  level (no reroll fishing), two at most, none for royals (`max_perks`).
- **Legends only by Ascension**: a guardian lets one tier-5 piece become a legend. They are no
  longer reward cards.
- **Command cap**: deployed pieces cost their value, the king is free; the rest waits on the bench.
  Cap 15 / 24 / 34 per act (`act*.tres → command`). Bench states: auto (filled by the game) or held
  (you benched it). A promotion over the cap benches the cheapest piece.
- **The boss is uncapped** (`final_uncapped`): the final fight takes every healthy piece, and gets
  no reinforcements.
- **Enemies scale with your Command**: material target = Command × ratio (fight 0.8, elite 1.0,
  guardian 1.15). Missing material arrives as reinforcements that never check your king, never
  allow a mate in one, and never take their own king's flight squares.
- **Value-banded offers**: each reward rolls one tier for its node kind (act 1 fight 1–2, elite 2–3,
  guardian 3; +1 per act), then distinct pieces of that tier. Measured: an offer whose best card
  beats the next by 2+ value went from ~40 % (v0.1) to 0–2.5 %.
- **Train slot**: 25 % of offers swap one card for XP to a piece (4 / 6 / 8 per act). Skipping
  pays 10 gold.
- **Shop**: tiered stock, rerolls (15 gold, +10 each), Bone Surgeon (promote one tier for 60 gold,
  dismiss for 10).
- **Move diagrams** come from Betza (`src/core/betza.gd`) on cards, shop and codex.
- **Core op `mates_in_one`** backs the reinforcement and encounter safety checks.

## c: Reliquary and campfire

- **Relic tiers**: common, uncommon, rare, boss (guardian only), curse (never offered). Odds per
  source in `run_config.relic_odds` (e.g. elite 60 % uncommon / 40 % rare). Shop prices by tier
  50 / 85 / 130 / 200.
- **19 new relics, 3 curses** with data-driven effects (`relic_def.gd`). Relics never weaken the
  final boss (skill and thinking-time relics skip it).
- **More relic chances**: a sealed reliquary (treasure) once per act (gold + 1 of 2 relics); a
  flawless fight offers a relic 35 % of the time; a flawless elite shows one more card. Measured:
  guaranteed relic picks on a random path per act went from ~1.4 to 2.3–2.6 (acts 1–2).
- **Relic shards were dropped** (a reward-slot currency toward a relic): treasure nodes and
  flawless relics add relic chances without a second currency.
- **Campfire: one action per visit**. Mend (raise up to 2 fallen, XP kept), Temper (one tier up,
  no XP), Drill (+3 XP to every deployed piece), Study (see the guardian, +60 s against it), Rite
  of Ash (burn one piece; another gains its XP plus its value), Kindle (a relic's numbers ×1.5,
  drawbacks unchanged), Cleanse (burn a curse, shown only when cursed).
- **Campfire screens are card pickers** (after the v0.2 playtest: the upgrade menu looked unfinished).
  The actions are one row of equal cards. Temper and Rite take two steps (the piece, then its new
  form or its heir), each with Back, and every grid sizes its cards to the largest. The recruit
  card (`UiKit.piece_card`) and unit card (`UiKit.unit_card`) are shared with the reward screen.
- **Event effects scale with tiers** (transform one tier up, gain a piece of a tier), not rarity.

## d: Randomness and events

- **"?" nodes** roll on entry: event 65, fight 15, treasure 10, shop 10. Every "?" that is not a
  fight adds 10 to the fight weight (pity), carried across acts (`flags.unknown_streak`).
- **Omens** on 25 % of fight and elite nodes, rolled with the map and shown as badges: Blood Moon
  (×2 XP), Fog (engine −4 skill), Iron Rain (+2 enemy pawns, ×1.5 gold), Eclipse (no increment),
  Requiem (the slain rise after a win). Never on guardians or the boss. `data/omens/`.
- **The roaming elite** starts on row 3 with an unused elite of the act's tier, steps along a
  random edge every 2 nodes you enter, and fights you if you enter its node (rare-relic odds).
  If it reaches the guardian, it joins: the guardian's material target rises by 0.15 × Command.
  No roamer in the final act.
- **18 events, 6 per act** (`event_def.acts`); the act's pool first, then unused ones from other
  acts, then repeats.
- **Problems (mate in two)**: 9 positions, 3 per tier, generated by `tools/gen_puzzles.py` and
  verified by the core op `mate_in_two` (exactly one key, at least 3 replies, no capturing key, a
  quiet key from tier 2). Your own pieces and relics stay out; move 2 must mate or the problem
  stands. A win pays a relic (rare-leaning odds), a loss costs gold, never the run. Each problem
  is seen once per run.
- **The Pit (skirmish)**: your king and the three greenest deployed pieces against a small army.
  Nothing stays dead, captured XP is kept, it does not count as a won fight.
- **The Tailor's stitch**: one non-pawn, non-royal piece gains a step (W, F) or a knight's leap (N)
  for 30 / 55 gold. Built as a lazy synthetic piece `<base>__<atom>` (Betza = base + atom, value
  +2 / +3, the base's look and upgrades), never in the codex or shop. One stitch per piece, kept
  at its level, lost on promotion. Only atoms that add squares are offered.
- **Pacts carry curses**: Bone Notary (gold or a relic, for Debt of Bone), Sunken Pact (a tier-up
  for Creeping Rot, or a rare-leaning relic for Cracked Hourglass), the Throne's Offer (two
  tier-ups for Creeping Rot, or 150 gold for Debt of Bone). Cleanse removes them.
- **The Oracle** gives +90 s against the boss; the Ferryman restores every fallen piece for gold
  or trades a pawn for +3 XP all round.
- **No fight is won on the first move**: if your formation could mate at once (an army without
  pawns can, against the boss's untouched start), the engine moves first. If the engine could then
  mate at once too, you keep the first move.

## v0.1 decisions replaced

- "All children shown at level-up" → at most three, one tier up.
- "Rarity tiers per act and node kind" for rewards → one rolled tier per offer; legends via
  Ascension only.
- "Shop: 3 pieces, 2 relics" → tiered stock with rerolls and the Bone Surgeon; relic prices by tier.
- XP thresholds 3 / 8 / 15 / 24 / 35 → 3 / 9 / 18 / 30 / 45 / 65.

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

- **Textured kit, not vector UI**: 47 frames and ornaments (forged iron, bone, stone, horned skulls)
  modelled and rendered in Blender from a Gemini concept sheet, nine-sliced in Godot
  (`assets/ui/kit/`, `kit.json` holds margins; rebuild with `tools/blender/ui/build_all.sh`).
  Every element falls back to a flat style if a texture is missing.
- Stone fills are tinted darker in code (`UiKit.KIT_TINT`) so bone and gold text keep contrast.
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

- **All audio is synthesised in code** (numpy/scipy, no samples, no licences): 25 SFX, 5 music
  loops (title, map, fight, boss, campfire) and a wind ambience. `tools/audio/build.sh` rebuilds
  the set byte-identically in about 30 s.
- Loops are seamless by construction (events wrap, reverb tails fold back), not crossfaded.
- Levels: SFX peak −3 dBFS, music and ambience −18 LUFS. Buses Music and Sfx; volumes in Settings.
- Checked by measurement and spectrograms only; no listening pass yet.

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

## Arenas (v0.3 slice)

- **An arena is an overlay on a fight or elite node**, rolled with the map like an omen
  (`data/arenas/*.tres`, `ArenaDef`): variant lines, rubble walls (FEN `*`), an n-check count, a
  marked zone. The encounter is drawn as usual; arena-specific encounter lists come later.
- **Placement per act** (`ActDef.arena_*`): act 1 at most one, from row 3, fights only; act 2 up to
  three, half the elites; act 3 up to four, every elite (elites roll first). Never on "?" nodes,
  guardians or the boss.
- Built: **Summit Altar** (a king on d4/e4/d5/e5 wins, either side), **Collapsed Nave** (rubble on
  c4/f4/c5/f5), **Tolling Bells** (third check wins). Arenas are symmetric; one-sided rules stay relics.
- Walls live in `FightController.walls`, never in `board`, so nothing treats a wall as a piece.
- Region lines from several sources merge into one line (`VariantGen`), so Sanctuary Banner and
  the Summit Altar both count.
- Variant wins are checked before "no legal moves" in the core, so they never read as mate.
- Props are procedural stand-ins (stone blocks, gold zone glow) until Blender props exist.
- Seven more for review (10 in all): **The Hunger** (`mustCapture`), **The Ascent** (a king on the
  far rank wins), **Shallow Crypt** (pawns promote on the 6th / 3rd), **Narrow Passage** (rubble
  a3-a6, h3-h6), **Burning Stakes** (`wallingRule = past`: every move burns the square left),
  **Gorgon Cloister** (`petrifyOnCaptureTypes = rbnq`: the capturer becomes a wall), **The Crow**
  (`wallingRule = duck`). "Mercy's End" (stalemate loses) was cut: the Mercy Denied relic is that rule.
- Walls can change every move: the controller diffs the FEN walls after each move. A capturer turned
  to stone leaves the unit map but is not slain (`petrified`); its statue keeps its look.
- The pinned engine refuses duck walling with a king, so The Crow sets `king = -`, `commoner = k`,
  `extinctionPieceTypes = kw` (both kings pseudo-royal; check and mate still work, a side with no
  move loses). The core now raises when the engine rejects a variant; before, the engine fell back
  to plain chess silently while the rules library played the variant.
- Walling moves are `from to,to wall` (about 30 per piece move); `mates_in_one` tries one wall
  square per piece move and all of them only where it checks or ends the game (setup guard, 7 s to
  under 1 s). The player clicks the piece, the target, then the crow's square.

## Piece readability

- Hovering any piece (either side, either turn) shows a tooltip at the cursor: portrait, side, name,
  unit stats or capture XP, moves text and move diagram. Rubble squares explain themselves.
- Fairy pieces wear a nameplate (world-space Label3D, blue-white for yours, ember for the engine's).
  Setting "Names over pieces": special pieces (default) / all / none; holding Alt shows all names.
- Plates sit at two heights by square colour, so neighbours never overlap. They follow the piece.
- Obsidian rim light raised (0.32 to 0.6, wider falloff) so the engine's pieces separate from the
  dark squares at the far side. Model silhouettes are unchanged; new silhouettes are art work.

## Clock gold

- A won map fight turns the clock left into gold: 1 per 20 s, at most 20 (`time_gold_seconds`,
  `time_gold_max` in the run config). A full 5:00 clock is 15 gold, about a tier-1 fight's base.
- Event fights (problems, skirmishes, the Pit) pay nothing for the clock; they have their own stakes.
- Not scaled by omens or gold relics, so the incentive reads the same in every fight.
- Presentation: coins fly from the clock into a purse while the converted seconds drain (gold
  digits), one `coin_tick` per coin rising in pitch, then the `gold` sound; the Victory modal and
  the reward screen list it.
- Autoplay keeps an almost full clock, so autoplay gold totals now overstate a human run.

## Scarce gold

- Gold is scarce by default so the clock is worth racing: base fight income cut to about 0.6x
  (act 1 fights 8-13, elites 21-30, guardian 36-48; acts 2/3 scale up), starting gold 25, skip 6,
  treasure 9-18. Prices cut to about 0.85x (pieces 8 + 7 per value, legendary +20, restore 38,
  reroll 12 +8, surgeon 50, relics 42/72/110/170). Event costs and rewards are unchanged.
- Gold relics follow the base: Pilgrim's Coin +5 per won fight, Debt of Bone -9.
- Seed-7 autoplay earns 529 gold over the run (852 before); a human run with less clock left earns less.

## Elite affixes, guardian arenas, second chance (v0.3)

- **Elite affixes** (`data/affixes`, `ActDef.affix_*`): act 1 one, act 2 one or two, act 3 two,
  drawn without repeats from the act's pool (act 1: Reinforced, Deep Thought, Vigilant, Hurried;
  act 2 adds Brutal, Legion; act 3 adds Relentless). Rolled with the map, saved with it, shown as a
  crown badge and tooltip lines on the node and as banner lines in the fight. Elites only; the
  roaming elite and guardians carry none. Affixes do not raise gold yet.
- **Guardian signature arenas** (`EncounterDef.arena`): the Choir Engine fights on Tolling Bells,
  the Abbot Engine on Gorgon Cloister. The boss stays plain chess.
- **Lich's Phylactery** (rare relic, `RelicDef.second_chance`): a fight that would end the run
  (a loss, or anything but a win against a guardian or the boss) starts over instead; the relic
  shatters and the loss is not applied. The base rule (losing ends the run) is unchanged.
- **Unlocks gate arenas and events too** (`unlock` on `ArenaDef` and `EventDef`, same keys as
  pieces and relics). Beating guardian 1 opens The Hunger, Gorgon Cloister and The Sunken Pact;
  guardian 2 opens Burning Stakes, The Crow, The Last Pit and Throne Pact; the first finished run
  opens The Ascent, Tolling Bells and The Drowned Composer. Meta-progression stays content-only.
  A guardian's signature arena ignores its lock.
- **Fusion (Graft)**: recipes live in `RunConfig.fusions` (knight + bishop = archbishop, knight +
  rook = chancellor, bishop + rook = queen, knight + queen = amazon), parts at most
  `fusion_tier_band` (3) tiers apart, never the king, the result must be unlocked. The part with
  more XP survives: XP = its own + half the other's, the higher level, one perk (the player picks
  at a campfire, the first otherwise), both lineages, captures summed. It costs the higher part's
  value + 1 Command (`Unit.command_override`, kept until the unit changes type), so a graft is a
  Command bargain, not a free upgrade. Sources: the Grafting Knife relic (uncommon; campfires offer
  Graft) and the Grafter event in act 2 (fuse the best-valued pair, or buy the knife for 60 gold).
  A shop service is left for later.

## Known gaps in v0.1

- An army with more than 19 distinct fairy piece types cannot fight (letter budget).
- Save points are map-only (no mid-fight save).
- No controller support; mouse only.
- Builds are not notarized (macOS) or Authenticode-signed (Windows).
- Windows usernames outside the system code page may break variant loading (temp path). Untested.
