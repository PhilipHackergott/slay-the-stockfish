extends GutTest
## Arenas: rule twists on fight nodes, through a real fight setup, the rules library and the engine.

var fight: FightController


func before_each() -> void:
	Run.new_run(11)
	fight = FightController.new()
	add_child_autofree(fight)


func _setup(arena: StringName, relic_ids: Array = []) -> bool:
	var relics: Array = relic_ids.map(func(id): return Content.relic(id))
	var units := Run.healthy_units()
	return await fight.setup(Content.encounter(&"rabble"), units, relics, Content.config, Run.formation(units),
		{"arena": arena})


## Puts the fight into a given position with the player to move.
func _position(fen: String) -> void:
	fight._rebase(fen)
	await fight._start_player_turn()


func test_fen_keeps_walls_and_check_counts_apart() -> void:
	var fen := "4k3/8/8/2*2*2/2*2*2/8/8/4W3 w - - 2+3 0 1"
	var st := Fen.parse(fen)
	assert_eq(st["walls"].size(), 4)
	assert_false(st["board"].has(Fen.sq("c4")))
	assert_eq(int(st["halfmove"]), 0)
	assert_eq(Fen.serialize(st), fen)
	assert_eq(Fen.checks_left(fen), {"w": 2, "b": 3})
	assert_eq(Fen.checks_left("4k3/8/8/8/8/8/8/4W3 w - - 0 1"), {})


func test_region_lines_from_a_relic_and_an_arena_merge() -> void:
	var ini: String = VariantGen.build("t_merge", "K", [], PackedStringArray(["flagRegionWhite = *8", "flagRegionWhite = d4 e4"]), false)["ini"]
	assert_string_contains(ini, "flagRegionWhite = *8 d4 e4")
	assert_eq(ini.count("flagRegionWhite"), 1)


func test_collapsed_nave_walls_block_moves_and_edits() -> void:
	assert_true(await _setup(&"collapsed_nave"))
	assert_eq(fight.walls.size(), 4)
	assert_string_contains(fight.banner_lines()[-1], "Collapsed Nave")
	await fight.begin()
	assert_true(await fight.try_player_move(fight.legal[0]))
	assert_eq(Fen.parse(fight.fen)["walls"].size(), 4, "the engine's reply keeps the rubble")
	await _position("4k3/8/8/2*2*2/2*2*2/8/8/2R1W3 w - - 0 1")
	assert_true(fight.legal.has("c1c3"))
	assert_false(fight.legal.has("c1c4"), "no piece stands on rubble")
	assert_false(fight.legal.has("c1c6"), "no slider passes through it")
	var edit := PositionEdit.move_fen(fight.fen, Fen.sq("c1"), Fen.sq("c4"), PackedInt32Array([7]), "P", 3)
	assert_false(edit["ok"], "the string cannot pull a piece onto rubble")


func test_summit_altar_your_king_wins_on_the_altar() -> void:
	assert_true(await _setup(&"summit_altar", [&"sanctuary_banner"]))
	assert_string_contains(fight.variant_ini, "flagRegionWhite = *8 d4 e4 d5 e5")
	assert_string_contains(fight.variant_ini, "flagRegionBlack = d4 e4 d5 e5")
	await _position("4k3/8/8/8/8/4W3/8/8 w - - 0 1")
	assert_true(await fight.try_player_move("e3e4"))
	assert_eq(fight.outcome.get("state"), "win")
	assert_eq(fight.outcome.get("reason"), Content.arena(&"summit_altar").win_text)


func test_summit_altar_the_engine_climbs_it_too() -> void:
	assert_true(await _setup(&"summit_altar"))
	fight.mods["omen_skill"] = 40
	fight._rebase("8/8/8/8/8/2k5/8/W7 b - - 0 1")
	await fight._engine_turn()
	assert_eq(fight.outcome.get("state"), "loss")
	assert_eq(fight.outcome.get("reason"), Content.arena(&"summit_altar").loss_text)


func test_tolling_bells_the_third_check_wins() -> void:
	assert_true(await _setup(&"tolling_bells"))
	assert_string_contains(fight.base_fen, " 3+3 ")
	await _position("4k3/8/8/8/8/8/8/R3W3 w - - 3+3 0 1")
	assert_true(await fight.try_player_move("a1a8"))
	assert_false(fight.finished, "one check is not enough")
	assert_eq(int(Fen.checks_left(fight.fen)["w"]), 2)
	await _position("4k3/8/8/8/8/8/8/R3W3 w - - 1+3 0 1")
	assert_true(await fight.try_player_move("a1a8"))
	assert_eq(fight.outcome.get("state"), "win")
	assert_eq(fight.outcome.get("reason"), Content.arena(&"tolling_bells").win_text)


func test_arenas_follow_each_acts_placement_and_survive_a_save() -> void:
	var seen := 0
	for s in 40:
		Run.new_run(100 + s)
		for a in 3:
			if a > 0:
				Run.act_index = a
				Run._build_act_map()
			var act := Run.current_act()
			var nodes: Array = Run.map.nodes.filter(func(n): return n.get("arena", &"") != &"")
			seen += nodes.size()
			assert_lte(nodes.size(), act.arena_max)
			for n in nodes:
				assert_gte(int(n["row"]), act.arena_from_row)
				assert_true(n["type"] == &"fight" or n["type"] == &"elite", str(n))
				assert_not_null(Content.arena(n["arena"]))
			if act.arena_elite_chance >= 1.0:
				for n in Run.map.nodes.filter(func(n): return n["type"] == &"elite"):
					assert_ne(n["arena"], &"", "act %d: every elite is an arena" % (a + 1))
			var back := RunMap.from_dict(Run.map.to_dict())
			for i in Run.map.nodes.size():
				assert_eq(back.node(i)["arena"], Run.map.node(i)["arena"])
	assert_gt(seen, 0)


func test_the_node_arena_reaches_the_fight() -> void:
	var id: int = -1
	for n in Run.map.nodes:
		if n["type"] == &"fight":
			id = n["id"]
			break
	Run.map.node(id)["arena"] = &"tolling_bells"
	Run.current_node = id
	var enc := Content.encounter(Run.map.node(id)["encounter"])
	assert_eq(Run.fight_mods(&"fight", enc).get("arena"), &"tolling_bells")
	assert_false(Run.fight_mods(&"guardian", enc).has("arena"), "guardians and the boss stay plain")
