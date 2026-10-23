class_name PositionEdit
extends RefCounted
## Position-edit relics: the game edits the position and the engine only sees the result.
## swap: two of your pieces trade places instead of moving (the engine moves next).
## move: one of your pieces jumps to an empty square in your half instead of moving.
## lift (hybrid): a free action that puts one of your pieces into your pocket; you still move, and
## may drop it as that move, which the engine sees.
## pawn_letters: upper-case letters of the player's pawn-like types ("P" plus custom pawns).


static func _pawn_ok(board: Dictionary, s: int, promo_ranks: PackedInt32Array, pawn_letters: String) -> bool:
	if not pawn_letters.contains(String(board.get(s, "#"))):
		return true
	var r := Fen.rank_of(s)
	return r != 0 and not promo_ranks.has(r)


static func _finish(st: Dictionary, fen: String, side: String) -> Dictionary:
	st["side"] = side
	st["ep"] = "-"
	st["castling"] = "-"
	if side == "b":
		st["halfmove"] = int(st["halfmove"]) + 1
	st["has_pocket"] = Fen.has_pocket(fen) or st.get("has_pocket", false)
	return {"ok": true, "fen": Fen.serialize(st), "reason": ""}


## The pure part: builds the edited FEN or says why not.
## promo_ranks: 0-based ranks where the player's pawns promote (7, plus 6 with the rule relic).
static func swap_fen(fen: String, a: int, b: int, promo_ranks: PackedInt32Array, pawn_letters: String = "P") -> Dictionary:
	var st := Fen.parse(fen)
	if st["side"] != "w":
		return {"ok": false, "reason": "not your turn"}
	if a == b:
		return {"ok": false, "reason": "pick two different pieces"}
	var board: Dictionary = st["board"]
	var pa: String = board.get(a, "")
	var pb: String = board.get(b, "")
	if pa == "" or pb == "" or not Fen.is_white(pa) or not Fen.is_white(pb):
		return {"ok": false, "reason": "swap two of your own pieces"}
	if pa == pb:
		return {"ok": false, "reason": "those pieces are the same type"}
	board[a] = pb
	board[b] = pa
	for s in [a, b]:
		if not _pawn_ok(board, s, promo_ranks, pawn_letters):
			return {"ok": false, "reason": "a pawn may not land there"}
	return _finish(st, fen, "b")


## max_rank: highest 0-based rank the piece may land on (3 = your half).
static func move_fen(fen: String, from: int, to: int, promo_ranks: PackedInt32Array, pawn_letters: String = "P",
		max_rank: int = 3) -> Dictionary:
	var st := Fen.parse(fen)
	if st["side"] != "w":
		return {"ok": false, "reason": "not your turn"}
	var board: Dictionary = st["board"]
	var p: String = board.get(from, "")
	if p == "" or not Fen.is_white(p):
		return {"ok": false, "reason": "move one of your own pieces"}
	if p == VariantGen.PLAYER_KING.to_upper():
		return {"ok": false, "reason": "the king will not be moved by strings"}
	if board.has(to) or st["walls"].has(to):
		return {"ok": false, "reason": "pick an empty square"}
	if Fen.rank_of(to) > max_rank:
		return {"ok": false, "reason": "only within your half (ranks 1-%d)" % (max_rank + 1)}
	board.erase(from)
	board[to] = p
	if not _pawn_ok(board, to, promo_ranks, pawn_letters):
		return {"ok": false, "reason": "a pawn may not land there"}
	return _finish(st, fen, "b")


static func lift_fen(fen: String, sq: int) -> Dictionary:
	var st := Fen.parse(fen)
	if st["side"] != "w":
		return {"ok": false, "reason": "not your turn"}
	var board: Dictionary = st["board"]
	var p: String = board.get(sq, "")
	if p == "" or not Fen.is_white(p):
		return {"ok": false, "reason": "lift one of your own pieces"}
	if p == VariantGen.PLAYER_KING.to_upper():
		return {"ok": false, "reason": "the king cannot be lifted"}
	board.erase(sq)
	st["pocket"] = String(st["pocket"]) + p
	st["has_pocket"] = true
	return _finish(st, fen, "w")


## The full check for edits made instead of a move: own king not left in check, valid position.
static func _validate(core: Node, res: Dictionary) -> Dictionary:
	if not res["ok"]:
		return res
	var check: bool = await core.in_check(res["fen"], "w")
	if check:
		return {"ok": false, "reason": "your king would be in check"}
	var v: Dictionary = await core.validate(res["fen"])
	if not v.get("valid", false):
		return {"ok": false, "reason": "invalid position: %s" % v.get("reason", v.get("error", "?"))}
	return res


static func validate_swap(core: Node, fen: String, a: int, b: int, promo_ranks: PackedInt32Array,
		pawn_letters: String = "P") -> Dictionary:
	return await _validate(core, swap_fen(fen, a, b, promo_ranks, pawn_letters))


static func validate_move(core: Node, fen: String, from: int, to: int, promo_ranks: PackedInt32Array,
		pawn_letters: String = "P") -> Dictionary:
	return await _validate(core, move_fen(fen, from, to, promo_ranks, pawn_letters))


## A free action: it must not give check (you would move again) nor expose your own king.
static func validate_lift(core: Node, fen: String, sq: int) -> Dictionary:
	var res := lift_fen(fen, sq)
	if not res["ok"]:
		return res
	var gives: bool = await core.in_check(res["fen"], "b")
	if gives:
		return {"ok": false, "reason": "lifting it would give check"}
	return await _validate(core, res)
