class_name RunConfig
extends Resource
## Run-wide numbers. Philip tunes balance by playing; everything here is data.

@export var starting_army: Array[StringName] = [&"king", &"pawn", &"pawn", &"pawn", &"pawn", &"knight", &"bishop"]
## Total XP needed to reach level 2, 3, 4, ...
@export var xp_thresholds: PackedInt32Array = PackedInt32Array([3, 8, 15, 24])
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
## Formation: preferred squares per piece id, then the overflow squares (centre first).
@export var formation: Dictionary = {}
@export var overflow_squares: PackedStringArray
@export var pawn_overflow_squares: PackedStringArray
## Map: one entry per row, comma-separated node types, bottom to top.
@export var map_rows: PackedStringArray
## Piece rewards: piece id -> weight.
@export var reward_weights_fight: Dictionary = {}
@export var reward_weights_elite: Dictionary = {}
@export var reward_choices: int = 3
@export var start_relic_choices: int = 4
@export var elite_relic_choices: int = 2
