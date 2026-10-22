class_name EncounterDef
extends Resource
## An enemy army and the engine tier that plays it.

@export var id: StringName
@export var display_name: String
## fight, elite or boss
@export var kind: StringName = &"fight"
@export var tier: int = 1
## Engine side (black): square name -> piece id, e.g. {"e8": &"king", "d7": &"pawn"}.
@export var layout: Dictionary = {}
## Engine strength: fixed time per move, Skill Level (-20..20), optional depth cap.
@export var movetime_ms: int = 100
@export var skill: int = 0
@export var depth: int = 0
@export_multiline var flavor: String
