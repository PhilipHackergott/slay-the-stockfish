class_name TreasureScreen
extends Control
## A sealed reliquary: a little gold and one relic of a few.

signal done

var autoplay := false
var _relic: VBoxContainer
var _ids: Array = []
var _leave: Button


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := Content.config
	var gold := Run.rng.randi_range(c.treasure_gold[0], c.treasure_gold[1])
	Run.add_gold(gold)
	_ids = Run.relic_choices(Run.relic_card_count(c.treasure_relic_choices), "treasure")
	var m := UiModal.new().setup("A Sealed Reliquary", 1100, false,
		"Someone hid this from the engine. The lock gives under your king's hand.")
	add_child(m)
	var top := UiKit.hbox(12)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(UiKit.icon("res://assets/ui/icons/icon_treasure_256.png", 120))
	var g := UiKit.vbox(4)
	g.add_child(UiKit.gold_label(gold, 30))
	g.add_child(UiKit.label("in tarnished coin", 18, UiKit.MUTED))
	top.add_child(g)
	m.body.add_child(top)
	Audio.play("gold")
	m.body.add_child(UiKit.divider(600, true))
	m.body.add_child(UiKit.caption("Take one relic", 20, UiKit.GOLD))
	_relic = UiKit.vbox(10)
	m.body.add_child(_relic)
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	_relic.add_child(flow)
	for id in _ids:
		var r: RelicDef = Content.relic(id)
		flow.add_child(UiKit.relic_card(r, func(): _take(r.id)))
	if _ids.is_empty():
		_relic.add_child(UiKit.label("The reliquary holds nothing you lack.", 20, UiKit.MUTED))
	_leave = UiKit.button("Leave it be" if not _ids.is_empty() else "Continue", func(): done.emit(), 22, _ids.is_empty())
	m.footer.add_child(_leave)
	if autoplay:
		await get_tree().create_timer(0.3).timeout
		if not _ids.is_empty():
			_take(_ids[0])
		done.emit()


func _take(id: StringName) -> void:
	Run.add_relic(id)
	Audio.play("relic")
	for c in _relic.get_children():
		c.queue_free()
	_relic.add_child(UiKit.label("You claim %s." % Content.relic(id).display_name, 22, UiKit.SOUL))
	_leave.text = "Continue"
