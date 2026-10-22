class_name FormationModal
extends Control
## Arrange the army on ranks 1-2: click a piece, then a square (swaps). Pawns may not stand on
## rank 1. Pieces left in reserve stand wherever there is room (rank 3 when the ranks are full).

signal saved

const CELL := 104

var _arr: Dictionary = {}
var _reserve: Array = []
var _sel := -1
var _sel_reserve := -1
var _grid: GridContainer
var _reserve_row: HFlowContainer
var _hint: Label
var _modal: UiModal


static func open_formation(parent: Node) -> FormationModal:
	var f := FormationModal.new()
	parent.add_child(f)
	return f


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal = UiModal.new().setup("Battle Formation", 1080, true, "Click a piece, then a square. Every fight opens with this arrangement.")
	add_child(_modal)
	_modal.closed.connect(queue_free)
	var hs := Run.healthy_units()
	var f := Run.formation(hs)
	for sq in f:
		if int(sq) < 16:
			_arr[int(sq)] = int(f[sq])
	for u in hs:
		if not _arr.values().has(u.id):
			_reserve.append(u.id)
	_grid = GridContainer.new()
	_grid.columns = 9
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_modal.body.add_child(UiKit.centered(_grid))
	_modal.body.add_child(UiKit.caption("Reserve", 18, UiKit.MUTED))
	_reserve_row = HFlowContainer.new()
	_reserve_row.add_theme_constant_override("h_separation", 8)
	_modal.body.add_child(_reserve_row)
	_hint = UiKit.label("", 18, UiKit.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal.body.add_child(_hint)
	_modal.footer.add_child(UiKit.button("Default", func():
		Run.formation_prefs.clear()
		_modal.close()
		saved.emit(), 20))
	_modal.footer.add_child(UiKit.button("Keep this formation", func():
		Run.set_formation(_arr)
		_modal.close()
		saved.emit(), 22, true))
	_rebuild()


func _rebuild() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for c in _reserve_row.get_children():
		c.queue_free()
	for rank in [1, 0]:
		_grid.add_child(UiKit.heading(str(rank + 1), 22, UiKit.DIM))
		for file in 8:
			var sq: int = rank * 8 + file
			_grid.add_child(_cell(sq))
	_grid.add_child(UiKit.spacer())
	for file in 8:
		var l := UiKit.heading("abcdefgh"[file], 20, UiKit.DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grid.add_child(l)
	for i in _reserve.size():
		var idx := i
		var b := _unit_button(int(_reserve[i]), _sel_reserve == i, func(): _click_reserve(idx))
		_reserve_row.add_child(b)
	if _reserve.is_empty():
		_reserve_row.add_child(UiKit.label("Everyone has a square.", 17, UiKit.DIM))
	var su := _selected_unit()
	_hint.text = "" if su == null else "%s selected%s" % [UiKit.unit_name(su), " · pawns stay off rank 1" if Run.is_pawn_like(su) else ""]


func _selected_unit() -> Unit:
	if _sel >= 0 and _arr.has(_sel):
		return Run.unit(_arr[_sel])
	if _sel_reserve >= 0:
		return Run.unit(_reserve[_sel_reserve])
	return null


func _cell(sq: int) -> Control:
	var su := _selected_unit()
	var allowed := su == null or Run.formation_square_ok(su, sq)
	var id: int = _arr.get(sq, -1)
	var b := _unit_button(id, _sel == sq, func(): _click_square(sq))
	b.disabled = not allowed and id < 0
	if not allowed:
		b.modulate = Color(0.6, 0.5, 0.5)
	return b


func _unit_button(id: int, selected: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL, CELL)
	var base := "slot_selected" if selected else "slot"
	var s := UiKit.frame(base, -1.0, 6.0)
	if s != null:
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", UiKit.frame("slot_hover", -1.0, 6.0) if not selected else s)
		b.add_theme_stylebox_override("pressed", UiKit.frame("slot_selected", -1.0, 6.0))
		b.add_theme_stylebox_override("disabled", s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	if id >= 0:
		var u := Run.unit(id)
		var p := UiKit.portrait(u.type, true, CELL - 22)
		p.position = Vector2(11, 11)
		b.add_child(p)
		b.tooltip_text = "%s\n%s" % [UiKit.unit_name(u), UiKit.moves_text(u.type)]
	return b


func _click_square(sq: int) -> void:
	var su := _selected_unit()
	if su == null:
		if _arr.has(sq):
			_sel = sq
			Audio.play("piece_select")
		_rebuild()
		return
	if _sel >= 0:
		var a: int = _arr.get(_sel, -1)
		var b: int = _arr.get(sq, -1)
		if b >= 0 and not Run.formation_square_ok(Run.unit(b), _sel):
			_hint.text = "%s cannot stand there." % UiKit.unit_name(Run.unit(b))
			_sel = -1
			_rebuild()
			return
		if Run.formation_square_ok(Run.unit(a), sq):
			_arr.erase(_sel)
			_arr.erase(sq)
			_arr[sq] = a
			if b >= 0:
				_arr[_sel] = b
			Audio.play("piece_move")
	elif _sel_reserve >= 0 and Run.formation_square_ok(su, sq):
		var displaced: int = _arr.get(sq, -1)
		_arr[sq] = su.id
		_reserve.remove_at(_sel_reserve)
		if displaced >= 0:
			_reserve.append(displaced)
		Audio.play("piece_drop")
	_sel = -1
	_sel_reserve = -1
	_rebuild()


func _click_reserve(i: int) -> void:
	if _sel >= 0:
		var id: int = _arr[_sel]
		_arr.erase(_sel)
		_reserve.append(id)
		_sel = -1
	else:
		_sel_reserve = i if _sel_reserve != i else -1
	_rebuild()
