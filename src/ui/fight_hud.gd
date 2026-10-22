class_name FightHud
extends Control
## Fight UI and input glue between the BoardView (clicks) and the FightController (rules).

signal continue_pressed(outcome: Dictionary)

var fight: FightController
var board: BoardView
var autoplay := false

var selected := -1
var targets: Dictionary = {}  # sq -> Array of uci
var swap_mode := false
var swap_first := -1
var drop_letter := ""

var _clock: Label
var _clock_panel: PanelContainer
var _think: Label
var _eval: Label
var _turn: Label
var _log: VBoxContainer
var _pocket_box: HBoxContainer
var _swap_btn: Button
var _resign_btn: Button
var _info: PanelContainer
var _info_body: VBoxContainer
var _overlay: Control
var _resign_armed := false
var _think_t := 0.0
var _thinking := false


func setup(p_fight: FightController, p_board: BoardView) -> FightHud:
	fight = p_fight
	board = p_board
	return self


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	fight.turn_started.connect(_on_turn)
	fight.engine_thinking.connect(_on_thinking)
	fight.moved.connect(_on_moved)
	fight.xp_gained.connect(_on_xp)
	fight.unit_lost.connect(_on_lost)
	fight.message.connect(func(t: String): _add_log(t, UiKit.MUTED))
	fight.fight_finished.connect(_on_finished)
	board.square_clicked.connect(_on_square)
	board.square_hovered.connect(_on_hover)
	board.right_clicked.connect(_cancel)
	_refresh_pocket()
	_refresh_swap()


