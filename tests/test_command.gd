extends GutTest
## Command: deployed pieces cost their value, the rest waits on the bench; perks and Ascension.


func before_each() -> void:
	Run.new_run(9)


func test_the_starting_army_fits_and_extra_recruits_wait_on_the_bench() -> void:
	assert_eq(Run.command_cap(), Run.current_act().command)
	assert_true(Run.command_used() <= Run.command_cap())
	assert_eq(Run.benched_units().size(), 0)
	var added: Array = []
	for i in 6:
		added.append(Run.add_unit(&"rook"))
	assert_true(Run.command_used() <= Run.command_cap())
	assert_true(added.any(func(u): return u.is_benched()), "rooks past the cap sit on the bench")
	assert_eq(Run.fight_units(&"fight").size(), Run.deployed_units().size())


func test_a_promotion_over_the_cap_benches_the_cheapest_piece() -> void:
	while Run.command_used() + 1 <= Run.command_cap():
		Run.add_unit(&"pawn")
	var pawn: Unit = Run.deployed_units().filter(func(u): return u.type == &"pawn")[0]
	pawn.xp = Run.xp_needed(pawn)
	Run.level_up(pawn, &"knight")
	assert_true(Run.command_used() <= Run.command_cap())
	assert_false(pawn.is_benched(), "the promoted piece stays; a cheaper one steps out")
	assert_gt(Run.benched_units().size(), 0)


func test_auto_bench_refills_but_a_held_piece_stays_out() -> void:
	while Run.command_used() + 3 <= Run.command_cap():
		Run.add_unit(&"knight")
	var extra := Run.add_unit(&"knight")
	assert_true(extra.is_benched())
	var held: Unit = Run.deployed_units().filter(func(u): return u.type == &"knight")[0]
	assert_true(Run.set_benched(held, true))
	assert_false(Run.set_benched(Run.king_unit(), true), "the king always fights")
	Run.autofill()
	assert_false(extra.is_benched(), "the auto-benched knight steps up into the freed Command")
	assert_true(held.is_benched(), "a piece the player benched stays benched")
	assert_eq(held.post, &"held")


func test_the_final_guardian_fight_takes_everyone() -> void:
	for i in 6:
		Run.add_unit(&"rook")
	Run.act_index = Content.acts.size() - 1
	assert_true(Run.current_act().final_uncapped)
	assert_eq(Run.fight_units(&"boss").size(), Run.healthy_units().size())
	assert_lt(Run.fight_units(&"fight").size(), Run.healthy_units().size())


func test_vanguard_and_veteran_and_bulwark_and_bounty() -> void:
	var k := Run.add_unit(&"knight")
	k.perks = PackedStringArray(["vanguard"])
	assert_eq(Run.command_cost(k), 2)
	k.perks = PackedStringArray(["veteran"])
	assert_eq(Run.capture_xp(k, 3, {}), 5, "3 XP × 1.5, rounded up")
	k.perks = PackedStringArray(["bulwark", "bounty"])
	var gold := Run.gold
	var o := {"state": "win", "slain": [k.id], "xp": [{"unit": k.id, "amount": 1, "captured": "p"}], "fought": [k.id]}
	Run.apply_fight(o, &"fight")
	assert_true(k.is_healthy(), "Bulwark survives a won fight")
	assert_eq(int(o["bounty_gold"]), 5)
	assert_eq(Run.gold, gold + int(o["gold"]) + 5)
	assert_eq(k.fights, 1)


func test_perk_offers_are_steady_and_capped() -> void:
	var u := Run.add_unit(&"amazon")
	var first := Run.perk_option(u)
	assert_ne(first, &"")
	assert_eq(Run.perk_option(u), first, "the same unit and level always offer the same perk")
	assert_eq(Run.perk_option(Run.king_unit()), &"", "royals take no perks")
	Run.take_perk(u, first)
	Run.take_perk(u, Run.perk_option(u))
	assert_eq(u.perks.size(), Content.config.max_perks)
	assert_eq(Run.perk_option(u), &"")


func test_queens_ascend_into_legends() -> void:
	var q := Run.add_unit(&"queen")
	var opts := Run.ascension_options(q)
	assert_false(opts.is_empty())
	for id in opts:
		assert_eq(Content.piece(id).rarity, &"legendary")
		assert_true(Run.is_unlocked(Content.piece(id).unlock))
	Run.ascend(q, opts[0])
	assert_eq(q.type, opts[0])
	assert_eq(Run.ascension_options(q), [])


func test_command_survives_save_and_load() -> void:
	var u := Run.add_unit(&"rook")
	Run.set_benched(u, true)
	u.perks = PackedStringArray(["vanguard"])
	var data := Run.to_save()
	Run.new_run(1)
	Run.from_save(data)
	var back := Run.unit(u.id)
	assert_eq(back.post, &"held")
	assert_eq(back.perks, PackedStringArray(["vanguard"]))
