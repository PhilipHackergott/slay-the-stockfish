extends GutTest
## Promotion trees, rewards, gold and the shop, acts, difficulty, save/load, and the profile.

const ROOTS := [&"pawn", &"knight", &"bishop", &"rook", &"queen", &"king"]


func before_all() -> void:
	Profile.path = "user://profile_test.json"
	Run.save_path = "user://run_test.json"


func before_each() -> void:
	Profile.reset()


func after_all() -> void:
	Run.delete_save()


# --- trees --------------------------------------------------------------------------------------

func test_every_upgrade_exists_and_trees_have_no_cycles() -> void:
	for p in Content.pieces.values():
		for c in p.upgrades:
			assert_not_null(Content.piece(c), "%s -> %s exists" % [p.id, c])
		assert_true(p.is_royal() or p.value > 0, "%s has a value" % p.id)
		assert_eq(p.model, "res://models/pieces/%s.glb" % p.id)
		assert_ne(p.moves_text, "", "%s explains its moves" % p.id)
		assert_true(p.is_standard() or p.betza != "" or p.is_royal(), "%s has a letter or Betza" % p.id)
	for root in Content.pieces.keys():
		var seen := {}
		var stack: Array = [[root, [root]]]
		while not stack.is_empty():
			var top: Array = stack.pop_back()
			for c in Content.piece(top[0]).upgrades:
				assert_false(Array(top[1]).has(c), "cycle through %s from %s" % [c, root])
				if not seen.has(c) and not Array(top[1]).has(c):
					seen[c] = true
					stack.append([c, Array(top[1]) + [c]])


func test_every_piece_is_reachable_or_a_reward() -> void:
	var reach := {}
	var todo: Array = ROOTS.duplicate()
	todo.append_array(Content.pieces.values().filter(func(p): return p.rarity != &"").map(func(p): return p.id))
	while not todo.is_empty():
		var id: StringName = todo.pop_back()
		if reach.has(id):
			continue
		reach[id] = true
		todo.append_array(Array(Content.piece(id).upgrades))
	for p in Content.pieces.values():
		assert_true(reach.has(p.id), "%s is reachable from a root or a reward" % p.id)


func test_king_tree_stays_royal() -> void:
	for id in [&"king", &"warlord", &"conqueror", &"regent"]:
		var d: PieceDef = Content.piece(id)
		assert_not_null(d, String(id))
		assert_true(d.is_royal(), "%s is royal" % id)
	assert_true(Content.piece(&"regent").twin_king)


func test_custom_letters_are_unique_and_never_standard() -> void:
	var ids: Array = Content.pieces.values().filter(func(p): return not p.is_standard() and not p.is_royal()).map(func(p): return p.id)
	var letters := VariantGen.assign_letters(ids.slice(0, 19))
	var used := {}
	for id in letters:
		var l: String = letters[id]
		assert_false("bknpqrw".contains(l), "%s got a reserved letter %s" % [id, l])
		assert_false(used.has(l), "letter %s used twice" % l)
		used[l] = true


func test_a_large_fairy_army_loads_in_the_engine() -> void:
	var custom: Array = []
	for p in Content.pieces.values():
		if not p.is_standard() and not p.is_royal() and custom.size() < 12:
			custom.append({"id": p.id, "betza": p.betza, "pawn_like": p.pawn_like, "ini_extra": p.ini_extra})
	var gen := VariantGen.build("t_big_fairy", "K", custom, PackedStringArray(), true)
	assert_false(gen.has("error"))
	var res: Dictionary = await ChessCore.load_variant("t_big_fairy", gen["ini"])
	assert_true(res.get("ok", false), str(res))


# --- xp, gold, rewards --------------------------------------------------------------------------

func test_level_ups_offer_every_child_and_maxed_xp_turns_into_gold() -> void:
	Run.new_run(3)
	var pawn: Unit = Run.units.filter(func(u): return u.type == &"pawn")[0]
	pawn.xp = 3
	assert_true(Run.can_level_up(pawn))
	assert_eq(Run.upgrade_options(pawn), Array(Content.piece(&"pawn").upgrades))
	var maxed := Run.add_unit(&"amazon")
	assert_false(Run.is_maxed(maxed), "a final form still has perks to take")
	while Run.perk_option(maxed) != &"":
		Run.take_perk(maxed, Run.perk_option(maxed))
	assert_eq(maxed.perks.size(), Content.config.max_perks)
	assert_true(Run.is_maxed(maxed))
	var gold_before := Run.gold
	var o := {"state": "win", "slain": [], "xp": [{"unit": maxed.id, "amount": 5, "captured": "r"}]}
	Run.apply_fight(o, &"fight")
	assert_eq(int(o["overflow_gold"]), 5 * Content.config.overflow_gold_per_xp)
	assert_gt(int(o["gold"]), 0, "a win pays gold")
	assert_eq(Run.gold, gold_before + int(o["gold"]) + int(o["overflow_gold"]) + int(o["bounty_gold"]))


func test_rewards_are_one_tier_distinct_and_respect_unlocks() -> void:
	Run.new_run(17)
	var trains := 0
	for act in 3:
		Run.act_index = act
		var tiers: Dictionary = Run.current_act().reward_tiers
		for kind in [&"fight", &"elite", &"guardian"]:
			if not tiers.has(String(kind)):
				continue
			for i in 20:
				var offer := Run.reward_offer(kind)
				var r: Array = offer["pieces"]
				assert_true(Array(tiers[String(kind)]).has(offer["tier"]), "act %d %s rolls its own tiers" % [act + 1, kind])
				assert_eq(r.size() + (1 if int(offer["train"]) > 0 else 0), Content.config.reward_choices)
				trains += 1 if int(offer["train"]) > 0 else 0
				var uniq := {}
				for id in r:
					uniq[id] = true
					var d: PieceDef = Content.piece(id)
					assert_true(Run.is_unlocked(d.unlock), "%s is unlocked" % id)
					assert_eq(d.tier, int(offer["tier"]), "%s is tier %d" % [id, offer["tier"]])
					assert_ne(d.rarity, &"legendary", "legends come only from Ascension")
				assert_eq(uniq.size(), r.size())
	assert_gt(trains, 0, "a Train slot shows up sometimes")


