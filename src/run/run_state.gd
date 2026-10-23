extends Node
## The run: the army as units with identity, relics, gold, the current act's map and progress.
## Saved at node boundaries (user://run.json), so a run can be continued from the title.

signal changed

const SAVE_VERSION := 2
const FAMILY_ORDER := [&"king", &"queen", &"rook", &"bishop", &"knight", &"pawn"]
## Where reinforcements stand when an encounter names none: pawns on rank 7, then minor pieces.
const GENERIC_REINFORCEMENTS := [["d7", "pawn"], ["e7", "pawn"], ["c7", "pawn"], ["f7", "pawn"], ["b7", "pawn"],
	["g7", "pawn"], ["a7", "pawn"], ["h7", "pawn"], ["b8", "knight"], ["g8", "knight"], ["c8", "bishop"],
	["f8", "bishop"], ["a8", "rook"], ["h8", "rook"], ["d8", "queen"]]

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
## Relic ids kindled at a campfire (their numbers are raised by half).
var kindled: Array = []
## Per-run scratch the campfire and the map share: study previews, used rites.
var flags: Dictionary = {}


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
	kindled.clear()
	flags.clear()
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


## After an act's guardian: on to the next act's map. More Command: the bench steps up.
func advance_act() -> void:
	act_index += 1
	current_node = -1
	visited.clear()
	shops.clear()
	_build_act_map()
	autofill()
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
	for n in map.nodes:
		if n["type"] == &"fight" or n["type"] == &"elite":
			_roll_omen(n)
		if n["type"] == &"elite":
			_roll_affixes(n, act)
		elif n["type"] == &"guardian":
			var g := Content.encounter(n["encounter"])
			if g != null and Content.arena(g.arena) != null:
				n["arena"] = g.arena
	_roll_arenas(act)
	_spawn_roamer()


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


## Encounters already placed on this act's map.
func _used_encounters() -> Dictionary:
	var used := {}
	for n in map.nodes:
		if n["encounter"] != &"":
			used[n["encounter"]] = true
	return used


## Node kinds that borrow another kind's numbers (gold, rewards, enemy ratio): the roamer is an elite.
func base_kind(kind: StringName) -> String:
	return "elite" if kind == &"roamer" else String(kind)


# --- omens, "?" nodes, the roaming elite ------------------------------------------------------

func _roll_omen(n: Dictionary) -> void:
	if Content.omens.is_empty() or rng.randf() >= cfg().omen_chance:
		return
	var ids: Array = Content.omens.keys()
	ids.sort()
	n["omen"] = ids[rng.randi_range(0, ids.size() - 1)]


func _roll_affixes(n: Dictionary, act: ActDef) -> void:
	if act == null or act.affix_max <= 0:
		return
	var pool: Array = Array(act.affix_pool).filter(func(a): return Content.affix(StringName(a)) != null)
	pool.sort()
	var picked: Array = []
	for i in mini(rng.randi_range(act.affix_min, act.affix_max), pool.size()):
		picked.append(StringName(pool.pop_at(rng.randi_range(0, pool.size() - 1))))
	n["affixes"] = picked


## The affixes of the elite you stand on.
func current_affixes() -> Array:
	if map == null or current_node < 0:
		return []
	var out: Array = []
	for a in map.node(current_node).get("affixes", []):
		var d := Content.affix(StringName(a))
		if d != null:
			out.append(d)
	return out


func _roll_arenas(act: ActDef) -> void:
	if act == null or act.arena_max <= 0 or Content.arenas.is_empty():
		return
	var ids: Array = Content.arenas.keys().filter(func(id): return is_unlocked(Content.arena(id).unlock))
	ids.sort()
	if ids.is_empty():
		return
	var placed := 0
	# Elites first, so an act that promises arena elites keeps that promise under arena_max.
	for kind in [&"elite", &"fight"]:
		var chance := act.arena_elite_chance if kind == &"elite" else act.arena_fight_chance
		for n in map.nodes:
			if placed >= act.arena_max or n["type"] != kind or int(n["row"]) < act.arena_from_row:
				continue
			if chance > 0.0 and rng.randf() < chance:
				n["arena"] = ids[rng.randi_range(0, ids.size() - 1)]
				placed += 1


## The arena of the node you stand on, or null.
func current_arena() -> ArenaDef:
	if map == null or current_node < 0:
		return null
	return Content.arena(StringName(map.node(current_node).get("arena", &"")))


## The omen over the node you stand on, or null.
func current_omen() -> OmenDef:
	if map == null or current_node < 0:
		return null
	return Content.omen(StringName(map.node(current_node).get("omen", &"")))


## A "?" node turns into an event, a fight, a treasure or the merchant when entered. Every time it
## is no fight, the next one is likelier to be (pity, carried across acts).
func _resolve_unknown(n: Dictionary) -> void:
	var w: Dictionary = cfg().unknown_odds.duplicate()
	var streak := int(flags.get("unknown_streak", 0))
	w["fight"] = int(w.get("fight", 0)) + streak * cfg().unknown_fight_pity
	var t := StringName(_weighted(w))
	flags["unknown_streak"] = 0 if t == &"fight" else streak + 1
	n["type"] = t
	n["unknown"] = true
	if t == &"fight":
		n["encounter"] = _pick_encounter(&"fight", int(n["row"]), _used_encounters())
		_roll_omen(n)


