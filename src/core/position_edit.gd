class_name PositionEdit
extends RefCounted
## Position-edit relics: the game edits the position and the engine only sees the result.
## MVP: swap two of your own pieces instead of moving (the engine moves next).


## The pure part: builds the edited FEN or says why not.
## promo_ranks: 0-based ranks where the player's pawns promote (7, plus 6 with the rule relic).
static func swap_fen(fen: String, a: int, b: int, promo_ranks: PackedInt32Array) -> Dictionary:
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
		if board[s] == "P":
			var r := Fen.rank_of(s)
			if r == 0 or promo_ranks.has(r):
				return {"ok": false, "reason": "a pawn may not land there"}
	st["side"] = "b"
	st["ep"] = "-"
	st["castling"] = "-"
	st["halfmove"] = int(st["halfmove"]) + 1
	st["has_pocket"] = Fen.has_pocket(fen)
	return {"ok": true, "fen": Fen.serialize(st), "reason": ""}


## The full check: own king not left in check, and the position passes FEN validation.
static func validate_swap(core: Node, fen: String, a: int, b: int, promo_ranks: PackedInt32Array) -> Dictionary:
	var res := swap_fen(fen, a, b, promo_ranks)
	if not res["ok"]:
		return res
	var check: bool = await core.in_check(res["fen"], "w")
	if check:
		return {"ok": false, "reason": "your king would be in check"}
	var v: Dictionary = await core.validate(res["fen"])
	if not v.get("valid", false):
		return {"ok": false, "reason": "invalid position: %s" % v.get("reason", v.get("error", "?"))}
	return res