func _build() -> void:
	var enc := fight.encounter
	# Top left: the enemy.
	var enemy := UiKit.panel(UiKit.EMBER if enc.kind != &"fight" else UiKit.EDGE, Color(0.04, 0.03, 0.05, 0.86), 16)
	enemy.position = Vector2(28, 24)
	enemy.custom_minimum_size = Vector2(420, 0)
	add_child(enemy)
	var ec := UiKit.vbox(4)
	enemy.add_child(ec)
	var kind_text: String = {&"fight": "Fight", &"elite": "Elite", &"boss": "Boss"}.get(enc.kind, "Fight")
	ec.add_child(UiKit.label(kind_text.to_upper() + " · TIER %d" % enc.tier, 16, UiKit.EMBER))
	ec.add_child(UiKit.heading(enc.display_name, 30))
	if enc.flavor != "":
		ec.add_child(UiKit.label(enc.flavor, 17, UiKit.MUTED, true))
	ec.add_child(UiKit.label("Fairy-Stockfish · skill %d · %d ms per move" % [enc.skill, enc.movetime_ms], 16, UiKit.DIM))
	_think = UiKit.heading("", 20, UiKit.EMBER)
	ec.add_child(_think)
	_eval = UiKit.label("", 18, UiKit.MUTED)
	ec.add_child(_eval)
	# Top right: relics.
	var relics := UiKit.hbox(10)
	relics.position = Vector2(1920 - 28 - 70 * maxi(1, fight.relic_defs.size()), 28)
	relics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(relics)
	for r in fight.relic_defs:
		var ic := UiKit.icon(r.icon, 64)
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		ic.tooltip_text = "%s\n%s" % [r.display_name, r.description]
		relics.add_child(ic)
	# Bottom right: clock and actions.
	_clock_panel = UiKit.panel(UiKit.SOUL, Color(0.03, 0.03, 0.05, 0.9), 14)
	_clock_panel.anchor_left = 1.0
	_clock_panel.anchor_right = 1.0
	_clock_panel.anchor_top = 1.0
	_clock_panel.anchor_bottom = 1.0
	_clock_panel.offset_left = -330
	_clock_panel.offset_right = -28
	_clock_panel.offset_top = -270
	_clock_panel.offset_bottom = -28
	add_child(_clock_panel)
	var cc := UiKit.vbox(8)
	_clock_panel.add_child(cc)
	_turn = UiKit.label("Your move", 20, UiKit.SOUL)
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cc.add_child(_turn)
	_clock = UiKit.heading("5:00", 64)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cc.add_child(_clock)
	var inc := UiKit.label("+%d s per move" % (fight.increment_ms / 1000), 16, UiKit.MUTED)
	inc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cc.add_child(inc)
	var actions := UiKit.hbox(10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(actions)
	_swap_btn = UiKit.button("Soul Exchange", _toggle_swap, 18)
	_swap_btn.tooltip_text = "Swap two of your pieces instead of moving."
	actions.add_child(_swap_btn)
	_resign_btn = UiKit.button("Resign", _on_resign, 18)
	actions.add_child(_resign_btn)
	# Bottom left: log.
	var log_panel := UiKit.panel(UiKit.EDGE, Color(0.03, 0.025, 0.045, 0.75), 14)
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = 28
	log_panel.offset_right = 28 + 440
	log_panel.offset_top = -250
	log_panel.offset_bottom = -28
	add_child(log_panel)
	_log = UiKit.vbox(2)
	log_panel.add_child(_log)
	_add_log("The engine awaits. You play white.", UiKit.MUTED)
	# Left middle: pocket tray.
	_pocket_box = UiKit.hbox(8)
	_pocket_box.position = Vector2(28, 430)
	_pocket_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pocket_box)
	# Hover info.
	_info = UiKit.panel(UiKit.EDGE, Color(0.03, 0.025, 0.045, 0.92), 12)
	_info.anchor_left = 1.0
	_info.anchor_right = 1.0
	_info.offset_left = -400
	_info.offset_right = -28
	_info.offset_top = 120
	_info.visible = false
	add_child(_info)
	_info_body = UiKit.vbox(4)
	_info.add_child(_info_body)
	# Controls hint.
	var hint := UiKit.label("Left click: select and move · Right click: cancel · Right drag: orbit · Wheel: zoom", 16, UiKit.DIM)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -400
	hint.offset_right = 400
	hint.offset_top = -40
	hint.offset_bottom = -12
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _process(delta: float) -> void:
	if fight == null:
		return
	var ms := maxf(fight.player_ms, 0.0)
	var s := int(ceil(ms / 1000.0))
	_clock.text = "%d:%02d" % [s / 60, s % 60]
	var low := s <= 30
	_clock.add_theme_color_override("font_color", UiKit.BLOOD if low else UiKit.BONE)
	if _thinking:
		_think_t += delta
		_think.text = "Stockfish is thinking" + ".".repeat(1 + int(_think_t * 3.0) % 3)
	_swap_btn.disabled = not fight.can_swap()


# --- turn flow ----------------------------------------------------------------------------------

func _on_turn(side: String) -> void:
	board.interactive = side == "w"
	_turn.text = "Your move" if side == "w" else "The engine moves"
	_turn.add_theme_color_override("font_color", UiKit.SOUL if side == "w" else UiKit.EMBER)
	_refresh_pocket()
	_refresh_swap()
	if side == "w" and autoplay:
		_autoplay_move()


func _on_thinking(on: bool) -> void:
	_thinking = on
	_think_t = 0.0
	if not on:
		_think.text = ""
		var sc: Dictionary = fight.last_engine_score
		if sc.get("mate") != null:
			var m := int(sc["mate"])
			_eval.text = "The engine sees mate in %d %s" % [absi(m), "for itself" if m > 0 else "against itself"]
		elif sc.get("cp") != null:
			var cp := -int(sc["cp"]) / 100.0
			_eval.text = "Engine evaluation: %s%.1f %s" % ["+" if cp >= 0 else "", cp, "in your favour" if cp >= 0 else "against you"]


func _on_moved(ev: Dictionary) -> void:
	var who := "You" if ev["side"] == "w" else "Engine"
	var text := "%s: %s" % [who, String(ev["uci"])]
	var captured := String(ev.get("captured", ""))
	if captured != "":
		var def: PieceDef = Content.piece_by_letter(captured.to_lower())
		text += " takes a %s" % (def.display_name.to_lower() if def != null else "piece")
	if ev.get("check", false):
		text += " · check"
	_add_log(text, UiKit.SOUL if ev["side"] == "w" else UiKit.EMBER)


