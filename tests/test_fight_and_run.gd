extends GutTest
## A scripted game against the real engine runs to a result, and a scripted run reaches the boss
## with unit identity, XP and losses kept across the run.


func test_scripted_game_against_engine_reaches_a_result() -> void:
	Run.new_run(5)
	var fight := FightController.new()
	add_child_autofree(fight)
	var boss: EncounterDef = Content.encounter(&"stockfish").duplicate()
	boss.movetime_ms = 30
	var units := Run.healthy_units()
	assert_true(await fight.setup(boss, units, [], Content.config, Run.formation(units)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	await fight.begin()
	var guard := 0
	while not fight.finished and guard < 300:
		guard += 1
		if fight.is_player_turn() and not fight.legal.is_empty():
			var caps := Array(fight.legal).filter(func(m): return fight.board.has(Fen.sq(m.substr(2, 2))) and not m.contains("@"))
			var pick: String = caps[0] if not caps.is_empty() else fight.legal[rng.randi_range(0, fight.legal.size() - 1)]
			await fight.try_player_move(pick)
		else:
			await get_tree().process_frame
	assert_true(fight.finished, "fight ended after %d plies" % fight.ply_count)
	assert_true(["win", "loss", "draw"].has(fight.outcome["state"]))
	gut.p("result: %s (%s) after %d plies" % [fight.outcome["state"], fight.outcome["reason"], fight.ply_count])



func test_a_formation_that_mates_at_once_gives_the_engine_the_first_move() -> void:
	Run.new_run(5)
	var units: Array = [Unit.make(1, &"king"), Unit.make(2, &"queen"), Unit.make(3, &"queen")]
	var fight := FightController.new()
	add_child_autofree(fight)
	assert_true(await fight.setup(Content.encounter(&"stockfish"), units, [], Content.config, {4: 1, 13: 2, 8: 3}))
	assert_true(fight.engine_first, "Qf2xf7 with the a2 queen behind it would mate at once")
	assert_eq(fight.base_fen.split(" ")[1], "b")
	assert_true(fight.banner_lines().has("Your formation threatens mate at once: the engine moves first."))
	var plain := FightController.new()
	add_child_autofree(plain)
	var army := Run.healthy_units()
	assert_true(await plain.setup(Content.encounter(&"stockfish"), army, [], Content.config, Run.formation(army)))
	assert_false(plain.engine_first)

func test_xp_goes_to_the_capturing_unit() -> void:
	Run.new_run(6)
	var fight := FightController.new()
	add_child_autofree(fight)
	var enc := EncounterDef.new()
	enc.id = &"t_xp"
	enc.layout = {"e8": &"king", "d3": &"knight"}
	enc.movetime_ms = 20
	enc.skill = 0
	var units := Run.healthy_units()
	assert_true(await fight.setup(enc, units, [], Content.config, Run.formation(units)))
	await fight.begin()
	var capturer := fight.unit_map.unit_at(Fen.sq("e2"))
	assert_true(fight.legal.has("e2d3"))
	await fight.try_player_move("e2d3")
	assert_eq(Run.unit(capturer).xp, 3, "a pawn that takes a knight gains 3 XP")
	assert_eq(fight.unit_map.unit_at(Fen.sq("d3")), capturer)


func test_scripted_run_crosses_three_acts_to_the_boss() -> void:
	Profile.path = "user://profile_test.json"
	Profile.reset()
	Run.new_run(42)
	var start_ids: Array = Run.units.map(func(u): return u.id)
	var steps := 0
	var guardians := 0
	var shops := 0
	var reached_boss := false
	while steps < 80:
		steps += 1
		var options := Run.available_nodes()
		assert_false(options.is_empty(), "the map always continues")
		var node := Run.enter_node(options[0])
		assert_ne(node["type"], &"unknown", "a ? node resolves when entered")
		match node["type"]:
			&"fight", &"elite", &"guardian", &"roamer":
				assert_ne(node["encounter"], &"", "fight nodes have an encounter")
				var pawns: Array = Run.healthy_units().filter(func(u): return u.type == &"pawn")
				var pawn: Unit = pawns[0] if not pawns.is_empty() else null
				var lost: Array = []
				var xp: Array = []
				if pawn != null:
					pawn.xp += 3
					xp.append({"unit": pawn.id, "amount": 3, "captured": "p"})
					var other: Array = Run.healthy_units().filter(func(u): return u.type == &"pawn" and u != pawn)
					if not other.is_empty():
						lost.append(other[0].id)
				Run.apply_fight({"state": "win", "slain": lost, "xp": xp}, node["type"])
				for u in Run.pending_level_ups():
					Run.level_up(u, Run.upgrade_options(u)[0])
				var offer := Run.reward_offer(node["type"])
				var rewards: Array = offer["pieces"]
				var cards: int = Content.config.reward_choices
				for r in Run.relic_defs():
					cards += r.extra_reward_choice
				assert_eq(rewards.size() + (1 if int(offer["train"]) > 0 else 0), cards)
				Run.add_unit(rewards[0])
				assert_true(Run.command_used() <= Run.command_cap(), "the deployed army fits its Command")
				if node["type"] != &"fight":
					Run.add_relic(Run.relic_choices(2, "guardian" if node["type"] == &"guardian" else "elite")[0])
				if node["type"] == &"guardian":
					guardians += 1
					assert_eq(node["encounter"], Run.current_act().final_encounter)
					Run.advance_act()
			&"campfire":
				if not Run.slain_units().is_empty():
					Run.restore(Run.slain_units()[0])
			&"event":
				var ev: EventDef = Run.pick_event()
				for o in ev.options:
					if Run.can_afford_option(o):
						Run.apply_event_option(o)
						break
			&"shop":
				shops += 1
				Run.add_gold(200)
				assert_not_null(Run.buy(node["id"], "pieces", 0))
			&"boss":
				assert_eq(node["encounter"], &"stockfish")
				reached_boss = true
				break
	assert_true(reached_boss, "reached the boss in %d steps" % steps)
	assert_eq(guardians, 2, "two guardians fell")
	assert_eq(Run.act_index, 2)
	for id in start_ids:
		assert_not_null(Run.unit(id), "unit %d kept its identity" % id)
	var ids: Array = Run.units.map(func(u): return u.id)
	assert_eq(ids.size(), Run.units.size())
	assert_gt(Run.units.size(), start_ids.size(), "rewards grew the army")
	assert_true(Run.units.any(func(u): return u.lineage.size() > 1), "someone levelled up")


func test_formation_places_every_unit_once() -> void:
	Run.new_run(1)
	for i in 10:
		Run.add_unit(&"pawn")
	Run.add_unit(&"rook")
	Run.add_unit(&"queen")
	var f := Run.formation(Run.healthy_units())
	assert_eq(f.size(), Run.healthy_units().size())
	assert_eq(f[Fen.sq("e1")], Run.units[0].id, "the king stands on e1")
	for sq in f:
		var u := Run.unit(f[sq])
		if u.type == &"pawn":
			assert_true(Fen.rank_of(sq) in [1, 2], "pawns on ranks 2-3")
