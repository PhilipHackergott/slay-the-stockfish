extends GutTest
## The run-start draft: the king alone, a 7-point budget, basics and specials, refunds, leftovers.


func before_each() -> void:
	Run.new_run(12)


func test_a_run_starts_with_the_king_and_seven_points() -> void:
	assert_eq(Run.units.size(), 1)
	assert_true(Content.piece(Run.units[0].type).is_royal())
	assert_true(Run.draft_open())
	assert_eq(Run.draft_points(), 7)
	var offers := Run.draft_offers()
	for t in Content.config.draft_basics:
		assert_true(offers.has(t), "%s always on offer" % t)
	var specials: Array = Run.draft["specials"]
	assert_lte(specials.size(), Content.config.draft_specials)
	for t in specials:
		assert_false(Content.config.draft_basics.has(t), "%s is not a basic" % t)
		assert_lte(Content.piece(t).value, 7)


func test_buying_refunding_and_leftover_gold() -> void:
	var n := Run.draft_buy(&"knight")
	assert_not_null(n)
	assert_eq(Run.draft_points(), 4)
	assert_false(Run.can_draft(&"rook"), "a rook costs 5")
	assert_true(Run.draft_refund(n))
	assert_eq(Run.draft_points(), 7)
	assert_false(Run.units.has(n))
	assert_not_null(Run.draft_buy(&"rook"))
	assert_not_null(Run.draft_buy(&"pawn"))
	var gold := Run.gold
	assert_eq(Run.finish_draft(), Content.config.draft_leftover_gold)
	assert_eq(Run.gold, gold + Content.config.draft_leftover_gold)
	assert_false(Run.draft_open())
	assert_null(Run.draft_buy(&"pawn"), "the draft is closed")
	assert_false(Run.draft_refund(Run.units[1]), "no refunds after the draft")


func test_a_special_is_one_of_a_kind_until_refunded() -> void:
	var specials: Array = Run.draft["specials"]
	if specials.is_empty():
		pass_test("no special rolled for this seed")
		return
	var t: StringName = specials[0]
	var u := Run.draft_buy(t)
	assert_not_null(u)
	assert_false(Run.draft_offers().has(t))
	Run.draft_refund(u)
	assert_true(Run.draft_offers().has(t))


func test_auto_draft_spends_everything_and_harder_runs_get_less() -> void:
	Run.auto_draft()
	assert_eq(Run.draft_points(), 0)
	assert_gt(Run.units.size(), 2)
	Run.new_run(12, 4)
	var removed := 0
	for t in Run.difficulty_mods()["remove_from_start"]:
		removed += Content.piece(t).value
	assert_eq(Run.draft_points(), 7 - removed)
