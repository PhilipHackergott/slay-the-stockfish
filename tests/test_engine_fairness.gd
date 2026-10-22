extends GutTest
## The custom royal piece must not count as material, or every evaluation (and the resign rule)
## is skewed in the player's favour.


func test_symmetric_start_evaluates_near_zero() -> void:
	var gen := VariantGen.build("sts_fair_test", "K", [], PackedStringArray(), false)
	var load_res: Dictionary = await ChessCore.load_variant("sts_fair_test", gen["ini"])
	assert_true(load_res.get("ok", false), "variant loads")
	var fen := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQWBNR w - - 0 1"
	var res: Dictionary = await ChessCore.engine_move(fen, PackedStringArray(), 200, 20, 10)
	assert_true(res.get("ok", false), "engine answers")
	assert_not_null(res.get("score_cp"), "a centipawn score, not a mate")
	assert_lt(absi(int(res.get("score_cp", 9999))), 150, "symmetric start is roughly level: %s" % res)


func test_engine_does_not_resign_before_min_plies() -> void:
	var cfg := RunConfig.new()
	assert_gt(cfg.resign_min_plies, 0, "the resign floor is configured")
