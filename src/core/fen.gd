class_name Fen
extends RefCounted
## FEN helpers. Squares are indices 0..63: file + 8 * rank (a1 = 0, h8 = 63).
## Pockets use Fairy-Stockfish notation, `board[B]`, upper case = white. Walls ("*") are kept apart
## from the pieces in "walls"; an n-check count ("3+3", checks each side still needs) in "checks".

const FILES := "abcdefgh"


static func sq(square_name: String) -> int:
	return FILES.find(square_name[0]) + 8 * (int(square_name.substr(1)) - 1)


static func sq_name(i: int) -> String:
	return FILES[i % 8] + str(i / 8 + 1)


static func file_of(i: int) -> int:
	return i % 8


static func rank_of(i: int) -> int:
	return i / 8


static func is_white(letter: String) -> bool:
	return letter != "" and letter == letter.to_upper()


static func parse(fen: String) -> Dictionary:
	var parts := fen.strip_edges().split(" ")
	var placement: String = parts[0]
	var pocket := ""
	var lb := placement.find("[")
	if lb >= 0:
		pocket = placement.substr(lb + 1, placement.find("]") - lb - 1)
		placement = placement.substr(0, lb)
	var board := {}
	var walls: Array = []
	var rows := placement.split("/")
	for r in rows.size():
		var rank := 7 - r
		var file := 0
		var row: String = rows[r]
		for c in row:
			if c.is_valid_int():
				file += int(c)
			elif c == "~" or c == "+":
				continue
			elif c == "*":
				walls.append(file + 8 * rank)
				file += 1
			else:
				board[file + 8 * rank] = c
				file += 1
	var checks := ""
	if parts.size() > 4 and parts[4].contains("+"):
		checks = parts[4]
		parts.remove_at(4)
	return {
		"board": board,
		"walls": walls,
		"checks": checks,
		"pocket": pocket,
		"side": parts[1] if parts.size() > 1 else "w",
		"castling": parts[2] if parts.size() > 2 else "-",
		"ep": parts[3] if parts.size() > 3 else "-",
		"halfmove": int(parts[4]) if parts.size() > 4 else 0,
		"fullmove": int(parts[5]) if parts.size() > 5 else 1,
	}


static func serialize(state: Dictionary) -> String:
	var board: Dictionary = state.get("board", {})
	var walls: Array = state.get("walls", [])
	var rows := PackedStringArray()
	for r in range(7, -1, -1):
		var row := ""
		var empty := 0
		for f in 8:
			var letter: String = "*" if walls.has(f + 8 * r) else board.get(f + 8 * r, "")
			if letter == "":
				empty += 1
				continue
			if empty > 0:
				row += str(empty)
				empty = 0
			row += letter
		if empty > 0:
			row += str(empty)
		rows.append(row)
	var placement := "/".join(rows)
	var pocket: String = state.get("pocket", "")
	if pocket != "" or state.get("has_pocket", false):
		placement += "[%s]" % pocket
	var ep: String = state.get("ep", "-")
	var checks: String = state.get("checks", "")
	if checks != "":
		ep += " " + checks
	return "%s %s %s %s %d %d" % [placement, state.get("side", "w"), state.get("castling", "-"),
		ep, int(state.get("halfmove", 0)), int(state.get("fullmove", 1))]


## Checks each side still needs ({"w": n, "b": n}), or {} without an n-check count.
static func checks_left(fen: String) -> Dictionary:
	var c: String = parse(fen)["checks"]
	if c == "":
		return {}
	var p := c.split("+")
	return {"w": int(p[0]), "b": int(p[1])}


## Fairy-Stockfish writes "[]" once a pocket exists, even when it is empty.
static func has_pocket(fen: String) -> bool:
	return fen.split(" ")[0].contains("[")