## One elite per act (not the final one) walks the map: {node, encounter, steps} in flags["roamer"].
## It climbs one row every roamer_every nodes you enter; catch it for a rare relic. If it reaches the
## guardian, flags["roamer_joined"] holds its encounter and the guardian fields more material.
func _spawn_roamer() -> void:
	flags.erase("roamer")
	flags.erase("roamer_joined")
	var act := current_act()
	if act == null or act.is_final_act() or map == null:
		return
	var row: Array = map.nodes.filter(func(n): return int(n["row"]) == cfg().roamer_start_row)
	var pool: Array = Content.encounters_of(&"elite", act.elite_tier)
	if row.is_empty() or pool.is_empty():
		return
	var used := _used_encounters()
	var fresh := pool.filter(func(e): return not used.has(e.id))
	if not fresh.is_empty():
		pool = fresh
	var start: Dictionary = row[rng.randi_range(0, row.size() - 1)]
	var enc: EncounterDef = pool[rng.randi_range(0, pool.size() - 1)]
	flags["roamer"] = {"node": int(start["id"]), "encounter": String(enc.id), "steps": 0}


## The node the roaming elite stands on, or -1.
func roamer_node() -> int:
	var r: Dictionary = flags.get("roamer", {})
	return int(r.get("node", -1))


func roamer_encounter() -> EncounterDef:
	var r: Dictionary = flags.get("roamer", flags.get("roamer_joined", {}))
	return Content.encounter(StringName(r.get("encounter", "")))


func _move_roamer() -> void:
	var r: Dictionary = flags.get("roamer", {})
	if r.is_empty():
		return
	r["steps"] = int(r.get("steps", 0)) + 1
	if int(r["steps"]) < cfg().roamer_every:
		return
	r["steps"] = 0
	var nxt := map.next_nodes(int(r["node"]))
	if nxt.is_empty():
		return
	var to: int = nxt[rng.randi_range(0, nxt.size() - 1)]
	var t: StringName = map.node(to)["type"]
	if t == &"guardian" or t == &"boss":
		flags.erase("roamer")
		flags["roamer_joined"] = {"encounter": r["encounter"]}
	else:
		r["node"] = to


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

## A new unit joins; it goes to the bench when the deployed army has no Command left for it.
func add_unit(type: StringName) -> Unit:
	var u := Unit.make(next_unit_id, type)
	next_unit_id += 1
	if not fits(u):
		u.post = &"bench"
	units.append(u)
	changed.emit()
	return u


func remove_unit(u: Unit) -> void:
	units.erase(u)
	formation_prefs.erase(u.id)
	changed.emit()


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


## The next-tier pieces a unit may become (unlocked ones, at most three).
func upgrade_options(u: Unit) -> Array:
	var def := Content.piece(u.type)
	if def == null:
		return []
	return Array(def.upgrades).filter(func(t): return Content.piece(t) != null and is_unlocked(Content.piece(t).unlock)).slice(0, 3)


## The perk a level-up offers next to the promotions (one, fixed per unit and level), or "".
func perk_option(u: Unit) -> StringName:
	var def := Content.piece(u.type)
	if def == null or def.is_royal() or u.perks.size() >= cfg().max_perks:
		return &""
	var ids: Array = Content.perk_ids().filter(func(p): return not u.has_perk(p))
	if ids.is_empty():
		return &""
	return ids[(u.id + u.level) % ids.size()]


## The legendary forms an Ascension may turn a tier-5 unit into.
func ascension_options(u: Unit) -> Array:
	var def := Content.piece(u.type)
	if def == null or not u.is_healthy():
		return []
	return Array(def.ascensions).filter(func(t): return Content.piece(t) != null and is_unlocked(Content.piece(t).unlock))


## Cannot rise any further: no promotion and no perk left, or the top level. Its XP turns into gold.
func is_maxed(u: Unit) -> bool:
	return xp_needed(u) < 0 or (upgrade_options(u).is_empty() and perk_option(u) == &"")


func can_level_up(u: Unit) -> bool:
	var need := xp_needed(u)
	return u.is_healthy() and need >= 0 and u.xp >= need and not is_maxed(u)


func pending_level_ups() -> Array:
	return units.filter(func(u): return can_level_up(u))


func level_up(u: Unit, new_type: StringName) -> void:
	_set_type(u, new_type)
	enforce_command()
	changed.emit()


## A level-up spent on a perk: the unit keeps its type.
func take_perk(u: Unit, perk: StringName) -> void:
	if not u.has_perk(perk):
		u.perks.append(String(perk))
	u.level += 1
	enforce_command()
	changed.emit()


func ascend(u: Unit, legend: StringName) -> void:
	u.type = legend
	u.lineage.append(String(legend))
	enforce_command()
	changed.emit()


func _set_type(u: Unit, new_type: StringName) -> void:
	u.type = new_type
	u.level += 1
	u.lineage.append(String(new_type))


# --- fusion (Graft) ---------------------------------------------------------------------------

## What two healthy units fuse into, or &"" (a recipe in the run config, tiers within the band).
func fusion_result(a: Unit, b: Unit) -> StringName:
	if a == null or b == null or a == b or not a.is_healthy() or not b.is_healthy():
		return &""
	var da := Content.piece(a.type)
	var db := Content.piece(b.type)
	if da == null or db == null or da.is_royal() or db.is_royal() or absi(da.tier - db.tier) > cfg().fusion_tier_band:
		return &""
	var parts := [String(a.type), String(b.type)]
	parts.sort()
	var into := StringName(cfg().fusions.get("+".join(parts), ""))
	return into if Content.piece(into) != null and is_unlocked(Content.piece(into).unlock) else &""


