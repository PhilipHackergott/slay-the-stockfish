extends Node
## The run: the army as units with identity, relics, gold, the current act's map and progress.
## Saved at node boundaries (user://run.json), so a run can be continued from the title.

signal changed

const SAVE_VERSION := 1
const FAMILY_ORDER := [&"king", &"queen", &"rook", &"bishop", &"knight", &"pawn"]

var save_path := "user://run.json"

var seed_value: int = 0
var rng := RandomNumberGenerator.new()
var units: Array = []
var relics: Array = []
var gold: int = 0
var difficulty: int = 0
## 0-based index into cfg().acts.
var act_index: int = 0
var map: RunMap
var current_node: int = -1
var visited: Array = []
var next_unit_id := 1
var active := false
var stats := {}
var last_outcome: Dictionary = {}
var used_events: Array = []
## Player-arranged squares: unit id -> square index (formation editor).
var formation_prefs: Dictionary = {}
## Shop stock per node id, so it survives leaving and continuing: {node_id: {pieces, relics}}.
var shops: Dictionary = {}
## The profile's unlock keys when the run began: what a run unlocks applies from the next run on.
var unlocks: Array = []


func cfg() -> RunConfig:
	return Content.config


func is_unlocked(key: StringName) -> bool:
	return key == &"" or unlocks.has(String(key))


func new_run(p_seed: int, p_difficulty: int = 0) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	difficulty = p_difficulty
	units.clear()
	relics.clear()
	visited.clear()
	used_events.clear()
	formation_prefs.clear()
	shops.clear()
	current_node = -1
	next_unit_id = 1
	act_index = 0
	unlocks = Array(Profile.data.get("unlocks", [])).map(func(k): return String(k))
	stats = {"fights_won": 0, "units_lost": 0, "captures": 0, "nodes": 0, "gold_earned": 0}
	var mods := difficulty_mods()
	gold = int(round(cfg().starting_gold * float(mods["gold_mult"])))
	var army: Array = Array(cfg().starting_army)
	for t in mods["remove_from_start"]:
		army.erase(t)
	for t in army:
		add_unit(t)
	_build_act_map()
	active = true
	changed.emit()


# --- acts -------------------------------------------------------------------------------------

func current_act() -> ActDef:
	var ids := cfg().acts
	return Content.act(ids[act_index]) if act_index < ids.size() else null


func act_count() -> int:
	return cfg().acts.size()


func is_final_act() -> bool:
	var a := current_act()
	return a == null or a.is_final_act() or act_index >= act_count() - 1


## After an act's guardian: on to the next act's map.
func advance_act() -> void:
	act_index += 1
	current_node = -1
	visited.clear()
	shops.clear()
	_build_act_map()
	changed.emit()


func _build_act_map() -> void:
	var act := current_act()
	var rows := PackedStringArray()
	if act != null:
		rows.append_array(act.map_rows)
		rows.append("boss" if act.is_final_act() else "guardian")
	else:
		rows = cfg().map_rows
	var used := {}
	map = RunMap.generate(rows, rng, func(type: StringName, row: int) -> StringName:
		return _pick_encounter(type, row, used))


func _pick_encounter(type: StringName, row: int, used: Dictionary) -> StringName:
	var act := current_act()
	var pool: Array = []
	match type:
		&"fight":
			var tier := 1 if row <= 2 else 2
			if act != null:
				tier = act.fight_tier if row < act.late_from_row else act.late_fight_tier
			pool = Content.encounters_of(&"fight", tier)
		&"elite":
			pool = Content.encounters_of(&"elite", act.elite_tier if act != null else -1)
			if pool.is_empty():
				pool = Content.encounters_of(&"elite")
		&"guardian", &"boss":
			if act != null and Content.encounter(act.final_encounter) != null:
				return act.final_encounter
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


# --- difficulty -------------------------------------------------------------------------------

