extends GutTest
## Every screen, filled with worst-case content, keeps its text inside its boxes and the screen:
## each visible control laid out by a container lies within its parent and within 1920x1080.
## Content under a ScrollContainer may be taller than the screen (that is what the scroll is for).

const SCREEN := Vector2(1920, 1080)
const TOLERANCE := 2.0

var _host: Control


func before_all() -> void:
	Profile.path = "user://profile_test.json"
	Run.save_path = "user://run_test.json"


func before_each() -> void:
	Profile.reset()
	Run.new_run(41)
	_host = Control.new()
	_host.size = SCREEN
	_host.theme = UiKit.theme()
	add_child_autofree(_host)


func after_all() -> void:
	Run.delete_save()


## A big army with long names, every relic, slain pieces and pending level-ups.
func _worst_case() -> void:
	for t in [&"leaping_queen", &"shieldbearer", &"dragon_horse", &"chancellor", &"skirmisher", &"archbishop",
			&"siege_queen", &"spearman", &"outrider", &"knibis", &"centaur", &"commoner"]:
		Run.add_unit(t)
	for id in Content.relics.keys():
		Run.add_relic(id)
	for u in Run.units:
		u.xp = 40
	Run.units[3].state = &"slain"
	Run.units[5].state = &"slain"
	Run.add_gold(900)


func _show(c: Control) -> void:
	_host.add_child(c)
	for i in 6:
		await get_tree().process_frame


func _check(screen: Control, label: String) -> void:
	var bad: Array = []
	_walk(screen, false, bad)
	assert_eq(bad.size(), 0, "%s overflows:\n%s" % [label, "\n".join(bad.slice(0, 12))])


func _walk(c: Control, scrolled: bool, bad: Array) -> void:
	if not c.is_visible_in_tree():
		return
	var p := c.get_parent() as Control
	# Buttons hold a content column (cards, options) plus decoration that may overhang (map rings).
	if not scrolled and p != null and (p is Container or (p is Button and c is Container)):
		var r := c.get_global_rect()
		var pr := p.get_global_rect().grow(TOLERANCE)
		var sr := Rect2(Vector2.ZERO, SCREEN).grow(TOLERANCE)
		if r.size.x > 0.5 and r.size.y > 0.5 and (not pr.encloses(r) or not sr.encloses(r)):
			bad.append("%s %s in %s %s (%s)" % [c.get_class(), r, p.get_class(), p.get_global_rect(), _text(c)])
	# A wrapping label squeezed to a sliver stacks its letters (a box sized by its own content).
	if c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF and (c as Label).text.length() > 8 \
			and c.size.x < 60.0:
		bad.append("collapsed Label %s (%s)" % [c.get_global_rect(), _text(c)])
	for ch in c.get_children():
		if ch is Control:
			_walk(ch, scrolled or c is ScrollContainer, bad)


func _text(c: Control) -> String:
	if c is Label:
		return (c as Label).text.left(50)
	if c is Button:
		return (c as Button).text.left(50)
	return String(c.name)


func test_map_fits() -> void:
	_worst_case()
	var m := MapScreen.new()
	await _show(m)
	_check(m, "map")
	var badges := m.find_children("*", "Panel", true, false).filter(func(p): return p.get_parent() is Button)
	assert_gt(badges.size(), 0, "the map shows node badges")
	for p in badges:
		assert_ne(p.tooltip_text, "", "every badge explains itself on hover")
		assert_eq(p.mouse_filter, Control.MOUSE_FILTER_PASS, "clicks reach the node")


func test_reward_fits() -> void:
	_worst_case()
	var o := {"state": "win", "reason": "checkmate: the engine's king falls", "slain": [], "plies": 40,
		"xp": [{"unit": 6, "amount": 3, "captured": "n"}, {"unit": 2, "amount": 1, "captured": "p"}],
		"encounter": &"bishop_of_ash", "gold": 40, "overflow_gold": 12}
	var r := RewardScreen.new().setup(o, &"guardian")
	await _show(r)
	_check(r, "reward")


func test_campfire_fits() -> void:
	_worst_case()
	for u in Run.units.slice(1, 4):
		u.state = &"slain"
	var c := CampfireScreen.new()
	await _show(c)
	_check(c, "campfire")
	for step in ["mend", "temper", "rite", "kindle", "cleanse"]:
		c.open_step(step)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(c, "campfire %s" % step)
	var risers := Run.healthy_units().filter(func(u): return not Run.upgrade_options(u).is_empty())
	c._temper_into(risers[0])
	await get_tree().process_frame
	await get_tree().process_frame
	_check(c, "campfire temper into")
	c._pick_heir(Run.healthy_units()[1])
	await get_tree().process_frame
	await get_tree().process_frame
	_check(c, "campfire rite heir")


func test_shop_fits() -> void:
	_worst_case()
	Run.relics.clear()
	var s := ShopScreen.new().setup(3)
	await _show(s)
	_check(s, "shop")


func test_treasure_fits() -> void:
	_worst_case()
	Run.add_relic(&"black_candle")
	var t := TreasureScreen.new()
	await _show(t)
	_check(t, "treasure")


func test_every_event_fits() -> void:
	_worst_case()
	Run.add_unit(&"chancellor")
	Run.add_unit(&"dragon_horse")
	for id in Content.events:
		var e := EventScreen.new().setup(Content.events[id])
		await _show(e)
		_check(e, "event %s" % id)
		for o in e.event.options:
			if String(o.get("effect", "")) == "stitch":
				e._stitch_step(o)
				await get_tree().process_frame
				await get_tree().process_frame
				_check(e, "event %s stitch %s" % [id, o["atom"]])
		e.queue_free()
	var long := "The panel goes dark with a sound like a sigh. A drawer slides open. You gain the Stockfish's Tooth, and Creeping Rot clings to you."
	var r := EventScreen.new().setup(Content.events[&"engine_riddle"], long)
	await _show(r)
	_check(r, "event result")


func test_relic_pick_fits() -> void:
	var ids: Array = Content.relics.keys()
	ids.sort_custom(func(a, b): return Content.relic(a).description.length() > Content.relic(b).description.length())
	var p := RelicPick.new().setup("Choose a Relic", "Every run begins with one.", ids.slice(0, 4), true)
	await _show(p)
	_check(p, "relic pick")


func test_formation_and_codex_fit() -> void:
	_worst_case()
	var f := FormationModal.new()
	await _show(f)
	_check(f, "formation")
	f.queue_free()
	var c := CodexModal.open_codex(_host)
	await _show(Control.new())
	_check(c, "codex")


func test_settings_fit() -> void:
	var s := SettingsModal.open_settings(_host)
	await _show(Control.new())
	_check(s, "settings")
