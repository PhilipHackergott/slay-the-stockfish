class_name RelicDef
extends Resource
## A relic. kind: rule (variant lines), pocket (FEN pocket + drops), edit (position edit),
## clock (player clock).

@export var id: StringName
@export var display_name: String
@export var kind: StringName
@export_multiline var description: String
## rule: lines appended to the fight's variant section.
@export var ini_lines: PackedStringArray
## rule: 0-based ranks where the player's pawns promote (the edit validator needs them).
@export var promotion_ranks: PackedInt32Array
## pocket: white pocket letters at the start of each fight, e.g. "B".
@export var pocket: String
## edit: uses per fight.
@export var charges_per_fight: int = 0
## clock: extra base time in seconds.
@export var clock_bonus_s: int = 0
@export var icon: String
