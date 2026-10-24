extends GutTest
## One test per MVP relic, through a real fight setup and the real engine.

var fight: FightController


func before_each() -> void:
	RunFixture.classic(11)
	fight = FightController.new()
	add_child_autofree(fight)


func _setup(relic_ids: Array, encounter_id: StringName = &"rabble") -> bool:
	var relics: Array = relic_ids.map(func(id): return Content.relic(id))
	var units := Run.healthy_units()
	return await fight.setup(Content.encounter(encounter_id), units, relics, Content.config, Run.formation(units))


func _engine_score(variant: String, ini: String, fen: String) -> int:
	await ChessCore.load_variant(variant, ini)
	var res: Dictionary = await ChessCore.engine_move(fen, PackedStringArray(), 0, 20, 8)
	if res.get("mate") != null:
		return 30000 if int(res["mate"]) > 0 else -30000
	return int(res.get("score_cp", 0))


func test_rule_relic_goes_into_the_variant_and_the_engine_search() -> void:
	assert_true(await _setup([&"ascendant_pawns"]))
	assert_string_contains(fight.variant_ini, "promotionRegionWhite = *7 *8")
	assert_true(fight.promo_ranks.has(6))
	# a pawn on the 6th now promotes on the 7th
	var legal: PackedStringArray = await ChessCore.legal("4k3/8/P7/8/8/8/8/4W3 w - - 0 1", PackedStringArray())
	assert_true(legal.has("a6a7q"))
	# the engine sees it: without the relic black's king catches the c-pawn (Ke7, c7 Kd7, c8 Kxc8);
	# with it the pawn queens on c7 out of reach
	var fen := "8/8/2P2k2/8/8/8/8/4W3 b - - 0 1"
	var plain: String = VariantGen.build("t_rule_off", "K", [], PackedStringArray(), false)["ini"]
	var ruled: String = VariantGen.build("t_rule_on", "K", [], PackedStringArray(["promotionRegionWhite = *7 *8"]), false)["ini"]
	var without: int = await _engine_score("t_rule_off", plain, fen)
	var with_relic: int = await _engine_score("t_rule_on", ruled, fen)
	assert_lt(with_relic, without - 300, "engine eval drops when it knows about the relic (%d vs %d)" % [with_relic, without])


func test_pocket_relic_goes_into_fen_variant_and_engine_search() -> void:
	assert_true(await _setup([&"reliquary_bishop"]))
	assert_string_contains(fight.base_fen, "[B]")
	assert_string_contains(fight.variant_ini, "pieceDrops = true")
	await fight.begin()
	assert_gt(fight.legal_drops("B").size(), 0)
	assert_true(Array(fight.legal_drops("B")).all(func(m): return "1234".contains(m.substr(3, 1))))
	var ini: String = VariantGen.build("t_pocket_on", "K", [], PackedStringArray(), true)["ini"]
	var fen := "4k3/pppppppp/8/8/8/8/PPPPPPPP/4W3%s b - - 0 1"
	var without: int = await _engine_score("t_pocket_on", ini, fen % "[]")
	var with_pocket: int = await _engine_score("t_pocket_on", ini, fen % "[B]")
	assert_lt(with_pocket, without - 150, "engine counts the bishop in your pocket (%d vs %d)" % [with_pocket, without])


func test_edit_relic_swaps_instead_of_moving() -> void:
	assert_true(await _setup([&"soul_exchange"]))
	await fight.begin()
	assert_eq(fight.edit_charges, 1)
	var knight_sq := fight.unit_map.square_of(_unit_of_type(&"knight").id)
	var bishop_sq := fight.unit_map.square_of(_unit_of_type(&"bishop").id)
	var res: Dictionary = await fight.try_swap(knight_sq, bishop_sq)
	assert_true(res["ok"], str(res))
	assert_eq(fight.edit_charges, 0)
	assert_eq(fight.unit_map.unit_at(knight_sq), _unit_of_type(&"bishop").id)
	# the engine has answered and it is the player's turn again
	assert_eq(fight.turn, "w")
	assert_eq(fight.moves.size(), 1)
	var again: Dictionary = await fight.try_swap(knight_sq, bishop_sq)
	assert_false(again["ok"])


func test_clock_relic_adds_base_time() -> void:
	assert_true(await _setup([&"bone_hourglass"]))
	assert_almost_eq(fight.player_ms, 360000.0, 1.0)
	var plain := FightController.new()
	add_child_autofree(plain)
	var units := Run.healthy_units()
	assert_true(await plain.setup(Content.encounter(&"rabble"), units, [], Content.config, Run.formation(units)))
	assert_almost_eq(plain.player_ms, 300000.0, 1.0)


func _unit_of_type(t: StringName) -> Unit:
	for u in Run.units:
		if u.type == t:
			return u
	return null
