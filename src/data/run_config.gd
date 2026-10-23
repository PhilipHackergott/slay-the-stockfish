class_name RunConfig
extends Resource
## Run-wide numbers. Philip tunes balance by playing; everything here is data.

@export var starting_army: Array[StringName] = [&"king", &"pawn", &"pawn", &"pawn", &"pawn", &"knight", &"bishop"]
@export var starting_gold: int = 30
## Total XP needed to reach level 2, 3, 4, ...
@export var xp_thresholds: PackedInt32Array = PackedInt32Array([3, 9, 18, 30, 45, 65])
## Perks a unit may hold; a level-up offers one perk next to its promotions.
@export var max_perks: int = 2
## Chance that one recruit slot is a Train slot instead (XP for a piece you already have).
@export var train_chance: float = 0.25
## Gold for skipping the recruit.
@export var skip_gold: int = 6
## A unit that cannot rise any further (final form or top level) turns each XP point into this much gold.
@export var overflow_gold_per_xp: int = 2
@export var clock_base_s: int = 300
@export var clock_increment_s: int = 3
## A won map fight turns the clock you have left into gold: one coin per this many seconds, capped.
@export var time_gold_seconds: int = 20
@export var time_gold_max: int = 20
## The engine resigns when its evaluation stays at or below -resign_cp for resign_moves moves.
@export var resign_cp: int = 600
@export var resign_moves: int = 3
## ...but never before this many plies, so outnumbered early enemies still make you play.
@export var resign_min_plies: int = 30
## Open questions (handover), with the proposal in use:
## draw: "survive" = no reward, the run goes on. loss of a normal fight ends the run.
@export var draw_outcome: StringName = &"survive"
@export var loss_ends_run: bool = true
## Formation: preferred squares per piece family (PieceDef.base), then the overflow squares.
@export var formation: Dictionary = {}
@export var overflow_squares: PackedStringArray
@export var pawn_overflow_squares: PackedStringArray
## Where the Regent's twin king stands (first free square).
@export var twin_squares: PackedStringArray = PackedStringArray(["d1", "f1", "d2", "f2", "e2", "c1", "g1"])
## Acts in order (ids of data/acts).
@export var acts: Array[StringName] = [&"act1", &"act2", &"act3"]
## Legacy single-act map (used only when no acts exist).
@export var map_rows: PackedStringArray
@export var reward_choices: int = 3
@export var start_relic_choices: int = 4
@export var elite_relic_choices: int = 2
@export var guardian_relic_choices: int = 3
## Shop: how many pieces and relics are on offer, and the prices before difficulty.
@export var shop_pieces: int = 3
@export var shop_relics: int = 2
@export var piece_price_base: int = 8
@export var piece_price_per_value: int = 7
@export var legendary_markup: int = 20
@export var restore_price: int = 38
## Rerolling the shop's wares: the first reroll costs this, each further one reroll_step more.
@export var reroll_price: int = 12
@export var reroll_step: int = 8
## The Bone Surgeon: promote a piece one tier for gold, or dismiss one for a little gold.
@export var surgeon_price: int = 50
@export var dismiss_gold: int = 10
## Relic tier weights per source (start, elite, guardian, treasure, shop, flawless, event).
@export var relic_odds: Dictionary = {
	"start": {"common": 60, "uncommon": 40}, "elite": {"uncommon": 60, "rare": 40}, "guardian": {"boss": 1},
	"treasure": {"common": 65, "uncommon": 35}, "shop": {"common": 50, "uncommon": 35, "rare": 15},
	"flawless": {"common": 70, "uncommon": 30}, "event": {"common": 60, "uncommon": 40},
	"roamer": {"rare": 90, "uncommon": 10}}
## Shop price of a relic by tier (a relic's own price, if set, wins).
@export var relic_prices: Dictionary = {"common": 42, "uncommon": 72, "rare": 110, "boss": 170}
## A won fight without losses may offer a relic (chance per node kind; elites offer one more card).
@export var flawless_relic_chance: Dictionary = {"fight": 0.35, "elite": 1.0}
## Campfire: how many fallen Mend raises, Drill XP, Study's extra seconds in the guardian fight.
@export var camp_mend_count: int = 2
@export var camp_drill_xp: int = 3
@export var camp_study_clock_s: int = 60
## Fusion (Graft): two unit types (sorted, joined by "+") -> the piece they become. Parts may differ by
## at most fusion_tier_band tiers. The result costs the higher part's value + 1 Command.
@export var fusions: Dictionary = {"bishop+knight": "archbishop", "knight+rook": "chancellor",
	"knight+queen": "amazon", "bishop+rook": "queen"}
@export var fusion_tier_band: int = 3
## What a "?" node turns into when entered (weights); every non-fight adds fight_pity to the fight weight.
@export var unknown_odds: Dictionary = {"event": 65, "fight": 15, "treasure": 10, "shop": 10}
@export var unknown_fight_pity: int = 10
## Share of fight and elite nodes that carry an omen.
@export var omen_chance: float = 0.25
## The roaming elite starts on this row and climbs one row every roamer_every nodes you enter; if it
## reaches the guardian, the guardian's material target grows by roamer_guardian_ratio (of Command).
@export var roamer_start_row: int = 3
@export var roamer_every: int = 2
@export var roamer_guardian_ratio: float = 0.15
@export var treasure_relic_choices: int = 2
@export var treasure_gold: PackedInt32Array = PackedInt32Array([9, 18])
