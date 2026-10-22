class_name TitleScreen
extends Control
## Title over the slowly orbiting board: continue, a new descent (difficulty and seed), the codex,
## settings.

signal begin(seed_value: int, difficulty: int)
signal continue_run

var _seed_edit: LineEdit
var _difficulty := 0
var _diff_rows: Array = []


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.vignette())
	_difficulty = Profile.max_difficulty()
	var col := UiKit.vbox(0)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.08
	col.offset_left = -700
	col.offset_right = 700
	add_child(col)
	var pre := UiKit.heading("SLAY THE", 44, UiKit.MUTED)
	pre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(pre)
	var t := UiKit.title("Stockfish", 150, UiKit.BONE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_shadow_color", Color(1.0, 0.3, 0.05, 0.55))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 0)
	t.add_theme_constant_override("shadow_outline_size", 24)
	col.add_child(t)
	col.add_child(UiKit.divider(560))
	var tag := UiKit.label("Build an army across the descent. Then beat the engine at full strength.", 26, UiKit.BONE)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var menu := UiKit.vbox(6)
	menu.anchor_left = 0.5
	menu.anchor_right = 0.5
	menu.anchor_top = 1.0
	menu.anchor_bottom = 1.0
	menu.offset_left = -300
	menu.offset_right = 300
	menu.offset_top = -430
	menu.offset_bottom = -80
	menu.alignment = BoxContainer.ALIGNMENT_END
	add_child(menu)
	if Run.has_save():
		menu.add_child(UiKit.menu_button("Continue the Descent", func(): continue_run.emit(), 36))
	menu.add_child(UiKit.menu_button("New Descent", _open_new_run, 36))
	menu.add_child(UiKit.menu_button("Codex", func(): CodexModal.open_codex(self), 30))
	menu.add_child(UiKit.menu_button("Settings", func(): SettingsModal.open_settings(self), 30))
	menu.add_child(UiKit.menu_button("Quit", func(): get_tree().quit(), 30))
	var diff := Content.difficulty(Profile.max_difficulty())
	var foot := UiKit.label("Runs %d · Victories %d · Highest tier: %s    —    Fairy-Stockfish plays every fight; lasting rules live in the variant, so the engine always plays fair." % [
		Profile.runs(), Profile.wins(), diff.display_name if diff else "Mortal"], 18, UiKit.DIM)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.anchor_right = 1.0
	foot.offset_top = -44
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(foot)
	UiKit.fade_in(self, 1.2)
	Audio.music("music_title")
	Audio.ambience("ambience_wind")


func _open_new_run() -> void:
	var m := UiModal.open(self, "A New Descent", 980, true)
	m.body.add_child(UiKit.caption("Difficulty", 20, UiKit.GOLD))
	_diff_rows.clear()
	for d in Content.difficulties:
		var dd: DifficultyDef = d
		var locked := dd.level > Profile.max_difficulty()
		var b := UiKit.button("", func(): _pick_difficulty(dd.level), 20)
		b.text = "%s%s" % [dd.display_name, "   (locked: win a run on the tier below)" if locked else ""]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = locked
		b.toggle_mode = true
		b.button_pressed = dd.level == _difficulty
		b.tooltip_text = dd.description
		var row := UiKit.vbox(2)
		row.add_child(b)
		if not locked:
			var l := UiKit.label("      " + dd.description, 17, UiKit.MUTED, true)
			row.add_child(l)
		m.body.add_child(row)
		_diff_rows.append([dd.level, b])
	m.body.add_child(UiKit.divider(500, true))
	var seed_row := UiKit.hbox(12)
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_row.add_child(UiKit.caption("Seed", 18, UiKit.MUTED))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(randi() % 1000000)
	_seed_edit.custom_minimum_size = Vector2(220, 0)
	_seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_row.add_child(_seed_edit)
	m.body.add_child(seed_row)
	if Run.has_save():
		var warn := UiKit.label("Beginning anew abandons the descent in progress.", 18, UiKit.BLOOD)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.body.add_child(warn)
	var go := UiKit.button("Descend", func():
		m.close()
		_go(), 28, true)
	go.custom_minimum_size.x = 320
	m.footer.add_child(go)


func _pick_difficulty(level: int) -> void:
	_difficulty = level
	for pair in _diff_rows:
		pair[1].set_pressed_no_signal(pair[0] == level)


func _go() -> void:
	var s := _seed_edit.text.strip_edges()
	begin.emit(int(s) if s.is_valid_int() else hash(s) % 1000000, _difficulty)
