extends Node
## Game flow: title -> starting relic -> act intro -> map -> nodes (fight, elite, campfire, event,
## shop, guardian) -> next act ... -> boss -> end. The run is saved whenever the map shows.
## Command line (after `--`): --seed=N, --difficulty=N, --screen=title|relic|map|fight|elite|guardian|
## boss|reward|campfire|event|shop|codex|settings|formation|pause|act|end, --act=N (0-based),
## --relics=id,id, --units=type,type, --autoplay (plays a whole run unattended), --shot=path.png
## [--shot-delay=s], --quit-after-shot, --quit-on-end, --isolated (separate profile and save files).

var world: World
var ui_root: Control
var screen: Control
var fight: FightController
var dev: PanelContainer
var args: Dictionary = {}
var autoplay := false
var _run_unlocks: Array = []
var _pause: UiModal


func _ready() -> void:
	args = _parse_args()
	autoplay = args.has("autoplay")
	if autoplay or args.has("isolated") or (args.has("screen") and args["screen"] != "title"):
		Profile.path = "user://profile_isolated.json"
		Profile.load_profile()
		Run.save_path = "user://run_isolated.json"
	Engine.time_scale = float(args.get("speed", "1"))
	world = World.new()
	world.name = "World"
	add_child(world)
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	UiKit.full(ui_root)
	ui_root.theme = UiKit.theme()
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)
	UiKit.install_cursor()
	SettingsModal.apply_window()
	Audio.apply_settings()
	_build_dev_panel()
	var ping: Dictionary = await ChessCore.call_core({"op": "ping"})
	if not ping.get("ok", false):
		push_warning("chess core unavailable: %s" % ping.get("error", "?"))
	print("STS BOOT OK core=%s kit=%s" % ["ok" if ping.get("ok", false) else "missing", "yes" if UiKit.has_kit() else "no"])
	if args.has("quit-after-boot"):
		await get_tree().create_timer(0.5).timeout
		get_tree().quit()
		return
	if args.has("shot"):
		_shoot_later(String(args["shot"]), float(args.get("shot-delay", "6")))
	_jump(String(args.get("screen", "title")))


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var i := s.find("=")
		if i > 0:
			out[s.substr(0, i)] = s.substr(i + 1)
		else:
			out[s] = "1"
	return out


func _set_screen(c: Control) -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	screen = c
	if c != null:
		ui_root.add_child(c)
	ui_root.move_child(dev, -1)


# --- flow -----------------------------------------------------------------------------------------

func _jump(where: String) -> void:
	if where == "title":
		_show_title()
		return
	_begin_run(int(args.get("seed", "7")), int(args.get("difficulty", "0")))
	for i in int(args.get("act", "0")):
		Run.advance_act()
	for id in String(args.get("relics", "")).split(",", false):
		Run.add_relic(StringName(id))
	for t in String(args.get("units", "")).split(",", false):
		Run.add_unit(StringName(t))
	Run.add_gold(int(args.get("gold", "0")))
	match where:
		"relic":
			_show_start_relics()
		"map":
			_show_map()
		"fight", "elite", "guardian", "boss", "shop":
			_enter(_first_node_of(StringName(where)))
		"reward":
			Run.unit(2).xp += 3
			var o := {"state": "win", "reason": "checkmate: the engine's king falls", "slain": [],
				"xp": [{"unit": 6, "amount": 3, "captured": "n"}, {"unit": 2, "amount": 1, "captured": "p"}],
				"plies": 31, "encounter": &"bishop_of_ash"}
			Run.apply_fight(o, &"elite")
			_show_reward(o, &"elite")
		"campfire":
			Run.units[2].state = &"slain"
			_set_screen(_campfire())
		"event":
			_show_event()
		"codex":
			_show_map()
			CodexModal.open_codex(ui_root)
		"settings":
			_show_map()
			SettingsModal.open_settings(ui_root)
		"formation":
			_show_map()
			var f := FormationModal.open_formation(ui_root)
			f.saved.connect(_show_map)
		"pause":
			_show_map()
			_toggle_pause()
		"act":
			_show_act_intro(_show_map)
		"end":
			_show_end(true, "checkmate: the engine's king falls")
		_:
			_show_title()


func _begin_run(seed_value: int, difficulty: int) -> void:
	Run.new_run(seed_value, difficulty)
	_run_unlocks.clear()


func _first_node_of(t: StringName) -> int:
	for n in Run.map.nodes:
		if n["type"] == t:
			return n["id"]
	return Run.map.start_nodes()[0]