func _on_xp(unit_id: int, amount: int, _captured: String) -> void:
	var u := Run.unit(unit_id)
	if u != null:
		_add_log("%s gains %d XP" % [UiKit.unit_name(u), amount], UiKit.GOLD)


func _on_lost(unit_id: int) -> void:
	var u := Run.unit(unit_id)
	if u != null:
		_add_log("%s is slain" % UiKit.unit_name(u), UiKit.BLOOD)
	elif fight.temp_units.has(unit_id):
		_add_log("Your pocket piece is taken", UiKit.BLOOD)


func _add_log(text: String, color: Color) -> void:
	_log.add_child(UiKit.label(text, 18, color, true))
	while _log.get_child_count() > 7:
		var c := _log.get_child(0)
		_log.remove_child(c)
		c.queue_free()


# --- selection and moves ------------------------------------------------------------------------

func _on_square(sq: int) -> void:
	if not fight.is_player_turn():
		return
	if swap_mode:
		_swap_click(sq)
		return
	if drop_letter != "":
		var uci := "%s@%s" % [drop_letter, Fen.sq_name(sq)]
		_cancel()
		if fight.legal.has(uci):
			_do_move(uci)
		return
	if selected >= 0 and targets.has(sq):
		var opts: Array = targets[sq]
		if opts.size() > 1:
			_ask_promotion(opts)
		else:
			_do_move(opts[0])
		return
	var letter := String(fight.board.get(sq, ""))
	if letter != "" and letter == letter.to_upper() and sq != selected:
		_select(sq)
	else:
		_cancel()


func _select(sq: int) -> void:
	selected = sq
	targets.clear()
	var marks := {}
	var is_pawn := String(fight.board.get(sq, "")).to_lower() == "p"
	for m in fight.legal_from(sq):
		var to := Fen.sq(m.substr(2, 2))
		if not targets.has(to):
			targets[to] = []
		targets[to].append(m)
		marks[to] = fight.board.has(to) or (is_pawn and to % 8 != sq % 8)
	board.show_selection(sq, marks)
	board.set_selected(sq)


func _cancel() -> void:
	selected = -1
	targets.clear()
	drop_letter = ""
	if swap_mode:
		swap_mode = false
		swap_first = -1
	_refresh_swap()
	board.set_selected(-1)
	board.clear_marks()


func _do_move(uci: String) -> void:
	selected = -1
	targets.clear()
	board.set_selected(-1)
	board.clear_marks()
	board.interactive = false
	var ok: bool = await fight.try_player_move(uci)
	if not ok and not fight.finished:
		board.interactive = true


func _ask_promotion(opts: Array) -> void:
	var modal := Control.new()
	UiKit.full(modal)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	UiKit.full(shade)
	modal.add_child(shade)
	var p := UiKit.panel(UiKit.SOUL)
	var col := UiKit.vbox(12)
	p.add_child(col)
	col.add_child(UiKit.heading("Promote to", 30))
	var row := UiKit.hbox(14)
	col.add_child(row)
	for m in opts:
		var promo := String(m).substr(4, 1)
		var def: PieceDef = Content.piece_by_letter(promo)
		var t: StringName = def.id if def != null else &"queen"
		var parts := UiKit.card(150, 190, func():
			modal.queue_free()
			_do_move(String(m)))
		var c: VBoxContainer = parts[1]
		c.add_child(UiKit.centered(UiKit.portrait(t, true, 100)))
		var n := UiKit.heading(UiKit.piece_name(t), 20)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(n)
		row.add_child(parts[0])
	var cancel := UiKit.button("Cancel", func(): modal.queue_free())
	col.add_child(UiKit.centered(cancel))
	var cc := UiKit.centered(p)
	UiKit.full(cc)
	modal.add_child(cc)


# --- pocket and swap ----------------------------------------------------------------------------

