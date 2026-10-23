class_name FormationModal
extends Control
## Arrange the army on ranks 1-2 and choose who fights: click a piece, then a square (swaps), the
## reserve or the bench. Pawns may not stand on rank 1. Deployed pieces cost Command (their value);
## the bench waits out fights. Reserve pieces stand wherever there is room.

signal saved

const CELL := 104

var _arr: Dictionary = {}
var _reserve: Array = []
var _bench: Array = []
var _sel := -1
var _sel_reserve := -1
var _sel_bench := -1
var _grid: GridContainer
var _reserve_row: HFlowContainer
var _bench_row: HFlowContainer
var _meter: Label
var _hint: Label
var _modal: UiModal


static func open_formation(parent: Node) -> FormationModal:
	var f := FormationModal.new()
	parent.add_child(f)
	return f


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal = UiModal.new().setup("Battle Formation", 1080, true,
		"Click a piece, then a square, the reserve or the bench. Every fight opens with this arrangement.")
	add_child(_modal)
	_modal.closed.connect(queue_free)
	var dep := Run.deployed_units()
	var f := Run.formation(dep)
	for sq in f:
		if int(sq) < 16:
			_arr[int(sq)] = int(f[sq])
	for u in dep:
		if not _arr.values().has(u.id):
			_reserve.append(u.id)
	for u in Run.benched_units():
		_bench.append(u.id)
	_meter = UiKit.label("", 22, UiKit.GOLD)
	_meter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal.body.add_child(_meter)
	_grid = GridContainer.new()
	_grid.columns = 9
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_modal.body.add_child(UiKit.centered(_grid))
	_modal.body.add_child(UiKit.caption("Reserve · deployed, no square yet", 18, UiKit.MUTED))
	_reserve_row = _row()
	_modal.body.add_child(_reserve_row)
	_modal.body.add_child(UiKit.caption("Bench · sits out fights, costs no Command", 18, UiKit.MUTED))
	_bench_row = _row()
	_modal.body.add_child(_bench_row)
	_hint = UiKit.label("", 18, UiKit.MUTED, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal.body.add_child(_hint)
	_modal.footer.add_child(UiKit.button("Default", func():
		Run.formation_prefs.clear()
		_modal.close()
		saved.emit(), 20))
	_modal.footer.add_child(UiKit.button("Keep this formation", _save, 22, true))
	_rebuild()


func _row() -> HFlowContainer:
	var r := HFlowContainer.new()
	r.add_theme_constant_override("h_separation", 8)
	r.add_theme_constant_override("v_separation", 8)
	return r


func _save() -> void:
	for u in Run.healthy_units():
		if _bench.has(u.id) and not u.is_benched():
			Run.set_benched(u, true)
	for u in Run.healthy_units():
		if not _bench.has(u.id) and u.is_benched():
			Run.set_benched(u, false)
	Run.set_formation(_arr)
	_modal.close()
	saved.emit()


func _used() -> int:
	var n := 0
	for id in _arr.values() + _reserve:
		n += Run.command_cost(Run.unit(int(id)))
	return n


func _fits(id: int) -> bool:
	var cap := Run.command_cap()
	return cap <= 0 or _used() + Run.command_cost(Run.unit(id)) <= cap


func _rebuild() -> void:
	for c in _grid.get_children() + _reserve_row.get_children() + _bench_row.get_children():
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
		_reserve_row.add_child(_unit_button(int(_reserve[i]), _sel_reserve == i, func(): _click_reserve(idx)))
	if _reserve.is_empty():
		_reserve_row.add_child(_drop_button("Everyone has a square." if _selected_unit() == null else "Move here",
			func(): _click_reserve(-1)))
	for i in _bench.size():
		var idx := i
		_bench_row.add_child(_unit_button(int(_bench[i]), _sel_bench == i, func(): _click_bench(idx)))
	if _sel >= 0 or _sel_reserve >= 0 or _bench.is_empty():
		_bench_row.add_child(_drop_button("Bench it" if _sel >= 0 or _sel_reserve >= 0 else "Nobody on the bench.",
			func(): _click_bench(-1)))
	var cap := Run.command_cap()
	var used := _used()
	_meter.text = "Command %d / %d" % [used, cap] if cap > 0 else "Command: no limit this act"
	_meter.add_theme_color_override("font_color", UiKit.BLOOD if cap > 0 and used > cap else UiKit.GOLD)
	var su := _selected_unit()
	if su == null:
		_hint.text = "A piece costs Command equal to its value. Your king is free."
	else:
		_hint.text = "%s selected · costs %d%s" % [UiKit.unit_name(su), Run.command_cost(su),
			" · pawns stay off rank 1" if Run.is_pawn_like(su) else ""]


func _selected_unit() -> Unit:
	if _sel >= 0 and _arr.has(_sel):
		return Run.unit(_arr[_sel])
	if _sel_reserve >= 0:
		return Run.unit(_reserve[_sel_reserve])
	if _sel_bench >= 0:
		return Run.unit(_bench[_sel_bench])
	return null


func _clear_sel() -> void:
	_sel = -1
	_sel_reserve = -1
	_sel_bench = -1


func _cell(sq: int) -> Control:
	var su := _selected_unit()
	var allowed := su == null or Run.formation_square_ok(su, sq)
	var id: int = _arr.get(sq, -1)
	var b := _unit_button(id, _sel == sq, func(): _click_square(sq))
	b.disabled = not allowed and id < 0
	if not allowed:
		b.modulate = Color(0.6, 0.5, 0.5)
	return b


func _drop_button(text: String, cb: Callable) -> Button:
	var b := _unit_button(-1, false, cb)
	b.custom_minimum_size = Vector2(CELL * 2, CELL * 0.6)
	b.text = text
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", UiKit.MUTED)
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
		var cost := Run.command_cost(u)
		if cost > 0:
			var c := UiKit.label(str(cost), 16, UiKit.GOLD)
			c.position = Vector2(CELL - 24, 4)
			b.add_child(c)
		b.tooltip_text = "%s · Command %d\n%s" % [UiKit.unit_name(u), cost, UiKit.moves_text(u.type)]
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
			_clear_sel()
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
	elif _sel_bench >= 0 and Run.formation_square_ok(su, sq):
		var displaced: int = _arr.get(sq, -1)
		var freed := Run.command_cost(Run.unit(displaced)) if displaced >= 0 else 0
		var cap := Run.command_cap()
		if cap > 0 and _used() - freed + Run.command_cost(su) > cap:
			_clear_sel()
			_rebuild()
			_hint.text = "Not enough Command for %s. Bench someone first." % UiKit.unit_name(su)
			return
		_arr[sq] = su.id
		_bench.remove_at(_sel_bench)
		if displaced >= 0:
			_bench.append(displaced)
		Audio.play("piece_drop")
	_clear_sel()
	_rebuild()


func _click_reserve(i: int) -> void:
	if _sel >= 0:
		_reserve.append(_arr[_sel])
		_arr.erase(_sel)
	elif _sel_bench >= 0:
		var id: int = _bench[_sel_bench]
		if not _fits(id):
			_clear_sel()
			_rebuild()
			_hint.text = "Not enough Command for %s. Bench someone first." % UiKit.unit_name(Run.unit(id))
			return
		_bench.remove_at(_sel_bench)
		_reserve.append(id)
	elif i >= 0:
		var keep := _sel_reserve != i
		_clear_sel()
		_sel_reserve = i if keep else -1
		_rebuild()
		return
	_clear_sel()
	_rebuild()


func _click_bench(i: int) -> void:
	var su := _selected_unit()
	if su != null and _sel_bench < 0:
		if Content.piece(su.type).is_royal():
			_clear_sel()
			_rebuild()
			_hint.text = "Your king always takes the field."
			return
		if _sel >= 0:
			_arr.erase(_sel)
		else:
			_reserve.remove_at(_sel_reserve)
		_bench.append(su.id)
		Audio.play("piece_drop")
		_clear_sel()
	elif i >= 0:
		var keep := _sel_bench != i
		_clear_sel()
		_sel_bench = i if keep else -1
	else:
		_clear_sel()
	_rebuild()