## Every tier from 1 to the run's difficulty, stacked.
func difficulty_mods() -> Dictionary:
	var m := {"skill_bonus": 0, "elite_skill_bonus": 0, "movetime_mult": 1.0, "clock_delta_s": 0,
		"remove_from_start": [], "gold_mult": 1.0, "price_mult": 1.0, "resign_cp_delta": 0}
	for d in Content.difficulties:
		if d.level < 1 or d.level > difficulty:
			continue
		m["skill_bonus"] += d.skill_bonus
		m["elite_skill_bonus"] += d.elite_skill_bonus
		m["movetime_mult"] *= d.movetime_mult
		m["clock_delta_s"] += d.clock_delta_s
		m["remove_from_start"].append_array(Array(d.remove_from_start))
		m["gold_mult"] *= d.gold_mult
		m["price_mult"] *= d.price_mult
		m["resign_cp_delta"] += d.resign_cp_delta
	return m


func top_difficulty() -> int:
	var top := 0
	for d in Content.difficulties:
		top = maxi(top, d.level)
	return top


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


func king_unit() -> Unit:
	for u in units:
		var d := Content.piece(u.type)
		if d != null and d.is_royal():
			return u
	return null


## Total XP a unit needs to reach the next level; -1 when there is no further threshold.
func xp_needed(u: Unit) -> int:
	var t := cfg().xp_thresholds
	return t[u.level - 1] if u.level - 1 < t.size() else -1


func upgrade_options(u: Unit) -> Array:
	var def := Content.piece(u.type)
	return def.upgrades.duplicate() if def != null else []


## Cannot rise any further: a final form or the top level. Its XP turns into gold.
func is_maxed(u: Unit) -> bool:
	return upgrade_options(u).is_empty() or xp_needed(u) < 0


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


# --- gold -------------------------------------------------------------------------------------

func add_gold(amount: int) -> void:
	gold += amount
	if amount > 0:
		stats["gold_earned"] = int(stats.get("gold_earned", 0)) + amount
	changed.emit()


func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	gold -= amount
	changed.emit()
	return true


func gold_bonus() -> float:
	var b := 0.0
	for r in relic_defs():
		b += r.gold_bonus
	return b


## Gold for a won fight of this node kind (act data), with difficulty and relics applied.
func roll_fight_gold(kind: StringName) -> int:
	var act := current_act()
	var r: Array = [10, 18]
	if act != null:
		r = act.gold.get(String(kind), act.gold.get("fight", r))
	var base := rng.randi_range(int(r[0]), int(r[1]))
	return int(round(base * float(difficulty_mods()["gold_mult"]) * (1.0 + gold_bonus())))


# --- relics -----------------------------------------------------------------------------------

func has_relic(id: StringName) -> bool:
	return relics.has(id)


func add_relic(id: StringName) -> void:
	if not relics.has(id) and Content.relic(id) != null:
		relics.append(id)
		changed.emit()


func relic_defs() -> Array:
	return relics.map(func(id): return Content.relic(id)).filter(func(r): return r != null)


## Relics not yet owned and unlocked in the profile, drawn without repeats.
func relic_choices(n: int) -> Array:
	var pool: Array = Content.relics.keys().filter(func(id):
		return not relics.has(id) and is_unlocked(Content.relic(id).unlock))
	pool.sort()
	var out: Array = []
	while not pool.is_empty() and out.size() < n:
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


# --- events -----------------------------------------------------------------------------------

func pick_event() -> EventDef:
	var pool: Array = Content.events.keys().filter(func(id): return not used_events.has(id))
	if pool.is_empty():
		pool = Content.events.keys()
	if pool.is_empty():
		return null
	pool.sort()
	var id: StringName = pool[rng.randi_range(0, pool.size() - 1)]
	used_events.append(id)
	return Content.events[id]


## Whether an option's cost can be paid (gold, or a pawn to give up).
func can_afford_option(opt: Dictionary) -> bool:
	match String(opt.get("cost", "")):
		"gold":
			return gold >= int(opt.get("cost_amount", 0))
		"lose_pawn":
			return healthy_units().any(func(u): return u.type == &"pawn")
		"lose_random":
			return healthy_units().any(func(u): return not Content.piece(u.type).is_royal())
	return true