## Every pair of healthy units that can fuse: [a, b, result].
func fusion_pairs() -> Array:
	var hs := healthy_units()
	var out: Array = []
	for i in hs.size():
		for j in range(i + 1, hs.size()):
			var into := fusion_result(hs[i], hs[j])
			if into != &"":
				out.append([hs[i], hs[j], into])
	return out


## Fuses b into a's line or a into b's: the part with more XP survives with XP = higher + half the
## lower, the higher level, one perk (keep_perk if either has it, else the first), both lineages,
## and a Command cost of the higher part's value + 1. Returns the fused unit, or null.
func fuse(a: Unit, b: Unit, keep_perk: String = "") -> Unit:
	var into := fusion_result(a, b)
	if into == &"":
		return null
	var hi := a if a.xp >= b.xp else b
	var lo := b if hi == a else a
	var cost := maxi(Content.piece(a.type).value, Content.piece(b.type).value) + 1
	var perks := Array(hi.perks) + Array(lo.perks)
	hi.xp += lo.xp / 2
	hi.level = maxi(hi.level, lo.level)
	hi.perks = PackedStringArray([keep_perk] if perks.has(keep_perk) else perks.slice(0, 1))
	hi.lineage.append_array(lo.lineage)
	hi.lineage.append(String(into))
	hi.captures += lo.captures
	hi.fights = maxi(hi.fights, lo.fights)
	hi.type = into
	hi.command_type = into
	hi.command_override = cost
	units.erase(lo)
	stats["fusions"] = int(stats.get("fusions", 0)) + 1
	enforce_command()
	autofill()
	changed.emit()
	return hi


## A campfire may Graft while a relic allows it.
func can_graft() -> bool:
	return relic_defs().any(func(r): return r.campfire_graft)


## Campfire: restore one slain unit (it keeps its XP and level: the handover's proposal).
func restore(u: Unit) -> void:
	u.state = &"healthy"
	u.post = &""
	if not fits(u):
		u.post = &"bench"
	changed.emit()


## Campfire: upgrade one healthy unit without XP.
func campfire_upgrade(u: Unit, new_type: StringName) -> void:
	_set_type(u, new_type)
	enforce_command()
	changed.emit()


## Train reward and drills: XP straight to a unit.
func train(u: Unit, amount: int) -> void:
	u.xp += amount
	changed.emit()


## Campfire Drill: XP to every deployed piece.
func drill() -> int:
	var n := 0
	for u in deployed_units():
		u.xp += cfg().camp_drill_xp
		n += 1
	changed.emit()
	return n


## Campfire Study: the act's guardian fight gives you extra clock time.
func study() -> void:
	flags["study"] = act_index
	changed.emit()


func studied() -> bool:
	return int(flags.get("study", -1)) == act_index


## Campfire Rite of Ash: burn one piece; the heir gains its XP plus its value. Returns the XP.
func rite(burned: Unit, heir: Unit) -> int:
	if burned == heir or Content.piece(burned.type).is_royal() or not heir.is_healthy():
		return 0
	var gain := burned.xp + Content.piece(burned.type).value
	remove_unit(burned)
	heir.xp += gain
	changed.emit()
	return gain


func kindle_options() -> Array:
	return relics.filter(func(id):
		var r := Content.relic(id)
		return r != null and r.kindle_text != "" and r.tier != &"curse" and not kindled.has(id))


func kindle(id: StringName) -> void:
	if kindle_options().has(id):
		kindled.append(id)
		enforce_command()
		autofill()
		changed.emit()


# --- command ----------------------------------------------------------------------------------

## The act's Command plus relics and the king line; 0 = no cap.
func command_cap() -> int:
	var act := current_act()
	if act == null or act.command <= 0:
		return 0
	var c := act.command
	for r in relic_defs():
		c += r.command_bonus
	var k := king_unit()
	if k != null:
		c += Content.piece(k.type).command_bonus
	return c


## What a unit costs to deploy: its value (the king is free, Vanguard takes one off).
func command_cost(u: Unit) -> int:
	var d := Content.piece(u.type)
	if d == null or d.is_royal():
		return 0
	var base := u.command_override if u.command_override >= 0 and u.command_type == u.type else d.value
	return maxi(0, base - (1 if u.has_perk(&"vanguard") else 0))


func deployed_units() -> Array:
	return units.filter(func(u): return u.is_healthy() and not u.is_benched())


func benched_units() -> Array:
	return units.filter(func(u): return u.is_healthy() and u.is_benched())


func command_used() -> int:
	var n := 0
	for u in deployed_units():
		n += command_cost(u)
	return n


## Whether a unit that is not deployed yet would fit.
func fits(u: Unit) -> bool:
	var cap := command_cap()
	return cap <= 0 or command_used() + command_cost(u) <= cap


## Over the cap (a promotion, a relic lost): bench the cheapest deployed pieces until it fits.
## Returns the benched units.
func enforce_command() -> Array:
	var out: Array = []
	var cap := command_cap()
	if cap <= 0:
		return out
	while command_used() > cap:
		var pool := deployed_units().filter(func(u): return command_cost(u) > 0)
		if pool.is_empty():
			break
		pool.sort_custom(func(a, b): return command_cost(a) < command_cost(b) if command_cost(a) != command_cost(b) else a.id > b.id)
		pool[0].post = &"bench"
		out.append(pool[0])
	return out


