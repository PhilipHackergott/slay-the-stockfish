class_name EventScreen
extends Control
## A text event with a few options (data/events). Options that cannot be taken are disabled. The
## Tailor's options ask which piece; a problem or the Pit asks main for a fight (fight_requested) and
## comes back as a result (setup with result text).

signal done
signal fight_requested(opt: Dictionary)

var event: EventDef
var autoplay := false
var result := ""
var _options: VBoxContainer
var _continue: Button


func setup(p_event: EventDef, p_result: String = "") -> EventScreen:
	event = p_event
	result = p_result
	return self


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UiModal.new().setup(event.title, 1000)
	add_child(m)
	Audio.play("event_page")
	var head := UiKit.hbox(20)
	head.add_child(UiKit.icon(event.icon, 130))
	var text := UiKit.label(event.text, 23, UiKit.BONE, true)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	m.body.add_child(head)
	m.body.add_child(UiKit.divider(600, true))
	_options = UiKit.vbox(10)
	m.body.add_child(_options)
	_continue = UiKit.button("Continue", func(): done.emit(), 24, true)
	_continue.custom_minimum_size.x = 300
	_continue.visible = false
	m.footer.add_child(_continue)
	if result != "":
		_show_result(result)
	else:
		_build_options()
	if autoplay:
		await get_tree().create_timer(0.2).timeout
		if result != "":
			done.emit()
			return
		var pick: Dictionary = event.options[0]
		for o in event.options:
			if Run.can_afford_option(o):
				pick = o
				break
		_choose(pick)
		if pick.has("fight"):
			return
		if String(pick.get("effect", "")) == "stitch":
			var us := Run.stitch_options(String(pick.get("atom", "W")))
			_stitch(pick, us[0])
		await get_tree().create_timer(0.2).timeout
		done.emit()


func _build_options() -> void:
	for c in _options.get_children():
		c.queue_free()
	for opt in event.options:
		var o: Dictionary = opt
		var parts := option_text(o)
		var ok := Run.can_afford_option(o)
		var b := UiKit.option_button(parts[0], parts[1], func(): _choose(o), UiKit.MUTED, ok)
		if not ok:
			b.tooltip_text = "You cannot take this now."
		_options.add_child(b)


## [title, detail] for an option: its `detail`, or the part of the label in parentheses, plus the cost
## and the curse that comes with it.
static func option_text(o: Dictionary) -> Array:
	var title := String(o.get("label", "..."))
	var detail := String(o.get("detail", ""))
	var i := title.find(" (")
	if detail == "" and i > 0 and title.ends_with(")"):
		detail = title.substr(i + 2, title.length() - i - 3)
		title = title.substr(0, i)
	if String(o.get("cost", "")) == "gold":
		var cost := "Costs %d gold." % int(o.get("cost_amount", 0))
		detail = cost if detail == "" else "%s · %s" % [detail, cost]
	var curse := Content.relic(StringName(o.get("curse", "")))
	if curse != null:
		var c := "Curse: %s (%s)" % [curse.display_name, curse.description.trim_suffix(".")]
		detail = c if detail == "" else "%s · %s" % [detail, c]
	if detail != "":
		detail = detail.substr(0, 1).to_upper() + detail.substr(1)
	return [title, detail]


func _choose(opt: Dictionary) -> void:
	if opt.has("fight"):
		for c in _options.get_children():
			c.queue_free()
		fight_requested.emit(opt)
		return
	if String(opt.get("effect", "")) == "stitch":
		_stitch_step(opt)
		return
	_show_result(Run.apply_event_option(opt))


## The Tailor: which piece takes the stitch.
func _stitch_step(opt: Dictionary) -> void:
	for c in _options.get_children():
		c.queue_free()
	var bar := UiKit.hbox(12)
	bar.add_child(UiKit.button("‹ Back", _build_options, 16))
	bar.add_child(UiKit.caption(String(opt.get("label", "Stitch")), 18, UiKit.GOLD))
	_options.add_child(bar)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	_options.add_child(flow)
	var atom := String(opt.get("atom", "W"))
	for u in Run.stitch_options(atom):
		var unit: Unit = u
		var d: PieceDef = Content.piece(Content.stitched_id(unit.type, atom))
		flow.add_child(UiKit.option_button("%s → %s" % [UiKit.unit_name(unit), d.display_name],
			"Value %d → %d. %s" % [Content.piece(unit.type).value, d.value, Content.STITCH_TEXT[atom].substr(0, 1).to_upper()
				+ Content.STITCH_TEXT[atom].substr(1) + "."], func(): _stitch(opt, unit), UiKit.MUTED, true, 290))


func _stitch(opt: Dictionary, u: Unit) -> void:
	var o := opt.duplicate()
	o["unit"] = u.id
	_show_result(Run.apply_event_option(o))


func _show_result(text: String) -> void:
	for c in _options.get_children():
		c.queue_free()
	var l := UiKit.label(text, 23, UiKit.GOLD, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_options.add_child(l)
	_continue.visible = true
