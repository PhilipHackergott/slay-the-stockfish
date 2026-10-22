extends GutTest
## No encounter may lose on the player's first move: every layout must survive a mate in 1 from
## open files (back-rank mates) and from a classic first rank.

const LETTER := {&"pawn": "p", &"knight": "n", &"bishop": "b", &"rook": "r", &"queen": "q", &"king": "k"}
## White armies as square → letter: rooks on every open file, and the classic first rank.
const ARMIES := [
	{"a1": "R", "b1": "R", "c1": "R", "d1": "R", "e1": "W", "f1": "R", "g1": "R", "h1": "R"},
	{"a1": "R", "b1": "N", "c1": "B", "d1": "Q", "e1": "W", "f1": "B", "g1": "N", "h1": "R",
		"c2": "P", "d2": "P", "e2": "P", "f2": "P"},
]


func _fen(board: Dictionary) -> String:
	var rows := PackedStringArray()
	for rank in range(7, -1, -1):
		var row := ""
		var empty := 0
		for file in 8:
			var name := "abcdefgh"[file] + str(rank + 1)
			if board.has(name):
				if empty > 0:
					row += str(empty)
					empty = 0
				row += String(board[name])
			else:
				empty += 1
		if empty > 0:
			row += str(empty)
		rows.append(row)
	return "/".join(rows) + " w - - 0 1"


func test_no_encounter_allows_mate_in_one() -> void:
	var gen := VariantGen.build("sts_m1_test", "K", [], PackedStringArray(), false)
	assert_true((await ChessCore.load_variant("sts_m1_test", gen["ini"])).get("ok", false), "variant loads")
	for id: StringName in Content.encounters:
		var enc: EncounterDef = Content.encounters[id]
		for army: Dictionary in ARMIES:
			var board := army.duplicate()
			for square: String in enc.layout:
				board[square] = LETTER[enc.layout[square]]
			var fen := _fen(board)
			var mates := PackedStringArray()
			for move in await ChessCore.legal(fen, PackedStringArray()):
				var res: Dictionary = await ChessCore.result(fen, PackedStringArray([move]))
				if res.get("state", "") == "win":
					mates.append(move)
			assert_eq(mates.size(), 0, "%s mated in one by %s (%s)" % [id, mates, fen])
