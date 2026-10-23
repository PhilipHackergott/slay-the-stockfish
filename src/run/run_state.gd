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
	return maxi(0, d.value - (1 if u.has_perk(&"vanguard") else 0))


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
	return float(act.enemy_ratio.get(String(kind), 0.0)) * mult * command_cap()


## Reinforcements that join an encounter, in order: [[square, piece id], ...].
func reinforcements(enc: EncounterDef, kind: StringName) -> Array:
	var target := enemy_target(kind)
	var have := layout_material(enc.layout)
	var out: Array = []
	if target <= 0.0 or have >= target:
		return out
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
	for e in order:
		if have >= target:
			break
		var at := Vector2i(Fen.file_of(Fen.sq(e[0])), Fen.rank_of(Fen.sq(e[0])))
		# The engine king keeps its flight squares: no back-rank box made of reinforcements.
		if taken.has(e[0]) or (absi(at.x - king.x) <= 1 and absi(at.y - king.y) <= 1):
			continue
		var d := Content.piece(StringName(e[1]))
		if d == null:
			continue
		taken[e[0]] = true
		out.append(e)
		have += d.value
	return out


## Everything a fight needs from the run besides units and relics: difficulty, reinforcements,
## relic effects on XP and the engine (relics never weaken the final boss), temporary pieces.
func fight_mods(kind: StringName, enc: EncounterDef) -> Dictionary:
	var m := difficulty_mods()
	m["reinforcements"] = reinforcements(enc, kind) if enc != null else []
	var xp_mult := 1.0
	var skill := 0
	var think := 1.0
	var first := false
	var extra: Array = []
	for r in relic_defs():
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
		r = act.gold.get(String(kind), act.gold.get("fight", r))
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
		"gain_piece_tier":
			var ids := draw_tier(_event_tier(opt), 1)
			if not ids.is_empty():
				var nu := add_unit(ids[0])
				text += " %s joins you%s." % [_name(nu), " on the bench" if nu.is_benched() else ""]
		"gain_relic":
			var choices := relic_choices(1, "event")
			if choices.is_empty():
				text += " The reliquary is empty."
			else:
				add_relic(choices[0])
				text += " You gain %s." % Content.relic(choices[0]).display_name
		"gold":
			add_gold(amount)
			text += " (+%d gold)" % amount
		"transform_up":
			var pool := healthy_units().filter(func(u):
				var d := Content.piece(u.type)
				return not d.is_royal() and d.tier < 5 and d.rarity != &"legendary")
			if not pool.is_empty():
				var t: Unit = pool[rng.randi_range(0, pool.size() - 1)]
				var ids := draw_tier(Content.piece(t.type).tier + 1, 1)
				if not ids.is_empty():
					var before := _name(t)
					_set_type(t, ids[0])
					text += " %s is now a %s." % [before, Content.piece(ids[0]).display_name]
	enforce_command()
	changed.emit()
	return text


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
	var won: bool = outcome.get("state") == "win"
	var defs := relic_defs()
	var veil := won and defs.any(func(r): return r.save_first_slain)
	var saved: Array = []
	var fell: Array = []
	var notes: Array = []
	for id in outcome.get("slain", []):
		var u := unit(int(id))
		if u == null or Content.piece(u.type).is_royal():
			continue
		if won and u.has_perk(&"bulwark"):
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
	outcome["relic_notes"] = notes
	var chance := float(cfg().flawless_relic_chance.get(String(kind), 0.0))
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
	outcome["gold"] = 0
	if won:
		stats["fights_won"] = int(stats.get("fights_won", 0)) + 1
		var flat := 0
		for r in defs:
			flat += r.gold_flat
		outcome["gold"] = maxi(0, roll_fight_gold(kind) + flat)
	add_gold(int(outcome["gold"]) + overflow + bounty)
	autofill()


## A recruit offer for a node kind: one tier rolled from the act's table, then distinct pieces of
## that tier; sometimes one slot is Train instead. {tier, pieces, train (XP, 0 = none)}.
func reward_offer(kind: StringName) -> Dictionary:
	var act := current_act()
	var tiers: Array = [1]
	if act != null:
		tiers = Array(act.reward_tiers.get(String(kind), act.reward_tiers.get("fight", [1])))
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
	flags = d.get("flags", {})
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
