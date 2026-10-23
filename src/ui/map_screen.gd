class_name MapScreen
extends Control
## The act map (Slay the Spire style, bottom to top) with the army roster and relics.

signal node_chosen(id: int)
signal formation_changed

const ICONS := {&"fight": "icon_fight", &"elite": "icon_elite", &"campfire": "icon_campfire",
	&"event": "icon_event", &"boss": "icon_boss", &"guardian": "icon_guardian", &"shop": "icon_shop"}
const TYPE_NAME := {&"fight": "Fight", &"elite": "Elite fight", &"campfire": "Campfire", &"event": "Event",
	&"boss": "Boss", &"guardian": "Guardian", &"shop": "The Bone Merchant"}
const ROMAN := ["I", "II", "III", "IV", "V"]

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
	var act := Run.current_act()
	var bar := UiKit.hbox(14)
	col.add_child(bar)
	var gold := UiKit.gold_label(Run.gold, 26)
	gold.tooltip_text = "Gold: earned in fights, spent at the Bone Merchant and in events."
	gold.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(gold)
	var diff := Content.difficulty(Run.difficulty)
	if diff != null and diff.level > 0:
		var dl := UiKit.caption(diff.display_name, 16, UiKit.BLOOD)
		dl.tooltip_text = diff.description
		dl.mouse_filter = Control.MOUSE_FILTER_PASS
		bar.add_child(dl)
	bar.add_child(UiKit.spacer(0, 0))
	bar.get_child(bar.get_child_count() - 1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(UiKit.button("Arrange", func():
		var f := FormationModal.open_formation(self)
		f.saved.connect(func(): formation_changed.emit()), 18))
	bar.add_child(UiKit.button("Codex", func(): CodexModal.open_codex(self), 18))
	var head := UiKit.title(act.display_name if act else "The Descent", 46)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var sub := UiKit.label("Act %s of %s · %s" % [ROMAN[mini(Run.act_index, 4)], ROMAN[mini(Run.act_count() - 1, 4)],
		act.subtitle if act else "choose your path towards the engine"], 20, UiKit.MUTED)
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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var col := UiKit.vbox(10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	col.add_child(UiKit.heading("Relics  (%d)" % Run.relics.size(), 28))
	var defs := Run.relic_defs()
	if defs.is_empty():
		col.add_child(UiKit.label("None yet.", 18, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	var detail := UiKit.vbox(2)
	detail.custom_minimum_size = Vector2(0, 120)
	col.add_child(detail)
	for r in defs:
		var rd: RelicDef = r
		var sl := UiKit.slot(UiKit.icon(rd.icon, 50))
		sl.mouse_entered.connect(func(): _show_relic(detail, rd))
		grid.add_child(sl)
	if not defs.is_empty():
		_show_relic(detail, defs[0])
	col.add_child(UiKit.spacer(10))
	col.add_child(UiKit.heading("The Run", 28))
	var s: Dictionary = Run.stats
	col.add_child(UiKit.label("Seed %d · gold %d" % [Run.seed_value, Run.gold], 18, UiKit.MUTED))
	col.add_child(UiKit.label("Fights won: %d" % int(s.get("fights_won", 0)), 19))
	col.add_child(UiKit.label("Pieces lost: %d" % int(s.get("units_lost", 0)), 19))
	col.add_child(UiKit.label("Nodes cleared: %d" % maxi(0, Run.visited.size()), 19))
	col.add_child(UiKit.spacer(16))
	col.add_child(UiKit.label("Captured pieces stay dead until a campfire or the merchant restores them. XP is gained by capturing; level-ups happen after fights. Each act ends with a guardian engine.", 16, UiKit.MUTED, true))
	return p


func _show_relic(box: VBoxContainer, r: RelicDef) -> void:
	for c in box.get_children():
		c.queue_free()
	box.add_child(UiKit.relic_info(r, 0, 16))


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
	var big := t == &"boss" or t == &"guardian"
	var size := 120 if big else 76
	var dim := 0.0 if avail or big else (0.3 if visited else 0.15)
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
	var ring_tex := UiKit.kit_tex("node_ring_available" if avail else ("node_ring_visited" if visited else "node_ring"))
	if ring_tex != null:
		var ring := TextureRect.new()
		ring.texture = ring_tex
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.stretch_mode = TextureRect.STRETCH_SCALE
		var grow := size * 0.2
		ring.position = Vector2(-grow, -grow)
		ring.size = Vector2(size + grow * 2.0, size + grow * 2.0)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ring)
	var tip: String = TYPE_NAME.get(t, String(t))
	if String(n["encounter"]) != "":
		var e: EncounterDef = Content.encounter(n["encounter"])
		if e != null:
			tip += ": %s\n%s" % [e.display_name, e.flavor]
	elif t == &"shop":
		tip += "\nBuy pieces and relics, or raise the fallen."
	b.tooltip_text = tip
	b.pivot_offset = Vector2(size, size) * 0.5
	if avail:
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "scale", Vector2(1.08, 1.08), 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
		b.pressed.connect(func(): node_chosen.emit(id))
	if visited and ring_tex == null:
		var mark := UiKit.label("✓", int(size * 0.45), UiKit.GOLD)
		mark.position = Vector2(size * 0.62, -size * 0.12)
		b.add_child(mark)
	return b


func _draw_edges() -> void:
	var map := Run.map
	if map == null:
		return
	for n in map.nodes:
		if _positions.has(n["id"]) and not UiKit.has_kit():
			var r := 66.0 if n["type"] == &"boss" or n["type"] == &"guardian" else 44.0
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
		if _positions.has(id) and not UiKit.has_kit():
			_map_area.draw_arc(_positions[id], 50.0, 0.0, TAU, 48, Color(UiKit.SOUL, 0.55), 2.0)
