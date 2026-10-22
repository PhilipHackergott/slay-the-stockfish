class_name PieceDef
extends Resource
## One piece type. Standard pieces carry their FEN letter; custom pieces carry Betza and get a
## letter from the variant generator per fight.

@export var id: StringName
@export var display_name: String
## FEN letter (lower case) for standard pieces; empty for custom pieces.
@export var letter: String
## Betza for custom pieces (empty for standard ones).
@export var betza: String
## Point value: the XP a unit gains for capturing this piece.
@export var value: int = 1
## Upgrade children (the standard ladder in the MVP).
@export var upgrades: Array[StringName] = []
## The king only: how the player's pseudo-royal king moves.
@export var royal_betza: String
@export var model: String
## Extra variant lines for custom pieces; "{L}" is replaced by the assigned letter.
@export var ini_extra: PackedStringArray
@export_multiline var flavor: String
