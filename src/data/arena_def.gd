class_name ArenaDef
extends Resource
## A fight node with a rule twist, shown on the map. The rule goes into the fight's variant, so the
## engine plays it too. Arenas are symmetric; one-sided rules belong to relics.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: String
## Lines appended to the fight's variant section.
@export var ini_lines: PackedStringArray
## Rubble walls (FEN "*"): squares no piece may enter or cross. A square already taken stays free.
@export var walls: PackedStringArray
## Checks each side must give to win (n-check, needs "checkCounting = true"); 0 = off.
@export var checks: int = 0
## Squares the board marks for the whole fight (the summit).
@export var zone: PackedStringArray
## Result lines when the arena's rule ends the fight.
@export var win_text: String
@export var loss_text: String
## Extra promotion ranks (0-based, white's view; the engine's are mirrored), as in the ini lines.
@export var promotion_ranks: PackedInt32Array
## What stands on the walls this arena leaves during the fight: rubble, stake or crow.
@export var wall_prop: StringName = &"rubble"
## How the wall squares this arena leaves during the fight are called and explained (hover).
@export var wall_name: String = "Rubble"
@export var wall_text: String = "Nothing stands on it or passes through it."