func _refresh_pocket() -> void:
	for c in _pocket_box.get_children():
		c.queue_free()
	var mine := ""
	for ch in fight.pocket:
		if ch == ch.to_upper():
			mine += ch
	if mine == "":
		return
	var p := UiKit.panel(UiKit.GOLD, Color(0.04, 0.035, 0.03, 0.88), 12)
	var col := UiKit.vbox(6)
	p.add_child(col)
	col.add_child(UiKit.label("POCKET", 16, UiKit.GOLD))
	var row := UiKit.hbox(8)
	col.add_child(row)
	for ch in mine:
		var def: PieceDef = Content.piece_by_letter(ch.to_lower())
		var t: StringName = def.id if def != null else &"bishop"
		var parts := UiKit.card(110, 130, func(): _arm_drop(ch), UiKit.GOLD)
		var c: VBoxContainer = parts[1]
		c.add_child(UiKit.centered(UiKit.portrait(t, true, 64)))
		var l := UiKit.label("Drop %s" % UiKit.piece_name(t), 15)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(l)
		row.add_child(parts[0])
	_pocket_box.add_child(p)


func _arm_drop(letter: String) -> void:
	if not fight.is_player_turn():
		return
	_cancel()
	drop_letter = letter.to_upper()
	var marks := {}
	for m in fight.legal_drops(drop_letter):
		marks[Fen.sq(m.substr(2, 2))] = false
	board.show_selection(-1, marks)
	_add_log("Choose a square in your half to drop the %s." % UiKit.piece_name(Content.piece_by_letter(letter.to_lower()).id).to_lower(), UiKit.GOLD)


func _refresh_swap() -> void:
	_swap_btn.visible = fight.edit_charges > 0 or _has_edit_relic()
	_swap_btn.text = ("Cancel exchange" if swap_mode else "Soul Exchange (%d)" % fight.edit_charges)


func _has_edit_relic() -> bool:
	for r in fight.relic_defs:
		if r.kind == &"edit":
			return true
	return false


func _toggle_swap() -> void:
	if swap_mode:
		_cancel()
		return
	if not fight.can_swap():
		return
	_cancel()
	swap_mode = true
	swap_first = -1
	_refresh_swap()
	_add_log("Soul Exchange: pick two of your pieces of different kinds.", Color(0.72, 0.56, 1.0))


func _swap_click(sq: int) -> void:
	var letter := String(fight.board.get(sq, ""))
	if letter == "" or letter != letter.to_upper():
		return
	if swap_first < 0:
		swap_first = sq
		board.clear_marks()
		board.mark(sq, BoardView.SWAP_COLOR, 2.0)
		board.set_selected(sq)
		return
	var a := swap_first
	swap_mode = false
	swap_first = -1
	board.set_selected(-1)
	board.clear_marks()
	board.interactive = false
	var res: Dictionary = await fight.try_swap(a, sq)
	_refresh_swap()
	if not res.get("ok", false):
		_add_log("The exchange fails: %s" % res.get("reason", "illegal"), UiKit.BLOOD)
		board.interactive = fight.is_player_turn()


func _on_resign() -> void:
	if fight.finished:
		return
	if not _resign_armed:
		_resign_armed = true
		_resign_btn.text = "Really resign?"
		get_tree().create_timer(3.0).timeout.connect(func():
			_resign_armed = false
			if is_instance_valid(_resign_btn):
				_resign_btn.text = "Resign")
		return
	fight.resign()


# --- hover info ---------------------------------------------------------------------------------

