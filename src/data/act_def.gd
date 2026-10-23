class_name ActDef
extends Resource
## One act of the descent: its map, which enemies it draws, its rewards and its last node.

@export var id: StringName
## 1-based order of the act in a run.
@export var index: int = 1
@export var display_name: String
@export var subtitle: String
@export_multiline var flavor: String
## One entry per row, comma-separated node types (fight, elite, unknown, event, campfire, shop,
## treasure), bottom to top. The act's last node (guardian or boss) is added on top.
@export var map_rows: PackedStringArray
## Fight encounter tier on rows below late_from_row, and from it on.
@export var fight_tier: int = 1
@export var late_fight_tier: int = 2
@export var late_from_row: int = 3
@export var elite_tier: int = 1
## The last node: an encounter of kind guardian (lesser engine) or boss (the final fight).
@export var final_encounter: StringName
## Command: the material budget of the deployed army (piece values, the king is free). 0 = no cap.
@export var command: int = 0
## The act's last fight ignores Command: every healthy piece, benched or not, fights.
@export var final_uncapped: bool = false
## Enemy material target per node kind as a share of Command: {"fight": 0.8, "elite": 1.0, ...}.
## Reinforcements join an encounter until it reaches the target; 0 or missing = the layout as is.
@export var enemy_ratio: Dictionary = {}
## Recruit tiers per node kind: {"fight": [1, 2], "elite": [2, 3], "guardian": [3]}. One tier is
## rolled per offer and every recruit on offer comes from it.
@export var reward_tiers: Dictionary = {}
## Tiers the shop draws its pieces from.
@export var shop_tiers: PackedInt32Array = PackedInt32Array([1, 2])
## XP of a Train reward slot.
@export var train_xp: int = 4
## Gold per won fight by node kind: {"fight": [16, 24], "elite": [40, 55], "guardian": [70, 90]}.
@export var gold: Dictionary = {}
## Arenas (data/arenas): fight and elite nodes from arena_from_row on carry one with these odds, at
## most arena_max per map. "?" nodes, guardians and the boss never do.
@export var arena_from_row: int = 3
@export var arena_max: int = 0
@export var arena_fight_chance: float = 0.0
@export var arena_elite_chance: float = 0.0


func is_final_act() -> bool:
	var e := Content.encounter(final_encounter)
	return e != null and e.kind == &"boss"
