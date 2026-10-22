class_name TitleScreen
extends Control
## Title over the slowly orbiting board.

signal begin(seed_value: int)

var _seed := 0
var _seed_edit: LineEdit


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.vignette())
	_seed = randi() % 1000000
	var col := UiKit.vbox(6)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.1
	col.offset_left = -700
	col.offset_right = 700
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
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
	var tag := UiKit.label("Build an army across the descent. Then beat the engine at full strength.", 26, UiKit.BONE)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var menu := UiKit.vbox(14)
	menu.anchor_left = 0.5
	menu.anchor_right = 0.5
	menu.anchor_top = 1.0
	menu.anchor_bottom = 1.0
	menu.offset_left = -200
	menu.offset_right = 200
	menu.offset_top = -300
	menu.offset_bottom = -90
	add_child(menu)
	var b := UiKit.button("Begin a Run", _go, 30)
	menu.add_child(b)
	var seed_row := UiKit.hbox(8)
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_row.add_child(UiKit.label("Seed", 20, UiKit.MUTED))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(_seed)
	_seed_edit.custom_minimum_size = Vector2(160, 0)
	_seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_row.add_child(_seed_edit)
	menu.add_child(seed_row)
	menu.add_child(UiKit.button("Quit", func(): get_tree().quit(), 22))
	var foot := UiKit.label("Fairy-Stockfish plays every fight. Lasting rules live in the variant, so the engine always plays fair.", 18, UiKit.DIM)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.anchor_right = 1.0
	foot.offset_top = -44
	foot.offset_left = 0
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(foot)
	UiKit.fade_in(self, 1.2)


func _go() -> void:
	var s := _seed_edit.text.strip_edges()
	begin.emit(int(s) if s.is_valid_int() else hash(s) % 1000000)
