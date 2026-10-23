class_name Betza
extends RefCounted
## Reads Betza notation for move diagrams only (cards, codex). The rules live in the chess core;
## this is a picture of them: leapers and riders, move-only, capture-only, cannon hops and
## initial moves, seen from the player's side (forward = +y).

## How the standard pieces move, in Betza.
const STANDARD := {"p": "fmWfcFifmnD", "n": "N", "b": "B", "r": "R", "q": "Q", "k": "K"}
const ATOM := {"W": Vector2i(1, 0), "F": Vector2i(1, 1), "D": Vector2i(2, 0), "N": Vector2i(2, 1),
	"A": Vector2i(2, 2), "H": Vector2i(3, 0), "C": Vector2i(3, 1), "Z": Vector2i(3, 2), "G": Vector2i(3, 3)}
const COMPOUND := {"R": ["W"], "B": ["F"], "Q": ["W", "F"], "K": ["W", "F"]}


## The Betza a piece type moves by: standard letter, royal line, or its own.
static func of(type: StringName) -> String:
	var d: PieceDef = Content.piece(type)
	if d == null:
		return ""
	if d.is_royal():
		return d.royal_betza
	if d.letter != "":
		return STANDARD.get(d.letter, "")
	return d.betza


## Squares within `radius` of the piece: {Vector2i: {move, capture, hop, initial}}.
static func squares(betza: String, radius: int = 3) -> Dictionary:
	var out := {}
	var i := 0
	var mods := ""
	while i < betza.length():
		var ch := betza[i]
		if ch >= "a" and ch <= "z":
			mods += ch
			i += 1
			continue
		if not (COMPOUND.has(ch) or ATOM.has(ch)):
			i += 1
			mods = ""
			continue
		var atoms: Array = COMPOUND.get(ch, [ch])
		var rider := ch == "R" or ch == "B" or ch == "Q"
		i += 1
		if i < betza.length() and betza[i] == ch:
			rider = true
			i += 1
		var num := ""
		while i < betza.length() and betza[i] >= "0" and betza[i] <= "9":
			num += betza[i]
			i += 1
		var limit := int(num) if num != "" else (radius if rider else 1)
		for a in atoms:
			_emit(out, ATOM[a], mods, limit, radius)
		mods = ""
	return out


static func _emit(out: Dictionary, base: Vector2i, mods: String, limit: int, radius: int) -> void:
	var dirs := {}
	for v in [Vector2i(base.x, base.y), Vector2i(base.y, base.x)]:
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				dirs[Vector2i(v.x * sx, v.y * sy)] = true
	var only_move := mods.contains("m") and not mods.contains("c")
	var only_capture := mods.contains("c") and not mods.contains("m")
	var hop := mods.contains("p")
	var initial := mods.contains("i")
	for d: Vector2i in dirs:
		if not _direction_ok(d, mods):
			continue
		for k in range(1, limit + 1):
			var sq := d * k
			if absi(sq.x) > radius or absi(sq.y) > radius:
				break
			# A cannon needs a screen, so its captures start two squares out.
			if hop and k == 1:
				continue
			var e: Dictionary = out.get(sq, {"move": false, "capture": false, "hop": false, "initial": true})
			e["move"] = e["move"] or (not only_capture and not hop)
			e["capture"] = e["capture"] or (not only_move and not hop)
			e["hop"] = e["hop"] or hop
			e["initial"] = e["initial"] and initial
			out[sq] = e


## Betza direction letters (f b l r s v); none = every direction.
static func _direction_ok(d: Vector2i, mods: String) -> bool:
	var any := false
	var ok := false
	for m in ["f", "b", "l", "r", "s", "v"]:
		if not mods.contains(m):
			continue
		any = true
		match m:
			"f":
				ok = ok or d.y > 0
			"b":
				ok = ok or d.y < 0
			"l":
				ok = ok or d.x < 0
			"r":
				ok = ok or d.x > 0
			"s":
				ok = ok or (d.x != 0 and absi(d.x) >= absi(d.y))
			"v":
				ok = ok or (d.y != 0 and absi(d.y) >= absi(d.x))
	return ok or not any
