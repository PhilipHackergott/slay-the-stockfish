class_name RunMap
extends RefCounted
## One act: rows of nodes from the bottom (row 0) to the boss at the top, as in Slay the Spire.
## Node: {id, row, x (0..1), type, encounter, edges (ids in the next row), omen (id or &""),
## unknown (it was a "?" node, resolved on entry)}.

var nodes: Array = []
var rows: int = 0


## rows_spec: one string per row, comma-separated node types. pick_encounter(type, row) -> StringName.
static func generate(rows_spec: PackedStringArray, rng: RandomNumberGenerator, pick_encounter: Callable) -> RunMap:
	var m := RunMap.new()
	m.rows = rows_spec.size()
	var by_row: Array = []
	for r in rows_spec.size():
		var types := Array(rows_spec[r].split(",", false))
		for i in range(types.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t: Variant = types[i]
			types[i] = types[j]
			types[j] = t
		var row_ids: Array = []
		for i in types.size():
			var n := {
				"id": m.nodes.size(), "row": r, "x": (i + 1.0) / (types.size() + 1.0),
				"type": StringName(String(types[i]).strip_edges()), "encounter": &"", "edges": [], "omen": &"",
				"unknown": false,
			}
			n["encounter"] = pick_encounter.call(n["type"], r)
			m.nodes.append(n)
			row_ids.append(n["id"])
		by_row.append(row_ids)
	for r in range(by_row.size() - 1):
		var here: Array = by_row[r]
		var nxt: Array = by_row[r + 1]
		for id in here:
			var n: Dictionary = m.nodes[id]
			var sorted := nxt.duplicate()
			sorted.sort_custom(func(a, b): return absf(m.nodes[a]["x"] - n["x"]) < absf(m.nodes[b]["x"] - n["x"]))
			n["edges"].append(sorted[0])
			if sorted.size() > 1 and absf(m.nodes[sorted[1]]["x"] - n["x"]) < 0.4 and rng.randf() < 0.65:
				n["edges"].append(sorted[1])
		for id in nxt:
			var reached := false
			for h in here:
				if m.nodes[h]["edges"].has(id):
					reached = true
					break
			if not reached:
				var best: int = here[0]
				for h in here:
					if absf(m.nodes[h]["x"] - m.nodes[id]["x"]) < absf(m.nodes[best]["x"] - m.nodes[id]["x"]):
						best = h
				m.nodes[best]["edges"].append(id)
	return m


func to_dict() -> Dictionary:
	var out: Array = []
	for n in nodes:
		out.append({"id": n["id"], "row": n["row"], "x": n["x"], "type": String(n["type"]),
			"encounter": String(n["encounter"]), "edges": n["edges"].duplicate(), "omen": String(n.get("omen", "")),
			"unknown": bool(n.get("unknown", false))})
	return {"rows": rows, "nodes": out}


static func from_dict(d: Dictionary) -> RunMap:
	var m := RunMap.new()
	m.rows = int(d.get("rows", 0))
	for n in d.get("nodes", []):
		m.nodes.append({"id": int(n["id"]), "row": int(n["row"]), "x": float(n["x"]), "type": StringName(n["type"]),
			"encounter": StringName(n["encounter"]), "edges": Array(n["edges"]).map(func(e): return int(e)),
			"omen": StringName(n.get("omen", "")), "unknown": bool(n.get("unknown", false))})
	return m


func node(id: int) -> Dictionary:
	return nodes[id]


func start_nodes() -> Array:
	return nodes.filter(func(n): return n["row"] == 0).map(func(n): return n["id"])


func next_nodes(id: int) -> Array:
	return nodes[id]["edges"].duplicate()


## The act's last node (guardian or boss).
func boss_node() -> int:
	for n in nodes:
		if n["type"] == &"boss" or n["type"] == &"guardian":
			return n["id"]
	return -1
