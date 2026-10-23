extends GutTest
## v0.2d events: act pools, every option well formed, problems, the Pit, pacts, the Tailor.

const EFFECTS := ["xp_all", "xp_random", "gain_piece", "gain_piece_tier", "gain_relic", "gold", "lose_gold",
	"transform_up", "restore_all", "study_boss", "stitch", "graft", "nothing"]
const COSTS := ["", "gold", "lose_pawn", "lose_random"]


func before_each() -> void:
	Run.new_run(41)
	Run.unlocks = Profile.UNLOCKS.keys().map(func(k): return String(k))


func _option(event: StringName, i: int) -> Dictionary:
	return Content.events[event].options[i]


func _check_part(id: StringName, o: Dictionary) -> void:
	assert_true(EFFECTS.has(String(o.get("effect", "nothing"))), "%s effect %s" % [id, o.get("effect")])
	assert_true(COSTS.has(String(o.get("cost", ""))), "%s cost %s" % [id, o.get("cost")])
	if o.has("source"):
		assert_true(Content.config.relic_odds.has(String(o["source"])), "%s source %s" % [id, o["source"]])
	if o.has("curse"):
		var c := Content.relic(StringName(o["curse"]))
		assert_true(c != null and c.tier == &"curse", "%s curse %s" % [id, o["curse"]])
	if o.has("relic"):
		assert_not_null(Content.relic(StringName(o["relic"])), "%s relic %s" % [id, o["relic"]])
	if o.has("atom"):
		assert_true(Content.STITCH_VALUE.has(String(o["atom"])), "%s atom" % id)


func test_nineteen_events_and_every_option_is_well_formed() -> void:
	assert_eq(Content.events.size(), 19)
	var per_act := {1: 0, 2: 0, 3: 0}
	for id in Content.events:
		var ev: EventDef = Content.events[id]
		assert_eq(ev.acts.size(), 1, "%s belongs to one act" % id)
		for a in ev.acts:
			per_act[a] += 1
		assert_true(ResourceLoader.exists(ev.icon), "%s icon" % id)
		assert_between(ev.options.size(), 2, 4)
		for o in ev.options:
			assert_ne(String(o.get("label", "")), "")
			assert_ne(String(o.get("result", "x")), "", "%s has a result line" % id)
			if o.has("fight"):
				assert_true(o.has("win") and o.has("lose"), "%s fight has win and lose parts" % id)
				_check_part(id, o["win"])
				_check_part(id, o["lose"])
				assert_not_null(Run.event_encounter(o), "%s has its encounter" % id)
				assert_true([&"puzzle", &"skirmish"].has(Run.event_encounter(o).kind))
			else:
				_check_part(id, o)
	assert_eq(per_act, {1: 6, 2: 7, 3: 6})


func test_events_come_from_the_act_pool_first() -> void:
	for a in 3:
		var seen := []
		for i in Content.events.values().filter(func(e): return e.acts.has(a + 1)).size():
			var ev := Run.pick_event()
			assert_true(ev.acts.has(a + 1), "act %d drew %s" % [a + 1, ev.id])
			assert_false(seen.has(ev.id), "no repeat")
			seen.append(ev.id)
		var spill := Run.pick_event()
		assert_false(spill.acts.has(a + 1), "an exhausted pool spills into another act's")
		Run.used_events.clear()
		if a < 2:
			Run.advance_act()


