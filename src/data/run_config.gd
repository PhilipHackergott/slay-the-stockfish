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
@export var skip_gold: int = 10
## A unit that cannot rise any further (final form or top level) turns each XP point into this much gold.
@export var overflow_gold_per_xp: int = 2
@export var clock_base_s: int = 300
@export var clock_increment_s: int = 3
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
@export var piece_price_base: int = 10
@export var piece_price_per_value: int = 8
@export var legendary_markup: int = 25
@export var restore_price: int = 45
## Rerolling the shop's wares: the first reroll costs this, each further one reroll_step more.
@export var reroll_price: int = 15
@export var reroll_step: int = 10
## The Bone Surgeon: promote a piece one tier for gold, or dismiss one for a little gold.
@export var surgeon_price: int = 60
@export var dismiss_gold: int = 10
## Relic tier weights per source (start, elite, guardian, treasure, shop, flawless, event).
@export var relic_odds: Dictionary = {
	"start": {"common": 60, "uncommon": 40}, "elite": {"uncommon": 60, "rare": 40}, "guardian": {"boss": 1},
	"treasure": {"common": 65, "uncommon": 35}, "shop": {"common": 50, "uncommon": 35, "rare": 15},
	"flawless": {"common": 70, "uncommon": 30}, "event": {"common": 60, "uncommon": 40}}
## Shop price of a relic by tier (a relic's own price, if set, wins).
@export var relic_prices: Dictionary = {"common": 50, "uncommon": 85, "rare": 130, "boss": 200}
## A won fight without losses may offer a relic (chance per node kind; elites offer one more card).
@export var flawless_relic_chance: Dictionary = {"fight": 0.35, "elite": 1.0}
## Campfire: how many fallen Mend raises, Drill XP, Study's extra seconds in the guardian fight.
@export var camp_mend_count: int = 2
@export var camp_drill_xp: int = 3
@export var camp_study_clock_s: int = 60
@export var treasure_relic_choices: int = 2
@export var treasure_gold: PackedInt32Array = PackedInt32Array([15, 30])
