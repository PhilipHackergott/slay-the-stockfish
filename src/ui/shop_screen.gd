class_name ShopScreen
extends Control
## The bone merchant: pieces, relics, and restoring the fallen, for gold. Stock is rolled once per
## shop node (Run.shop) so leaving and continuing shows the same wares.

signal done

var node_id := -1
var autoplay := false
var _gold: HBoxContainer
var _wares: VBoxContainer


func setup(p_node_id: int) -> ShopScreen:
	node_id = p_node_id
	return self


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UiModal.new().setup("The Bone Merchant", 1280, false,
		"\"Everything here belonged to someone who lost to the engine. Prices are fair. Mostly.\"", 680)
	add_child(m)
	var top := UiKit.hbox(10)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(UiKit.caption("Your purse", 18, UiKit.MUTED))
	_gold = UiKit.gold_label(Run.gold, 30)
	top.add_child(_gold)
	m.body.add_child(top)
	_wares = UiKit.vbox(14)
	m.body.add_child(_wares)
	_rebuild()
	var leave := UiKit.button("Leave the merchant", func(): done.emit(), 24, true)
	leave.custom_minimum_size.x = 340
	m.footer.add_child(leave)
	Run.changed.connect(_refresh_gold)
	if autoplay:
		_auto()


func _exit_tree() -> void:
	if Run.changed.is_connected(_refresh_gold):
		Run.changed.disconnect(_refresh_gold)


func _refresh_gold() -> void:
	if _gold != null:
		(_gold.get_child(1) as Label).text = str(Run.gold)


func _rebuild() -> void:
	for c in _wares.get_children():
		c.queue_free()
	var stock := Run.shop(node_id)
	_wares.add_child(UiKit.caption("Pieces", 20, UiKit.GOLD))
	var row := UiKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_wares.add_child(row)
	var pieces: Array = stock["pieces"]
	for i in pieces.size():
		row.add_child(_piece_card(i, pieces[i]))
	if pieces.is_empty():
		row.add_child(UiKit.label("The shelves are bare.", 19, UiKit.MUTED))
	_wares.add_child(UiKit.divider(700, true))
	_wares.add_child(UiKit.caption("Relics", 20, UiKit.GOLD))
	var rrow := UiKit.hbox(18)
	rrow.alignment = BoxContainer.ALIGNMENT_CENTER
	_wares.add_child(rrow)
	var relics: Array = stock["relics"]
	for i in relics.size():
		rrow.add_child(_relic_card(i, relics[i]))
	if relics.is_empty():
		rrow.add_child(UiKit.label("No relics for sale: you carry them all.", 19, UiKit.MUTED))
	_wares.add_child(UiKit.divider(700, true))
	_wares.add_child(UiKit.caption("Raise the fallen", 20, UiKit.SOUL))
	var slain := Run.slain_units()
	if slain.is_empty():
		_wares.add_child(UiKit.label("No one needs raising.", 19, UiKit.MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 24)
	flow.add_theme_constant_override("v_separation", 10)
	_wares.add_child(flow)
	for u in slain:
		var h := UiKit.hbox(8)
		h.add_child(UiKit.portrait(u.type, true, 48, 0.5))
		h.add_child(UiKit.label(UiKit.unit_name(u), 18))
		var b := _price_button(Run.restore_price(), false, func():
			if Run.buy_restore(u):
				Audio.play("shop_buy")
				_rebuild())
		h.add_child(b)
		flow.add_child(h)


func _price_button(price: int, sold: bool, cb: Callable) -> Button:
	var b := UiKit.button("Sold" if sold else "Buy  ·  %d gold" % price, cb, 18, not sold and Run.gold >= price)
	b.disabled = sold or Run.gold < price
	if not sold and Run.gold < price:
		b.tooltip_text = "Not enough gold."
	return b


func _piece_card(i: int, item: Dictionary) -> Control:
	var t := StringName(item["id"])
	var def: PieceDef = Content.piece(t)
	var box := UiKit.vbox(8)
	var parts := UiKit.card(260, 340, func(): pass)
	parts[0].disabled = bool(item["sold"])
	parts[0].mouse_default_cursor_shape = Control.CURSOR_ARROW
	var c: VBoxContainer = parts[1]
	c.add_theme_constant_override("separation", 5)
	c.add_child(UiKit.centered(UiKit.portrait(t, true, 120, 0.6 if item["sold"] else 0.0)))
	var n := UiKit.heading(UiKit.piece_name(t), 23)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(n)
	c.add_child(UiKit.rarity_badge(def.rarity if def else &"common"))
	var mv := UiKit.label(UiKit.moves_text(t), 16, UiKit.MUTED, true)
	mv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(mv)
	box.add_child(parts[0])
	box.add_child(_price_button(int(item["price"]), bool(item["sold"]), func():
		if Run.buy(node_id, "pieces", i) != null:
			Audio.play("shop_buy")
			_rebuild()))
	return box


func _relic_card(i: int, item: Dictionary) -> Control:
	var r: RelicDef = Content.relic(StringName(item["id"]))
	var box := UiKit.vbox(8)
	var parts := UiKit.card(380, 200, func(): pass, UiKit.KIND_COLOR.get(r.kind, UiKit.EDGE))
	parts[0].disabled = bool(item["sold"])
	parts[0].mouse_default_cursor_shape = Control.CURSOR_ARROW
	var c: VBoxContainer = parts[1]
	var h := UiKit.hbox(12)
	h.add_child(UiKit.icon(r.icon, 100, 0.5 if item["sold"] else 0.0))
	var info := UiKit.vbox(2)
	info.custom_minimum_size = Vector2(210, 0)
	info.add_child(UiKit.heading(r.display_name, 20))
	info.add_child(UiKit.caption(String(UiKit.KIND_LABEL.get(r.kind, r.kind)), 13, UiKit.KIND_COLOR.get(r.kind, UiKit.MUTED)))
	info.add_child(UiKit.label(r.description, 15, UiKit.MUTED, true))
	h.add_child(info)
	c.add_child(h)
	box.add_child(parts[0])
	box.add_child(_price_button(int(item["price"]), bool(item["sold"]), func():
		if Run.buy(node_id, "relics", i) != null:
			Audio.play("relic")
			_rebuild()))
	return box


func _auto() -> void:
	await get_tree().create_timer(0.2).timeout
	var stock := Run.shop(node_id)
	for i in stock["pieces"].size():
		if Run.buy(node_id, "pieces", i) != null:
			break
	await get_tree().create_timer(0.2).timeout
	done.emit()
