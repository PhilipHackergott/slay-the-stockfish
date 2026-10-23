extends GutTest
## Elite affixes: rolled per act with the map, saved with it, and applied to the elite's fight.


func _elites() -> Array:
	return Run.map.nodes.filter(func(n): return n["type"] == &"elite")


func test_each_act_rolls_its_affix_count_from_its_pool() -> void:
	var seen := 0
	for s in 20:
		Run.new_run(300 + s)
		for a in 3:
			if a > 0:
				Run.act_index = a
				Run._build_act_map()
			var act := Run.current_act()
			for n in _elites():
				var list: Array = n["affixes"]
				assert_between(list.size(), act.affix_min, act.affix_max, "act %d" % (a + 1))
				for id in list:
					assert_true(act.affix_pool.has(String(id)))
					assert_not_null(Content.affix(id))
				var unique := {}
				for id in list:
					unique[id] = true
				assert_eq(unique.size(), list.size(), "no affix twice")
				seen += list.size()
			var back := RunMap.from_dict(Run.map.to_dict())
			for n in _elites():
				assert_eq(back.node(n["id"])["affixes"], n["affixes"])
	assert_gt(seen, 0)
	for n in Run.map.nodes.filter(func(n): return n["type"] != &"elite"):
		assert_true(n["affixes"].is_empty(), "only elites carry affixes")


func test_affixes_reach_the_elite_fight() -> void:
	Run.new_run(5)
	var n: Dictionary = _elites()[0]
	Run.current_node = n["id"]
	var enc := Content.encounter(n["encounter"])
	n["affixes"] = []
	var plain := Run.fight_mods(&"elite", enc)
	n["affixes"] = [&"vigilant", &"brutal", &"hurried", &"reinforced", &"deep_thought", &"relentless"]
	var m := Run.fight_mods(&"elite", enc)
	assert_true(m["engine_first"])
	assert_eq(int(m["affix_skill"]), 3)
	assert_eq(int(m["clock_delta_s"]), int(plain["clock_delta_s"]) - 60)
	assert_almost_eq(float(m["movetime_mult"]), float(plain["movetime_mult"]) * 2.0, 0.001)
	assert_true(m["no_increment"])
	assert_eq(m["reinforcements"].size(), plain["reinforcements"].size() + 2)
	assert_eq(m["banner"].filter(func(l): return String(l).begins_with("Elite · ")).size(), 6)
	assert_false(Run.fight_mods(&"fight", enc).has("affix_skill"), "only the elite fight reads them")