## Applies one event option and returns the text to show.
func apply_event_option(opt: Dictionary) -> String:
	var text: String = opt.get("result", "")
	var amount := int(opt.get("amount", 1))
	match String(opt.get("cost", "")):
		"gold":
			spend_gold(int(opt.get("cost_amount", 0)))
		"lose_pawn":
			var pawns := healthy_units().filter(func(u): return u.type == &"pawn")
			if not pawns.is_empty():
				var p: Unit = pawns[rng.randi_range(0, pawns.size() - 1)]
				p.state = &"slain"
				text += " %s is gone." % _name(p)
		"lose_random":
			var pool := healthy_units().filter(func(u): return not Content.piece(u.type).is_royal())
			if not pool.is_empty():
				var v: Unit = pool[rng.randi_range(0, pool.size() - 1)]
				v.state = &"slain"
				text += " (%s is slain)" % _name(v)
	match String(opt.get("effect", "nothing")):
		"xp_all":
			for u in healthy_units():
				u.xp += amount
		"xp_random":
			var hs := healthy_units()
			if not hs.is_empty():
				var u: Unit = hs[rng.randi_range(0, hs.size() - 1)]
				u.xp += amount
				text += " (%s +%d XP)" % [_name(u), amount]
		"gain_piece":
			add_unit(StringName(opt.get("piece", "pawn")))
		"gain_piece_rarity":
			var ids := _draw_pieces({String(opt.get("rarity", "uncommon")): 1}, 1)
			if not ids.is_empty():
				var nu := add_unit(ids[0])
				text += " %s joins you." % _name(nu)
		"gain_relic":
			var choices := relic_choices(1)
			if choices.is_empty():
				text += " The reliquary is empty."
			else:
				add_relic(choices[0])
				text += " You gain %s." % Content.relic(choices[0]).display_name
		"gold":
			add_gold(amount)
			text += " (+%d gold)" % amount
		"transform_random":
			var pool := healthy_units().filter(func(u): return not Content.piece(u.type).is_royal())
			var ids := _draw_pieces({String(opt.get("rarity", "uncommon")): 1}, 1)
			if not pool.is_empty() and not ids.is_empty():
				var t: Unit = pool[rng.randi_range(0, pool.size() - 1)]
				var before := _name(t)
				t.type = ids[0]
				t.lineage.append(String(ids[0]))
				text += " %s is now a %s." % [before, Content.piece(ids[0]).display_name]
	changed.emit()
	return text


func _name(u: Unit) -> String:
	var d := Content.piece(u.type)
	return "%s #%d" % [d.display_name if d != null else String(u.type), u.id]


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

## Applies a finished fight: slain units stay dead until a campfire restores them. A win pays gold;
## XP earned by units that cannot rise any further turns into gold too.
func apply_fight(outcome: Dictionary, kind: StringName = &"fight") -> void:
	last_outcome = outcome
	for id in outcome.get("slain", []):
		var u := unit(int(id))
		if u != null and not Content.piece(u.type).is_royal():
			u.state = &"slain"
			stats["units_lost"] = int(stats.get("units_lost", 0)) + 1
	for u in healthy_units():
		u.fights += 1
	var overflow := 0
	for e in outcome.get("xp", []):
		var u := unit(int(e["unit"]))
		stats["captures"] = int(stats.get("captures", 0)) + 1
		if u != null and is_maxed(u):
			overflow += int(e["amount"]) * cfg().overflow_gold_per_xp
	outcome["overflow_gold"] = overflow
	outcome["gold"] = 0
	if outcome.get("state") == "win":
		stats["fights_won"] = int(stats.get("fights_won", 0)) + 1
		outcome["gold"] = roll_fight_gold(kind)
	add_gold(int(outcome["gold"]) + overflow)


## Piece rewards: n distinct pieces, rarity first (act data per node kind), then weight.
func reward_choices(kind: StringName) -> Array:
	var act := current_act()
	var weights: Dictionary = {"common": 80, "uncommon": 20}
	if act != null:
		weights = act.reward_rarity.get(String(kind), act.reward_rarity.get("elite" if kind == &"guardian" else "fight", weights))
	return _draw_pieces(weights, cfg().reward_choices)


## rarity_weights: {"common": 80, ...}. Unlocked pieces only, no repeats.
func _draw_pieces(rarity_weights: Dictionary, n: int, exclude: Array = []) -> Array:
	var out: Array = []
	var tries := 0
	while out.size() < n and tries < 40:
		tries += 1
		var rarity := StringName(_weighted(rarity_weights))
		var pool: Array = Content.pieces_of_rarity(rarity).filter(func(p):
			return is_unlocked(p.unlock) and not out.has(p.id) and not exclude.has(p.id))
		if pool.is_empty():
			pool = Content.pieces_of_rarity(&"common").filter(func(p): return not out.has(p.id) and not exclude.has(p.id))
		if pool.is_empty():
			break
		var w := {}
		for p in pool:
			w[p.id] = maxi(1, p.reward_weight)
		out.append(StringName(_weighted(w)))
	return out


