class_name EncounterDef
extends Resource
## An enemy army and the engine tier that plays it.

@export var id: StringName
@export var display_name: String
## fight, elite, guardian (an act's lesser engine), boss (the final fight); event fights: puzzle, skirmish
@export var kind: StringName = &"fight"
@export var tier: int = 1
## Engine side (black): square name -> piece id, e.g. {"e8": &"king", "d7": &"pawn"}.
@export var layout: Dictionary = {}
## Pieces that join, in order, until the enemy reaches its material target (ActDef.enemy_ratio):
## square name -> piece id. Empty = the generic order (pawns on rank 7, then minor pieces).
@export var reinforcements: Dictionary = {}
## Puzzles: your side is set, not your army (square name -> piece id, temporary pieces); you must
## win within move_limit moves of yours. solution: the key move (tools/gen_puzzles.py checked it).
@export var player_layout: Dictionary = {}
@export var move_limit: int = 0
@export var solution: String
## Engine strength: fixed time per move, Skill Level (-20..20), optional depth cap.
@export var movetime_ms: int = 100
@export var skill: int = 0
@export var depth: int = 0
@export_multiline var flavor: String
## Guardians: the arena they always fight on (data/arenas), shown on their map node.
@export var arena: StringName
