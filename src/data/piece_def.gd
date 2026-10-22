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
## Point value: the XP a unit gains for capturing this piece, and the base of its shop price.
@export var value: int = 1
## Children in the promotion tree (standard-ladder steps and custom nodes alike). Empty = final form.
@export var upgrades: Array[StringName] = []
## King line only: how the player's pseudo-royal king moves (the piece is always the letter w).
@export var royal_betza: String
## King line only: a second pseudo-royal king joins each fight; the fight is lost when the last falls.
@export var twin_king: bool = false
## Moves forward only and promotes like a pawn (joins promotionPawnTypes, keeps to rank 2 and up).
@export var pawn_like: bool = false
## Reward pool: &"common", &"uncommon", &"legendary"; empty = only reachable through a tree.
@export var rarity: StringName
## Weight inside its rarity pool.
@export var reward_weight: int = 10
## Model family and formation slot: pawn, knight, bishop, rook, queen, king.
@export var base: StringName
## Height in metres (selection glow, hover info); the glb is authored to it.
@export var height: float = 1.0
@export var model: String
## Profile unlock key ("" = always available), see Profile.UNLOCKS.
@export var unlock: StringName
## Extra variant lines for custom pieces; "{L}" is replaced by the assigned letter.
@export var ini_extra: PackedStringArray
## One line for cards and hover info: how it moves.
@export var moves_text: String
@export_multiline var flavor: String


func is_royal() -> bool:
	return royal_betza != ""


func is_final() -> bool:
	return upgrades.is_empty()


func is_standard() -> bool:
	return letter != ""


## Can capture en passant (Betza "e" modifier, or the standard pawn).
func takes_en_passant() -> bool:
	return letter == "p" or (betza != "" and betza.contains("e"))
