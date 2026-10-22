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
## Pocket pieces from relics and the Regent's twin exist for one fight only.
var temporary := false


static func make(unit_id: int, unit_type: StringName) -> Unit:
	var u := Unit.new()
	u.id = unit_id
	u.type = unit_type
	u.lineage.append(String(unit_type))
	return u


static func from_dict(d: Dictionary) -> Unit:
	var u := Unit.new()
	u.id = int(d.get("id", 0))
	u.type = StringName(d.get("type", "pawn"))
	u.xp = int(d.get("xp", 0))
	u.level = int(d.get("level", 1))
	u.state = StringName(d.get("state", "healthy"))
	u.lineage = PackedStringArray(d.get("lineage", [String(u.type)]))
	u.captures = int(d.get("captures", 0))
	u.fights = int(d.get("fights", 0))
	return u


func is_healthy() -> bool:
	return state == &"healthy"


func to_dict() -> Dictionary:
	return {"id": id, "type": String(type), "xp": xp, "level": level, "state": String(state),
		"lineage": Array(lineage), "captures": captures, "fights": fights}
