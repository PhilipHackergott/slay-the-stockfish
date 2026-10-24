extends GutTest
## Fairy rules in real fights: custom pawns promote, the Regent's twin, the new rule relics
## (pass, sanctuary flag), and the move and lift edits.


func before_all() -> void:
	Profile.path = "user://profile_test.json"
	Profile.reset()


func _enc(layout: Dictionary) -> EncounterDef:
	var e := EncounterDef.new()
	e.id = &"t_fairy"
	e.layout = layout
	e.movetime_ms = 20
	e.skill = 0
	return e


func _fight(units: Array, relics: Array, layout: Dictionary, formation: Dictionary) -> FightController:
	var f := FightController.new()
	add_child_autofree(f)
	assert_true(await f.setup(_enc(layout), units, relics, Content.config, formation))
	return f


func test_custom_pawn_promotes_on_the_last_rank() -> void:
	RunFixture.classic(1)
	var king := Run.king_unit()
	var sb := Run.add_unit(&"shieldbearer")
	var f := await _fight([king, sb], [], {"a8": &"king"}, {Fen.sq("e1"): king.id, Fen.sq("e7"): sb.id})
	await f.begin()
	var l: String = f.letters[&"shieldbearer"]
	assert_eq(String(f.board[Fen.sq("e7")]), l.to_upper())
	var promos := Array(f.legal).filter(func(m): return m.begins_with("e7e8") and m.length() == 5)
	assert_gt(promos.size(), 0, "shieldbearer promotes: %s" % [f.legal])


func test_regent_brings_a_twin_king() -> void:
	RunFixture.classic(1)
	var king := Run.king_unit()
	king.type = &"regent"
	var f := await _fight([king], [], {"e8": &"king"}, {Fen.sq("e1"): king.id})
	var ws := f.board.values().filter(func(x): return x == VariantGen.PLAYER_KING.to_upper())
	assert_eq(ws.size(), 2, "two royal pieces: %s" % [f.board])


func test_held_breath_lets_you_pass() -> void:
	RunFixture.classic(1)
	var king := Run.king_unit()
	var f := await _fight([king], [Content.relic(&"held_breath")], {"a8": &"king", "h7": &"pawn"}, {Fen.sq("e1"): king.id})
	await f.begin()
	assert_true(f.can_pass)
	var mv := f.pass_move()
	assert_eq(mv, "e1e1")
	assert_true(await f.try_player_move(mv))
	assert_eq(f.ply_count >= 1, true)


func test_sanctuary_banner_wins_on_the_last_rank() -> void:
	var r: RelicDef = Content.relic(&"sanctuary_banner")
	var gen := VariantGen.build("t_flag", "K", [], r.ini_lines, false)
	assert_true((await ChessCore.load_variant("t_flag", gen["ini"])).get("ok", false))
	var res: Dictionary = await ChessCore.result("k7/8/8/8/8/8/4W3/8 w - - 0 1", PackedStringArray())
	assert_ne(res.get("state", ""), "win", "not yet")
	res = await ChessCore.result("k7/4W3/8/8/8/8/8/8 w - - 0 1", PackedStringArray(["e7e8"]))
	assert_eq(res.get("state", ""), "win", "the king reached the sanctuary: %s" % res)


func test_mercy_denied_makes_stalemate_lose() -> void:
	var r: RelicDef = Content.relic(&"mercy_denied")
	var gen := VariantGen.build("t_stale", "K", [], r.ini_lines, false)
	assert_true((await ChessCore.load_variant("t_stale", gen["ini"])).get("ok", false))
	# Black to move, stalemated in the corner.
	var res: Dictionary = await ChessCore.result("k7/2Q5/1W6/8/8/8/8/8 b - - 0 1", PackedStringArray())
	assert_eq(res.get("state", ""), "win", "the stalemated engine loses: %s" % res)


func test_puppeteers_string_moves_a_piece_to_an_empty_square() -> void:
	RunFixture.classic(1)
	var king := Run.king_unit()
	var n: Unit = Run.units.filter(func(u): return u.type == &"knight")[0]
	var f := await _fight([king, n], [Content.relic(&"puppeteers_string")], {"e8": &"king"},
		{Fen.sq("e1"): king.id, Fen.sq("b1"): n.id})
	await f.begin()
	assert_true(f.can_edit_move())
	var bad: Dictionary = await f.try_edit_move(Fen.sq("e1"), Fen.sq("e2"))
	assert_false(bad.get("ok", true), "the king cannot be pulled")
	var res: Dictionary = await f.try_edit_move(Fen.sq("b1"), Fen.sq("d3"))
	assert_true(res.get("ok", false), str(res))
	assert_eq(f.unit_map.unit_at(Fen.sq("d3")), n.id, "the unit moved with its piece")


func test_soul_lantern_lifts_into_the_pocket_and_drops_back() -> void:
	RunFixture.classic(1)
	var king := Run.king_unit()
	var b: Unit = Run.units.filter(func(u): return u.type == &"bishop")[0]
	var f := await _fight([king, b], [Content.relic(&"soul_lantern")], {"e8": &"king"},
		{Fen.sq("e1"): king.id, Fen.sq("c1"): b.id})
	await f.begin()
	var res: Dictionary = await f.try_lift(Fen.sq("c1"))
	assert_true(res.get("ok", false), str(res))
	assert_false(f.board.has(Fen.sq("c1")))
	assert_string_contains(f.pocket, "B")
	assert_true(f.is_player_turn(), "lifting is a free action")
	var drops := Array(f.legal).filter(func(m): return m.begins_with("B@"))
	assert_gt(drops.size(), 0)
	assert_true(await f.try_player_move(drops[0]))
	assert_eq(f.unit_map.unit_at(Fen.sq(drops[0].substr(2, 2))), b.id, "the dropped bishop is the same unit")