func test_problems_build_in_the_game_variant_and_nothing_wins_at_once() -> void:
	var puzzles := Content.encounters_of(&"puzzle")
	assert_eq(puzzles.size(), 9)
	for t in [1, 2, 3]:
		assert_eq(Content.encounters_of(&"puzzle", t).size(), 3, "three problems of tier %d" % t)
	var gen := VariantGen.build("sts_problem_test", "K", [], PackedStringArray(), false)
	assert_true((await ChessCore.load_variant("sts_problem_test", gen["ini"])).get("ok", false))
	for e in puzzles:
		var enc: EncounterDef = e
		var rows := []
		for r in range(7, -1, -1):
			var row := ""
			var empty := 0
			for f in 8:
				var sq := "abcdefgh"[f] + str(r + 1)
				var l := ""
				if enc.layout.has(sq):
					l = Content.piece(StringName(enc.layout[sq])).letter
				elif enc.player_layout.has(sq):
					var t := StringName(enc.player_layout[sq])
					l = VariantGen.PLAYER_KING.to_upper() if t == &"king" else Content.piece(t).letter.to_upper()
				if l == "":
					empty += 1
					continue
				if empty > 0:
					row += str(empty)
					empty = 0
				row += l
			rows.append(row + (str(empty) if empty > 0 else ""))
		var fen := "/".join(rows) + " w - - 0 1"
		assert_eq(enc.move_limit, 2)
		assert_true((await ChessCore.validate(fen)).get("valid", false), "%s valid (%s)" % [enc.id, fen])
		assert_eq((await ChessCore.mates_in_one(fen)).size(), 0, "%s: nothing mates at once" % enc.id)
		assert_true((await ChessCore.legal(fen, PackedStringArray())).has(enc.solution), "%s key is legal" % enc.id)


func _puzzle_fight(enc: EncounterDef) -> FightController:
	var fight := FightController.new()
	add_child_autofree(fight)
	assert_true(await fight.setup(enc, [], [], Content.config, {}, Run.fight_mods(&"puzzle", enc)))
	fight.set_physics_process(false)
	await fight.begin()
	return fight


func test_a_problem_is_won_by_the_key_and_lost_after_two_moves() -> void:
	var enc: EncounterDef = Content.encounter(&"puzzle_2_2")
	var fight := await _puzzle_fight(enc)
	assert_true(fight.unit_map.unit_at(Fen.sq("c4")) < -1, "the problem's king is a temporary piece")
	assert_true(fight.banner_lines()[0].begins_with("Mate in 2"))
	await fight.try_player_move(enc.solution)
	assert_false(fight.finished)
	var mates: PackedStringArray = await ChessCore.mates_in_one(fight.fen)
	assert_gt(mates.size(), 0, "after the key, every reply allows a mate")
	await fight.try_player_move(mates[0])
	assert_eq(fight.outcome.get("state"), "win", str(fight.outcome, " moves=", fight.moves, " mates=", mates))
	var other := await _puzzle_fight(enc)
	var wrong := ""
	for m in other.legal:
		if m != enc.solution:
			wrong = m
			break
	await other.try_player_move(wrong)
	if not other.finished:
		var mating: PackedStringArray = await ChessCore.mates_in_one(other.fen)
		var quiet := ""
		for m in other.legal:
			if not mating.has(m):
				quiet = m
				break
		await other.try_player_move(quiet)
	assert_eq(other.outcome.get("state"), "loss", str(other.outcome, " moves=", other.moves))
	assert_true(String(other.outcome.get("reason", "")).begins_with("no mate in 2"))


func test_problems_rotate_and_their_parts_pay_out() -> void:
	var opt := _option(&"hanged_problemist", 0)
	Run.add_gold(100)
	var g := Run.gold
	var text := Run.apply_event_fight({"state": "loss", "encounter": "puzzle_1_1"}, opt)
	assert_eq(Run.gold, g - 15, "a failed problem costs its gold")
	assert_ne(text, "")
	assert_false(Run._puzzles(1).any(func(e): return e.id == &"puzzle_1_1"), "a tried problem is not set again")
	var relics := Run.relics.size()
	Run.apply_event_fight({"state": "win", "encounter": "puzzle_1_2"}, opt)
	assert_eq(Run.relics.size(), relics + 1, "a solved problem pays a relic")
	assert_eq(Run._puzzles(1).size(), 1)
	Run.add_relic(&"choir_crown")
	Run.add_relic(&"chapel_bell")
	var mods := Run.fight_mods(&"puzzle", Content.encounter(&"puzzle_1_3"))
	assert_false(bool(mods["engine_first"]), "relics stay out of problems")
	assert_eq(Array(mods["start_pieces"]).size(), 0)


