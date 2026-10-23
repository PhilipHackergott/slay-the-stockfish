class_name AffixDef
extends Resource
## A trait of an elite, rolled with the act's map (ActDef.affix_*) and shown on its node.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## Engine skill change and thinking-time multiplier.
@export var engine_skill_delta: int = 0
@export var movetime_mult: float = 1.0
## Enemy pawns on top of the material target, and a multiplier on that target.
@export var extra_pawns: int = 0
@export var enemy_ratio_mult: float = 1.0
## Your clock: base time change in seconds, and no increment.
@export var clock_delta_s: int = 0
@export var no_increment: bool = false
## The engine moves first.
@export var engine_first: bool = false