## Benched-for-room units step up while there is Command for them, the strongest first.
func autofill() -> void:
	var pool := benched_units().filter(func(u): return u.post == &"bench")
	pool.sort_custom(func(a, b): return command_cost(a) > command_cost(b) if command_cost(a) != command_cost(b) else a.id < b.id)
	for u in pool:
		if fits(u):
			u.post = &""


## The player benches a unit (it stays benched) or deploys one (if it fits). Returns success.
func set_benched(u: Unit, on: bool) -> bool:
	if on:
		if Content.piece(u.type).is_royal():
			return false
		u.post = &"held"
	else:
		if not u.is_benched():
			return true
		if not fits(u):
			return false
		u.post = &""
	changed.emit()
	return true


## Who fights a node of this kind: the deployed army, or everyone in an uncapped final fight.
func fight_units(kind: StringName) -> Array:
	var act := current_act()
	if (kind == &"boss" or kind == &"guardian") and act != null and act.final_uncapped:
		return healthy_units()
	return deployed_units()


## Material of an enemy layout (its king excluded).
func layout_material(layout: Dictionary) -> int:
	var n := 0
	for sq in layout:
		var d := Content.piece(StringName(layout[sq]))
		if d != null and not d.is_royal() and d.id != &"king":
			n += d.value
	return n


## The material an encounter of this kind is filled up to (Command x the act's ratio); 0 = as is.
func enemy_target(kind: StringName) -> float:
	var act := current_act()
	if act == null:
		return 0.0
	var mult := 1.0
	for r in relic_defs():
		mult *= r.enemy_ratio_mult
	var ratio := float(act.enemy_ratio.get(base_kind(kind), 0.0))
	if kind == &"guardian" and flags.has("roamer_joined"):
		ratio += cfg().roamer_guardian_ratio
	return ratio * mult * command_cap()


## Reinforcements that join an encounter, in order: [[square, piece id], ...]. extra_pawns come on
## top of the material target (Iron Rain).
func reinforcements(enc: EncounterDef, kind: StringName, extra_pawns: int = 0, ratio_mult: float = 1.0) -> Array:
	var target := enemy_target(kind) * ratio_mult
	var have := layout_material(enc.layout)
	var out: Array = []
	var order: Array = []
	for sq in enc.reinforcements:
		order.append([String(sq), String(enc.reinforcements[sq])])
	order.append_array(GENERIC_REINFORCEMENTS)
	var taken := {}
	var king := Vector2i(-9, -9)
	for sq in enc.layout:
		taken[String(sq)] = true
		if StringName(enc.layout[sq]) == &"king":
			king = Vector2i(Fen.file_of(Fen.sq(String(sq))), Fen.rank_of(Fen.sq(String(sq))))
	# The engine king keeps its flight squares: no back-rank box made of reinforcements.
	var free := func(sq: String) -> bool:
		var at := Vector2i(Fen.file_of(Fen.sq(sq)), Fen.rank_of(Fen.sq(sq)))
		return not taken.has(sq) and (absi(at.x - king.x) > 1 or absi(at.y - king.y) > 1)
	for e in order:
		if target <= 0.0 or have >= target:
			break
		var d := Content.piece(StringName(e[1]))
		if d == null or not free.call(e[0]):
			continue
		taken[e[0]] = true
		out.append(e)
		have += d.value
	for e in GENERIC_REINFORCEMENTS:
		if extra_pawns <= 0:
			break
		if e[1] == "pawn" and free.call(e[0]):
			taken[e[0]] = true
			out.append(e)
			extra_pawns -= 1
	return out


## Everything a fight needs from the run besides units and relics: difficulty, reinforcements,
## relic effects on XP and the engine (relics never weaken the final boss), temporary pieces, the
## node's omen, banner lines for the HUD.
func fight_mods(kind: StringName, enc: EncounterDef) -> Dictionary:
	var m := difficulty_mods()
	var omen := current_omen() if kind != &"guardian" and kind != &"boss" else null
	var affixes: Array = current_affixes() if kind == &"elite" else []
	var banner: Array = []
	m["node_kind"] = kind
	var pawns := omen.extra_pawns if omen != null else 0
	var ratio := 1.0
	for af in affixes:
		pawns += af.extra_pawns
		ratio *= af.enemy_ratio_mult
	m["reinforcements"] = reinforcements(enc, kind, pawns, ratio) if enc != null else []
	var xp_mult := 1.0
	var skill := 0
	var think := 1.0
	var first := false
	var extra: Array = []
	for r in (relic_defs() if kind != &"puzzle" else []):
		xp_mult *= r.xp_mult
		skill += r.engine_skill_delta
		think *= r.movetime_mult
		first = first or r.engine_first
		extra.append_array(Array(r.start_pieces))
	m["xp_mult"] = xp_mult
	if kind != &"boss":
		m["relic_skill"] = skill
		m["movetime_mult"] = float(m["movetime_mult"]) * think
	m["engine_first"] = first
	m["start_pieces"] = extra
	if kind == &"guardian" and studied():
		m["clock_delta_s"] = int(m["clock_delta_s"]) + cfg().camp_study_clock_s
	if map != null and current_node >= 0 and bool(map.node(current_node).get("unknown", false)) and kind == &"fight":
		banner.append("Ambush: the unknown path was a fight.")
	if kind == &"roamer":
		banner.append("You caught the roaming elite. Beat it for a rare relic.")
	if flags.has("second_chance"):
		banner.append("%s shatters: the fight begins again." % String(flags["second_chance"]))
		flags.erase("second_chance")
	if enc != null and enc.move_limit > 0:
		banner.append("Mate in %d: your relics stay out of it, and move %d must checkmate." % [enc.move_limit, enc.move_limit])
	if kind == &"skirmish":
		banner.append("The Pit: no piece of yours stays dead here.")
	if kind == &"boss" and int(flags.get("oracle_s", 0)) > 0:
		m["clock_delta_s"] = int(m["clock_delta_s"]) + int(flags["oracle_s"])
		banner.append("The Oracle's reading: +%d s on your clock." % int(flags["oracle_s"]))
	if kind == &"guardian" and flags.has("roamer_joined"):
		var re := roamer_encounter()
		banner.append("%s has joined the guardian: more enemy pieces." % (re.display_name if re != null else "The roaming elite"))
	var arena := current_arena() if kind == &"fight" or kind == &"elite" or kind == &"guardian" else null
	if arena != null:
		m["arena"] = arena.id
	if omen != null:
		m["xp_mult"] = float(m["xp_mult"]) * omen.xp_mult
		m["omen_skill"] = omen.engine_skill_delta
		m["no_increment"] = omen.no_increment
		banner.append("Omen · %s: %s" % [omen.display_name, omen.description])
	for af in affixes:
		m["affix_skill"] = int(m.get("affix_skill", 0)) + af.engine_skill_delta
		m["movetime_mult"] = float(m["movetime_mult"]) * af.movetime_mult
		m["clock_delta_s"] = int(m["clock_delta_s"]) + af.clock_delta_s
		m["no_increment"] = bool(m.get("no_increment", false)) or af.no_increment
		m["engine_first"] = bool(m["engine_first"]) or af.engine_first
		banner.append("Elite · %s: %s" % [af.display_name, af.description])
	m["banner"] = banner
	return m


