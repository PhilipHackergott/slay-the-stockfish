class_name Unit
extends RefCounted
## One piece of the player's army with its identity and history for the whole run.

var id: int
var type: StringName
var xp: int = 0
var level: int = 1
var state: StringName = &"healthy"
var lineage: PackedStringArray = []
var captures: int = 0
var fights: int = 0
## Pocket pieces from relics exist for one fight only.
var temporary := false


static func make(unit_id: int, unit_type: StringName) -> Unit:
	var u := Unit.new()
	u.id = unit_id
	u.type = unit_type
	u.lineage.append(String(unit_type))
	return u


func is_healthy() -> bool:
	return state == &"healthy"


func to_dict() -> Dictionary:
	return {"id": id, "type": type, "xp": xp, "level": level, "state": state,
		"lineage": Array(lineage), "captures": captures}
