class_name EventScreen
extends Control
## A text event with a few options (data/events).

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
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0.02, 0.5)
	UiKit.full(shade)
	add_child(shade)
	add_child(UiKit.vignette())
	var p := UiKit.panel(UiKit.EDGE, Color(0.03, 0.025, 0.045, 0.94), 28)
	p.custom_minimum_size = Vector2(960, 0)
	var col := UiKit.vbox(14)
	p.add_child(col)
	var cc := UiKit.centered(p)
	UiKit.full(cc)
	add_child(cc)
	var head := UiKit.hbox(18)
	head.add_child(UiKit.icon("res://assets/ui/icons/icon_event_256.png", 120))
	var hc := UiKit.vbox(6)
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.add_child(UiKit.title(event.title, 46))
	hc.add_child(UiKit.label(event.text, 22, UiKit.BONE, true))
	head.add_child(hc)
	col.add_child(head)
	_options = UiKit.vbox(10)
	col.add_child(_options)
	for opt in event.options:
		var o: Dictionary = opt
		var b := UiKit.button(String(o.get("label", "...")), func(): _choose(o), 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_options.add_child(b)
	_continue = UiKit.button("Continue", func(): done.emit(), 24)
	_continue.visible = false
	col.add_child(UiKit.centered(_continue))
	UiKit.fade_in(self)
	if autoplay:
		await get_tree().create_timer(0.2).timeout
		_choose(event.options[0])
		await get_tree().create_timer(0.2).timeout
		done.emit()


func _choose(opt: Dictionary) -> void:
	var text := Run.apply_event_option(opt)
	for c in _options.get_children():
		c.queue_free()
	_options.add_child(UiKit.label(text, 23, UiKit.GOLD, true))
	_continue.visible = true
