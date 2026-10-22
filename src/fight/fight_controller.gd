class_name FightController
extends Node
## One fight against the engine. Pure logic: the board view (or a test) listens to signals and
## may set `presenter` (an object with coroutines present_move(ev) and present_swap(a, b)).
## The player is white; every ply goes through the chess core.

signal ready_to_play
signal turn_started(side: String)
signal legal_ready(moves: PackedStringArray)
signal engine_thinking(on: bool)
signal moved(ev: Dictionary)
signal swapped(a: int, b: int)
signal xp_gained(unit_id: int, amount: int, captured: String)
signal unit_lost(unit_id: int)
signal message(text: String)
signal fight_finished(outcome: Dictionary)

static var _fight_counter := 0

var encounter: EncounterDef
var cfg: RunConfig
var relic_defs: Array = []
var presenter: Object

var variant_name := ""
var variant_ini := ""
var base_fen := ""
var moves := PackedStringArray()
var fen := ""
var board: Dictionary = {}
var pocket := ""
var unit_map := UnitMap.new()
var temp_units: Dictionary = {}
var legal := PackedStringArray()
var turn := "w"
var busy := false
var finished := false
var outcome: Dictionary = {}

var player_ms := 0.0
var increment_ms := 0
var clock_running := false
var edit_charges := 0
var promo_ranks := PackedInt32Array([7])

var engine_bad_streak := 0
var last_engine_score: Dictionary = {}
var slain: Array = []
var xp_log: Array = []
var ply_count := 0
var _next_temp_id := -1


## units: Array of Unit (healthy army). relics: Array of RelicDef.
func setup(p_encounter: EncounterDef, units: Array, relics: Array, p_cfg: RunConfig, formation: Dictionary) -> bool:
	encounter = p_encounter
	cfg = p_cfg
	relic_defs = relics
	_fight_counter += 1
	variant_name = "sts_fight_%d" % _fight_counter
	var relic_lines := PackedStringArray()
	var has_pocket := false
	pocket = ""
	var clock_bonus := 0
	edit_charges = 0
	for r in relics:
		match r.kind:
			&"rule":
				relic_lines.append_array(r.ini_lines)
				for rank in r.promotion_ranks:
					if not promo_ranks.has(rank):
						promo_ranks.append(rank)
			&"pocket":
				has_pocket = true
				pocket += r.pocket.to_upper()
			&"edit":
				edit_charges += r.charges_per_fight
			&"clock":
				clock_bonus += r.clock_bonus_s
	var king: PieceDef = Content.piece(&"king")
	var gen := VariantGen.build(variant_name, king.royal_betza if king != null else "K", _custom_pieces(units),
		relic_lines, has_pocket)
	if gen.has("error"):
		push_warning("fight: %s" % gen["error"])
		return false
	variant_ini = gen["ini"]
	var load_res: Dictionary = await ChessCore.load_variant(variant_name, variant_ini)
	if not load_res.get("ok", false):
		push_warning("fight: variant did not load: %s" % load_res.get("error", "?"))
		return false
	board = {}
	unit_map = UnitMap.new()
	for sq in formation:
		var u: Unit = _unit(int(formation[sq]), units)
		if u == null:
			continue
		board[int(sq)] = _letter_for(u.type, true)
		unit_map.place(int(sq), u.id)
	for sq_name in encounter.layout:
		board[Fen.sq(String(sq_name))] = _letter_for(StringName(encounter.layout[sq_name]), false)
	var st := {"board": board, "pocket": pocket, "has_pocket": has_pocket, "side": "w", "castling": "-",
		"ep": "-", "halfmove": 0, "fullmove": 1}
	base_fen = Fen.serialize(st)
	fen = base_fen
	moves = PackedStringArray()
	var v: Dictionary = await ChessCore.validate(fen)
	if not v.get("valid", false):
		push_warning("fight: start position invalid (%s): %s" % [v.get("reason", v.get("error", "?")), fen])
		return false
	player_ms = (cfg.clock_base_s + clock_bonus) * 1000.0
	increment_ms = cfg.clock_increment_s * 1000
	ready_to_play.emit()
	return true


func _custom_pieces(units: Array) -> Array:
	var out: Array = []
	var ids := {}
	for u in units:
		ids[u.type] = true
	for id in encounter.layout.values():
		ids[StringName(id)] = true
	for id in ids:
		var def: PieceDef = Content.piece(id)
		if def != null and def.betza != "":
			out.append({"id": def.id, "betza": def.betza, "ini_extra": def.ini_extra})
	return out


func _unit(id: int, units: Array) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func _letter_for(type: StringName, white: bool) -> String:
	if type == &"king":
		return VariantGen.PLAYER_KING.to_upper() if white else "k"
	var def: PieceDef = Content.piece(type)
	var l := def.letter if def != null and def.letter != "" else "p"
	return l.to_upper() if white else l


func begin() -> void:
	await _start_player_turn()


# --- player -----------------------------------------------------------------------------------

func _start_player_turn() -> void:
	if finished:
		return
	turn = "w"
	legal = await ChessCore.legal(base_fen, moves)
	if finished:
		return
	clock_running = true
	turn_started.emit("w")
	legal_ready.emit(legal)


func is_player_turn() -> bool:
	return turn == "w" and not busy and not finished


func legal_from(square: int) -> PackedStringArray:
	var from_name := Fen.sq_name(square)
	var out := PackedStringArray()
	for m in legal:
		if m.substr(0, 2) == from_name and not m.contains("@"):
			out.append(m)
	return out


