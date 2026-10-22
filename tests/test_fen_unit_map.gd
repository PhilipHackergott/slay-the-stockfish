extends GutTest
## FEN helpers and unit tracking through captures, promotion, en passant, drops and swaps.


func test_fen_roundtrip_with_pocket_and_custom_king() -> void:
	var fen := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQWBNR[B] w - - 0 1"
	var st := Fen.parse(fen)
	assert_eq(st["pocket"], "B")
	assert_eq(st["board"][Fen.sq("e1")], "W")
	assert_eq(Fen.serialize(st), fen)


func test_fen_ignores_promoted_marker() -> void:
	var st := Fen.parse("4k3/8/8/8/8/8/8/Q~3W3[] b - - 0 1")
	assert_eq(st["board"][Fen.sq("a1")], "Q")
	assert_eq(st["board"][Fen.sq("e1")], "W")
	assert_true(Fen.has_pocket("4k3/8/8/8/8/8/8/4W3[] b - - 0 1"))


func test_square_names() -> void:
	assert_eq(Fen.sq("a1"), 0)
	assert_eq(Fen.sq("h8"), 63)
	assert_eq(Fen.sq_name(Fen.sq("e4")), "e4")


func _board(fen: String) -> Dictionary:
	return Fen.parse(fen)["board"]


func test_white_capture_moves_unit_and_reports_victim() -> void:
	var m := UnitMap.new()
	m.place(Fen.sq("e4"), 7)
	var ev := m.apply_move("e4d5", _board("4k3/8/8/3p4/4P3/8/8/4W3 w - - 0 1"), "w")
	assert_eq(ev["captured"], "p")
	assert_eq(ev["mover_unit"], 7)
	assert_eq(m.unit_at(Fen.sq("d5")), 7)
	assert_eq(m.unit_at(Fen.sq("e4")), -1)


func test_black_capture_kills_unit() -> void:
	var m := UnitMap.new()
	m.place(Fen.sq("e4"), 3)
	var ev := m.apply_move("d5e4", _board("4k3/8/8/3p4/4P3/8/8/4W3 b - - 0 1"), "b")
	assert_eq(ev["captured_unit"], 3)
	assert_eq(m.square_of(3), -1)


func test_en_passant_both_ways() -> void:
	var m := UnitMap.new()
	m.place(Fen.sq("e5"), 4)
	var ev := m.apply_move("e5d6", _board("4k3/8/8/3pP3/8/8/8/4W3 w - d6 0 1"), "w")
	assert_eq(ev["captured_sq"], Fen.sq("d5"))
	assert_eq(ev["captured"], "p")
	assert_eq(m.unit_at(Fen.sq("d6")), 4)
	var m2 := UnitMap.new()
	m2.place(Fen.sq("e4"), 9)
	var ev2 := m2.apply_move("d4e3", _board("4k3/8/8/8/3pP3/8/8/4W3 b - e3 0 1"), "b")
	assert_eq(ev2["captured_unit"], 9)


func test_promotion_keeps_unit() -> void:
	var m := UnitMap.new()
	m.place(Fen.sq("e7"), 5)
	var ev := m.apply_move("e7e8q", _board("k7/4P3/8/8/8/8/8/4W3 w - - 0 1"), "w")
	assert_eq(ev["promotion"], "Q")
	assert_eq(m.unit_at(Fen.sq("e8")), 5)


func test_drop_event() -> void:
	var m := UnitMap.new()
	var ev := m.apply_move("B@e3", _board("4k3/8/8/8/8/8/8/4W3[B] w - - 0 1"), "w")
	assert_eq(ev["drop"], "B")
	assert_eq(ev["to"], Fen.sq("e3"))
	assert_eq(ev["captured"], "")


func test_swap() -> void:
	var m := UnitMap.new()
	m.place(1, 10)
	m.place(2, 11)
	m.swap(1, 2)
	assert_eq(m.unit_at(1), 11)
	assert_eq(m.unit_at(2), 10)
