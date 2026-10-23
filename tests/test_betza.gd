extends GutTest
## Move diagrams read Betza: the squares match what the pieces can do.


func _kinds(sq: Dictionary) -> Dictionary:
	var out := {"move": 0, "capture": 0, "both": 0, "hop": 0, "initial": 0}
	for k in sq:
		var e: Dictionary = sq[k]
		if e.get("initial", false):
			out["initial"] += 1
		elif e.get("hop", false):
			out["hop"] += 1
		elif e.get("move", false) and e.get("capture", false):
			out["both"] += 1
		elif e.get("move", false):
			out["move"] += 1
		else:
			out["capture"] += 1
	return out


func test_standard_pieces() -> void:
	assert_eq(Betza.squares("N").size(), 8)
	assert_eq(Betza.squares("R", 3).size(), 12)
	assert_eq(Betza.squares("B", 3).size(), 12)
	assert_eq(Betza.squares("Q", 3).size(), 24)
	assert_eq(Betza.squares("K").size(), 8)
	var p := _kinds(Betza.squares(Betza.STANDARD["p"]))
	assert_eq(p["move"], 1, "a pawn steps forward")
	assert_eq(p["capture"], 2, "and takes diagonally forward")
	assert_eq(p["initial"], 1, "with a first double step")
	assert_true(Betza.squares(Betza.STANDARD["p"]).has(Vector2i(0, 1)))


func test_cannon_hops_to_capture() -> void:
	var def: PieceDef = Content.piece(&"cannon")
	var k := _kinds(Betza.squares(def.betza))
	assert_gt(k["hop"], 0)


func test_every_piece_has_a_diagram() -> void:
	for id in Content.pieces:
		assert_gt(Betza.squares(Betza.of(id)).size(), 0, "%s has squares (%s)" % [id, Betza.of(id)])
		var d := MoveDiagram.make(id)
		assert_not_null(d)
		d.free()
