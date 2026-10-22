class_name FightController
extends Node
## One fight against the engine. Pure logic: the board view (or a test) listens to signals and
## may set `presenter` (an object with coroutines present_move(ev), present_swap(a, b),
## present_teleport(from, to) and present_lift(sq)). The player is white; every ply goes through
## the chess core.

signal ready_to_play
signal turn_started(side: String)
signal legal_ready(moves: PackedStringArray)
signal engine_thinking(on: bool)
signal moved(ev: Dictionary)
signal swapped(a: int, b: int)
signal lifted(sq: int)
signal xp_gained(unit_id: int, amount: int, captured: String)
signal unit_lost(unit_id: int)
signal message(text: String)
signal fight_finished(outcome: Dictionary)

static var _fight_counter := 0

var encounter: EncounterDef
var cfg: RunConfig
var relic_defs: Array = []
var presenter: Object
## Difficulty modifiers (Run.difficulty_mods()): skill_bonus, elite_skill_bonus, movetime_mult,
## clock_delta_s, resign_cp_delta.
var mods: Dictionary = {}

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

## Custom piece letters of this fight: piece id -> letter (lower case).
var letters: Dictionary = {}
## The player's king line node (always the letter W on the board).
var royal_type: StringName = &"king"
## Upper-case letters of the player's pawn-like types; lower-case letters that capture en passant.
var pawn_letters := "P"
var ep_letters := "p"
## Run units lifted into the pocket (hybrid relic), waiting to be dropped: [{letter, unit}].
var pocket_units: Array = []

var player_ms := 0.0
var increment_ms := 0
var clock_running := false
var edit_charges := 0
var move_charges := 0
var lift_charges := 0
var can_pass := false
var promo_ranks := PackedInt32Array([7])

var engine_bad_streak := 0
var last_engine_score: Dictionary = {}
var slain: Array = []
var xp_log: Array = []
var ply_count := 0
var _next_temp_id := -1


## units: Array of Unit (healthy army). relics: Array of RelicDef. p_mods: difficulty modifiers.
func setup(p_encounter: EncounterDef, units: Array, relics: Array, p_cfg: RunConfig, formation: Dictionary,
		p_mods: Dictionary = {}) -> bool:
	encounter = p_encounter
	cfg = p_cfg
	relic_defs = relics
	mods = p_mods
	_fight_counter += 1
	variant_name = "sts_fight_%d" % _fight_counter
	var relic_lines := PackedStringArray()
	var has_pocket := false
	pocket = ""
	var clock_bonus := 0
	var inc_bonus := 0
	edit_charges = 0
	move_charges = 0
	lift_charges = 0
	for r in relics:
		match r.kind:
			&"rule":
				relic_lines.append_array(r.ini_lines)
				for rank in r.promotion_ranks:
					if not promo_ranks.has(rank):
						promo_ranks.append(rank)
				for line in r.ini_lines:
					if String(line).begins_with("passWhite"):
						can_pass = true
			&"pocket":
				has_pocket = true
				pocket += r.pocket.to_upper()
			&"edit":
				if r.edit_kind == &"move":
					move_charges += r.charges_per_fight
				else:
					edit_charges += r.charges_per_fight
			&"hybrid":
				has_pocket = true
				lift_charges += r.charges_per_fight
			&"clock":
				clock_bonus += r.clock_bonus_s
				inc_bonus += r.increment_bonus_s
	var royal_def: PieceDef = Content.piece(&"king")
	for u in units:
		var d: PieceDef = Content.piece(u.type)
		if d != null and d.is_royal():
			royal_def = d
	royal_type = royal_def.id if royal_def != null else &"king"
	var custom := _custom_pieces(units)
	var gen := VariantGen.build(variant_name, royal_def.royal_betza if royal_def != null else "K", custom,
		relic_lines, has_pocket)
	if gen.has("error"):
		push_warning("fight: %s" % gen["error"])
		return false
	variant_ini = gen["ini"]
	letters = gen["letters"]
	Content.set_fight_letters(letters, royal_type)
	pawn_letters = "P"
	ep_letters = "p"
	for c in custom:
		var l: String = letters[c["id"]]
		if c["pawn_like"]:
			pawn_letters += l.to_upper()
		if c["ep"]:
			ep_letters += l
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
	if royal_def != null and royal_def.twin_king:
		_place_twin()
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
	player_ms = maxf(60.0, float(cfg.clock_base_s + clock_bonus + int(mods.get("clock_delta_s", 0)))) * 1000.0
	increment_ms = (cfg.clock_increment_s + inc_bonus) * 1000
	ready_to_play.emit()
	return true