## XP for one capture by a unit: the captured piece's value, perks, relics and fight modifiers.
func capture_xp(u: Unit, base: int, mods: Dictionary) -> int:
	if base <= 0:
		return 0
	var x := float(base) * float(mods.get("xp_mult", 1.0))
	if u.has_perk(&"veteran"):
		x *= 1.5
	var bonus := 0
	var d := Content.piece(u.type)
	for r in relic_defs():
		if r.xp_bonus != 0 and (r.xp_family == &"" or (d != null and d.base == r.xp_family)):
			bonus += r.xp_bonus
	return maxi(1, ceili(x - 0.001) + bonus)


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
		r = act.gold.get(base_kind(kind), act.gold.get("fight", r))
	var base := rng.randi_range(int(r[0]), int(r[1]))
	return int(round(base * float(difficulty_mods()["gold_mult"]) * (1.0 + gold_bonus())))


# --- relics -----------------------------------------------------------------------------------

func has_relic(id: StringName) -> bool:
	return relics.has(id)


func add_relic(id: StringName) -> void:
	if not relics.has(id) and Content.relic(id) != null:
		relics.append(id)
		enforce_command()
		changed.emit()


func remove_relic(id: StringName) -> void:
	relics.erase(id)
	kindled.erase(id)
	enforce_command()
	changed.emit()


## A fight that would end the run: a second-chance relic shatters and the fight starts over.
func take_second_chance() -> bool:
	for id in relics:
		var r := Content.relic(id)
		if r != null and r.second_chance:
			remove_relic(id)
			flags["second_chance"] = r.display_name
			return true
	return false


## The relics in effect (kindled ones with their stronger numbers).
func relic_defs() -> Array:
	var out: Array = []
	for id in relics:
		var r := Content.relic(id)
		if r != null:
			out.append(r.kindled() if kindled.has(id) else r)
	return out


func curses() -> Array:
	return relics.filter(func(id): return Content.relic(id) != null and Content.relic(id).tier == &"curse")


## Relic cards for a source (start, elite, guardian, treasure, shop, flawless, event): n distinct,
## not owned, unlocked, by the source's tier odds; a short tier hands its slot to the others.
## Curses are never offered.
func relic_choices(n: int, source: String = "event") -> Array:
	var odds: Dictionary = cfg().relic_odds.get(source, {"common": 1, "uncommon": 1, "rare": 1})
	var pool: Array = Content.relics.keys().filter(func(id):
		var r := Content.relic(id)
		return not relics.has(id) and is_unlocked(r.unlock) and odds.has(String(r.tier)))
	pool.sort()
	var out: Array = []
	while not pool.is_empty() and out.size() < n:
		var w := {}
		for id in pool:
			var t := String(Content.relic(id).tier)
			w[t] = int(odds[t])
		var tier := StringName(_weighted(w))
		var of_tier: Array = pool.filter(func(id): return Content.relic(id).tier == tier)
		var pick: StringName = of_tier[rng.randi_range(0, of_tier.size() - 1)]
		out.append(pick)
		pool.erase(pick)
	return out


## How many relic cards a source shows (Black Candle adds one).
func relic_card_count(base: int) -> int:
	var n := base
	for r in relic_defs():
		n += r.relic_choice_bonus
	return n


# --- events -----------------------------------------------------------------------------------

## An unused event of this act's pool; else any unused one; else any.
func pick_event() -> EventDef:
	var all: Array = Content.events.keys().filter(func(id): return is_unlocked(Content.events[id].unlock))
	all.sort()
	var fresh := all.filter(func(id): return not used_events.has(id))
	var pool := fresh.filter(func(id):
		var acts: PackedInt32Array = Content.events[id].acts
		return acts.is_empty() or acts.has(act_index + 1))
	if pool.is_empty():
		pool = fresh
	if pool.is_empty():
		pool = all
	if pool.is_empty():
		return null
	var id: StringName = pool[rng.randi_range(0, pool.size() - 1)]
	used_events.append(id)
	return Content.events[id]


