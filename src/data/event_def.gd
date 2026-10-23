class_name EventDef
extends Resource
## A text event with choices. Each option: {label, detail, effect, amount, piece, tier, source, result,
## cost, cost_amount, curse}.
## effects: xp_all, xp_random, gain_piece, gain_piece_tier (option "tier" or the act's top fight tier),
## gain_relic (option "source" picks the relic odds, default event), gold, lose_gold, transform_up
## (amount pieces), restore_all, study_boss (amount seconds on your clock against the final boss),
## stitch (atom W/F/N onto a piece you choose), nothing.
## costs: gold (cost_amount), lose_pawn, lose_random. curse: a curse relic that comes with the option.
## Event fights: "fight" puzzle (tier) or skirmish (encounter, units), with "win" and "lose" parts that
## are options themselves.

@export var id: StringName
@export var title: String
@export_multiline var text: String
@export var options: Array[Dictionary] = []
## Acts (1-based) whose ? nodes draw this event; empty = any act.
@export var acts: PackedInt32Array = PackedInt32Array()
@export var icon: String = "res://assets/ui/icons/icon_event_256.png"
## Profile unlock key ("" = always in the pool).
@export var unlock: StringName
