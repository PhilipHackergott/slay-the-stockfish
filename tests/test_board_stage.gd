extends GutTest
## The board editor: draft buys drop onto the board and can be returned; moves are kept.

var _bv: BoardView


func before_each() -> void:
	_bv = BoardView.new()
	add_child_autofree(_bv)


func _show_army() -> void:
	var dp := Run.display_position()
	_bv.setup_position(dp["board"], dp["units"], false)


func test_muster_buys_onto_the_board_and_returns() -> void:
	Run.new_run(7, 0)
	_show_army()
	assert_eq(_bv.pieces.size(), 1, "the king stands alone")
	var s := BoardStage.new().setup(_bv, true)
	add_child_autofree(s)
	await s._buy(&"knight")
	assert_eq(Run.draft_points(), Content.config.draft_budget - 3)
	var k: Unit = Run.units.filter(func(u): return u.type == &"knight")[0]
	var sq: int = s._square_of(k.id)
	assert_between(sq, 0, 15)
	assert_eq(_bv.piece_at(sq).unit_id, k.id, "the knight stands where the formation puts it")
	await s._refund(k)
	assert_eq(Run.draft_points(), Content.config.draft_budget)
	assert_eq(_bv.pieces.size(), 1)
	var gold := Run.gold
	s._finish()
	assert_false(Run.draft_open())
	assert_eq(Run.gold, gold + Content.config.draft_budget * Content.config.draft_leftover_gold)


func test_moves_on_the_board_are_kept() -> void:
	RunFixture.classic(7)
	_show_army()
	var s := BoardStage.new().setup(_bv)
	add_child_autofree(s)
	var arr: Dictionary = s._arrangement()
	var from := -1
	for sq in arr:
		if not Run.is_pawn_like(Run.unit(int(arr[sq]))) and int(sq) < 8:
			from = int(sq)
	var to := -1
	for t in range(8, 16):
		if not arr.has(t):
			to = t
			break
	assert_true(from >= 0 and to >= 0)
	var id := int(arr[from])
	s._on_square(from)
	await s._on_square(to)
	assert_eq(int(Run.formation_prefs.get(id, -1)), to)
	assert_eq(_bv.piece_at(to).unit_id, id)
	assert_null(_bv.piece_at(from))
