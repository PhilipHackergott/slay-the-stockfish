class_name MapScreen
extends Control
## The act map (Slay the Spire style, bottom to top) with the army roster and relics.

signal node_chosen(id: int)

const ICONS := {&"fight": "icon_fight", &"elite": "icon_elite", &"campfire": "icon_campfire",
	&"event": "icon_event", &"boss": "icon_boss"}
const TYPE_NAME := {&"fight": "Fight", &"elite": "Elite fight", &"campfire": "Campfire", &"event": "Event", &"boss": "Boss: Stockfish"}

var _map_area: Control
var _positions: Dictionary = {}
var _available: Array = []


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.vignette())
	var root := UiKit.hbox(24)
	UiKit.full(root)
	root.offset_left = 32
	root.offset_right = -32
	root.offset_top = 28
	root.offset_bottom = -28
	add_child(root)
	root.add_child(ArmyPanel.new())
	var center := UiKit.panel(UiKit.EDGE, Color(0.03, 0.025, 0.045, 0.82), 20)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var col := UiKit.vbox(6)
	center.add_child(col)
	var head := UiKit.title("The Descent", 48)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var sub := UiKit.label("Act I · choose your path towards the engine", 20, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	_map_area = Control.new()
	_map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_area.draw.connect(_draw_edges)
	col.add_child(_map_area)
	root.add_child(_side_panel())
	_map_area.resized.connect(_layout_nodes)
	UiKit.fade_in(self)


func _side_panel() -> Control:
	var p := UiKit.panel(UiKit.EDGE, Color(0.035, 0.03, 0.05, 0.88), 16)
	p.custom_minimum_size = Vector2(340, 0)
	var col := UiKit.vbox(10)
	p.add_child(col)
	col.add_child(UiKit.heading("Relics", 28))
	if Run.relics.is_empty():
		col.add_child(UiKit.label("None yet.", 18, UiKit.MUTED))
	for r in Run.relic_defs():
		var h := UiKit.hbox(10)
		h.add_child(UiKit.icon(r.icon, 64))
		var c := UiKit.vbox(0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(UiKit.heading(r.display_name, 18))
		c.add_child(UiKit.label(r.description, 15, UiKit.MUTED, true))
		h.add_child(c)
		col.add_child(h)
	col.add_child(UiKit.spacer(16))
	col.add_child(UiKit.heading("The Run", 28))
	var s: Dictionary = Run.stats
	col.add_child(UiKit.label("Seed %d" % Run.seed_value, 18, UiKit.MUTED))
	col.add_child(UiKit.label("Fights won: %d" % int(s.get("fights_won", 0)), 19))
	col.add_child(UiKit.label("Pieces lost: %d" % int(s.get("units_lost", 0)), 19))
	col.add_child(UiKit.label("Nodes cleared: %d" % maxi(0, Run.visited.size()), 19))
	col.add_child(UiKit.spacer(16))
	col.add_child(UiKit.label("Captured pieces stay dead until a campfire restores them. XP is gained by capturing; level-ups happen after fights.", 16, UiKit.MUTED, true))
	return p


func _layout_nodes() -> void:
	for c in _map_area.get_children():
		c.queue_free()
	_positions.clear()
	_available = Run.available_nodes()
	var map := Run.map
	if map == null:
		return
	var sz := _map_area.size
	var rows := maxi(1, map.rows - 1)
	for n in map.nodes:
		var x := lerpf(sz.x * 0.16, sz.x * 0.84, float(n["x"]))
		var y := lerpf(sz.y - 50.0, 70.0, float(n["row"]) / float(rows))
		_positions[n["id"]] = Vector2(x, y)
	for n in map.nodes:
		_map_area.add_child(_node_button(n))
	_map_area.queue_redraw()


func _node_button(n: Dictionary) -> Control:
	var id: int = n["id"]
	var t: StringName = n["type"]
	var visited := Run.visited.has(id)
	var avail := _available.has(id)
	var size := 120 if t == &"boss" else 76
	var dim := 0.0 if avail or t == &"boss" else (0.3 if visited else 0.15)
	var desat := 0.0 if avail else 0.35
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size = Vector2(size, size)
	b.size = Vector2(size, size)
	b.position = _positions[id] - Vector2(size, size) * 0.5
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.disabled = not avail
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if avail else Control.CURSOR_ARROW
	var ic := UiKit.icon("res://assets/ui/icons/%s_256.png" % ICONS.get(t, "icon_unknown"), size, dim, desat)
	UiKit.full(ic)
	b.add_child(ic)
	var tip: String = TYPE_NAME.get(t, String(t))
	if String(n["encounter"]) != "":
		var e: EncounterDef = Content.encounter(n["encounter"])
		if e != null:
			tip += ": %s\n%s" % [e.display_name, e.flavor]
	b.tooltip_text = tip
	b.pivot_offset = Vector2(size, size) * 0.5
	if avail:
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "scale", Vector2(1.08, 1.08), 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
		b.pressed.connect(func(): node_chosen.emit(id))
	if visited:
		var mark := UiKit.label("✓", int(size * 0.45), UiKit.GOLD)
		mark.position = Vector2(size * 0.62, -size * 0.12)
		b.add_child(mark)
	return b


func _draw_edges() -> void:
	var map := Run.map
	if map == null:
		return
	for n in map.nodes:
		if _positions.has(n["id"]):
			var r := 66.0 if n["type"] == &"boss" else 44.0
			_map_area.draw_circle(_positions[n["id"]], r, Color(0.24, 0.21, 0.32, 0.55))
		for e in n["edges"]:
			if not _positions.has(n["id"]) or not _positions.has(e):
				continue
			var a: Vector2 = _positions[n["id"]]
			var b: Vector2 = _positions[e]
			var walked: bool = Run.visited.has(n["id"]) and Run.visited.has(e)
			var open: bool = int(n["id"]) == Run.current_node and _available.has(e)
			var col := UiKit.GOLD if walked else (UiKit.SOUL if open else Color(0.66, 0.62, 0.6, 0.75))
			var dir := (b - a).normalized()
			_map_area.draw_dashed_line(a + dir * 42.0, b - dir * 42.0, col, 3.0 if walked or open else 2.0, 10.0)
	for id in _available:
		if _positions.has(id):
			_map_area.draw_arc(_positions[id], 50.0, 0.0, TAU, 48, Color(UiKit.SOUL, 0.55), 2.0)
