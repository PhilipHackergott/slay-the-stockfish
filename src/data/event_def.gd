class_name EventDef
extends Resource
## A text event with choices. Each option: {label, effect, amount, piece, rarity, result, cost, cost_amount}.
## effects: xp_all, xp_random, gain_piece, gain_piece_rarity, gain_relic, gold, transform_random, nothing.
## costs: gold (cost_amount), lose_pawn, lose_random.

@export var id: StringName
@export var title: String
@export_multiline var text: String
@export var options: Array[Dictionary] = []
