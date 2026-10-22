class_name VariantGen
extends RefCounted
## Writes one Fairy-Stockfish variant section per fight. The rules library and the engine both
## load it, so the game and the engine always agree on what is legal.

const PLAYER_KING := "w"
## Free letters for custom pieces (p n b r q k are standard, w is the player's king). The engine
## allows 26 piece types per fight, standard ones included, which leaves these 19.
const LETTER_POOL := "acdefghijlmostuvxyz"


## Letters for showing custom pieces outside a fight (map, title): the same pool, in order.
static func assign_letters(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		if not out.has(id) and out.size() < LETTER_POOL.length():
			out[id] = LETTER_POOL[out.size()]
	return out


## custom: Array of {id, betza, pawn_like, ini_extra (PackedStringArray, "{L}" = the letter)} for
## every non-standard piece type on either side. relic_lines: rule-relic lines. pocket: drops on.
## Returns {ini, letters: {id: letter}} or {error}.
static func build(variant_name: String, king_betza: String, custom: Array, relic_lines: PackedStringArray,
		pocket: bool) -> Dictionary:
	var lines := PackedStringArray([
		"[%s:chess]" % variant_name,
		"king = k",
		"customPiece1 = %s:%s" % [PLAYER_KING, king_betza],
		"extinctionPieceTypes = %s" % PLAYER_KING,
		"extinctionPseudoRoyal = true",
		"extinctionValue = loss",
		"castling = false",
		# 0 means "no override" to the engine; without this it values the royal piece like a commoner.
		"pieceValueMg = %s:1" % PLAYER_KING,
		"pieceValueEg = %s:1" % PLAYER_KING,
	])
	var letters := {}
	var extra := PackedStringArray()
	var pawn_letters := "p"
	for c in custom:
		var id: StringName = c["id"]
		if letters.has(id):
			continue
		if letters.size() >= LETTER_POOL.length():
			return {"error": "piece-type budget exceeded (%d custom types)" % (letters.size() + 1)}
		var letter := LETTER_POOL[letters.size()]
		letters[id] = letter
		lines.append("customPiece%d = %s:%s" % [letters.size() + 1, letter, c["betza"]])
		if c.get("pawn_like", false):
			pawn_letters += letter
		for line in c.get("ini_extra", PackedStringArray()):
			extra.append(String(line).replace("{L}", letter))
	# Custom pawns promote like pawns; p stays first (the engine's main pawn type).
	if pawn_letters.length() > 1:
		lines.append("promotionPawnTypesWhite = %s" % pawn_letters)
		lines.append("promotionPawnTypesBlack = %s" % pawn_letters)
	lines.append_array(extra)
	if pocket:
		lines.append_array(PackedStringArray([
			"pieceDrops = true", "capturesToHand = false", "dropRegionWhite = *1 *2 *3 *4"]))
	lines.append_array(relic_lines)
	return {"ini": "\n".join(lines) + "\n", "letters": letters}