## The Regent's twin: a second W on the first free twin square. It is no run unit.
func _place_twin() -> void:
	for s in cfg.twin_squares:
		var i := Fen.sq(String(s))
		if board.has(i):
			continue
		board[i] = VariantGen.PLAYER_KING.to_upper()
		var t := Unit.make(_next_temp_id, royal_type)
		t.temporary = true
		temp_units[t.id] = t
		unit_map.place(i, t.id)
		_next_temp_id -= 1
		return


## Every non-standard, non-royal piece type on either side: {id, betza, pawn_like, ep, ini_extra}.
func _custom_pieces(units: Array) -> Array:
	var out: Array = []
	var ids: Array = []
	for u in units:
		if not ids.has(u.type):
			ids.append(u.type)
	for id in encounter.layout.values():
		if not ids.has(StringName(id)):
			ids.append(StringName(id))
	for id in ids:
		var def: PieceDef = Content.piece(id)
		if def != null and def.betza != "" and not def.is_royal():
			out.append({"id": def.id, "betza": def.betza, "pawn_like": def.pawn_like, "ep": def.takes_en_passant(),
				"ini_extra": def.ini_extra})
	return out


func _unit(id: int, units: Array) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func _letter_for(type: StringName, white: bool) -> String:
	var def: PieceDef = Content.piece(type)
	if def != null and def.is_royal():
		return VariantGen.PLAYER_KING.to_upper() if white else "k"
	var l := "p"
	if def != null and def.letter != "":
		l = def.letter
	elif letters.has(type):
		l = letters[type]
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


## Board moves from a square (drops and passes excluded).
func legal_from(square: int) -> PackedStringArray:
	var from_name := Fen.sq_name(square)
	var out := PackedStringArray()
	for m in legal:
		if m.substr(0, 2) == from_name and not m.contains("@") and m.substr(2, 2) != from_name:
			out.append(m)
	return out