func _on_hover(sq: int) -> void:
	for c in _info_body.get_children():
		c.queue_free()
	if sq < 0 or not fight.board.has(sq):
		_info.visible = false
		return
	var letter := String(fight.board[sq])
	var white := letter == letter.to_upper()
	var def: PieceDef = Content.piece_by_letter(letter.to_lower())
	var t: StringName = def.id if def != null else &"pawn"
	var h := UiKit.hbox(12)
	h.add_child(UiKit.portrait(t, white, 72))
	var col := UiKit.vbox(2)
	h.add_child(col)
	if white:
		var uid := fight.unit_map.unit_at(sq)
		var u: Unit = Run.unit(uid)
		if u == null and fight.temp_units.has(uid):
			u = fight.temp_units[uid]
		if u != null:
			col.add_child(UiKit.heading(UiKit.unit_name(u) if not u.temporary else "Pocket %s" % UiKit.piece_name(u.type), 20))
			if u.type != t:
				col.add_child(UiKit.label("promoted to %s for this fight" % UiKit.piece_name(t).to_lower(), 16, UiKit.GOLD))
			col.add_child(UiKit.label("Level %d · %d XP · %d captures" % [u.level, u.xp, u.captures], 17, UiKit.MUTED))
			if u.lineage.size() > 1:
				col.add_child(UiKit.label(" → ".join(Array(u.lineage).map(func(x): return UiKit.piece_name(StringName(x)))), 16, UiKit.MUTED))
		else:
			col.add_child(UiKit.heading(UiKit.piece_name(t), 20))
	else:
		col.add_child(UiKit.heading("Engine %s" % UiKit.piece_name(t).to_lower(), 20, UiKit.EMBER))
		col.add_child(UiKit.label("Worth %d XP if captured" % (def.value if def != null else 0), 17, UiKit.GOLD))
	col.add_child(UiKit.label(UiKit.MOVES.get(t, ""), 16, UiKit.DIM, true))
	col.custom_minimum_size = Vector2(250, 0)
	_info_body.add_child(h)
	_info.visible = true


# --- results ------------------------------------------------------------------------------------

func _on_finished(outcome: Dictionary) -> void:
	board.interactive = false
	_thinking = false
	_think.text = ""
	await get_tree().create_timer(1.0 if not autoplay else 0.2).timeout
	if not is_inside_tree():
		return
	_show_result(outcome)


func _show_result(outcome: Dictionary) -> void:
	_overlay = Control.new()
	UiKit.full(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0.02, 0.45)
	UiKit.full(shade)
	_overlay.add_child(shade)
	var state := String(outcome.get("state", "draw"))
	var accent := UiKit.GOLD if state == "win" else (UiKit.BLOOD if state == "loss" else UiKit.MUTED)
	var p := UiKit.panel(accent, Color(0.03, 0.025, 0.045, 0.94), 28)
	p.custom_minimum_size = Vector2(640, 0)
	var col := UiKit.vbox(10)
	p.add_child(col)
	var t := UiKit.title({"win": "Victory", "loss": "Defeat", "draw": "Stalemate"}.get(state, "Draw"), 72, accent)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var r := UiKit.label(String(outcome.get("reason", "")), 24, UiKit.BONE)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(r)
	var info := UiKit.label("%d plies played" % int(outcome.get("plies", 0)), 18, UiKit.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(info)
	var lost: Array = outcome.get("slain", [])
	if not lost.is_empty():
		var names: Array = []
		for id in lost:
			var u := Run.unit(int(id))
			if u != null:
				names.append(UiKit.unit_name(u))
		if not names.is_empty():
			var l := UiKit.label("Slain: " + ", ".join(names), 19, UiKit.BLOOD, true)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(l)
	var btn := UiKit.button("Continue", func(): continue_pressed.emit(outcome), 26)
	col.add_child(UiKit.spacer(8))
	col.add_child(UiKit.centered(btn))
	var cc := UiKit.centered(p)
	UiKit.full(cc)
	_overlay.add_child(cc)
	UiKit.fade_in(_overlay, 0.5)
	if autoplay:
		get_tree().create_timer(0.3).timeout.connect(func(): continue_pressed.emit(outcome))


# --- autoplay (automated full-run checks) -------------------------------------------------------

func _autoplay_move() -> void:
	await get_tree().process_frame
	if not fight.is_player_turn():
		return
	var res: Dictionary = await ChessCore.engine_move(fight.base_fen, fight.moves, 40, 20, 0)
	if fight.finished or not fight.is_player_turn():
		return
	var mv := String(res.get("move", ""))
	if mv == "" or not fight.legal.has(mv):
		mv = fight.legal[0] if not fight.legal.is_empty() else ""
	if mv != "":
		_do_move(mv)
