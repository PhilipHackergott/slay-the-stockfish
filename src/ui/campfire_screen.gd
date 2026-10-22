class_name CampfireScreen
extends Control
## Restore one slain piece or upgrade one healthy piece (no XP needed).

signal done

var autoplay := false
var _body: VBoxContainer
var _leave: Button


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.0, 0.0, 0.45)
	UiKit.full(shade)
	add_child(shade)
	add_child(UiKit.vignette())
	var p := UiKit.panel(Color(1.0, 0.6, 0.3, 0.8), Color(0.04, 0.025, 0.02, 0.94), 26)
	p.custom_minimum_size = Vector2(1100, 0)
	var col := UiKit.vbox(14)
	p.add_child(col)
	var cc := UiKit.centered(p)
	UiKit.full(cc)
	add_child(cc)
	var head := UiKit.hbox(18)
	head.add_child(UiKit.icon("res://assets/ui/icons/icon_campfire_256.png", 120))
	var hc := UiKit.vbox(4)
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.add_child(UiKit.title("The Campfire", 52, Color(1.0, 0.75, 0.5)))
	hc.add_child(UiKit.label("The fire burns low and blue. Its heat can mend one fallen piece, or temper one living piece into something greater. Choose one.", 21, UiKit.BONE, true))
	head.add_child(hc)
	col.add_child(head)
	_body = UiKit.vbox(12)
	col.add_child(_body)
	_build_choices()
	_leave = UiKit.button("Leave the fire", func(): done.emit(), 24)
	col.add_child(UiKit.centered(_leave))
	UiKit.fade_in(self)
	if autoplay:
		_auto()


func _build_choices() -> void:
	for c in _body.get_children():
		c.queue_free()
	var cols := UiKit.hbox(30)
	_body.add_child(cols)
	var left := UiKit.vbox(8)
	left.custom_minimum_size = Vector2(500, 0)
	cols.add_child(left)
	left.add_child(UiKit.heading("Restore a fallen piece", 26, UiKit.SOUL))
	var slain := Run.slain_units()
	if slain.is_empty():
		left.add_child(UiKit.label("No one has fallen. Yet.", 19, UiKit.MUTED))
	for u in slain:
		left.add_child(_unit_button(u, "Restore (keeps %d XP)" % u.xp, func(): _restore(u)))
	var right := UiKit.vbox(8)
	right.custom_minimum_size = Vector2(500, 0)
	cols.add_child(right)
	right.add_child(UiKit.heading("Upgrade a living piece", 26, UiKit.GOLD))
	var any := false
	for u in Run.healthy_units():
		var opts := Run.upgrade_options(u)
		if opts.is_empty():
			continue
		any = true
		var row := UiKit.hbox(8)
		row.add_child(UiKit.portrait(u.type, true, 48))
		var name_l := UiKit.label(UiKit.unit_name(u), 19)
		name_l.custom_minimum_size = Vector2(150, 0)
		row.add_child(name_l)
		for opt in opts:
			var t: StringName = opt
			var b := UiKit.button("→ %s" % UiKit.piece_name(t), func(): _upgrade(u, t), 17)
			row.add_child(b)
		right.add_child(row)
	if not any:
		right.add_child(UiKit.label("No piece can rise further.", 19, UiKit.MUTED))


func _unit_button(u: Unit, action: String, cb: Callable) -> Control:
	var row := UiKit.hbox(10)
	row.add_child(UiKit.portrait(u.type, true, 48, 0.5))
	var l := UiKit.label("%s · Lv %d" % [UiKit.unit_name(u), u.level], 19)
	l.custom_minimum_size = Vector2(190, 0)
	row.add_child(l)
	row.add_child(UiKit.button(action, cb, 17))
	return row


func _restore(u: Unit) -> void:
	Run.restore(u)
	_finish("%s rises from the ashes, its %d XP intact." % [UiKit.unit_name(u), u.xp], u.type)


func _upgrade(u: Unit, t: StringName) -> void:
	var before := UiKit.unit_name(u)
	Run.campfire_upgrade(u, t)
	_finish("%s is tempered in the fire and becomes a %s." % [before, UiKit.piece_name(t).to_lower()], t)


func _finish(text: String, t: StringName) -> void:
	for c in _body.get_children():
		c.queue_free()
	var h := UiKit.hbox(16)
	h.add_child(UiKit.portrait(t, true, 96))
	h.add_child(UiKit.label(text, 24, UiKit.BONE, true))
	h.get_child(1).custom_minimum_size = Vector2(800, 0)
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
