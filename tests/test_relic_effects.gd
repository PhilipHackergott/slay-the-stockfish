extends GutTest
## Relic tiers, offers and the run-side effects (gold, XP, saves, Command, engine, rewards).


func before_each() -> void:
	RunFixture.classic(21)


func test_every_relic_has_a_tier_a_label_and_an_icon() -> void:
	for id in Content.relics:
		var r: RelicDef = Content.relics[id]
		assert_true(UiKit.TIER_LABEL.has(r.tier), "%s tier %s" % [id, r.tier])
		assert_true(UiKit.KIND_LABEL.has(r.kind), "%s kind %s" % [id, r.kind])
		assert_true(ResourceLoader.exists(r.icon), "%s icon %s" % [id, r.icon])
		assert_ne(r.description, "")


func test_offers_follow_their_tiers_and_never_hold_curses() -> void:
	var allowed := {"start": [&"common", &"uncommon"], "guardian": [&"boss"], "elite": [&"uncommon", &"rare"]}
	for source in ["start", "guardian", "elite", "treasure", "shop", "flawless", "event"]:
		for i in 10:
			var ids := Run.relic_choices(4, source)
			assert_false(ids.is_empty(), source)
			for id in ids:
				var t: StringName = Content.relic(id).tier
				assert_ne(t, &"curse", "%s offers no curses" % source)
				if allowed.has(source):
					assert_true(allowed[source].has(t), "%s offered %s (%s)" % [source, id, t])
	assert_eq(Run.relic_price(&"tattered_standard"), Content.config.relic_prices["common"])


func test_the_roamer_offers_its_own_odds() -> void:
	var o := {"state": "win", "slain": [], "xp": [], "encounter": &"bishop_of_ash", "gold": 40}
	var rares := 0
	for i in 20:
		var r: RewardScreen = RewardScreen.new().setup(o, &"roamer")
		var ids: Array = r._relic_ids_for_kind()
		rares += ids.filter(func(id): return Content.relic(id).tier == &"rare").size()
		r.free()
	assert_gt(rares, 28, "about 9 in 10 roamer cards are rare")


func test_gold_relics() -> void:
	Run.add_relic(&"pilgrims_coin")
	var o := {"state": "win", "slain": [], "xp": [], "fought": []}
	var before := Run.gold
	Run.apply_fight(o, &"fight")
	var act := Run.current_act()
	assert_between(int(o["gold"]), int(act.gold["fight"][0]) + 5, int(act.gold["fight"][1]) + 5)
	assert_eq(Run.gold, before + int(o["gold"]))
	Run.remove_relic(&"pilgrims_coin")
	Run.add_relic(&"debt_of_bone")
	var o2 := {"state": "win", "slain": [], "xp": [], "fought": []}
	Run.apply_fight(o2, &"fight")
	assert_true(int(o2["gold"]) >= 0 and int(o2["gold"]) <= int(act.gold["fight"][1]) - 9 + 1)
	var p := Run.piece_price(&"rook")
	Run.add_relic(&"merchants_ledger")
	assert_eq(Run.piece_price(&"rook"), int(round(p * 0.8)))


func test_xp_relics() -> void:
	var k := Run.add_unit(&"knight")
	var pawn: Unit = Run.units.filter(func(u): return u.type == &"pawn")[0]
	assert_eq(Run.capture_xp(k, 3, {}), 3)
	Run.add_relic(&"whetstone")
	assert_eq(Run.capture_xp(k, 3, {}), 4, "Whetstone: knights +1")
	assert_eq(Run.capture_xp(pawn, 3, {}), 3, "not for pawns")
	Run.add_relic(&"creeping_rot")
	assert_eq(Run.capture_xp(pawn, 1, {}), 1, "Rot never takes the last XP")
	assert_eq(Run.capture_xp(k, 3, {}), 3)
	Run.add_relic(&"abbots_censer")
	assert_eq(Run.capture_xp(pawn, 3, Run.fight_mods(&"fight", null)), 5, "3 × 2 − 1")


func test_veil_locket_and_whistle() -> void:
	Run.add_relic(&"mourning_veil")
	Run.add_relic(&"martyrs_locket")
	Run.add_relic(&"drill_whistle")
	var a := Run.add_unit(&"knight")
	var b := Run.add_unit(&"bishop")
	var c := Run.add_unit(&"rook")
	var o := {"state": "win", "slain": [a.id, b.id], "xp": [], "fought": [a.id, b.id, c.id]}
	Run.apply_fight(o, &"fight")
	assert_true(a.is_healthy(), "the Veil saves the first to fall")
	assert_false(b.is_healthy())
	assert_eq(c.xp, 2 + 1, "Locket +2 for one loss, Whistle +1")
	assert_false(bool(o["flawless"]))


