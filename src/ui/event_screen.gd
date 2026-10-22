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
		var label := String(o.get("label", "..."))
		if String(o.get("cost", "")) == "gold":
			label += "   [%d gold]" % int(o.get("cost_amount", 0))
		var b := UiKit.button(label, func(): _choose(o), 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not Run.can_afford_option(o)
		if b.disabled:
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


func _choose(opt: Dictionary) -> void:
	var text := Run.apply_event_option(opt)
	for c in _options.get_children():
		c.queue_free()
	var l := UiKit.label(text, 23, UiKit.GOLD, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_options.add_child(l)
	_continue.visible = true
