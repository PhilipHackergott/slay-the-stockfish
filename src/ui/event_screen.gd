class_name EventScreen
extends Control
## A text event with a few options (data/events). Options whose cost cannot be paid are disabled.

signal done

var event: EventDef
var autoplay := false
var _options: VBoxContainer
var _continue: Button


func setup(p_event: EventDef) -> EventScreen:
	event = p_event
	return self


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UiModal.new().setup(event.title, 1000)
	add_child(m)
	Audio.play("event_page")
	var head := UiKit.hbox(20)
	head.add_child(UiKit.icon("res://assets/ui/icons/icon_event_256.png", 130))
	var text := UiKit.label(event.text, 23, UiKit.BONE, true)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	m.body.add_child(head)
	m.body.add_child(UiKit.divider(600, true))
	_options = UiKit.vbox(10)
	m.body.add_child(_options)
	for opt in event.options:
		var o: Dictionary = opt
		var parts := option_text(o)
		var ok := Run.can_afford_option(o)
		var b := UiKit.option_button(parts[0], parts[1], func(): _choose(o), UiKit.MUTED, ok)
		if not ok:
			b.tooltip_text = "You cannot pay this."
		_options.add_child(b)
	_continue = UiKit.button("Continue", func(): done.emit(), 24, true)
	_continue.custom_minimum_size.x = 300
	_continue.visible = false
	m.footer.add_child(_continue)
	if autoplay:
		await get_tree().create_timer(0.2).timeout
		var pick: Dictionary = event.options[0]
		for o in event.options:
			if Run.can_afford_option(o):
				pick = o
				break
		_choose(pick)
		await get_tree().create_timer(0.2).timeout
		done.emit()


## [title, detail] for an option: its `detail`, or the part of the label in parentheses, plus the cost.
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
	if detail != "":
		detail = detail.substr(0, 1).to_upper() + detail.substr(1)
	return [title, detail]


func _choose(opt: Dictionary) -> void:
	var text := Run.apply_event_option(opt)
	for c in _options.get_children():
		c.queue_free()
	var l := UiKit.label(text, 23, UiKit.GOLD, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_options.add_child(l)
	_continue.visible = true
