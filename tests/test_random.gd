extends GutTest
## v0.2d randomness: "?" nodes with pity, omens on fights, the roaming elite.


func before_each() -> void:
	Run.new_run(31)


func _fight_node() -> Dictionary:
	for n in Run.map.nodes:
		if n["type"] == &"fight":
			return n
	return {}


func _with_omen(id: StringName) -> Dictionary:
	var n := _fight_node()
	n["omen"] = id
	Run.current_node = int(n["id"])
	return n


func test_unknown_nodes_resolve_by_odds_and_pity_raises_fights() -> void:
	var counts := {}
	for i in 600:
		Run.flags["unknown_streak"] = 0
		var n := {"id": 0, "row": 1, "type": &"unknown", "encounter": &"", "omen": &""}
		Run._resolve_unknown(n)
		counts[n["type"]] = int(counts.get(n["type"], 0)) + 1
		assert_true(bool(n["unknown"]))
		if n["type"] == &"fight":
			assert_ne(n["encounter"], &"", "a resolved fight has an encounter")
	assert_almost_eq(float(counts.get(&"event", 0)) / 600.0, 0.65, 0.07, "events %s" % counts)
	assert_almost_eq(float(counts.get(&"fight", 0)) / 600.0, 0.15, 0.05, "fights %s" % counts)
	assert_gt(int(counts.get(&"treasure", 0)), 0)
	assert_gt(int(counts.get(&"shop", 0)), 0)
	var fights := 0
	for i in 200:
		Run.flags["unknown_streak"] = 12
		var n := {"id": 0, "row": 1, "type": &"unknown", "encounter": &"", "omen": &""}
		Run._resolve_unknown(n)
		if n["type"] == &"fight":
			fights += 1
			assert_eq(int(Run.flags["unknown_streak"]), 0, "a fight resets the pity")
		else:
			assert_eq(int(Run.flags["unknown_streak"]), 13)
	assert_gt(fights, 100, "after twelve fight-free ? nodes, a fight is likelier than not")


func test_maps_have_unknown_nodes_and_omens_only_on_fights() -> void:
	var fights := 0
	var omens := 0
	for seed_value in range(1, 31):
		Run.new_run(seed_value)
		for a in Run.act_count():
			assert_true(Run.map.nodes.any(func(n): return n["type"] == &"unknown"), "act %d has a ? node" % a)
			for n in Run.map.nodes:
				var t: StringName = n["type"]
				if t == &"fight" or t == &"elite":
					fights += 1
					if n["omen"] != &"":
						omens += 1
						assert_not_null(Content.omen(n["omen"]))
				else:
					assert_eq(n["omen"], &"", "no omen on a %s" % t)
			if a < Run.act_count() - 1:
				Run.advance_act()
	assert_almost_eq(float(omens) / float(fights), Content.config.omen_chance, 0.06)


func test_every_omen_has_an_icon_and_text() -> void:
	assert_eq(Content.omens.size(), 5)
	for id in Content.omens:
		var o: OmenDef = Content.omens[id]
		assert_true(ResourceLoader.exists(o.icon), "%s icon" % id)
		assert_ne(o.description, "")


func test_omen_effects_on_the_fight_and_its_outcome() -> void:
	var enc: EncounterDef = Content.encounter(_fight_node()["encounter"])
	var plain := Run.fight_mods(&"fight", enc)
	_with_omen(&"blood_moon")
	assert_almost_eq(float(Run.fight_mods(&"fight", enc)["xp_mult"]), float(plain["xp_mult"]) * 2.0, 0.001)
	_with_omen(&"fog")
	assert_eq(int(Run.fight_mods(&"fight", enc)["omen_skill"]), -4)
	_with_omen(&"eclipse")
	assert_true(bool(Run.fight_mods(&"fight", enc)["no_increment"]))
	_with_omen(&"iron_rain")
	var rained: Array = Run.fight_mods(&"fight", enc)["reinforcements"]
	var pawns := func(list: Array) -> int: return list.filter(func(e): return e[1] == "pawn").size()
	assert_eq(pawns.call(rained), pawns.call(plain["reinforcements"]) + 2, "Iron Rain: two more pawns")
	var banner: Array = Run.fight_mods(&"fight", enc)["banner"]
	assert_true(banner.any(func(l): return String(l).begins_with("Omen · Iron Rain")))
	var o := {"state": "win", "slain": [], "xp": []}
	Run.apply_fight(o, &"fight")
	var r: Array = Run.current_act().gold["fight"]
	assert_between(int(o["gold"]), int(round(int(r[0]) * 1.5)), int(round(int(r[1]) * 1.5)) + 1)
	_with_omen(&"requiem")
	var pawn: Unit = Run.healthy_units().filter(func(u): return u.type == &"pawn")[0]
	var o2 := {"state": "win", "slain": [pawn.id], "xp": []}
	Run.apply_fight(o2, &"fight")
	assert_true(pawn.is_healthy(), "Requiem: the slain pawn rises")
	assert_true(Array(o2["relic_notes"]).any(func(l): return String(l).begins_with("Requiem")))
	var guardian := Run.fight_mods(&"guardian", Content.encounter(Run.current_act().final_encounter))
	assert_false(guardian.has("omen_skill"), "no omen over a guardian")


