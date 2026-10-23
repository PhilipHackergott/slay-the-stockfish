class_name PerkDef
extends Resource
## A perk a unit can take instead of a promotion. Effects are keyed by id in the run and the fight:
## veteran (more capture XP), bulwark (survives in a won fight), vanguard (cheaper Command),
## bounty (gold per capture).

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: String
