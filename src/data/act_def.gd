class_name ActDef
extends Resource
## One act of the descent: its map, which enemies it draws, its rewards and its last node.

@export var id: StringName
## 1-based order of the act in a run.
@export var index: int = 1
@export var display_name: String
@export var subtitle: String
@export_multiline var flavor: String
## One entry per row, comma-separated node types (fight, elite, event, campfire, shop), bottom to top.
## The act's last node (guardian or boss) is added on top.
@export var map_rows: PackedStringArray
## Fight encounter tier on rows below late_from_row, and from it on.
@export var fight_tier: int = 1
@export var late_fight_tier: int = 2
@export var late_from_row: int = 3
@export var elite_tier: int = 1
## The last node: an encounter of kind guardian (lesser engine) or boss (the final fight).
@export var final_encounter: StringName
## Reward rarity weights per node kind: {"fight": {"common": 80, "uncommon": 20}, ...}.
@export var reward_rarity: Dictionary = {}
## Gold per won fight by node kind: {"fight": [16, 24], "elite": [40, 55], "guardian": [70, 90]}.
@export var gold: Dictionary = {}
## Shop piece rarity weights.
@export var shop_rarity: Dictionary = {}


func is_final_act() -> bool:
	var e := Content.encounter(final_encounter)
	return e != null and e.kind == &"boss"
