extends Node
## Game flow: title -> starting relic -> map -> nodes (fight, elite, campfire, event, boss) -> end.
## Command line (after `--`): --seed=N, --screen=title|relic|map|fight|elite|boss|reward|campfire|event|end,
## --relics=id,id, --autoplay (plays a whole run unattended), --shot=path.png [--shot-delay=s],
## --quit-after-shot, --quit-on-end.

var world: World
var ui_root: Control
var screen: Control
var fight: FightController
var dev: PanelContainer
var args: Dictionary = {}
var autoplay := false


func _ready() -> void:
	args = _parse_args()
	autoplay = args.has("autoplay")
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
	_build_dev_panel()
	var ping: Dictionary = await ChessCore.call_core({"op": "ping"})
	if not ping.get("ok", false):
		push_warning("chess core unavailable: %s" % ping.get("error", "?"))
	print("STS BOOT OK core=%s" % ("ok" if ping.get("ok", false) else "missing"))
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
	Run.new_run(int(args.get("seed", "7")))
	for id in String(args.get("relics", "")).split(",", false):
		Run.add_relic(StringName(id))
	match where:
		"relic":
			_show_start_relics()
		"map":
			_show_map()
		"fight", "elite", "boss":
			_enter(_first_node_of(StringName("fight" if where == "fight" else where)))
		"reward":
			_show_reward({"state": "win", "reason": "checkmate: the engine's king falls", "slain": [],
				"xp": [{"unit": 6, "amount": 3, "captured": "n"}, {"unit": 2, "amount": 1, "captured": "p"}],
				"plies": 31, "encounter": &"cathedral_sentinel"}, &"elite")
			Run.unit(2).xp += 3
		"campfire":
			Run.units[2].state = &"slain"
			_set_screen(_campfire())
		"event":
			_show_event()
		"end":
			_show_end(true, "checkmate: the engine's king falls")
		_:
			_show_title()


func _first_node_of(t: StringName) -> int:
	for n in Run.map.nodes:
		if n["type"] == t:
			return n["id"]
	return Run.map.start_nodes()[0]


func _show_title() -> void:
	world.rig.set_mode("orbit")
	_show_board_tableau()
	var t := TitleScreen.new()
	t.begin.connect(func(s: int):
		Run.new_run(s)
		_show_start_relics())
	_set_screen(t)
	if autoplay:
		await get_tree().create_timer(0.5).timeout
		Run.new_run(int(args.get("seed", "7")))
		_show_start_relics()


## The full boss position as a backdrop for the title.
func _show_board_tableau() -> void:
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
		_show_map())
	_set_screen(pick)
	if autoplay:
		await get_tree().create_timer(0.3).timeout
		if is_instance_valid(pick):
			pick.picked.emit(Run.relic_choices(1)[0])


func _show_map() -> void:
	world.rig.set_mode("map")
	var units := Run.healthy_units()
	var formation := Run.formation(units)
	var b := {}
	var um := UnitMap.new()
	for sq in formation:
		var u := Run.unit(int(formation[sq]))
		b[int(sq)] = (VariantGen.PLAYER_KING if u.type == &"king" else Content.piece(u.type).letter).to_upper()
		um.place(int(sq), u.id)
	world.board_view.setup_position(b, um, true)
	var m := MapScreen.new()
	m.node_chosen.connect(_enter)
	_set_screen(m)
	if autoplay:
		await get_tree().create_timer(0.4).timeout
		var av := Run.available_nodes()
		if not av.is_empty() and is_instance_valid(m):
			_enter(av[0])


func _enter(id: int) -> void:
	var node := Run.enter_node(id)
	match node["type"]:
		&"fight", &"elite", &"boss":
			_start_fight(node)
		&"campfire":
			_set_screen(_campfire())
		&"event":
			_show_event()
		_:
			_show_map()


func _campfire() -> CampfireScreen:
	world.rig.set_mode("map")
	var c := CampfireScreen.new()
	c.autoplay = autoplay
	c.done.connect(_after_node)
	return c


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
	var ok: bool = await fight.setup(enc, units, Run.relic_defs(), Content.config, Run.formation(units))
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
	var army: Array = Run.healthy_units().map(func(u): return String(u.type))
	print("STS FIGHT row=%d enc=%s result=%s (%s) plies=%d army=%s relics=%s" % [int(node["row"]), node["encounter"],
		outcome.get("state"), outcome.get("reason"), int(outcome.get("plies", 0)), ",".join(army), ",".join(Run.relics)])
	Run.apply_fight(outcome)
	world.board_view.interactive = false
	var state := String(outcome.get("state", "draw"))
	var kind: StringName = node["type"]
	if state == "win":
		if kind == &"boss":
			_show_end(true, String(outcome.get("reason", "")))
		else:
			_show_reward(outcome, kind)
	elif state == "loss" and Content.config.loss_ends_run:
		_show_end(false, String(outcome.get("reason", "")))
	elif kind == &"boss":
		_show_end(false, "the engine holds its throne (%s)" % outcome.get("reason", state))
	else:
		_after_node()


func _show_reward(outcome: Dictionary, kind: StringName) -> void:
	world.rig.set_mode("map")
	var r := RewardScreen.new().setup(outcome, kind)
	r.autoplay = autoplay
	r.done.connect(_after_node)
	_set_screen(r)


func _show_end(victory: bool, reason: String) -> void:
	world.rig.set_mode("orbit")
	print("STS RUN END victory=%s reason=%s nodes=%d fights_won=%d lost=%d" % [victory, reason, Run.visited.size(),
		int(Run.stats.get("fights_won", 0)), int(Run.stats.get("units_lost", 0))])
	var e := EndScreen.new().setup(victory, reason)
	e.new_run.connect(func():
		Run.new_run(randi() % 1000000)
		_show_start_relics())
	e.to_title.connect(_show_title)
	_set_screen(e)
	if args.has("quit-on-end"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


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
	var row2 := UiKit.hbox(6)
	col.add_child(row2)
	for id in Content.relics.keys():
		var rid: StringName = id
		row2.add_child(UiKit.button("+%s" % rid, func(): Run.add_relic(rid), 14))
	var row3 := UiKit.hbox(6)
	col.add_child(row3)
	for t in [&"pawn", &"knight", &"bishop", &"rook", &"queen"]:
		var tt: StringName = t
		row3.add_child(UiKit.button("+%s" % tt, func(): Run.add_unit(tt), 14))
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