func test_eclipse_and_fog_in_a_real_fight() -> void:
	_with_omen(&"eclipse")
	var fight := FightController.new()
	add_child_autofree(fight)
	var enc := EncounterDef.new()
	enc.id = &"t_omen"
	enc.kind = &"fight"
	enc.layout = {"e8": &"king", "d7": &"pawn", "e7": &"pawn"}
	enc.movetime_ms = 20
	enc.skill = 5
	var units := Run.fight_units(&"fight")
	var mods := Run.fight_mods(&"fight", enc)
	mods["omen_skill"] = -4
	assert_true(await fight.setup(enc, units, Run.relic_defs(), Content.config, Run.formation(units), mods))
	assert_eq(fight.increment_ms, 0, "Eclipse: no increment")
	assert_eq(fight.engine_skill(), 1, "Fog: four levels weaker")
	assert_true(Array(fight.banner_lines()).any(func(l): return String(l).begins_with("Omen · Eclipse")))


func _first_in_row(row: int) -> int:
	for n in Run.map.nodes:
		if int(n["row"]) == row:
			return int(n["id"])
	return -1


func test_the_roamer_climbs_every_second_node_and_joins_the_guardian() -> void:
	var start := Run.roamer_node()
	assert_ne(start, -1, "act 1 has a roaming elite")
	assert_eq(int(Run.map.node(start)["row"]), Content.config.roamer_start_row)
	assert_eq(Run.roamer_encounter().kind, &"elite")
	var target_before := Run.enemy_target(&"guardian")
	var entered := 0
	while Run.roamer_node() >= 0:
		var options: Array = Run.available_nodes().filter(func(id): return id != Run.roamer_node())
		if options.is_empty():
			break
		var before := Run.roamer_node()
		var row_before := int(Run.map.node(before)["row"])
		var node := Run.enter_node(options[0])
		entered += 1
		assert_ne(node["type"], &"roamer")
		if Run.roamer_node() >= 0 and entered % Content.config.roamer_every != 0:
			assert_eq(Run.roamer_node(), before, "it waits between steps")
		elif Run.roamer_node() >= 0:
			assert_eq(int(Run.map.node(Run.roamer_node())["row"]), row_before + 1, "it climbs one row")
			assert_true(Run.map.next_nodes(before).has(Run.roamer_node()), "along an edge")
	if Run.roamer_node() < 0:
		assert_true(Run.flags.has("roamer_joined"), "it reached the guardian")
		assert_almost_eq(Run.enemy_target(&"guardian"), target_before + Content.config.roamer_guardian_ratio * Run.command_cap(), 0.01)
		var mods := Run.fight_mods(&"guardian", Content.encounter(Run.current_act().final_encounter))
		assert_true(Array(mods["banner"]).any(func(l): return String(l).contains("joined the guardian")))


func test_catching_the_roamer_is_an_elite_fight_with_a_rare_relic() -> void:
	var at := _first_in_row(0)
	Run.flags["roamer"] = {"node": at, "encounter": String(Run.roamer_encounter().id), "steps": 0}
	var node := Run.enter_node(at)
	assert_eq(node["type"], &"roamer")
	assert_eq(Content.encounter(node["encounter"]).kind, &"elite")
	assert_eq(Run.roamer_node(), -1, "caught")
	assert_false(Run.flags.has("roamer_joined"))
	assert_eq(Run.enemy_target(&"roamer"), Run.enemy_target(&"elite"))
	var offer := Run.reward_offer(&"roamer")
	assert_true(Array(Run.current_act().reward_tiers["elite"]).has(int(offer["tier"])))
	var g := Run.roll_fight_gold(&"roamer")
	var r: Array = Run.current_act().gold["elite"]
	assert_between(g, int(r[0]), int(r[1]))
	var rare := 0
	for i in 40:
		for id in Run.relic_choices(1, "roamer"):
			if Content.relic(id).tier == &"rare":
				rare += 1
	assert_gt(rare, 25, "the roamer's relic is mostly rare")


func test_the_roamer_survives_a_save_and_skips_the_final_act() -> void:
	Run.enter_node(Run.available_nodes()[0])
	Run.enter_node(Run.available_nodes()[0])
	var at := Run.roamer_node()
	var save: Dictionary = JSON.parse_string(JSON.stringify(Run.to_save()))
	Run.new_run(99)
	assert_true(Run.from_save(save))
	assert_eq(Run.roamer_node(), at)
	Run.advance_act()
	assert_ne(Run.roamer_node(), -1, "act 2 has one")
	Run.advance_act()
	assert_eq(Run.roamer_node(), -1, "none in the final act")
	assert_null(Run.roamer_encounter())
