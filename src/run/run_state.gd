extends Node
## The run: the army as units with identity, relics, the act map and progress.

signal changed

var seed_value: int = 0
var rng := RandomNumberGenerator.new()
var units: Array = []
var relics: Array = []
var map: RunMap
var current_node: int = -1
var visited: Array = []
var next_unit_id := 1
var active := false
var stats := {}
var last_outcome: Dictionary = {}


func cfg() -> RunConfig:
	return Content.config


func new_run(p_seed: int) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	units.clear()
	relics.clear()
	visited.clear()
	current_node = -1
	next_unit_id = 1
	stats = {"fights_won": 0, "units_lost": 0, "captures": 0, "nodes": 0}
	for t in cfg().starting_army:
		add_unit(t)
	var used := {}
	map = RunMap.generate(cfg().map_rows, rng, func(type: StringName, row: int) -> StringName:
		return _pick_encounter(type, row, used))
	active = true
	changed.emit()


func _pick_encounter(type: StringName, row: int, used: Dictionary) -> StringName:
	var pool: Array = []
	match type:
		&"fight":
			pool = Content.encounters_of(&"fight", 1 if row <= 2 else 2)
		&"elite":
			pool = Content.encounters_of(&"elite")
		&"boss":
			pool = Content.encounters_of(&"boss")
		_:
			return &""
	if pool.is_empty():
		return &""
	var fresh := pool.filter(func(e): return not used.has(e.id))
	var src: Array = fresh if not fresh.is_empty() else pool
	var pick: EncounterDef = src[rng.randi_range(0, src.size() - 1)]
	used[pick.id] = true
	return pick.id


# --- army -------------------------------------------------------------------------------------

func add_unit(type: StringName) -> Unit:
	var u := Unit.make(next_unit_id, type)
	next_unit_id += 1
	units.append(u)
	changed.emit()
	return u


func unit(id: int) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func healthy_units() -> Array:
	return units.filter(func(u): return u.is_healthy())


func slain_units() -> Array:
	return units.filter(func(u): return not u.is_healthy())


## Total XP a unit needs to reach the next level; -1 when there is no further threshold.
func xp_needed(u: Unit) -> int:
	var t := cfg().xp_thresholds
	return t[u.level - 1] if u.level - 1 < t.size() else -1


func upgrade_options(u: Unit) -> Array:
	var def := Content.piece(u.type)
	return def.upgrades.duplicate() if def != null else []


func can_level_up(u: Unit) -> bool:
	var need := xp_needed(u)
	return u.is_healthy() and need >= 0 and u.xp >= need and not upgrade_options(u).is_empty()


func pending_level_ups() -> Array:
	return units.filter(func(u): return can_level_up(u))


func level_up(u: Unit, new_type: StringName) -> void:
	_set_type(u, new_type)
	changed.emit()


func _set_type(u: Unit, new_type: StringName) -> void:
	u.type = new_type
	u.level += 1
	u.lineage.append(String(new_type))


## Campfire: restore one slain unit (it keeps its XP and level: the handover's proposal).
func restore(u: Unit) -> void:
	u.state = &"healthy"
	changed.emit()


## Campfire: upgrade one healthy unit without XP.
func campfire_upgrade(u: Unit, new_type: StringName) -> void:
	_set_type(u, new_type)
	changed.emit()


# --- relics -----------------------------------------------------------------------------------

func has_relic(id: StringName) -> bool:
	return relics.has(id)


func add_relic(id: StringName) -> void:
	if not relics.has(id) and Content.relic(id) != null:
		relics.append(id)
		changed.emit()


func relic_defs() -> Array:
	return relics.map(func(id): return Content.relic(id)).filter(func(r): return r != null)


func relic_choices(n: int) -> Array:
	var pool: Array = Content.relics.keys().filter(func(id): return not relics.has(id))
	pool.sort()
	var out: Array = []
	while not pool.is_empty() and out.size() < n:
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


