class_name SettingsModal
extends RefCounted
## Volume sliders, fullscreen, and a profile reset (asks first). Settings live in the Profile.

const VOLUMES := [["master_db", "Master"], ["music_db", "Music"], ["sfx_db", "Effects"]]


static func open_settings(parent: Node) -> UiModal:
	var m := UiModal.open(parent, "Settings", 820, true)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 18)
	m.body.add_child(UiKit.centered(grid))
	for pair in VOLUMES:
		var key: String = pair[0]
		grid.add_child(UiKit.caption(pair[1], 20, UiKit.BONE))
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 100
		s.step = 1
		s.custom_minimum_size = Vector2(420, 40)
		s.value = _db_to_pct(float(Profile.setting(key, 0.0)))
		var val := UiKit.label("%d%%" % int(s.value), 20, UiKit.MUTED)
		val.custom_minimum_size = Vector2(64, 0)
		s.value_changed.connect(func(v: float):
			val.text = "%d%%" % int(v)
			Profile.data["settings"][key] = _pct_to_db(v)
			Audio.apply_settings())
		s.drag_ended.connect(func(_c: bool):
			Profile.save()
			Audio.play("ui_click"))
		grid.add_child(s)
		grid.add_child(val)
	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = bool(Profile.setting("fullscreen", false))
	fs.toggled.connect(func(on: bool):
		Profile.set_setting("fullscreen", on)
		apply_window())
	m.body.add_child(UiKit.centered(fs))
	m.body.add_child(UiKit.divider(500, true))
	var reset := UiKit.button("Erase all progress", func():
		UiModal.confirm(m, "Erase Progress?", "Runs, victories, unlocks and difficulty tiers are forgotten. Settings stay.",
			"Erase", func():
				var keep: Dictionary = Profile.data.get("settings", {}).duplicate()
				Profile.reset()
				Profile.data["settings"] = keep
				Profile.save()), 18)
	m.body.add_child(UiKit.centered(reset))
	m.footer.add_child(UiKit.button("Done", m.close, 22, true))
	return m


static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var on := bool(Profile.setting("fullscreen", false))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


static func _db_to_pct(db: float) -> float:
	return 0.0 if db <= -40.0 else clampf(db_to_linear(db) * 100.0, 0.0, 100.0)


static func _pct_to_db(pct: float) -> float:
	return -80.0 if pct <= 0.5 else linear_to_db(pct / 100.0)
