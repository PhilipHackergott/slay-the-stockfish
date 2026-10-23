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
			var nodes: Array = Run.map.nodes.filter(func(n): return n.get("arena", &"") != &"" and n["type"] != &"guardian")
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
	assert_false(Run.fight_mods(&"boss", enc).has("arena"), "the boss stays plain")


func test_guardians_fight_on_their_signature_arena() -> void:
	for a in 2:
		if a > 0:
			Run.act_index = a
			Run._build_act_map()
		var g: Dictionary = Run.map.nodes.filter(func(n): return n["type"] == &"guardian")[0]
		var enc := Content.encounter(g["encounter"])
		assert_ne(enc.arena, &"", "%s has a signature arena" % enc.id)
		assert_eq(g["arena"], enc.arena)
		Run.current_node = g["id"]
		assert_eq(Run.fight_mods(&"guardian", enc).get("arena"), enc.arena)


func test_every_arena_loads_into_a_fight_with_its_icon() -> void:
	assert_eq(Content.arenas.size(), 10)
	for id in Content.arenas:
		fight = FightController.new()
		add_child_autofree(fight)
		assert_true(await _setup(id), "%s sets up" % id)
		await fight.begin()
		assert_false(fight.legal.is_empty(), "%s has legal moves" % id)
		assert_true(ResourceLoader.exists(Content.arena(id).icon), "%s icon" % id)


func test_the_hunger_forces_the_capture() -> void:
	assert_true(await _setup(&"the_hunger"))
	await _position("4k3/8/8/3p4/4P3/8/8/4W3 w - - 0 1")
	assert_eq(Array(fight.legal), ["e4d5"])


func test_the_ascent_a_king_on_the_far_rank_wins_both_ways() -> void:
	assert_true(await _setup(&"the_ascent"))
	await _position("k7/4W3/8/8/8/8/8/8 w - - 0 1")
	assert_true(await fight.try_player_move("e7e8"))
	assert_eq(fight.outcome.get("reason"), Content.arena(&"the_ascent").win_text)
	fight = FightController.new()
	add_child_autofree(fight)
	assert_true(await _setup(&"the_ascent"))
	fight.mods["omen_skill"] = 40
	fight._rebase("8/8/8/8/8/8/4k3/W7 b - - 0 1")
	await fight._engine_turn()
	assert_eq(fight.outcome.get("state"), "loss")
	assert_eq(fight.outcome.get("reason"), Content.arena(&"the_ascent").loss_text)


func test_shallow_crypt_pawns_promote_on_rank_6() -> void:
	assert_true(await _setup(&"shallow_crypt"))
	assert_true(fight.promo_ranks.has(5))
	await _position("4k3/8/8/4P3/8/8/8/4W3 w - - 0 1")
	assert_true(fight.legal.has("e5e6q"))
	assert_false(fight.legal.has("e5e6"))


func test_narrow_passage_walls_both_flanks() -> void:
	assert_true(await _setup(&"narrow_passage"))
	assert_eq(fight.walls.size(), 8)
	assert_true(fight.walls.has(Fen.sq("a3")) and fight.walls.has(Fen.sq("h6")))


func test_burning_stakes_leave_a_wall_where_a_piece_was() -> void:
	assert_true(await _setup(&"burning_stakes"))
	await _position("4k3/8/8/8/8/8/4P3/4W3 w - - 0 1")
	fight.walls = []
	assert_true(fight.legal.has("e2e3,e3e2"))
	assert_true(await fight.try_player_move("e2e3,e3e2"))
	assert_true(fight.walls.has(Fen.sq("e2")), "the square the pawn left burns")
	assert_eq(fight.walls.size(), 2, "the engine's reply burns a square too")
	assert_true(fight.statues.is_empty())


func test_gorgon_cloister_a_capturing_rook_turns_to_stone_but_is_not_slain() -> void:
	assert_true(await _setup(&"gorgon_cloister"))
	var rook := Run.add_unit(&"rook")
	await _position("4k3/8/8/3p4/8/8/8/3RW3 w - - 0 1")
	fight.walls = []
	fight.unit_map.by_square = {Fen.sq("d1"): rook.id, Fen.sq("e1"): Run.units[0].id}
	assert_true(await fight.try_player_move("d1d5"))
	var d5 := Fen.sq("d5")
	assert_true(fight.walls.has(d5))
	assert_eq(fight.statues.get(d5), "R")
	assert_true(fight.petrified.has(rook.id))
	assert_false(fight.slain.has(rook.id), "a statue wakes after the fight")
	assert_eq(fight.unit_map.unit_at(d5), -1)
	assert_true(fight.xp_log.any(func(e): return int(e["unit"]) == rook.id), "the capture still pays XP")


func test_the_crow_moves_after_every_move() -> void:
	assert_true(await _setup(&"the_crow"))
	await _position("4k3/8/8/8/8/8/4P3/4W3 w - - 0 1")
	fight.walls = []
	var mv := ""
	for m in fight.legal:
		if String(m).begins_with("e2e3,") and String(m).ends_with("a6"):
			mv = m
	assert_ne(mv, "", "moves are move plus crow square")
	assert_true(await fight.try_player_move(mv))
	assert_eq(fight.walls.size(), 1, "one crow, moved by the engine")
	assert_ne(fight.walls[0], Fen.sq("a6"), "the engine moved it on")
	var ev := fight.unit_map.apply_move("e3e4,e4h5", fight.board, "w")
	assert_eq(ev["promotion"], "", "the crow part is not a promotion")
	assert_eq(ev["to"], Fen.sq("e4"))
