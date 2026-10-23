class_name OmenDef
extends Resource
## A sign over one fight, rolled with the act's map and shown on its node. Never on a guardian or the boss.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: String
## Capture XP multiplier.
@export var xp_mult: float = 1.0
## Engine skill change (negative = weaker).
@export var engine_skill_delta: int = 0
## Enemy pawns on top of the encounter's material target.
@export var extra_pawns: int = 0
## Multiplier on the fight's gold.
@export var gold_mult: float = 1.0
## Your clock gains nothing per move.
@export var no_increment: bool = false
## Pieces slain in a won fight get back up afterwards.
@export var revive_slain: bool = false