## Whether an option can be taken: its cost paid (gold, a pawn to give up), a piece to stitch, a
## problem to set.
func can_afford_option(opt: Dictionary) -> bool:
	if String(opt.get("effect", "")) == "stitch" and stitch_options(String(opt.get("atom", "W"))).is_empty():
		return false
	if String(opt.get("effect", "")) == "graft" and fusion_pairs().is_empty():
		return false
	if String(opt.get("effect", "")) == "gain_relic" and opt.has("relic") and has_relic(StringName(opt["relic"])):
		return false
	if String(opt.get("fight", "")) == "puzzle" and _puzzles(int(opt.get("tier", 1))).is_empty():
		return false
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
		"gain_piece_tier":
			var ids := draw_tier(_event_tier(opt), 1)
			if not ids.is_empty():
				var nu := add_unit(ids[0])
				text += " %s joins you%s." % [_name(nu), " on the bench" if nu.is_benched() else ""]
		"graft":
			var pairs := fusion_pairs()
			pairs.sort_custom(func(x, y): return Content.piece(x[2]).value > Content.piece(y[2]).value)
			if not pairs.is_empty():
				var names := "%s and %s" % [_name(pairs[0][0]), _name(pairs[0][1])]
				var fused := fuse(pairs[0][0], pairs[0][1])
				text += " %s become one %s." % [names, Content.piece(fused.type).display_name.to_lower()]
		"gain_relic":
			var choices := [StringName(opt["relic"])] if opt.has("relic") else relic_choices(1, String(opt.get("source", "event")))
			if choices.is_empty():
				text += " The reliquary is empty."
			else:
				add_relic(choices[0])
				text += " You gain %s." % Content.relic(choices[0]).display_name
		"gold":
			add_gold(amount)
			text += " (+%d gold)" % amount
		"lose_gold":
			var lost := mini(gold, amount)
			spend_gold(lost)
			text += " (-%d gold)" % lost
		"transform_up":
			for i in amount:
				var pool := healthy_units().filter(func(u):
					var d := Content.piece(u.type)
					return not d.is_royal() and d.tier < 5 and d.rarity != &"legendary")
				if pool.is_empty():
					break
				var t: Unit = pool[rng.randi_range(0, pool.size() - 1)]
				var ids := draw_tier(Content.piece(t.type).tier + 1, 1)
				if not ids.is_empty():
					var before := _name(t)
					_set_type(t, ids[0])
					text += " %s is now a %s." % [before, Content.piece(ids[0]).display_name]
		"restore_all":
			var fallen := slain_units()
			for u in fallen:
				restore(u)
			text += " (%d pieces return)" % fallen.size()
		"study_boss":
			flags["oracle_s"] = int(flags.get("oracle_s", 0)) + amount
		"stitch":
			var u := unit(int(opt.get("unit", -1)))
			if u != null:
				var before := _name(u)
				stitch(u, String(opt.get("atom", "W")))
				text += " %s is now a %s." % [before, Content.piece(u.type).display_name.to_lower()]
	if opt.has("curse"):
		var c := Content.relic(StringName(opt["curse"]))
		if c != null and not has_relic(c.id):
			add_relic(c.id)
			text += " %s clings to you." % c.display_name
	enforce_command()
	changed.emit()
	return text


## Pieces the Tailor can stitch this atom onto: healthy, not royal, not pawn-like, not stitched yet,
## and the atom must add squares.
func stitch_options(atom: String) -> Array:
	return healthy_units().filter(func(u):
		var d := Content.piece(u.type)
		if d == null or d.is_royal() or d.pawn_like or d.base == &"pawn" or String(u.type).contains(Content.STITCH):
			return false
		var b := Betza.of(u.type)
		return Betza.squares(b + atom).size() > Betza.squares(b).size())


## The stitch keeps the unit's level; it holds until the piece rises a tier.
func stitch(u: Unit, atom: String) -> void:
	u.type = Content.stitched_id(u.type, atom)
	u.lineage.append(String(u.type))
	enforce_command()
	changed.emit()


## The Pit: your king and your n greenest deployed pieces (least XP first).
func skirmish_units(n: int) -> Array:
	var out: Array = []
	var k := king_unit()
	if k != null and k.is_healthy():
		out.append(k)
	var rest := deployed_units().filter(func(u): return not Content.piece(u.type).is_royal())
	rest.sort_custom(func(a, b): return a.xp < b.xp or (a.xp == b.xp and a.id < b.id))
	out.append_array(rest.slice(0, n))
	return out


## Problems of a tier not solved or failed yet this run (all of them once every one was tried).
func _puzzles(tier: int) -> Array:
	var done: Array = flags.get("puzzles", [])
	var all := Content.encounters_of(&"puzzle", tier)
	all.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var fresh := all.filter(func(e): return not done.has(String(e.id)))
	return fresh if not fresh.is_empty() else all


## The encounter of an event fight: the option's own, or a problem of its tier.
func event_encounter(opt: Dictionary) -> EncounterDef:
	if opt.has("encounter"):
		return Content.encounter(StringName(opt["encounter"]))
	var pool := _puzzles(int(opt.get("tier", 1)))
	return pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else null