func _show_title() -> void:
	world.rig.set_mode("orbit")
	_show_board_tableau()
	var t := TitleScreen.new()
	t.begin.connect(func(s: int, d: int):
		Run.delete_save()
		_begin_run(s, d)
		_show_start_relics())
	t.continue_run.connect(func():
		if Run.load_game():
			_show_map()
		else:
			_show_title())
	_set_screen(t)
	if autoplay:
		await get_tree().create_timer(0.5).timeout
		_begin_run(int(args.get("seed", "7")), int(args.get("difficulty", "0")))
		_show_start_relics()


## The full boss position as a backdrop for the title.
func _show_board_tableau() -> void:
	Content.clear_fight_letters()
	var b := {}
	var back := "rnbqkbnr"
	for f in 8:
		b[f] = back[f].to_upper() if back[f] != "k" else VariantGen.PLAYER_KING.to_upper()
		b[8 + f] = "P"
		b[48 + f] = "p"
		b[56 + f] = back[f]
	world.board_view.setup_position(b, null, false)


func _show_start_relics() -> void:
	var pick := RelicPick.new().setup("Choose a Relic", "Every run begins with one. Choose how you will cheat the engine.",
		Run.relic_choices(Content.config.start_relic_choices), false)
	pick.picked.connect(func(id: StringName):
		Run.add_relic(id)
		_show_act_intro(_show_map))
	_set_screen(pick)
	if autoplay:
		await get_tree().create_timer(0.3).timeout
		if is_instance_valid(pick):
			pick.picked.emit(Run.relic_choices(1)[0])


## A card for the act about to begin (name, subtitle, flavour), then `then`.
func _show_act_intro(then: Callable) -> void:
	world.rig.set_mode("orbit")
	var act := Run.current_act()
	if act == null:
		then.call()
		return
	var holder := Control.new()
	UiKit.full(holder)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_screen(holder)
	var m := UiModal.new().setup(act.display_name, 900, false, act.subtitle)
	holder.add_child(m)
	var roman := ["I", "II", "III", "IV", "V"]
	var cap := UiKit.caption("Act %s" % roman[mini(Run.act_index, 4)], 22, UiKit.EMBER)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.body.add_child(cap)
	var fl := UiKit.label(act.flavor, 23, UiKit.BONE, true)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.body.add_child(fl)
	var fin: EncounterDef = Content.encounter(act.final_encounter)
	if fin != null:
		m.body.add_child(UiKit.divider(420, true))
		var g := UiKit.label("At the bottom waits %s." % fin.display_name, 20, UiKit.MUTED)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.body.add_child(g)
	var go := UiKit.button("Descend", func(): then.call(), 26, true)
	go.custom_minimum_size.x = 300
	m.footer.add_child(go)
	Audio.play("check_bell", -6.0)
	if autoplay:
		await get_tree().create_timer(0.3).timeout
		if is_instance_valid(holder):
			then.call()


func _show_map() -> void:
	world.rig.set_mode("map")
	Run.save_game()
	_display_army()
	var m := MapScreen.new()
	m.node_chosen.connect(func(id: int):
		Audio.play("map_step")
		_enter(id))
	m.formation_changed.connect(_show_map)
	_set_screen(m)
	Audio.music("music_map")
	Audio.ambience("ambience_wind")
	if autoplay:
		await get_tree().create_timer(0.4).timeout
		var av := Run.available_nodes()
		if not av.is_empty() and is_instance_valid(m) and screen == m:
			_enter(av[0])


func _display_army() -> void:
	var dp := Run.display_position()
	world.board_view.setup_position(dp["board"], dp["units"], true)


func _enter(id: int) -> void:
	var node := Run.enter_node(id)
	match node["type"]:
		&"fight", &"elite", &"guardian", &"boss":
			_start_fight(node)
		&"campfire":
			_set_screen(_campfire())
		&"event":
			_show_event()
		&"shop":
			_show_shop(id)
		_:
			_show_map()


func _campfire() -> CampfireScreen:
	world.rig.set_mode("map")
	var c := CampfireScreen.new()
	c.autoplay = autoplay
	c.done.connect(_after_node)
	return c


func _show_shop(id: int) -> void:
	world.rig.set_mode("map")
	var s := ShopScreen.new().setup(id)
	s.autoplay = autoplay
	s.done.connect(_after_node)
	_set_screen(s)


func _show_event() -> void:
	var ev := Run.pick_event()
	if ev == null:
		_after_node()
		return
	var e := EventScreen.new().setup(ev)
	e.autoplay = autoplay
	e.done.connect(_after_node)
	_set_screen(e)


