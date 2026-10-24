class_name BoardStage
extends Control
## The army edited on the 3D board: click a piece, then a square on ranks 1-2 (moves or swaps; pawns
## stay off rank 1), or bench it in the panel; benched pieces step back in from the panel. Every
## change is kept at once (Run.set_formation). Draft mode is the run-start muster: the king stands
## alone, the merchant's stall is on the far side, and pieces bought with the budget drop onto the
## board; a bought piece can be returned for its price.

signal done

var draft := false
var autoplay := false
var board: BoardView
var _modal: UiModal
var _body: VBoxContainer
var _hint: Label
var _sel := -1
var _busy := false


func setup(p_board: BoardView, p_draft: bool = false) -> BoardStage:
	board = p_board
	draft = p_draft
	return self


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if draft:
		_modal = UiModal.new().setup("Muster", 1000, false,
			"Your king stands alone. Spend %d points of bone on an army, then place it. Unspent points become %d gold each." % [
				Content.config.draft_budget, Content.config.draft_leftover_gold], 760).docked()
	else:
		_modal = UiModal.new().setup("Battle Formation", 1000, true,
			"Click a piece, then a square. Every fight opens with this arrangement.", 760).docked()
		_modal.closed.connect(_close)
	add_child(_modal)
	_body = UiKit.vbox(12)
	_modal.body.add_child(_body)
	_hint = UiKit.label("", 18, UiKit.MUTED, true)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal.body.add_child(_hint)
	if draft:
		var go := UiKit.button("Begin the descent", _finish, 24, true)
		go.custom_minimum_size.x = 320
		_modal.footer.add_child(go)
	else:
		_modal.footer.add_child(UiKit.button("Default", func():
			Run.formation_prefs.clear()
			_refresh_board(), 20))
		_modal.footer.add_child(UiKit.button("Done", func(): _modal.close(), 22, true))
	board.interactive = true
	board.square_clicked.connect(_on_square)
	board.right_clicked.connect(_deselect)
	_rebuild()
	if autoplay:
		_auto()


func _exit_tree() -> void:
	if board != null and is_instance_valid(board):
		board.interactive = false
		board.set_selected(-1)
		board.clear_marks()
		if board.square_clicked.is_connected(_on_square):
			board.square_clicked.disconnect(_on_square)
		if board.right_clicked.is_connected(_deselect):
			board.right_clicked.disconnect(_deselect)


func _close() -> void:
	done.emit()
	queue_free()


func _finish() -> void:
	var g := Run.finish_draft()
	if g > 0:
		Audio.play("gold")
	Run.set_formation(_arrangement())
	done.emit()


func _auto() -> void:
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(self):
		return
	if draft:
		Run.auto_draft()
		_finish()
	else:
		_modal.close()


# --- arrangement --------------------------------------------------------------------------------

## {square: unit id} as the board stands.
func _arrangement() -> Dictionary:
	return Run.formation(Run.deployed_units())


func _square_of(id: int) -> int:
	var arr := _arrangement()
	for sq in arr:
		if int(arr[sq]) == id:
			return int(sq)
	return -1


func _letter_at(sq: int) -> String:
	return String(Run.display_position()["board"].get(sq, "P"))


## The view after an edit whose animation is done (or Default): letters may change when a new kind
## of piece arrives.
func _refresh_board() -> void:
	var dp := Run.display_position()
	var units: UnitMap = dp["units"]
	var want: Dictionary = dp["board"]
	var same := board.pieces.size() == want.size()
	for sq in board.pieces:
		if not want.has(sq) or (board.pieces[sq] as PieceView).unit_id != units.unit_at(int(sq)):
			same = false
	if same:
		board.sync(want)
	else:
		board.setup_position(want, units, false)
	_deselect()


# --- input ---------------------------------------------------------------------------------------

func _on_square(sq: int) -> void:
	if _busy:
		return
	var arr := _arrangement()
	if _sel < 0:
		if arr.has(sq):
			_select(sq)
		return
	if sq == _sel:
		_deselect()
		return
	var a := Run.unit(int(arr.get(_sel, -1)))
	if a == null:
		_deselect()
		return
	var b := Run.unit(int(arr.get(sq, -1)))
	if not Run.formation_square_ok(a, sq):
		if b != null:
			_select(sq)
		else:
			_hint.text = "Pawns stay off rank 1." if Run.is_pawn_like(a) else "Only ranks 1 and 2."
			Audio.play("ui_deny")
		return
	if b != null and not Run.formation_square_ok(b, _sel):
		_hint.text = "%s cannot stand there." % UiKit.unit_name(b)
		Audio.play("ui_deny")
		return
	var from := _sel
	arr.erase(from)
	arr.erase(sq)
	arr[sq] = a.id
	if b != null:
		arr[from] = b.id
	Run.set_formation(arr)
	_deselect()
	_busy = true
	if b != null:
		await board.present_swap(from, sq)
	else:
		await board.present_hop(from, sq)
	_busy = false
	if is_instance_valid(self):
		_rebuild()


func _select(sq: int) -> void:
	_sel = sq
	Audio.play("piece_select")
	board.set_selected(sq)
	var u := Run.unit(int(_arrangement().get(sq, -1)))
	var targets := {}
	for t in 16:
		if t != sq and u != null and Run.formation_square_ok(u, t):
			targets[t] = false
	board.show_selection(sq, targets)
	_rebuild()


func _deselect() -> void:
	_sel = -1
	if board != null:
		board.set_selected(-1)
		board.clear_marks()
	if _body != null:
		_rebuild()


# --- panel ---------------------------------------------------------------------------------------

