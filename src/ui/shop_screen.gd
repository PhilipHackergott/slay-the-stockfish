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
		"\"Everything here belonged to someone who lost to the engine. Prices are fair. Mostly.\"", 680).docked()
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
	var head := UiKit.hbox(18)
	head.add_child(UiKit.caption("Pieces", 20, UiKit.GOLD))
	head.add_child(UiKit.spacer(0, 20))
	var price := Run.reroll_price(node_id)
	var reroll := UiKit.button("New wares  ·  %d gold" % price, func():
		if Run.reroll_shop(node_id):
			Audio.play("shop_buy")
			_rebuild(), 17)
	reroll.disabled = Run.gold < price
	reroll.tooltip_text = "Restock pieces and relics. Each restock here costs %d more." % Content.config.reroll_step
	head.add_child(reroll)
	_wares.add_child(head)
	var row := _flow(14)
	_wares.add_child(row)
	var pieces: Array = stock["pieces"]
	for i in pieces.size():
		row.add_child(_piece_card(i, pieces[i]))
	if pieces.is_empty():
		row.add_child(UiKit.label("The shelves are bare.", 19, UiKit.MUTED))
	_wares.add_child(UiKit.divider(560, true))
	_wares.add_child(UiKit.caption("Relics", 20, UiKit.GOLD))
	var rrow := _flow(14)
	_wares.add_child(rrow)
	var relics: Array = stock["relics"]
	for i in relics.size():
		rrow.add_child(_relic_card(i, relics[i]))
	if relics.is_empty():
		rrow.add_child(UiKit.label("No relics for sale: you carry them all.", 19, UiKit.MUTED))
	_wares.add_child(UiKit.divider(560, true))
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
	_wares.add_child(UiKit.divider(560, true))
	_wares.add_child(UiKit.caption("The Bone Surgeon", 20, UiKit.GOLD))
	_wares.add_child(UiKit.label("Raise a piece one tier for %d gold, graft it to a partner for %d gold, or let it go for %d gold. Pick a piece:" % [
		Run.surgeon_price(), Run.graft_price(), Content.config.dismiss_gold], 18, UiKit.MUTED, true))
	_wares.add_child(_surgeon())


var _surgeon_sel := -1


func _surgeon() -> Control:
	var col := UiKit.vbox(10)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	col.add_child(flow)
	for u in Run.healthy_units():
		if Content.piece(u.type).is_royal():
			continue
		var unit: Unit = u
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = unit.id == _surgeon_sel
		b.custom_minimum_size = Vector2(64, 64)
		b.add_theme_stylebox_override("normal", UiKit.frame("slot", -1.0, 4.0))
		b.add_theme_stylebox_override("hover", UiKit.frame("slot_hover", -1.0, 4.0))
		b.add_theme_stylebox_override("pressed", UiKit.frame("slot_selected", -1.0, 4.0))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var p := UiKit.portrait(unit.type, true, 52)
		p.position = Vector2(6, 6)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(p)
		b.tooltip_text = UiKit.unit_name(unit)
		b.pressed.connect(func():
			_surgeon_sel = unit.id if _surgeon_sel != unit.id else -1
			_rebuild())
		flow.add_child(b)
	var su := Run.unit(_surgeon_sel)
	if su == null or not su.is_healthy():
		return col
	var opts := _flow(10)
	col.add_child(opts)
	var price := Run.surgeon_price()
	for t in Run.upgrade_options(su):
		var target: StringName = t
		var def: PieceDef = Content.piece(target)
		var ob := UiKit.option_button("%s → %s" % [UiKit.unit_name(su), UiKit.piece_name(target)],
			"Tier %d · value %d · %d gold" % [def.tier, def.value, price], func():
				if Run.surgeon_promote(su, target):
					Audio.play("level_up")
					_rebuild(), UiKit.GOLD, Run.gold >= price, 280)
		opts.add_child(ob)
	var graft_cost := Run.graft_price()
	for u in Run.healthy_units():
		var other: Unit = u
		var into := Run.fusion_result(su, other)
		if into == &"":
			continue
		var cmd := maxi(Content.piece(su.type).value, Content.piece(other.type).value) + 1
		opts.add_child(UiKit.option_button("Graft with %s → %s" % [UiKit.unit_name(other), UiKit.piece_name(into)],
			"Command %d · %d gold" % [cmd, graft_cost], func():
				var fused := Run.buy_graft(su, other)
				if fused != null:
					_surgeon_sel = fused.id
					Audio.play("level_up")
				_rebuild(), UiKit.GOLD, Run.gold >= graft_cost, 280))
	var dismiss := UiKit.option_button("Let %s go" % UiKit.unit_name(su), "+%d gold · gone for the run" % Content.config.dismiss_gold,
		func():
			Run.dismiss(su)
			_surgeon_sel = -1
			Audio.play("gold")
			_rebuild(), UiKit.BLOOD, true, 240)
	opts.add_child(dismiss)
	return col


func _flow(gap: int) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.alignment = FlowContainer.ALIGNMENT_CENTER
	f.add_theme_constant_override("h_separation", gap)
	f.add_theme_constant_override("v_separation", gap)
	return f


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
	var parts := UiKit.card(196, 0, func(): pass)
	parts[0].disabled = bool(item["sold"])
	parts[0].mouse_default_cursor_shape = Control.CURSOR_ARROW
	var c: VBoxContainer = parts[1]
	c.add_theme_constant_override("separation", 5)
	c.alignment = BoxContainer.ALIGNMENT_BEGIN
	c.add_child(UiKit.centered(UiKit.portrait(t, true, 96, 0.6 if item["sold"] else 0.0)))
	var n := UiKit.heading(UiKit.piece_name(t), 22)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(n)
	var v := UiKit.label("Tier %d · value %d" % [def.tier, def.value], 16, UiKit.RARITY_COLOR.get(def.rarity, UiKit.MUTED))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(v)
	c.add_child(UiKit.centered(MoveDiagram.make(t, 12.0)))
	var mv := UiKit.label(UiKit.moves_text(t), 15, UiKit.MUTED, true)
	mv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(mv)
	parts[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(parts[0])
	box.add_child(_price_button(int(item["price"]), bool(item["sold"]), func():
		if Run.buy(node_id, "pieces", i) != null:
			Audio.play("shop_buy")
			_rebuild()))
	return box


func _relic_card(i: int, item: Dictionary) -> Control:
	var r: RelicDef = Content.relic(StringName(item["id"]))
	var box := UiKit.vbox(8)
	var parts := UiKit.card(300, 0, func(): pass, UiKit.KIND_COLOR.get(r.kind, UiKit.EDGE))
	parts[0].disabled = bool(item["sold"])
	parts[0].mouse_default_cursor_shape = Control.CURSOR_ARROW
	var c: VBoxContainer = parts[1]
	var h := UiKit.hbox(12)
	h.add_child(UiKit.icon(r.icon, 72, 0.5 if item["sold"] else 0.0))
	var info := UiKit.vbox(2)
	info.custom_minimum_size = Vector2(180, 0)
	info.add_child(UiKit.heading(r.display_name, 20))
	info.add_child(UiKit.caption(UiKit.relic_tag(r), 13, UiKit.KIND_COLOR.get(r.kind, UiKit.MUTED)))
	info.add_child(UiKit.label(r.description, 15, UiKit.MUTED, true))
	h.add_child(info)
	c.add_child(h)
	parts[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
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
