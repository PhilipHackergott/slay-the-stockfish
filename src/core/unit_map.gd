class_name UnitMap
extends RefCounted
## Which run unit stands on which square during a fight (player side only). The engine only
## sees piece letters; identity, XP and lineage live here.

var by_square: Dictionary = {}


func place(square: int, unit_id: int) -> void:
	by_square[square] = unit_id


func unit_at(square: int) -> int:
	return by_square.get(square, -1)


func square_of(unit_id: int) -> int:
	for s in by_square:
		if by_square[s] == unit_id:
			return s
	return -1


func swap(a: int, b: int) -> void:
	var ua := unit_at(a)
	var ub := unit_at(b)
	by_square.erase(a)
	by_square.erase(b)
	if ua >= 0:
		by_square[b] = ua
	if ub >= 0:
		by_square[a] = ub


## Applies one UCI move given the board before it ({square: letter}) and the side that moves.
## Returns the move event used for XP, losses and presentation.
## pawn_letters: lower-case letters that capture en passant.
func apply_move(uci: String, board: Dictionary, side: String, pawn_letters: String = "p") -> Dictionary:
	var ev := {
		"uci": uci, "side": side, "drop": "", "from": -1, "to": -1, "captured_sq": -1,
		"captured": "", "promotion": "", "mover": "", "mover_unit": -1, "captured_unit": -1,
	}
	if uci.contains("@"):
		var letter := uci.substr(0, 1)
		ev["drop"] = letter.to_upper() if side == "w" else letter.to_lower()
		ev["mover"] = ev["drop"]
		ev["to"] = Fen.sq(uci.substr(2, 2))
		return ev
	var from := Fen.sq(uci.substr(0, 2))
	var to := Fen.sq(uci.substr(2, 2))
	ev["from"] = from
	ev["to"] = to
	if uci.length() > 4:
		var p := uci.substr(4, 1)
		ev["promotion"] = p.to_upper() if side == "w" else p.to_lower()
	var mover: String = board.get(from, "")
	ev["mover"] = mover
	var captured_sq := -1
	if board.has(to):
		captured_sq = to
	elif pawn_letters.contains(mover.to_lower()) and Fen.file_of(from) != Fen.file_of(to):
		captured_sq = Fen.file_of(to) + 8 * Fen.rank_of(from)
		if not board.has(captured_sq):
			captured_sq = -1
	if captured_sq >= 0:
		ev["captured_sq"] = captured_sq
		ev["captured"] = board[captured_sq]
		ev["captured_unit"] = unit_at(captured_sq)
		by_square.erase(captured_sq)
	var mu := unit_at(from)
	ev["mover_unit"] = mu
	if mu >= 0:
		by_square.erase(from)
		by_square[to] = mu
	return ev