func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	if draft:
		var pts := UiKit.hbox(10)
		pts.alignment = BoxContainer.ALIGNMENT_CENTER
		pts.add_child(UiKit.caption("Points", 20, UiKit.MUTED))
		pts.add_child(UiKit.heading(str(Run.draft_points()), 36, UiKit.GOLD))
		_body.add_child(pts)
		_body.add_child(_offers())
		_body.add_child(UiKit.divider(520, true))
	var cap := Run.command_cap()
	var meter := UiKit.label("Command %d / %d" % [Run.command_used(), cap] if cap > 0 else "Command: no limit this act", 20, UiKit.GOLD)
	meter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(meter)
	_body.add_child(_selection())
	if not draft:
		_body.add_child(_bench())
	_hint.text = "Click a piece on the board, then a square. Right-click lets go." if _sel < 0 else "Click a square to move it there."


func _offers() -> Control:
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	for t in Run.draft_offers():
		var type: StringName = t
		var d: PieceDef = Content.piece(type)
		var special := not Content.config.draft_basics.has(type)
		var b := _piece_button(type, "%s\n%d pt%s%s" % [UiKit.piece_name(type), d.value, "" if d.value == 1 else "s", " · one" if special else ""],
			Run.can_draft(type), func(): _buy(type))
		b.tooltip_text = "%s · value %d%s\n%s" % [UiKit.piece_name(type), d.value, " · only one on offer" if special else "",
			UiKit.moves_text(type)]
		flow.add_child(b)
	return flow


func _selection() -> Control:
	var col := UiKit.vbox(8)
	var u := Run.unit(int(_arrangement().get(_sel, -1))) if _sel >= 0 else null
	if u == null:
		return col
	var h := UiKit.hbox(12)
	h.add_child(UiKit.portrait(u.type, true, 64))
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiKit.heading(UiKit.unit_name(u), 22))
	info.add_child(UiKit.label("Command %d · %s" % [Run.command_cost(u), UiKit.moves_text(u.type)], 15, UiKit.MUTED, true))
	h.add_child(info)
	col.add_child(h)
	var row := UiKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if draft and Run.draft.get("bought", []).has(u.id):
		var v := Content.piece(u.type).value
		row.add_child(UiKit.button("Return  ·  +%d pt%s" % [v, "" if v == 1 else "s"], func(): _refund(u), 18))
	if not draft and not Content.piece(u.type).is_royal():
		row.add_child(UiKit.button("Bench it", func(): _bench_unit(u), 18))
	col.add_child(row)
	return col


func _bench() -> Control:
	var col := UiKit.vbox(6)
	col.add_child(UiKit.caption("Bench · sits out fights, costs no Command", 18, UiKit.MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	col.add_child(flow)
	var benched := Run.benched_units()
	for x in benched:
		var u: Unit = x
		var b := _piece_button(u.type, "%s\nCommand %d" % [UiKit.piece_name(u.type), Run.command_cost(u)], Run.fits(u), func(): _deploy(u))
		b.tooltip_text = "%s · Command %d\n%s" % [UiKit.unit_name(u), Run.command_cost(u),
			"Click to bring it onto the board." if Run.fits(u) else "Not enough Command. Bench someone first."]
		flow.add_child(b)
	if benched.is_empty():
		flow.add_child(UiKit.label("Nobody on the bench.", 17, UiKit.DIM))
	return col


func _piece_button(type: StringName, tag: String, enabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(108, 128)
	b.add_theme_stylebox_override("normal", UiKit.frame("slot", -1.0, 6.0))
	b.add_theme_stylebox_override("hover", UiKit.frame("slot_hover", -1.0, 6.0))
	b.add_theme_stylebox_override("pressed", UiKit.frame("slot_selected", -1.0, 6.0))
	b.add_theme_stylebox_override("disabled", UiKit.frame("slot", -1.0, 6.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.disabled = not enabled
	b.pressed.connect(cb)
	var p := UiKit.portrait(type, true, 70, 0.0 if enabled else 0.6)
	p.position = Vector2(19, 6)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(p)
	var l := UiKit.label(tag, 14, UiKit.GOLD if enabled else UiKit.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 78)
	l.size = Vector2(108, 44)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	return b


# --- edits ---------------------------------------------------------------------------------------

func _buy(type: StringName) -> void:
	if _busy:
		return
	var u := Run.draft_buy(type)
	if u == null:
		return
	Audio.play("shop_buy")
	await _arrive(u)


func _deploy(u: Unit) -> void:
	if _busy or not Run.set_benched(u, false):
		return
	await _arrive(u)


## A unit that just joined the deployed army drops onto the square the formation gives it.
func _arrive(u: Unit) -> void:
	var sq := _square_of(u.id)
	Run.set_formation(_arrangement())
	_deselect()
	if sq < 0:
		_refresh_board()
		return
	_busy = true
	await board.present_drop(_letter_at(sq), sq, u.id)
	_busy = false
	if is_instance_valid(self):
		_refresh_board()


func _refund(u: Unit) -> void:
	var sq := _square_of(u.id)
	if _busy or not Run.draft_refund(u):
		return
	await _leave(sq)


func _bench_unit(u: Unit) -> void:
	var sq := _square_of(u.id)
	if _busy or not Run.set_benched(u, true):
		return
	await _leave(sq)


func _leave(sq: int) -> void:
	Run.set_formation(_arrangement())
	_deselect()
	_busy = true
	if sq >= 0:
		await board.present_lift(sq)
	_busy = false
	if is_instance_valid(self):
		_refresh_board()