func test_command_engine_and_reward_relics() -> void:
	var cap := Run.command_cap()
	Run.add_relic(&"tattered_standard")
	assert_eq(Run.command_cap(), cap + 2)
	var target := Run.enemy_target(&"fight")
	Run.add_relic(&"black_candle")
	assert_almost_eq(Run.enemy_target(&"fight"), target * 1.15, 0.01)
	assert_eq(Run.relic_card_count(2), 3)
	Run.add_relic(&"stockfish_tooth")
	assert_eq(int(Run.fight_mods(&"fight", null)["relic_skill"]), -2)
	assert_false(Run.fight_mods(&"boss", null).has("relic_skill"), "relics never weaken the final boss")
	Run.add_relic(&"bone_dice")
	var offer := Run.reward_offer(&"fight")
	assert_eq(offer["pieces"].size() + (1 if int(offer["train"]) > 0 else 0), Content.config.reward_choices + 1)


func test_kindling_raises_numbers_but_not_drawbacks() -> void:
	var coin: RelicDef = Content.relic(&"pilgrims_coin").kindled()
	assert_eq(coin.gold_flat, 8)
	var censer: RelicDef = Content.relic(&"abbots_censer").kindled()
	assert_almost_eq(censer.xp_mult, 2.5, 0.001)
	assert_eq(censer.clock_bonus_s, -60)
	var tooth: RelicDef = Content.relic(&"stockfish_tooth").kindled()
	assert_eq(tooth.engine_skill_delta, -3)
	Run.add_relic(&"tattered_standard")
	Run.kindled.append(&"tattered_standard")
	assert_eq(Run.command_cap(), Run.current_act().command + 3)


func test_campfire_actions() -> void:
	var a := Run.add_unit(&"knight")
	var b := Run.add_unit(&"rook")
	a.xp = 5
	var gain := Run.rite(a, b)
	assert_eq(gain, 5 + 3, "its XP plus its value")
	assert_null(Run.unit(a.id), "the burned piece is gone")
	assert_eq(Run.rite(Run.king_unit(), b), 0, "the king never burns")
	var xp_before: Array = Run.deployed_units().map(func(u): return u.xp)
	Run.drill()
	for i in Run.deployed_units().size():
		assert_eq(Run.deployed_units()[i].xp, xp_before[i] + Content.config.camp_drill_xp)
	Run.add_relic(&"pilgrims_coin")
	Run.add_relic(&"creeping_rot")
	assert_true(Run.kindle_options().has(&"pilgrims_coin"))
	assert_false(Run.kindle_options().has(&"creeping_rot"), "curses never kindle")
	Run.kindle(&"pilgrims_coin")
	assert_false(Run.kindle_options().has(&"pilgrims_coin"))
	assert_eq(Run.curses(), [&"creeping_rot"])
	Run.remove_relic(&"creeping_rot")
	assert_eq(Run.curses(), [])
	var clock := int(Run.fight_mods(&"guardian", null)["clock_delta_s"])
	Run.study()
	assert_eq(int(Run.fight_mods(&"guardian", null)["clock_delta_s"]), clock + Content.config.camp_study_clock_s)
	assert_eq(int(Run.fight_mods(&"fight", null)["clock_delta_s"]), clock, "Study is for the guardian only")
	Run.advance_act()
	assert_false(Run.studied(), "a new act, a new guardian")


func test_bell_and_crown_in_a_real_fight() -> void:
	Run.add_relic(&"chapel_bell")
	Run.add_relic(&"choir_crown")
	var fight := FightController.new()
	add_child_autofree(fight)
	var enc := EncounterDef.new()
	enc.id = &"t_relics"
	enc.kind = &"fight"
	enc.layout = {"e8": &"king", "d7": &"pawn", "e7": &"pawn"}
	enc.movetime_ms = 20
	enc.skill = 0
	var units := Run.fight_units(&"fight")
	assert_true(await fight.setup(enc, units, Run.relic_defs(), Content.config, Run.formation(units), Run.fight_mods(&"fight", enc)))
	var bell := -1
	for i in range(16, 24):
		if fight.unit_map.unit_at(i) < -1:
			bell = i
	assert_ne(bell, -1, "the Bell's pawn stands on the third rank as a temporary unit")
	assert_eq(fight.board.get(bell, ""), "P")
	assert_true(fight.base_fen.contains(" b "), "the Crown: black to move")
	await fight.begin()
	var guard := 0
	while not fight.is_player_turn() and guard < 300:
		guard += 1
		await get_tree().process_frame
	assert_eq(fight.moves.size(), 1, "the engine opened")


func test_phylactery_gives_one_second_chance() -> void:
	RunFixture.classic(3)
	assert_false(Run.take_second_chance(), "nothing to shatter")
	Run.add_relic(&"lichs_phylactery")
	assert_true(Run.take_second_chance())
	assert_false(Run.has_relic(&"lichs_phylactery"), "it shatters")
	var banner: Array = Run.fight_mods(&"fight", null)["banner"]
	assert_true(banner.any(func(l): return String(l).contains("shatters")))
	assert_false(Run.fight_mods(&"fight", null)["banner"].any(func(l): return String(l).contains("shatters")), "said once")
	assert_false(Run.take_second_chance(), "once per run")
