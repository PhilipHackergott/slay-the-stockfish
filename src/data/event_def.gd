class_name EventDef
extends Resource
## A text event with choices. Each option: {label, effect, amount, piece, relic, result}.
## effects: xp_all, xp_random, gain_piece, gain_relic, lose_random, nothing.

@export var id: StringName
@export var title: String
@export_multiline var text: String
@export var options: Array[Dictionary] = []