## An event fight is over. Nothing of it lasts but XP taken (no losses, no fight count); the
## option's win or lose part applies.
func apply_event_fight(outcome: Dictionary, opt: Dictionary) -> String:
	if String(opt.get("fight", "")) == "puzzle":
		var done: Array = flags.get("puzzles", [])
		done.append(String(outcome.get("encounter", "")))
		flags["puzzles"] = done
	var part: Dictionary = opt.get("win" if String(outcome.get("state", "")) == "win" else "lose", {})
	return apply_event_option(part) if not part.is_empty() else ""


## Tier for event pieces: the option's, else the top tier of this act's fight rewards.
func _event_tier(opt: Dictionary) -> int:
	if opt.has("tier"):
		return int(opt["tier"])
	var act := current_act()
	var tiers: Array = Array(act.reward_tiers.get("fight", [1])) if act != null else [1]
	return int(tiers.max())


func _name(u: Unit) -> String:
	var d := Content.piece(u.type)
	return "%s #%d" % [d.display_name if d != null else String(u.type), u.id]


# --- map and nodes ----------------------------------------------------------------------------

func available_nodes() -> Array:
	if map == null:
		return []
	return map.start_nodes() if current_node < 0 else map.next_nodes(current_node)


## Steps onto a node. A "?" resolves here; the roaming elite, if it stands here, is the fight instead
## (kind roamer); otherwise it climbs on.
func enter_node(id: int) -> Dictionary:
	var caught := roamer_node() == id
	current_node = id
	visited.append(id)
	stats["nodes"] = int(stats.get("nodes", 0)) + 1
	var n: Dictionary = map.node(id)
	if caught:
		var enc := roamer_encounter()
		flags.erase("roamer")
		changed.emit()
		return {"id": id, "row": n["row"], "type": &"roamer", "encounter": enc.id if enc != null else n["encounter"],
			"omen": n.get("omen", &"")}
	if n["type"] == &"unknown":
		_resolve_unknown(n)
	_move_roamer()
	changed.emit()
	return n


func is_boss_node(id: int) -> bool:
	return map != null and id >= 0 and map.node(id)["type"] == &"boss"


# --- fights -----------------------------------------------------------------------------------

## Applies a finished fight: slain units stay dead until a campfire restores them. A win pays gold;
## XP earned by units that cannot rise any further turns into gold too.
func apply_fight(outcome: Dictionary, kind: StringName = &"fight") -> void:
	last_outcome = outcome
	var won: bool = outcome.get("state") == "win"
	var defs := relic_defs()
	var omen := current_omen() if kind != &"guardian" and kind != &"boss" else null
	var requiem := won and omen != null and omen.revive_slain
	var veil := won and defs.any(func(r): return r.save_first_slain)
	var saved: Array = []
	var fell: Array = []
	var notes: Array = []
	for id in outcome.get("slain", []):
		var u := unit(int(id))
		if u == null or Content.piece(u.type).is_royal():
			continue
		if (won and u.has_perk(&"bulwark")) or requiem:
			saved.append(u.id)
			continue
		if veil:
			veil = false
			saved.append(u.id)
			notes.append("Mourning Veil: %s gets back up." % _name(u))
			continue
		u.state = &"slain"
		fell.append(u)
		stats["units_lost"] = int(stats.get("units_lost", 0)) + 1
	outcome["saved"] = saved
	outcome["flawless"] = won and fell.is_empty()
	var fought: Array = []
	for id in outcome.get("fought", []):
		var u := unit(int(id))
		if u != null and u.is_healthy():
			u.fights += 1
			fought.append(u)
	var on_loss := 0
	var after := 0
	for r in defs:
		on_loss += r.xp_on_loss
		after += r.xp_after_fight
	if on_loss > 0 and not fell.is_empty():
		for u in fought:
			u.xp += on_loss * fell.size()
		notes.append("Martyr's Locket: +%d XP to %d pieces." % [on_loss * fell.size(), fought.size()])
	if after > 0 and won:
		for u in fought:
			u.xp += after
		notes.append("Drill Whistle: +%d XP to %d pieces." % [after, fought.size()])
	if requiem and not saved.is_empty():
		notes.append("Requiem: %d slain pieces rise again." % saved.size())
	outcome["relic_notes"] = notes
	var chance := float(cfg().flawless_relic_chance.get(base_kind(kind), 0.0))
	outcome["flawless_relic"] = bool(outcome["flawless"]) and chance > 0.0 and rng.randf() < chance
	var overflow := 0
	var bounty := 0
	for e in outcome.get("xp", []):
		var u := unit(int(e["unit"]))
		stats["captures"] = int(stats.get("captures", 0)) + 1
		if u != null and is_maxed(u):
			overflow += int(e["amount"]) * cfg().overflow_gold_per_xp
		if u != null and u.has_perk(&"bounty"):
			bounty += 5
	outcome["overflow_gold"] = overflow
	outcome["bounty_gold"] = bounty
	outcome["time_gold"] = time_gold(float(outcome.get("clock_left_ms", 0.0))) if won else 0
	outcome["gold"] = 0
	if won:
		stats["fights_won"] = int(stats.get("fights_won", 0)) + 1
		var flat := 0
		for r in defs:
			flat += r.gold_flat
		var gold_mult := omen.gold_mult if omen != null else 1.0
		outcome["gold"] = maxi(0, int(round(roll_fight_gold(kind) * gold_mult)) + flat)
		if gold_mult != 1.0:
			notes.append("%s: %d%% gold." % [omen.display_name, int(round(gold_mult * 100.0))])
	add_gold(int(outcome["gold"]) + overflow + bounty + int(outcome["time_gold"]))
	autofill()


