extends GutTest
## Fusion (Graft): recipes, the surviving unit, Command, the Grafting Knife and the Grafter.


func before_each() -> void:
	Run.new_run(5)
	Run.unlocks = []


func _unit(type: StringName, xp: int, perks: Array = []) -> Unit:
	var u := Run.add_unit(type)
	u.xp = xp
	u.perks = PackedStringArray(perks)
	return u


func test_recipes_need_a_partner_and_respect_unlocks() -> void:
	var n := _unit(&"knight", 0)
	var b := _unit(&"bishop", 0)
	var q := _unit(&"queen", 0)
	assert_eq(Run.fusion_result(n, b), &"archbishop")
	assert_eq(Run.fusion_result(b, n), &"archbishop", "order does not matter")
	assert_eq(Run.fusion_result(n, n), &"", "not with itself")
	assert_eq(Run.fusion_result(n, q), &"", "the amazon is locked")
	Run.unlocks = ["guardian_1"]
	assert_eq(Run.fusion_result(n, q), &"amazon")
	var king: Unit = Run.healthy_units().filter(func(u): return Content.piece(u.type).is_royal())[0]
	assert_eq(Run.fusion_result(king, n), &"", "never the king")


func test_the_more_experienced_part_survives_with_one_perk() -> void:
	var n := _unit(&"knight", 10, ["veteran"])
	var r := _unit(&"rook", 4, ["bounty"])
	var before := Run.units.size()
	var fused := Run.fuse(n, r, "bounty")
	assert_eq(fused, n)
	assert_eq(fused.type, &"chancellor")
	assert_eq(fused.xp, 12)
	assert_eq(Array(fused.perks), ["bounty"])
	assert_true(fused.lineage.has("rook") and fused.lineage[fused.lineage.size() - 1] == "chancellor")
	assert_eq(Run.units.size(), before - 1)
	assert_false(Run.units.has(r))
	assert_eq(Run.command_cost(fused), 6, "the rook's 5 + 1, not the chancellor's 8")
	var back := Unit.from_dict(fused.to_dict())
	assert_eq(Run.command_cost(back), 6, "saved")


func test_the_knife_opens_graft_and_the_grafter_fuses_the_best_pair() -> void:
	assert_false(Run.can_graft())
	Run.add_relic(&"grafting_knife")
	assert_true(Run.can_graft())
	var opts: Array = Content.events[&"the_grafter"].options
	var buy: Dictionary = opts[1]
	assert_false(Run.can_afford_option(buy), "already holds the knife")
	for u in Run.units.duplicate():
		if not Content.piece(u.type).is_royal():
			Run.units.erase(u)
	assert_false(Run.can_afford_option(opts[0]), "no pair")
	_unit(&"knight", 0)
	_unit(&"bishop", 0)
	_unit(&"rook", 0)
	assert_true(Run.can_afford_option(opts[0]))
	var text := Run.apply_event_option(opts[0])
	assert_true(text.contains("queen"), "bishop + rook is worth most: " + text)
	assert_eq(Run.stats.get("fusions"), 1)