func legal_drops(letter: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m in legal:
		if m.begins_with(letter.to_upper() + "@"):
			out.append(m)
	return out


## The pass move (rule relic): the king to its own square, or "" if passing is not legal now.
func pass_move() -> String:
	if not can_pass:
		return ""
	for m in legal:
		if not m.contains("@") and m.length() >= 4 and m.substr(0, 2) == m.substr(2, 2):
			return m
	return ""


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


func can_edit_move() -> bool:
	return move_charges > 0 and is_player_turn()


func can_lift() -> bool:
	return lift_charges > 0 and is_player_turn()


## The swap edit: two of your pieces trade places instead of moving.
func try_swap(a: int, b: int) -> Dictionary:
	if not can_swap():
		return {"ok": false, "reason": "no swap left"}
	busy = true
	var res: Dictionary = await PositionEdit.validate_swap(ChessCore, fen, a, b, promo_ranks, pawn_letters)
	if not res["ok"] or finished:
		busy = false
		return res
	edit_charges -= 1
	_stop_clock_with_increment()
	_rebase(res["fen"])
	unit_map.swap(a, b)
	swapped.emit(a, b)
	if presenter != null and presenter.has_method("present_swap"):
		await presenter.present_swap(a, b)
	message.emit("Soul Exchange: %s and %s trade places." % [Fen.sq_name(a), Fen.sq_name(b)])
	return await _after_edit(res)


## The move edit: one of your pieces jumps to an empty square in your half instead of moving.
func try_edit_move(from: int, to: int) -> Dictionary:
	if not can_edit_move():
		return {"ok": false, "reason": "no strings left"}
	busy = true
	var res: Dictionary = await PositionEdit.validate_move(ChessCore, fen, from, to, promo_ranks, pawn_letters)
	if not res["ok"] or finished:
		busy = false
		return res
	move_charges -= 1
	_stop_clock_with_increment()
	_rebase(res["fen"])
	var uid := unit_map.unit_at(from)
	unit_map.by_square.erase(from)
	if uid != -1:
		unit_map.place(to, uid)
	if presenter != null and presenter.has_method("present_teleport"):
		await presenter.present_teleport(from, to)
	message.emit("Puppeteer's String: %s is pulled to %s." % [Fen.sq_name(from), Fen.sq_name(to)])
	return await _after_edit(res)


## The hybrid: a free action that lifts one of your pieces into your pocket. You still move.
func try_lift(sq: int) -> Dictionary:
	if not can_lift():
		return {"ok": false, "reason": "the lantern is dark"}
	busy = true
	var res: Dictionary = await PositionEdit.validate_lift(ChessCore, fen, sq)
	if not res["ok"] or finished:
		busy = false
		return res
	lift_charges -= 1
	var letter := String(board.get(sq, ""))
	var uid := unit_map.unit_at(sq)
	unit_map.by_square.erase(sq)
	pocket_units.append({"letter": letter, "unit": uid})
	_rebase(res["fen"])
	lifted.emit(sq)
	if presenter != null and presenter.has_method("present_lift"):
		await presenter.present_lift(sq)
	message.emit("Soul Lantern: the piece on %s waits in your pocket. Drop it as a move." % Fen.sq_name(sq))
	busy = false
	if not finished:
		legal = await ChessCore.legal(base_fen, moves)
		legal_ready.emit(legal)
		turn_started.emit("w")
	return res


func _rebase(new_fen: String) -> void:
	base_fen = new_fen
	moves = PackedStringArray()
	fen = base_fen
	var st := Fen.parse(fen)
	board = st["board"]
	pocket = st["pocket"]


func _after_edit(res: Dictionary) -> Dictionary:
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

func engine_skill() -> int:
	var s := encounter.skill
	if encounter.kind == &"fight" or encounter.kind == &"elite":
		s += int(mods.get("skill_bonus", 0))
	if encounter.kind == &"elite":
		s += int(mods.get("elite_skill_bonus", 0))
	return clampi(s, -20, 20)


func engine_movetime() -> int:
	return maxi(10, int(encounter.movetime_ms * float(mods.get("movetime_mult", 1.0))))


func _engine_turn() -> void:
	if finished:
		return
	turn = "b"
	turn_started.emit("b")
	engine_thinking.emit(true)
	var res: Dictionary = await ChessCore.engine_move(base_fen, moves, engine_movetime(), engine_skill(), encounter.depth)
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
	return cp != null and int(cp) <= -(cfg.resign_cp + int(mods.get("resign_cp_delta", 0)))


# --- shared -----------------------------------------------------------------------------------

func _play(uci: String, side: String) -> Dictionary:
	var before := board
	var ev := unit_map.apply_move(uci, before, side, ep_letters)
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
		_place_dropped(ev)
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


## A drop: a lifted run unit comes back, otherwise a relic's pocket piece joins for this fight.
func _place_dropped(ev: Dictionary) -> void:
	var letter := String(ev["drop"])
	for i in pocket_units.size():
		if pocket_units[i]["letter"] == letter:
			var uid: int = pocket_units[i]["unit"]
			pocket_units.remove_at(i)
			unit_map.place(ev["to"], uid)
			ev["mover_unit"] = uid
			return
	var def: PieceDef = Content.piece_by_letter(letter)
	var t := Unit.make(_next_temp_id, def.id if def != null else &"bishop")
	t.temporary = true
	temp_units[t.id] = t
	unit_map.place(ev["to"], t.id)
	ev["mover_unit"] = t.id
	_next_temp_id -= 1


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
	elif reason == "rule" and state == "win":
		reason = "your king reaches the sanctuary"
	elif reason == "no moves":
		reason = "stalemate: the trapped side loses"
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
