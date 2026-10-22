class_name CampfireScreen
extends Control
## Restore one slain piece or upgrade one healthy piece (no XP needed).

signal done

var autoplay := false
var _body: VBoxContainer
var _leave: Button


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UiModal.new().setup("The Campfire", 1180, false, "", 640)
	m.accent = Color(1.0, 0.72, 0.45)
	add_child(m)
	var head := UiKit.hbox(18)
	head.add_child(UiKit.icon("res://assets/ui/icons/icon_campfire_256.png", 112))
	var l := UiKit.label("The fire burns low and blue. Its heat can mend one fallen piece, or temper one living piece into something greater. Choose one.", 22, UiKit.BONE, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	m.body.add_child(head)
	m.body.add_child(UiKit.divider(700, true))
	_body = UiKit.vbox(12)
	m.body.add_child(_body)
	_build_choices()
	_leave = UiKit.button("Leave the fire", func(): done.emit(), 24)
	_leave.custom_minimum_size.x = 320
	m.footer.add_child(_leave)
	Audio.music("music_campfire")
	if autoplay:
		_auto()


func _build_choices() -> void:
	for c in _body.get_children():
		c.queue_free()
	var cols := UiKit.hbox(30)
	_body.add_child(cols)
	var left := UiKit.vbox(10)
	left.custom_minimum_size = Vector2(470, 0)
	cols.add_child(left)
	left.add_child(UiKit.caption("Restore a fallen piece", 20, UiKit.SOUL))
	var slain := Run.slain_units()
	if slain.is_empty():
		left.add_child(UiKit.label("No one has fallen. Yet.", 19, UiKit.MUTED))
	for u in slain:
		left.add_child(_unit_row(u, true, [UiKit.button("Restore", func(): _restore(u), 18)]))
	var right := UiKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UiKit.caption("Temper a living piece", 20, UiKit.GOLD))
	var any := false
	for u in Run.healthy_units():
		var opts := Run.upgrade_options(u)
		if opts.is_empty():
			continue
		any = true
		var btns: Array = []
		for opt in opts:
			var t: StringName = opt
			var b := UiKit.button(UiKit.piece_name(t), func(): _upgrade(u, t), 16)
			b.tooltip_text = UiKit.moves_text(t)
			btns.append(b)
		right.add_child(_unit_row(u, false, btns))
	if not any:
		right.add_child(UiKit.label("No piece can rise further.", 19, UiKit.MUTED))


func _unit_row(u: Unit, slain: bool, buttons: Array) -> Control:
	var row := UiKit.hbox(10)
	row.add_child(UiKit.portrait(u.type, true, 52, 0.5 if slain else 0.0))
	var info := UiKit.vbox(0)
	info.custom_minimum_size = Vector2(170, 0)
	info.add_child(UiKit.heading(UiKit.unit_name(u), 18))
	info.add_child(UiKit.label("Lv %d · %d XP" % [u.level, u.xp], 16, UiKit.MUTED))
	row.add_child(info)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	for b in buttons:
		flow.add_child(b)
	row.add_child(flow)
	return row


func _restore(u: Unit) -> void:
	Run.restore(u)
	Audio.play("piece_spawn")
	_finish("%s rises from the ashes, its %d XP intact." % [UiKit.unit_name(u), u.xp], u.type)


func _upgrade(u: Unit, t: StringName) -> void:
	var before := UiKit.unit_name(u)
	Run.campfire_upgrade(u, t)
	Audio.play("level_up")
	_finish("%s is tempered in the fire and becomes a %s." % [before, UiKit.piece_name(t).to_lower()], t)


func _finish(text: String, t: StringName) -> void:
	for c in _body.get_children():
		c.queue_free()
	var h := UiKit.hbox(18)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UiKit.portrait(t, true, 110))
	var l := UiKit.label(text, 24, UiKit.BONE, true)
	l.custom_minimum_size = Vector2(760, 0)
	h.add_child(l)
	_body.add_child(h)
	_leave.text = "Continue"


func _auto() -> void:
	await get_tree().create_timer(0.2).timeout
	var slain := Run.slain_units()
	if not slain.is_empty():
		_restore(slain[0])
	else:
		for u in Run.healthy_units():
			var opts := Run.upgrade_options(u)
			if not opts.is_empty():
				_upgrade(u, opts[0])
				break
	await get_tree().create_timer(0.2).timeout
	done.emit()