func test_the_pit_takes_the_king_and_the_greenest_and_nothing_lasts() -> void:
	var army := Run.deployed_units().filter(func(u): return not Content.piece(u.type).is_royal())
	army[0].xp = 9
	army[1].xp = 5
	var us := Run.skirmish_units(3)
	assert_eq(us.size(), 4)
	assert_true(Content.piece(us[0].type).is_royal())
	assert_false(us.has(army[0]), "the most experienced stays out")
	var opt := _option(&"the_pit", 0)
	var g := Run.gold
	var fallen: Unit = us[1]
	Run.apply_event_fight({"state": "win", "slain": [fallen.id], "xp": []}, opt)
	assert_eq(Run.gold, g + 30)
	assert_true(fallen.is_healthy(), "no piece stays dead in the pit")
	assert_eq(int(Run.stats["fights_won"]), 0, "the pit is no fight of the run")


func test_pacts_bring_their_curse() -> void:
	var g := Run.gold
	var text := Run.apply_event_option(_option(&"bone_notary", 0))
	assert_eq(Run.gold, g + 90)
	assert_true(Run.has_relic(&"debt_of_bone"))
	assert_string_contains(text, "Debt of Bone")
	assert_string_contains(EventScreen.option_text(_option(&"bone_notary", 0))[1], "Curse: Debt of Bone")
	Run.apply_event_option(_option(&"throne_pact", 0))
	assert_true(Run.has_relic(&"creeping_rot"))


func test_the_ferryman_and_the_oracle() -> void:
	var fallen: Array = Run.units.slice(1, 3)
	for u in fallen:
		u.state = &"slain"
	Run.add_gold(50)
	Run.apply_event_option(_option(&"the_ferryman", 0))
	assert_true(fallen.all(func(u): return u.is_healthy()))
	Run.apply_event_option(_option(&"the_oracle", 0))
	var boss := Content.encounter(&"stockfish")
	var base := int(Run.difficulty_mods()["clock_delta_s"])
	assert_eq(int(Run.fight_mods(&"boss", boss)["clock_delta_s"]), base + 90)
	assert_eq(int(Run.fight_mods(&"fight", boss)["clock_delta_s"]), base, "only against the final boss")


func test_the_tailor_stitches_a_step_that_lasts_until_the_piece_rises() -> void:
	var rook := Run.add_unit(&"rook")
	var bishop: Unit = Run.units.filter(func(u): return u.type == &"bishop")[0]
	var w := Run.stitch_options("W")
	assert_true(w.has(bishop))
	assert_false(w.has(rook), "a rook already steps straight")
	assert_false(w.any(func(u): return u.type == &"pawn" or Content.piece(u.type).is_royal()))
	assert_true(Run.stitch_options("F").has(rook))
	var level := bishop.level
	var o := _option(&"drowned_tailor", 0).duplicate()
	o["unit"] = bishop.id
	Run.add_gold(30)
	var g := Run.gold
	Run.apply_event_option(o)
	assert_eq(Run.gold, g - 30)
	assert_eq(bishop.type, &"bishop__W")
	assert_eq(bishop.level, level, "a stitch is no level")
	var d := Content.piece(bishop.type)
	assert_eq(d.betza, "BW")
	assert_eq(d.value, 5)
	assert_eq(d.display_name, "Stitched Bishop")
	assert_eq(d.look, &"bishop")
	assert_eq(Array(d.upgrades), Array(Content.piece(&"bishop").upgrades), "it rises like a bishop")
	assert_false(Content.pieces.has(bishop.type), "no codex or shop entry")
	assert_false(Run.stitch_options("F").has(bishop), "one stitch per piece")
	var save: Dictionary = JSON.parse_string(JSON.stringify(Run.to_save()))
	Run.new_run(2)
	assert_true(Run.from_save(save))
	assert_eq(Run.unit(bishop.id).type, &"bishop__W")
	var fight := FightController.new()
	add_child_autofree(fight)
	var enc := EncounterDef.new()
	enc.id = &"t_stitch"
	enc.kind = &"fight"
	enc.layout = {"e8": &"king", "a7": &"pawn"}
	var units := Run.healthy_units()
	assert_true(await fight.setup(enc, units, [], Content.config, Run.formation(units), {}))
	assert_true(fight.letters.has(&"bishop__W"), "the stitched piece is a custom piece in the variant")
	assert_true(fight.variant_ini.contains(":BW"))