## Gold for the clock left after a won map fight.
func time_gold(clock_left_ms: float) -> int:
	return clampi(floori(clock_left_ms / 1000.0 / maxf(1.0, cfg().time_gold_seconds)), 0, cfg().time_gold_max)


## A recruit offer for a node kind: one tier rolled from the act's table, then distinct pieces of
## that tier; sometimes one slot is Train instead. {tier, pieces, train (XP, 0 = none)}.
func reward_offer(kind: StringName) -> Dictionary:
	var act := current_act()
	var tiers: Array = [1]
	if act != null:
		tiers = Array(act.reward_tiers.get(base_kind(kind), act.reward_tiers.get("fight", [1])))
	var tier := int(tiers[rng.randi_range(0, tiers.size() - 1)])
	var n := cfg().reward_choices
	for r in relic_defs():
		n += r.extra_reward_choice
	var pieces := draw_tier(tier, n)
	var train_xp := 0
	if pieces.size() >= n and rng.randf() < cfg().train_chance:
		pieces.pop_back()
		train_xp = act.train_xp if act != null else 4
	return {"tier": tier, "pieces": pieces, "train": train_xp}


func reward_choices(kind: StringName) -> Array:
	return reward_offer(kind)["pieces"]


## n distinct unlocked recruits of one tier, by weight; the next tiers down, then up, fill a short pool.
func draw_tier(tier: int, n: int, exclude: Array = []) -> Array:
	var out: Array = []
	for t in [tier, tier - 1, tier + 1, tier - 2]:
		if out.size() >= n:
			break
		var pool: Array = Content.recruits_of_tier(t).filter(func(p):
			return is_unlocked(p.unlock) and not out.has(p.id) and not exclude.has(p.id))
		while out.size() < n and not pool.is_empty():
			var w := {}
			for p in pool:
				w[p.id] = maxi(1, p.reward_weight)
			var id := StringName(_weighted(w))
			out.append(id)
			pool = pool.filter(func(p): return p.id != id)
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
	return int(round(p * price_mult()))


func relic_price(id: StringName) -> int:
	var r := Content.relic(id)
	var base := 100
	if r != null:
		base = r.price if r.price > 0 else int(cfg().relic_prices.get(String(r.tier), 100))
	return int(round(base * price_mult()))


## Shop prices: difficulty times relics (Ledger, Engine Shard).
func price_mult() -> float:
	var m := float(difficulty_mods()["price_mult"])
	for r in relic_defs():
		m *= r.price_mult
	return m


func restore_price() -> int:
	return int(round(cfg().restore_price * price_mult()))


## The stock of the shop at node_id (rolled once, then kept until rerolled).
func shop(node_id: int) -> Dictionary:
	if shops.has(node_id):
		return shops[node_id]
	var stock := _roll_stock()
	stock["rerolls"] = 0
	shops[node_id] = stock
	return stock


func _roll_stock() -> Dictionary:
	var act := current_act()
	var tiers: Array = Array(act.shop_tiers) if act != null else [1, 2]
	var stock := {"pieces": [], "relics": []}
	var ids: Array = []
	for i in cfg().shop_pieces:
		ids.append_array(draw_tier(int(tiers[rng.randi_range(0, tiers.size() - 1)]), 1, ids))
	for id in ids:
		stock["pieces"].append({"id": String(id), "price": piece_price(id), "sold": false})
	for id in relic_choices(cfg().shop_relics, "shop"):
		stock["relics"].append({"id": String(id), "price": relic_price(id), "sold": false})
	return stock


func reroll_price(node_id: int) -> int:
	var n := int(shop(node_id).get("rerolls", 0))
	return int(round((cfg().reroll_price + cfg().reroll_step * n) * price_mult()))


## New wares for gold (the price rises with every reroll at this shop).
func reroll_shop(node_id: int) -> bool:
	var n := int(shop(node_id).get("rerolls", 0))
	if not spend_gold(reroll_price(node_id)):
		return false
	var stock := _roll_stock()
	stock["rerolls"] = n + 1
	shops[node_id] = stock
	changed.emit()
	return true


func surgeon_price() -> int:
	return int(round(cfg().surgeon_price * price_mult()))


## The Bone Surgeon raises a healthy piece one tier for gold.
func surgeon_promote(u: Unit, new_type: StringName) -> bool:
	if not u.is_healthy() or not upgrade_options(u).has(new_type) or not spend_gold(surgeon_price()):
		return false
	_set_type(u, new_type)
	enforce_command()
	changed.emit()
	return true


## The Bone Surgeon takes a piece off your hands for a little gold (never the king).
func dismiss(u: Unit) -> int:
	if Content.piece(u.type).is_royal():
		return 0
	remove_unit(u)
	add_gold(cfg().dismiss_gold)
	return cfg().dismiss_gold


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
	var hs := deployed_units()
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
		"kindled": kindled.map(func(r): return String(r)), "flags": flags.duplicate(true),
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
	kindled = Array(d.get("kindled", [])).map(func(x): return StringName(x))
	flags = _whole(d.get("flags", {}))
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
		stock["rerolls"] = int(shop_in[k].get("rerolls", 0))
		shops[int(k)] = stock
	active = true
	changed.emit()
	return true


## JSON reads every number as a float: whole ones back to int (node ids, counters), nested too.
func _whole(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)):
		return int(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _whole(v[k])
		return out
	if v is Array:
		return v.map(func(e): return _whole(e))
	return v


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
