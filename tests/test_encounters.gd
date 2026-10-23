extends GutTest
## No encounter may lose on the player's first move: every layout must survive a mate in 1 from
## open files (back-rank mates) and from a classic first rank. Fairy enemies get their per-fight
## letters exactly as a fight would assign them.

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


func _customs(enc: EncounterDef) -> Array:
	var out: Array = []
	for id in enc.layout.values():
		var def: PieceDef = Content.piece(StringName(id))
		assert_not_null(def, "%s uses a known piece (%s)" % [enc.id, id])
		if def != null and def.letter == "" and not def.is_royal() and not out.any(func(c): return c["id"] == def.id):
			out.append({"id": def.id, "betza": def.betza, "pawn_like": def.pawn_like, "ini_extra": def.ini_extra})
	return out


func test_every_encounter_piece_exists_and_kinds_are_known() -> void:
	for id: StringName in Content.encounters:
		var enc: EncounterDef = Content.encounters[id]
		assert_true([&"fight", &"elite", &"guardian", &"boss"].has(enc.kind), "%s kind %s" % [id, enc.kind])
		assert_true(enc.layout.values().has(&"king") or enc.layout.values().has("king"), "%s has an engine king" % id)
		_customs(enc)


## Every encounter an act can roll, with that act's reinforcements: valid, no check on the player,
## no mate in one from the classic first rank, and the enemy reaches its share of your Command.
func test_reinforced_layouts_are_valid_and_safe() -> void:
	Run.new_run(1)
	var n := 0
	for ai in Content.acts.size():
		Run.act_index = ai
		var act := Run.current_act()
		var pairs: Array = []
		for t in [act.fight_tier, act.late_fight_tier]:
			for e in Content.encounters_of(&"fight", t):
				pairs.append([&"fight", e])
		for e in Content.encounters_of(&"elite", act.elite_tier):
			pairs.append([&"elite", e])
		var fin: EncounterDef = Content.encounter(act.final_encounter)
		pairs.append([fin.kind, fin])
		for p in pairs:
			var kind: StringName = p[0]
			var enc: EncounterDef = p[1]
			var extra := Run.reinforcements(enc, kind)
			var full := enc.duplicate()
			var layout: Dictionary = enc.layout.duplicate()
			var material := Run.layout_material(layout)
			for e in extra:
				layout[e[0]] = StringName(e[1])
				material += Content.piece(StringName(e[1])).value
			full.layout = layout
			if Run.enemy_target(kind) > 0.0:
				assert_true(material >= Run.enemy_target(kind) - 0.001 or extra.size() > 0,
					"act %d %s %s: %d material for a target of %.1f" % [ai + 1, kind, enc.id, material, Run.enemy_target(kind)])
			n += 1
			var gen := VariantGen.build("sts_rf_test_%d" % n, "K", _customs(full), PackedStringArray(), false)
			assert_true((await ChessCore.load_variant("sts_rf_test_%d" % n, gen["ini"])).get("ok", false))
			var board: Dictionary = ARMIES[1].duplicate()
			for square: String in layout:
				var t := StringName(layout[square])
				var def: PieceDef = Content.piece(t)
				board[square] = def.letter if def.letter != "" else String(gen["letters"][t])
			var fen := _fen(board)
			var tag := "act %d %s %s +%d (%s)" % [ai + 1, kind, enc.id, extra.size(), fen]
			assert_true((await ChessCore.validate(fen)).get("valid", false), "%s is valid" % tag)
			assert_false(await ChessCore.in_check(fen, "w"), "%s does not check the player" % tag)
			assert_eq(await ChessCore.mates_in_one(fen), PackedStringArray(), "%s has no mate in one" % tag)
	Run.act_index = 0


func test_no_encounter_allows_mate_in_one() -> void:
	var n := 0
	for id: StringName in Content.encounters:
		var enc: EncounterDef = Content.encounters[id]
		n += 1
		var gen := VariantGen.build("sts_m1_test_%d" % n, "K", _customs(enc), PackedStringArray(), false)
		assert_false(gen.has("error"), "%s builds a variant" % id)
		assert_true((await ChessCore.load_variant("sts_m1_test_%d" % n, gen["ini"])).get("ok", false), "%s variant loads" % id)
		var letters: Dictionary = gen["letters"]
		for army: Dictionary in ARMIES:
			var board := army.duplicate()
			for square: String in enc.layout:
				var t := StringName(enc.layout[square])
				var def: PieceDef = Content.piece(t)
				board[square] = def.letter if def.letter != "" else String(letters[t])
			var fen := _fen(board)
			assert_true((await ChessCore.validate(fen)).get("valid", false), "%s position is valid (%s)" % [id, fen])
			var mates: PackedStringArray = await ChessCore.mates_in_one(fen)
			assert_eq(mates.size(), 0, "%s mated in one by %s (%s)" % [id, mates, fen])