func _after_node() -> void:
	if Run.map != null and Run.available_nodes().is_empty():
		_show_end(true, "the descent is over")
	else:
		_show_map()


func _start_fight(node: Dictionary) -> void:
	var enc: EncounterDef = Content.encounter(node["encounter"])
	_set_screen(null)
	world.rig.set_mode("fight")
	if fight != null and is_instance_valid(fight):
		fight.queue_free()
	fight = FightController.new()
	fight.name = "Fight"
	add_child(fight)
	var units := Run.healthy_units()
	var ok: bool = await fight.setup(enc, units, Run.relic_defs(), Content.config, Run.formation(units), Run.difficulty_mods())
	if not ok:
		push_warning("fight setup failed for %s" % enc.id)
		_show_map()
		return
	world.board_view.setup_position(fight.board, fight.unit_map, true)
	fight.presenter = world.board_view
	var hud := FightHud.new().setup(fight, world.board_view)
	hud.autoplay = autoplay
	hud.continue_pressed.connect(_after_fight.bind(node))
	_set_screen(hud)
	await get_tree().create_timer(1.2).timeout
	fight.begin()
	if args.has("click"):
		_scripted_clicks(String(args["click"]).split(",", false))


## Real mouse clicks at the squares' screen positions (exercises picking and the HUD).
func _scripted_clicks(squares: PackedStringArray) -> void:
	for name in squares:
		await get_tree().create_timer(2.5).timeout
		var pos := get_viewport().get_final_transform() * world.rig.cam.unproject_position(BoardView.sq_pos(Fen.sq(name)))
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = pos
			ev.global_position = pos
			Input.parse_input_event(ev)
		print("STS CLICK %s at %s" % [name, pos])


func _after_fight(outcome: Dictionary, node: Dictionary) -> void:
	var kind: StringName = node["type"]
	Run.apply_fight(outcome, kind)
	var army: Array = Run.healthy_units().map(func(u): return String(u.type))
	print("STS FIGHT act=%d row=%d kind=%s enc=%s result=%s (%s) plies=%d gold=%d army=%s relics=%s" % [Run.act_index + 1,
		int(node["row"]), kind, node["encounter"], outcome.get("state"), outcome.get("reason"), int(outcome.get("plies", 0)),
		Run.gold, ",".join(army), ",".join(Run.relics)])
	world.board_view.interactive = false
	Content.clear_fight_letters()
	var state := String(outcome.get("state", "draw"))
	if state == "win":
		match kind:
			&"boss":
				_show_end(true, String(outcome.get("reason", "")))
			&"guardian":
				_run_unlocks.append_array(Profile.record_guardian(Run.act_index + 1))
				_show_reward(outcome, kind)
			_:
				_show_reward(outcome, kind)
	elif state == "loss" and Content.config.loss_ends_run:
		_show_end(false, String(outcome.get("reason", "")))
	elif kind == &"boss" or kind == &"guardian":
		var enc: EncounterDef = Content.encounter(node["encounter"])
		_show_end(false, "%s holds the way (%s)" % [enc.display_name if enc else "the engine", outcome.get("reason", state)])
	else:
		_after_node()


func _show_reward(outcome: Dictionary, kind: StringName) -> void:
	world.rig.set_mode("map")
	_display_army()
	var r := RewardScreen.new().setup(outcome, kind)
	r.autoplay = autoplay
	if kind == &"guardian":
		r.done.connect(_next_act)
	else:
		r.done.connect(_after_node)
	_set_screen(r)


func _next_act() -> void:
	if Run.is_final_act():
		_show_end(true, "the last guardian falls")
		return
	Run.advance_act()
	Run.save_game()
	_show_act_intro(_show_map)


