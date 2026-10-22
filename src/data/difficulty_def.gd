class_name DifficultyDef
extends Resource
## One difficulty tier ("Descent"). Tiers stack: tier N applies every tier from 1 to N.
## Winning a run on tier N unlocks tier N + 1.

@export var level: int = 0
@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## Engine Skill Level bonus in fights and elites (guardians and the boss are capped at 20).
@export var skill_bonus: int = 0
@export var elite_skill_bonus: int = 0
## Multiplies the engine's time per move.
@export var movetime_mult: float = 1.0
## Added to the player's base clock in seconds (negative = less time).
@export var clock_delta_s: int = 0
## Pieces removed from the starting army.
@export var remove_from_start: Array[StringName] = []
## Multiplies gold income and shop prices.
@export var gold_mult: float = 1.0
@export var price_mult: float = 1.0
## Added to the engine's resign threshold (it fights on longer).
@export var resign_cp_delta: int = 0