func _weighted(weights: Dictionary) -> Variant:
	var total := 0
	for v in weights.values():
		total += int(v)
	var roll := rng.randi_range(1, maxi(total, 1))
	var keys := weights.keys()
	keys.sort()
	for k in keys:
		roll -= int(weights[k])
		if roll <= 0:
			return k
	return keys[0]


# --- shop -------------------------------------------------------------------------------------

func piece_price(id: StringName) -> int:
	var d := Content.piece(id)
	if d == null:
		return 999
	var p := cfg().piece_price_base + cfg().piece_price_per_value * d.value
	if d.rarity == &"legendary":
		p += cfg().legendary_markup
	return int(round(p * float(difficulty_mods()["price_mult"])))


func relic_price(id: StringName) -> int:
	var r := Content.relic(id)
	return int(round((r.price if r != null else 100) * float(difficulty_mods()["price_mult"])))


func restore_price() -> int:
	return int(round(cfg().restore_price * float(difficulty_mods()["price_mult"])))


## The stock of the shop at node_id (rolled once, then kept).
func shop(node_id: int) -> Dictionary:
	if shops.has(node_id):
		return shops[node_id]
	var act := current_act()
	var weights: Dictionary = act.shop_rarity if act != null else {"common": 60, "uncommon": 40}
	var stock := {"pieces": [], "relics": []}
	for id in _draw_pieces(weights, cfg().shop_pieces):
		stock["pieces"].append({"id": String(id), "price": piece_price(id), "sold": false})
	for id in relic_choices(cfg().shop_relics):
		stock["relics"].append({"id": String(id), "price": relic_price(id), "sold": false})
	shops[node_id] = stock
	return stock


## kind: "pieces" or "relics". Returns the bought unit, relic id, or null.
func buy(node_id: int, kind: String, index: int) -> Variant:
	var stock := shop(node_id)
	var item: Dictionary = stock[kind][index]
	if item["sold"] or not spend_gold(int(item["price"])):
		return null
	item["sold"] = true
	if kind == "pieces":
		return add_unit(StringName(item["id"]))
	add_relic(StringName(item["id"]))
	return StringName(item["id"])


func buy_restore(u: Unit) -> bool:
	if u.is_healthy() or not spend_gold(restore_price()):
		return false
	restore(u)
	return true


# --- formation --------------------------------------------------------------------------------

## The formation family of a unit: king, queen, rook, bishop, knight, pawn, or "" (overflow).
func family(u: Unit) -> StringName:
	var d := Content.piece(u.type)
	if d == null:
		return &""
	if d.is_royal():
		return &"king"
	if d.pawn_like:
		return &"pawn"
	return d.base if d.base != &"pawn" else &""


func is_pawn_like(u: Unit) -> bool:
	var d := Content.piece(u.type)
	return d != null and d.pawn_like


## A square the formation editor may use for this unit (ranks 1-2; pawns not on rank 1).
func formation_square_ok(u: Unit, sq: int) -> bool:
	if sq < 0 or sq > 15:
		return false
	return not (is_pawn_like(u) and sq < 8)


## Squares for the player's healthy units: arranged squares first, then preferred squares per
## family, then overflow.
func formation(fight_units: Array) -> Dictionary:
	var taken := {}
	var out := {}
	var c := cfg()
	var rest: Array = []
	for u in fight_units:
		var sq := int(formation_prefs.get(u.id, -1))
		if formation_square_ok(u, sq) and not taken.has(sq):
			taken[sq] = true
			out[sq] = u.id
		else:
			rest.append(u)
	rest.sort_custom(func(a, b):
		var ia := FAMILY_ORDER.find(family(a))
		var ib := FAMILY_ORDER.find(family(b))
		ia = ia if ia >= 0 else 4
		ib = ib if ib >= 0 else 4
		return ia < ib if ia != ib else a.id < b.id)
	for u in rest:
		var fam := family(u)
		var prefs: Array = Array(c.formation.get(String(fam), PackedStringArray()))
		var fallback: Array = Array(c.pawn_overflow_squares if fam == &"pawn" else c.overflow_squares)
		for s in prefs + fallback:
			var i := Fen.sq(String(s))
			if not taken.has(i) and not (fam == &"pawn" and i < 8):
				taken[i] = true
				out[i] = u.id
				break
	return out


