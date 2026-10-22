class_name RunConfig
extends Resource
## Run-wide numbers. Philip tunes balance by playing; everything here is data.

@export var starting_army: Array[StringName] = [&"king", &"pawn", &"pawn", &"pawn", &"pawn", &"knight", &"bishop"]
@export var starting_gold: int = 30
## Total XP needed to reach level 2, 3, 4, ...
@export var xp_thresholds: PackedInt32Array = PackedInt32Array([3, 8, 15, 24, 35])
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