func _show_end(victory: bool, reason: String) -> void:
	world.rig.set_mode("orbit")
	Content.clear_fight_letters()
	print("STS RUN END victory=%s reason=%s act=%d difficulty=%d fights_won=%d lost=%d gold_earned=%d" % [victory, reason,
		Run.act_index + 1, Run.difficulty, int(Run.stats.get("fights_won", 0)), int(Run.stats.get("units_lost", 0)),
		int(Run.stats.get("gold_earned", 0))])
	var unlocks: Array = _run_unlocks.duplicate()
	unlocks.append_array(Profile.record_run_end(victory, Run.difficulty, Run.act_index + 1, Run.top_difficulty()))
	_run_unlocks.clear()
	Run.delete_save()
	var e := EndScreen.new().setup(victory, reason, unlocks)
	e.new_run.connect(func():
		_begin_run(randi() % 1000000, Run.difficulty)
		_show_start_relics())
	e.to_title.connect(_show_title)
	_set_screen(e)
	if args.has("quit-on-end"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


# --- pause menu (Esc) -----------------------------------------------------------------------------

func _toggle_pause() -> void:
	if _pause != null and is_instance_valid(_pause):
		_pause.close()
		return
	if not Run.active or screen is TitleScreen or screen is EndScreen:
		return
	var in_fight := fight != null and is_instance_valid(fight) and not fight.finished and screen is FightHud
	if in_fight:
		fight.set_physics_process(false)
	_pause = UiModal.open(ui_root, "Paused", 620, true)
	_pause.closed.connect(func():
		if in_fight and is_instance_valid(fight):
			fight.set_physics_process(true))
	var col := UiKit.vbox(4)
	_pause.body.add_child(col)
	col.add_child(UiKit.menu_button("Resume", _pause.close, 30))
	col.add_child(UiKit.menu_button("Codex", func(): CodexModal.open_codex(ui_root), 28))
	col.add_child(UiKit.menu_button("Settings", func(): SettingsModal.open_settings(ui_root), 28))
	var quit_text := "Quit to Title" + (" (this fight is forfeit)" if in_fight else "")
	col.add_child(UiKit.menu_button(quit_text, func():
		_pause.close()
		_quit_to_title(), 24))
	col.add_child(UiKit.menu_button("Abandon the Run", func():
		UiModal.confirm(ui_root, "Abandon the Run?", "The descent ends here and counts as a defeat.", "Abandon", func():
			if is_instance_valid(_pause):
				_pause.close()
			if fight != null and is_instance_valid(fight):
				fight.queue_free()
			_show_end(false, "you abandoned the descent")), 24))


func _quit_to_title() -> void:
	if fight != null and is_instance_valid(fight):
		fight.queue_free()
		fight = null
	Audio.loop("clock_low", false)
	Audio.loop("engine_think", false)
	_show_title()


# --- dev panel (F1) -------------------------------------------------------------------------------

func _build_dev_panel() -> void:
	dev = UiKit.panel(UiKit.EMBER, Color(0.02, 0.02, 0.03, 0.95), 12)
	dev.position = Vector2(20, 20)
	dev.visible = false
	ui_root.add_child(dev)
	var col := UiKit.vbox(6)
	dev.add_child(col)
	col.add_child(UiKit.heading("Dev (F1)", 20, UiKit.EMBER))
	var row1 := UiKit.hbox(6)
	col.add_child(row1)
	row1.add_child(UiKit.button("Win fight", _dev_finish.bind("win"), 16))
	row1.add_child(UiKit.button("Lose fight", _dev_finish.bind("loss"), 16))
	row1.add_child(UiKit.button("+50 gold", func(): Run.add_gold(50), 16))
	row1.add_child(UiKit.button("Next act", func():
		Run.advance_act()
		_show_map(), 16))
	var row2 := HFlowContainer.new()
	row2.custom_minimum_size = Vector2(900, 0)
	col.add_child(row2)
	for id in Content.relics.keys():
		var rid: StringName = id
		row2.add_child(UiKit.button("+%s" % rid, func(): Run.add_relic(rid), 13))
	var row3 := HFlowContainer.new()
	row3.custom_minimum_size = Vector2(900, 0)
	col.add_child(row3)
	var ids: Array = Content.pieces.keys()
	ids.sort()
	for t in ids:
		var tt: StringName = t
		if Content.piece(tt).is_royal():
			continue
		row3.add_child(UiKit.button("+%s" % tt, func(): Run.add_unit(tt), 13))
	var row4 := UiKit.hbox(6)
	col.add_child(row4)
	row4.add_child(UiKit.button("+5 XP all", func():
		for u in Run.healthy_units():
			u.xp += 5
		Run.changed.emit(), 14))
	row4.add_child(UiKit.button("Heal all", func():
		for u in Run.slain_units():
			Run.restore(u), 14))
	row4.add_child(UiKit.button("Map", _show_map, 14))


func _dev_finish(state: String) -> void:
	if fight != null and is_instance_valid(fight) and not fight.finished:
		fight._finish(state, "dev " + state)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			dev.visible = not dev.visible
		elif event.keycode == KEY_F12:
			_shoot("user://shot_%d.png" % Time.get_unix_time_from_system())
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_toggle_pause()


# --- screenshots ----------------------------------------------------------------------------------

func _shoot_later(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	_shoot(path)
	if args.has("quit-after-shot"):
		get_tree().quit()


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	img.save_png(abs_path)
	print("STS SHOT %s" % abs_path)