func test_locked_relics_are_not_offered_until_unlocked() -> void:
	Run.new_run(5)
	for i in 20:
		assert_false(Run.relic_choices(40, "shop").has(&"puppeteers_string"))
	Profile.unlock(&"runs_2")
	assert_false(Run.relic_choices(40, "shop").has(&"puppeteers_string"), "unlocks apply from the next run on")
	Run.new_run(6)
	assert_true(Run.relic_choices(40, "shop").has(&"puppeteers_string"))


# --- shop ---------------------------------------------------------------------------------------

func test_shop_sells_once_and_charges_gold() -> void:
	Run.new_run(8)
	Run.add_gold(1000)
	var stock := Run.shop(99)
	assert_eq(stock["pieces"].size(), Content.config.shop_pieces)
	assert_eq(Run.shop(99), stock, "the stock is rolled once")
	var n := Run.units.size()
	var price := int(stock["pieces"][0]["price"])
	var gold := Run.gold
	assert_not_null(Run.buy(99, "pieces", 0))
	assert_eq(Run.units.size(), n + 1)
	assert_eq(Run.gold, gold - price)
	assert_null(Run.buy(99, "pieces", 0), "sold out")
	var u: Unit = Run.units[1]
	u.state = &"slain"
	assert_true(Run.buy_restore(u))
	assert_true(u.is_healthy())


func test_shop_refuses_when_poor() -> void:
	Run.new_run(8)
	Run.gold = 0
	assert_null(Run.buy(5, "pieces", 0))


# --- acts and difficulty ------------------------------------------------------------------------

func test_three_acts_end_in_guardians_then_the_boss() -> void:
	Run.new_run(21)
	assert_eq(Run.act_count(), 3)
	for i in 3:
		var last: Dictionary = Run.map.nodes.filter(func(n): return n["row"] == Run.map.rows - 1)[0]
		assert_eq(last["type"], &"boss" if i == 2 else &"guardian", "act %d ends right" % (i + 1))
		assert_eq(last["encounter"], Run.current_act().final_encounter)
		assert_true(Run.map.nodes.any(func(n): return n["type"] == &"shop"), "act %d has a shop" % (i + 1))
		assert_eq(Run.is_final_act(), i == 2)
		if i < 2:
			Run.advance_act()
	assert_eq(Run.act_index, 2)


func test_difficulty_tiers_stack() -> void:
	Run.new_run(4, 0)
	var base := Run.units.size()
	Run.new_run(4, 5)
	var m := Run.difficulty_mods()
	assert_eq(int(m["skill_bonus"]), 2)
	assert_eq(int(m["clock_delta_s"]), -60)
	assert_eq(Run.units.size(), base - 1, "damned removes a pawn")
	assert_gt(float(m["price_mult"]), 1.0)
	assert_gt(float(m["movetime_mult"]), 1.0)


# --- formation ----------------------------------------------------------------------------------

func test_formation_editor_prefs_are_kept_and_pawns_stay_off_rank_one() -> void:
	Run.new_run(2)
	var king := Run.king_unit()
	var pawn: Unit = Run.units.filter(func(u): return u.type == &"pawn")[0]
	assert_false(Run.formation_square_ok(pawn, Fen.sq("a1")))
	Run.set_formation({Fen.sq("d1"): king.id, Fen.sq("a2"): pawn.id})
	var f := Run.formation(Run.healthy_units())
	assert_eq(f[Fen.sq("d1")], king.id)
	assert_eq(f[Fen.sq("a2")], pawn.id)
	assert_eq(f.size(), Run.healthy_units().size())


# --- save and load ------------------------------------------------------------------------------

func test_save_and_load_round_trip() -> void:
	Run.new_run(77, 2)
	Run.add_relic(&"soul_exchange")
	Run.add_gold(55)
	Run.units[3].xp = 2
	Run.level_up(Run.units[2], &"spearman")
	var first: int = Run.available_nodes()[0]
	Run.enter_node(first)
	Run.shop(first)
	Run.set_formation({Fen.sq("e1"): Run.king_unit().id})
	Run.save_game()
	var before := JSON.stringify(Run.to_save())
	var next_roll := Run.rng.randi()
	Run.new_run(1)
	assert_true(Run.load_game())
	assert_eq(JSON.stringify(Run.to_save()), before)
	assert_eq(Run.rng.randi(), next_roll, "the rng continues where it was saved")
	assert_eq(Run.unit(Run.units[2].id).lineage, PackedStringArray(["pawn", "spearman"]))
	Run.delete_save()
	assert_false(Run.has_save())


# --- profile ------------------------------------------------------------------------------------

func test_profile_unlocks_on_run_end() -> void:
	var got := Profile.record_run_end(true, 0, 3, Run.top_difficulty())
	assert_true(got.has(&"runs_1"))
	assert_true(got.has(&"win"))
	assert_true(got.has(&"difficulty_1"))
	assert_eq(Profile.max_difficulty(), 1)
	assert_true(Profile.is_unlocked(&"win"))
	assert_string_contains(Profile.unlock_text("win"), "Nightmare")
	var g := Profile.record_guardian(1)
	assert_true(g.has(&"guardian_1"))