## Stores a full arrangement from the editor: {square: unit id}.
func set_formation(arrangement: Dictionary) -> void:
	formation_prefs.clear()
	for sq in arrangement:
		formation_prefs[int(arrangement[sq])] = int(sq)
	changed.emit()


## The army as it would stand on the board outside a fight (map, editor): {board, units}.
func display_position() -> Dictionary:
	var hs := healthy_units()
	var f := formation(hs)
	var ids: Array = []
	var royal: StringName = &"king"
	for u in hs:
		var d := Content.piece(u.type)
		if d.is_royal():
			royal = d.id
		elif d.letter == "" and not ids.has(u.type):
			ids.append(u.type)
	Content.set_fight_letters(VariantGen.assign_letters(ids), royal)
	var b := {}
	var um := UnitMap.new()
	for sq in f:
		var u := unit(int(f[sq]))
		var l := Content.letter_of(u.type)
		b[int(sq)] = (l if l != "" else "p").to_upper()
		um.place(int(sq), u.id)
	return {"board": b, "units": um}


# --- save and load ----------------------------------------------------------------------------

func to_save() -> Dictionary:
	var prefs := {}
	for k in formation_prefs:
		prefs[str(k)] = formation_prefs[k]
	var shop_out := {}
	for k in shops:
		shop_out[str(k)] = shops[k]
	return {
		"version": SAVE_VERSION, "seed": seed_value, "rng_state": str(rng.state), "difficulty": difficulty,
		"units": units.map(func(u): return u.to_dict()), "relics": relics.map(func(r): return String(r)),
		"gold": gold, "act_index": act_index, "map": map.to_dict() if map != null else {},
		"current_node": current_node, "visited": visited.duplicate(), "next_unit_id": next_unit_id,
		"stats": stats.duplicate(), "used_events": used_events.map(func(e): return String(e)),
		"formation_prefs": prefs, "shops": shop_out, "unlocks": unlocks.duplicate(),
	}


func from_save(d: Dictionary) -> bool:
	if int(d.get("version", 0)) != SAVE_VERSION:
		return false
	seed_value = int(d.get("seed", 0))
	rng.seed = seed_value
	rng.state = String(d.get("rng_state", "0")).to_int()
	difficulty = int(d.get("difficulty", 0))
	units = Array(d.get("units", [])).map(func(x): return Unit.from_dict(x))
	relics = Array(d.get("relics", [])).map(func(x): return StringName(x))
	gold = int(d.get("gold", 0))
	act_index = int(d.get("act_index", 0))
	map = RunMap.from_dict(d.get("map", {}))
	current_node = int(d.get("current_node", -1))
	visited = Array(d.get("visited", [])).map(func(x): return int(x))
	next_unit_id = int(d.get("next_unit_id", 1))
	stats = d.get("stats", {})
	for k in stats:
		stats[k] = int(stats[k])
	used_events = Array(d.get("used_events", [])).map(func(x): return StringName(x))
	unlocks = Array(d.get("unlocks", [])).map(func(x): return String(x))
	formation_prefs.clear()
	var prefs: Dictionary = d.get("formation_prefs", {})
	for k in prefs:
		formation_prefs[int(k)] = int(prefs[k])
	shops.clear()
	var shop_in: Dictionary = d.get("shops", {})
	for k in shop_in:
		var stock := {"pieces": [], "relics": []}
		for kind in stock:
			for item in shop_in[k].get(kind, []):
				stock[kind].append({"id": String(item["id"]), "price": int(item["price"]), "sold": bool(item["sold"])})
		shops[int(k)] = stock
	active = true
	changed.emit()
	return true


func save_game() -> void:
	if not active:
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("run: cannot write %s" % save_path)
		return
	f.store_string(JSON.stringify(to_save()))


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func load_game() -> bool:
	if not has_save():
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary or not from_save(parsed):
		push_warning("run: save %s is unreadable or from another version" % save_path)
		return false
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	active = false