# --- events -----------------------------------------------------------------------------------

## Applies one event option and returns the text to show.
func apply_event_option(opt: Dictionary) -> String:
	var text: String = opt.get("result", "")
	var amount := int(opt.get("amount", 1))
	match String(opt.get("effect", "nothing")):
		"xp_all":
			for u in healthy_units():
				u.xp += amount
		"xp_random":
			var hs := healthy_units()
			if not hs.is_empty():
				var u: Unit = hs[rng.randi_range(0, hs.size() - 1)]
				u.xp += amount
				text += " (%s +%d XP)" % [Content.piece(u.type).display_name, amount]
		"gain_piece":
			add_unit(StringName(opt.get("piece", "pawn")))
		"gain_relic":
			var choices := relic_choices(1)
			if choices.is_empty():
				text += " The reliquary is empty."
			else:
				add_relic(choices[0])
				text += " You gain %s." % Content.relic(choices[0]).display_name
	if String(opt.get("cost", "")) == "lose_pawn":
		var pawns := healthy_units().filter(func(u): return u.type == &"pawn")
		if not pawns.is_empty():
			var p: Unit = pawns[rng.randi_range(0, pawns.size() - 1)]
			p.state = &"slain"
			text += " A pawn is lost to the water."
	changed.emit()
	return text


# --- map and nodes ----------------------------------------------------------------------------

func available_nodes() -> Array:
	if map == null:
		return []
	return map.start_nodes() if current_node < 0 else map.next_nodes(current_node)


func enter_node(id: int) -> Dictionary:
	current_node = id
	visited.append(id)
	stats["nodes"] = int(stats.get("nodes", 0)) + 1
	changed.emit()
	return map.node(id)


func is_boss_node(id: int) -> bool:
	return map != null and id >= 0 and map.node(id)["type"] == &"boss"


# --- fights -----------------------------------------------------------------------------------

## Applies a finished fight: slain units stay dead until a campfire restores them.
func apply_fight(outcome: Dictionary) -> void:
	last_outcome = outcome
	for id in outcome.get("slain", []):
		var u := unit(int(id))
		if u != null and u.type != &"king":
			u.state = &"slain"
			stats["units_lost"] = int(stats.get("units_lost", 0)) + 1
	for u in healthy_units():
		u.fights += 1
	if outcome.get("state") == "win":
		stats["fights_won"] = int(stats.get("fights_won", 0)) + 1
	changed.emit()


## Piece rewards: n distinct standard pieces drawn by weight.
func reward_choices(kind: StringName) -> Array:
	var weights: Dictionary = cfg().reward_weights_elite if kind == &"elite" else cfg().reward_weights_fight
	var pool := weights.duplicate()
	var out: Array = []
	while not pool.is_empty() and out.size() < cfg().reward_choices:
		var total := 0
		for w in pool.values():
			total += int(w)
		var roll := rng.randi_range(1, maxi(total, 1))
		for id in pool.keys():
			roll -= int(pool[id])
			if roll <= 0:
				out.append(StringName(id))
				pool.erase(id)
				break
	return out


## Squares for the player's healthy units: preferred squares per type, then overflow.
func formation(fight_units: Array) -> Dictionary:
	var taken := {}
	var out := {}
	var c := cfg()
	var order := [&"king", &"queen", &"rook", &"bishop", &"knight", &"pawn"]
	var sorted := fight_units.duplicate()
	sorted.sort_custom(func(a, b):
		var ia := order.find(a.type)
		var ib := order.find(b.type)
		return ia < ib if ia != ib else a.id < b.id)
	for u in sorted:
		var prefs: Array = Array(c.formation.get(String(u.type), PackedStringArray()))
		var fallback: Array = Array(c.pawn_overflow_squares if u.type == &"pawn" else c.overflow_squares)
		for s in prefs + fallback:
			var i := Fen.sq(String(s))
			if not taken.has(i):
				taken[i] = true
				out[i] = u.id
				break
	return out
