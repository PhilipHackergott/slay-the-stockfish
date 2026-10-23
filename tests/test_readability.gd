extends GutTest
## Pieces name themselves: fairy pieces by default, all on demand, none when switched off.


func _view(id: StringName, white: bool) -> PieceView:
	var d: PieceDef = Content.piece(id)
	var v := PieceView.new()
	add_child_autofree(v)
	v.setup(d.letter.to_upper() if white else d.letter.to_lower())
	return v


func _plate(v: PieceView) -> Label3D:
	for c in v.get_children():
		if c is Label3D and c.visible:
			return c
	return null


func test_fairy_mode_names_only_special_pieces() -> void:
	var horse := _view(&"dragon_horse", false)
	var pawn := _view(&"pawn", false)
	horse.set_nameplate("fairy")
	pawn.set_nameplate("fairy")
	assert_not_null(_plate(horse))
	assert_true(horse.is_special())
	assert_eq(_plate(horse).text, horse.def.display_name)
	assert_null(_plate(pawn))


func test_all_and_off_modes() -> void:
	var pawn := _view(&"pawn", true)
	pawn.set_nameplate("all")
	assert_not_null(_plate(pawn))
	pawn.set_nameplate("off")
	assert_null(_plate(pawn))


func test_neighbouring_plates_sit_at_different_heights() -> void:
	var a := _view(&"dragon_horse", false)
	var b := _view(&"dragon_king", false)
	a.position = BoardView.sq_pos(Fen.sq("b8"))
	b.position = BoardView.sq_pos(Fen.sq("c8"))
	a.set_nameplate("fairy")
	b.set_nameplate("fairy")
	assert_ne(_plate(a).position.y - a.height(), _plate(b).position.y - b.height())
