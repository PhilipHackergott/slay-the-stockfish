extends GutTest
## Variant generator (with throwaway Betza test pieces) and the position-edit validator.


func test_generator_writes_the_fight_plumbing() -> void:
	var gen := VariantGen.build("t_gen_base", "K", [], PackedStringArray(), false)
	var ini: String = gen["ini"]
	for line in ["[t_gen_base:chess]", "king = k", "customPiece1 = w:K", "extinctionPieceTypes = w",
			"extinctionPseudoRoyal = true", "extinctionValue = loss", "castling = false"]:
		assert_string_contains(ini, line)
	assert_false(ini.contains("pieceDrops"))


func test_generator_pocket_and_rule_lines() -> void:
	var gen := VariantGen.build("t_gen_relics", "K", [], PackedStringArray(["promotionRegionWhite = *7 *8"]), true)
	var ini: String = gen["ini"]
	assert_string_contains(ini, "pieceDrops = true")
	assert_string_contains(ini, "capturesToHand = false")
	assert_string_contains(ini, "dropRegionWhite = *1 *2 *3 *4")
	assert_string_contains(ini, "promotionRegionWhite = *7 *8")


func test_generator_assigns_letters_to_any_betza_piece() -> void:
	var custom := [
		{"id": &"test_wazir", "betza": "W"},
		{"id": &"test_camel", "betza": "C"},
		{"id": &"test_wazir", "betza": "W"},
	]
	var gen := VariantGen.build("t_gen_custom", "KN", custom, PackedStringArray(), false)
	assert_eq(gen["letters"].size(), 2)
	assert_string_contains(gen["ini"], "customPiece2 = a:W")
	assert_string_contains(gen["ini"], "customPiece3 = c:C")
	assert_string_contains(gen["ini"], "customPiece1 = w:KN")


func test_generator_enforces_piece_type_budget() -> void:
	var custom: Array = []
	for i in 20:
		custom.append({"id": StringName("t%d" % i), "betza": "W"})
	assert_true(VariantGen.build("t_gen_budget", "K", custom, PackedStringArray(), false).has("error"))


func test_throwaway_betza_piece_moves_in_the_core() -> void:
	var custom := [{"id": &"test_camel", "betza": "C", "ini_extra": PackedStringArray()}]
	var gen := VariantGen.build("t_gen_camel", "K", custom, PackedStringArray(), false)
	var res: Dictionary = await ChessCore.load_variant("t_gen_camel", gen["ini"])
	assert_true(res.get("ok", false), str(res))
	var letter: String = gen["letters"][&"test_camel"]
	var fen := "4k3/8/8/8/3%s4/8/8/4W3 w - - 0 1" % letter.to_upper()
	var legal: PackedStringArray = await ChessCore.legal(fen, PackedStringArray())
	assert_true(legal.has("d4e7"), "camel (1,3) leap")
	assert_true(legal.has("d4a5"), "camel (3,1) leap")
	assert_false(legal.has("d4d5"))


# --- position edits ---------------------------------------------------------------------------

var p7 := PackedInt32Array([7])


func test_swap_flips_side_and_clears_rights() -> void:
	var res := PositionEdit.swap_fen("4k3/8/8/8/8/1N6/3P4/4W3 w KQ e3 4 9", Fen.sq("b3"), Fen.sq("d2"), p7)
	assert_true(res["ok"], str(res))
	if not res["ok"]:
		return
	var st := Fen.parse(res["fen"])
	assert_eq(st["side"], "b")
	assert_eq(st["ep"], "-")
	assert_eq(st["castling"], "-")
	assert_eq(st["board"][Fen.sq("d2")], "N")
	assert_eq(st["board"][Fen.sq("b3")], "P")


func test_swap_pawn_rules() -> void:
	var fen := "R3k3/8/8/8/8/8/1P6/4W3 w - - 0 1"
	assert_false(PositionEdit.swap_fen(fen, Fen.sq("a8"), Fen.sq("b2"), p7)["ok"], "pawn onto the last rank")
	var fen7 := "4k3/R7/8/8/8/8/1P6/4W3 w - - 0 1"
	assert_true(PositionEdit.swap_fen(fen7, Fen.sq("a7"), Fen.sq("b2"), p7)["ok"])
	assert_false(PositionEdit.swap_fen(fen7, Fen.sq("a7"), Fen.sq("b2"), PackedInt32Array([6, 7]))["ok"],
		"with the rule relic the 7th rank promotes")
	var fen1 := "4k3/8/8/8/8/8/1P6/R3W3 w - - 0 1"
	assert_false(PositionEdit.swap_fen(fen1, Fen.sq("a1"), Fen.sq("b2"), p7)["ok"], "pawn onto the first rank")


func test_swap_needs_two_own_pieces() -> void:
	var fen := "4k3/8/8/8/8/8/3p4/1N2W3 w - - 0 1"
	assert_false(PositionEdit.swap_fen(fen, Fen.sq("b1"), Fen.sq("d2"), p7)["ok"])
	assert_false(PositionEdit.swap_fen(fen, Fen.sq("b1"), Fen.sq("b1"), p7)["ok"])


func test_pawn_back_on_start_rank_regains_double_step() -> void:
	await ChessCore.load_variant("t_edit_double", VariantGen.build("t_edit_double", "K", [], PackedStringArray(), false)["ini"])
	var res: Dictionary = await PositionEdit.validate_swap(ChessCore, "4k3/8/8/8/8/2P5/1N6/4W3 w - - 0 1",
		Fen.sq("c3"), Fen.sq("b2"), p7)
	assert_true(res["ok"], str(res))
	var after: PackedStringArray = await ChessCore.legal(res["fen"].replace(" b ", " w "), PackedStringArray())
	assert_true(after.has("b2b4"), "double step from the start rank")


func test_swap_may_not_leave_own_king_in_check() -> void:
	await ChessCore.load_variant("t_edit_check", VariantGen.build("t_edit_check", "K", [], PackedStringArray(), false)["ini"])
	var fen := "r3k3/8/8/N7/8/8/8/4W3 w - - 0 1"
	var res: Dictionary = await PositionEdit.validate_swap(ChessCore, fen, Fen.sq("a5"), Fen.sq("e1"), p7)
	assert_false(res["ok"])
	assert_string_contains(res["reason"], "check")


func test_swap_may_give_check() -> void:
	await ChessCore.load_variant("t_edit_give", VariantGen.build("t_edit_give", "K", [], PackedStringArray(), false)["ini"])
	var fen := "4k3/8/8/8/8/8/8/1R2N2W w - - 0 1"
	var res: Dictionary = await PositionEdit.validate_swap(ChessCore, fen, Fen.sq("b1"), Fen.sq("e1"), p7)
	assert_true(res["ok"], str(res))
	assert_true(await ChessCore.in_check(res["fen"], "b"))
