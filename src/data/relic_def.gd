class_name RelicDef
extends Resource
## A relic. kind: rule (variant lines), pocket (FEN pocket + drops), edit (position edit),
## hybrid (lift a piece into the pocket, drop it as a move), clock (player clock), gold (economy).

@export var id: StringName
@export var display_name: String
@export var kind: StringName
@export_multiline var description: String
## rule: lines appended to the fight's variant section.
@export var ini_lines: PackedStringArray
## rule: 0-based ranks where the player's pawns promote (the edit validator needs them).
@export var promotion_ranks: PackedInt32Array
## pocket: white pocket letters at the start of each fight, e.g. "B" (standard letters only).
@export var pocket: String
## edit / hybrid: uses per fight.
@export var charges_per_fight: int = 0
## edit: &"swap" (two of your pieces trade places) or &"move" (one piece to an empty square).
@export var edit_kind: StringName = &"swap"
## clock: extra base time and extra increment in seconds.
@export var clock_bonus_s: int = 0
@export var increment_bonus_s: int = 0
## gold: extra share of fight gold (0.5 = +50 %).
@export var gold_bonus: float = 0.0
## Extra Command for the deployed army.
@export var command_bonus: int = 0
## Shop price before difficulty.
@export var price: int = 100
## Profile unlock key ("" = always available).
@export var unlock: StringName
@export var icon: String