func legal_drops(letter: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m in legal:
		if m.begins_with(letter.to_upper() + "@"):
			out.append(m)
	return out


func try_player_move(uci: String) -> bool:
	if not is_player_turn() or not legal.has(uci):
		return false
	busy = true
	_stop_clock_with_increment()
	await _play(uci, "w")
	busy = false
	if finished:
		return true
	if await _check_end():
		return true
	await _engine_turn()
	return true


func can_swap() -> bool:
	return edit_charges > 0 and is_player_turn()


## The edit relic: swap two of your pieces instead of moving.
func try_swap(a: int, b: int) -> Dictionary:
	if not can_swap():
		return {"ok": false, "reason": "no swap left"}
	busy = true
	var res: Dictionary = await PositionEdit.validate_swap(ChessCore, fen, a, b, promo_ranks)
	if not res["ok"] or finished:
		busy = false
		return res
	edit_charges -= 1
	_stop_clock_with_increment()
	base_fen = res["fen"]
	moves = PackedStringArray()
	fen = base_fen
	board = Fen.parse(fen)["board"]
	unit_map.swap(a, b)
	swapped.emit(a, b)
	if presenter != null and presenter.has_method("present_swap"):
		await presenter.present_swap(a, b)
	message.emit("Soul Exchange: %s and %s trade places." % [Fen.sq_name(a), Fen.sq_name(b)])
	busy = false
	if finished:
		return res
	if not await _check_end():
		await _engine_turn()
	return res


func resign() -> void:
	if not finished:
		_finish("loss", "you resigned")


func _stop_clock_with_increment() -> void:
	clock_running = false
	player_ms += increment_ms


func _physics_process(delta: float) -> void:
	if clock_running and not finished:
		player_ms -= delta * 1000.0
		if player_ms <= 0.0:
			player_ms = 0.0
			_finish("loss", "your clock ran out")


# --- engine -----------------------------------------------------------------------------------

func _engine_turn() -> void:
	if finished:
		return
	turn = "b"
	turn_started.emit("b")
	engine_thinking.emit(true)
	var res: Dictionary = await ChessCore.engine_move(base_fen, moves, encounter.movetime_ms, encounter.skill, encounter.depth)
	engine_thinking.emit(false)
	if finished:
		return
	if not res.get("ok", false):
		push_warning("fight: engine failed: %s" % res.get("error", "?"))
		_finish("draw", "the engine fell silent")
		return
	last_engine_score = {"cp": res.get("score_cp"), "mate": res.get("mate")}
	if _engine_is_lost(res):
		engine_bad_streak += 1
	else:
		engine_bad_streak = 0
	if engine_bad_streak >= cfg.resign_moves and ply_count >= cfg.resign_min_plies:
		_finish("win", "the engine resigns")
		return
	await _play(String(res["move"]), "b")
	if finished:
		return
	if await _check_end():
		return
	await _start_player_turn()


## Scores are from the engine's side (it is the side to move).
func _engine_is_lost(res: Dictionary) -> bool:
	var mate: Variant = res.get("mate")
	if mate != null:
		return int(mate) < 0
	var cp: Variant = res.get("score_cp")
	return cp != null and int(cp) <= -cfg.resign_cp


# --- shared -----------------------------------------------------------------------------------

func _play(uci: String, side: String) -> Dictionary:
	var before := board
	var ev := unit_map.apply_move(uci, before, side)
	var res: Dictionary = await ChessCore.apply(base_fen, moves, uci)
	if not res.get("ok", false):
		push_warning("fight: core refused %s: %s" % [uci, res.get("error", "?")])
		_finish("draw", "the rules broke")
		return ev
	moves.append(uci)
	fen = res["fen"]
	var st := Fen.parse(fen)
	board = st["board"]
	pocket = st["pocket"]
	ply_count += 1
	ev["capture"] = res.get("capture", false)
	ev["check"] = res.get("check", false)
	ev["fen"] = fen
	if side == "w" and ev["drop"] != "":
		var t := Unit.make(_next_temp_id, Content.piece_by_letter(ev["drop"]).id if Content.piece_by_letter(ev["drop"]) else &"bishop")
		t.temporary = true
		temp_units[t.id] = t
		unit_map.place(ev["to"], t.id)
		ev["mover_unit"] = t.id
		_next_temp_id -= 1
	if side == "w" and ev["captured"] != "":
		var u: Unit = Run.unit(int(ev["mover_unit"]))
		var amount := Content.value_of_letter(ev["captured"])
		if u != null and amount > 0:
			u.xp += amount
			u.captures += 1
			xp_log.append({"unit": u.id, "amount": amount, "captured": ev["captured"]})
			xp_gained.emit(u.id, amount, ev["captured"])
	if side == "b" and int(ev["captured_unit"]) >= 0:
		var lost := int(ev["captured_unit"])
		slain.append(lost)
		unit_lost.emit(lost)
	moved.emit(ev)
	if presenter != null and presenter.has_method("present_move"):
		await presenter.present_move(ev)
	return ev


func _check_end() -> bool:
	var r: Dictionary = await ChessCore.result(base_fen, moves)
	if finished:
		return true
	var state: String = r.get("state", "ongoing")
	if state == "ongoing":
		return false
	var reason: String = r.get("reason", "")
	if state == "win" and reason == "checkmate":
		reason = "checkmate: the engine's king falls"
	elif state == "loss" and reason == "checkmate":
		reason = "checkmate: your king falls"
	_finish(state, reason)
	return true


func _finish(state: String, reason: String) -> void:
	if finished:
		return
	finished = true
	clock_running = false
	outcome = {"state": state, "reason": reason, "slain": slain.duplicate(), "xp": xp_log.duplicate(),
		"plies": ply_count, "encounter": encounter.id if encounter else &""}
	message.emit(reason)
	fight_finished.emit(outcome)
