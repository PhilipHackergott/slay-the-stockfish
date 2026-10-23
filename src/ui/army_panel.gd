class_name ArmyPanel
extends PanelContainer
## The army roster: every unit with identity, level, XP progress, lineage and state.

var _list: VBoxContainer
var _title: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.035, 0.03, 0.05, 0.88), UiKit.EDGE, 16))
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(380, 0)
	var col := UiKit.vbox(8)
	add_child(col)
	_title = UiKit.heading("Your Army", 28)
	col.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = UiKit.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	Run.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var units := Run.units.duplicate()
	units.sort_custom(func(a, b):
		if a.is_healthy() != b.is_healthy():
			return a.is_healthy()
		var va: int = 99 if Content.piece(a.type).is_royal() else Content.piece(a.type).value
		var vb: int = 99 if Content.piece(b.type).is_royal() else Content.piece(b.type).value
		return va > vb if va != vb else a.id < b.id)
	_title.text = "Your Army  (%d / %d)" % [Run.healthy_units().size(), Run.units.size()]
	for u in units:
		_list.add_child(row(u))


static func row(u: Unit, compact: bool = false) -> Control:
	var h := UiKit.hbox(12)
	var slain := not u.is_healthy()
	h.add_child(UiKit.portrait(u.type, true, 48 if compact else 56, 0.7 if slain else 0.0))
	var col := UiKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	var top := UiKit.hbox(8)
	col.add_child(top)
	var name_l := UiKit.heading(UiKit.unit_name(u), 19, UiKit.DIM if slain else UiKit.BONE)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	var lv := UiKit.label("Lv %d" % u.level, 18, UiKit.GOLD if not slain else UiKit.DIM)
	top.add_child(lv)
	if slain:
		top.add_child(UiKit.label("slain", 18, UiKit.BLOOD))
	var need := Run.xp_needed(u)
	var bar_row := UiKit.hbox(8)
	col.add_child(bar_row)
	var maxed := Run.is_maxed(u)
	var bar := UiKit.bar(float(u.xp), float(need if need > 0 and not maxed else maxi(u.xp, 1)),
		"gold" if Run.can_level_up(u) or maxed else "soul", 120)
	bar_row.add_child(bar)
	var xp_text := "%d XP, turns to gold" % u.xp if maxed else "%d / %d XP" % [u.xp, need]
	var xl := UiKit.label(xp_text, 16, UiKit.MUTED, true)
	xl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(xl)
	if u.lineage.size() > 1 and not compact:
		var names: Array = []
		for t in u.lineage:
			names.append(UiKit.piece_name(StringName(t)))
		col.add_child(UiKit.label(" → ".join(names), 15, UiKit.MUTED, true))
	h.tooltip_text = "%s\n%s\nCaptures: %d · Fights: %d" % [UiKit.unit_name(u), UiKit.moves_text(u.type), u.captures, u.fights]
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h
