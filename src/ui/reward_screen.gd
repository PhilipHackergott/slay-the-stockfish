class_name RewardScreen
extends Control
## After a won fight: gold and XP summary, level-ups (the only place they happen), a recruit, and a
## relic after elites and guardians.

signal done

var outcome: Dictionary = {}
var kind: StringName = &"fight"
var autoplay := false

var _levels: VBoxContainer
var _recruit: VBoxContainer
var _relic: VBoxContainer
var _continue: Button
var _recruit_done := false
var _relic_done := true


func setup(p_outcome: Dictionary, p_kind: StringName) -> RewardScreen:
	outcome = p_outcome
	kind = p_kind
	_relic_done = not _has_relic()
	return self


func _has_relic() -> bool:
	return kind == &"elite" or kind == &"guardian"


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var enc: EncounterDef = Content.encounter(outcome.get("encounter", &""))
	var title := "The Guardian Falls" if kind == &"guardian" else "Spoils of Victory"
	var m := UiModal.new().setup(title, 1240, false,
		"%s · %s" % [enc.display_name if enc else "Fight", outcome.get("reason", "")], 690)
	add_child(m)
	var col := m.body
	col.add_child(_gold_summary())
	col.add_child(_xp_summary())
	col.add_child(UiKit.divider(700, true))
	col.add_child(UiKit.caption("Level-ups", 20, UiKit.GOLD))
	_levels = UiKit.vbox(12)
	col.add_child(_levels)
	_rebuild_levels()
	col.add_child(UiKit.divider(700, true))
	col.add_child(UiKit.caption("Recruit a piece", 20, UiKit.GOLD))
	_recruit = UiKit.vbox(10)
	col.add_child(_recruit)
	_build_recruits()
	if _has_relic():
		col.add_child(UiKit.divider(700, true))
		col.add_child(UiKit.caption("The %s's relic" % ("guardian" if kind == &"guardian" else "elite"), 20, UiKit.GOLD))
		_relic = UiKit.vbox(10)
		col.add_child(_relic)
		_build_relics()
	_continue = UiKit.button("Continue the descent" if kind != &"guardian" else "Descend further", func(): done.emit(), 26, true)
	_continue.custom_minimum_size.x = 380
	m.footer.add_child(_continue)
	_update_continue()
	if autoplay:
		_auto()


func _gold_summary() -> Control:
	var h := UiKit.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var g := int(outcome.get("gold", 0))
	var o := int(outcome.get("overflow_gold", 0))
	h.add_child(UiKit.gold_label(g + o, 30))
	var parts: Array = ["%d for the victory" % g]
	if o > 0:
		parts.append("%d from XP your finished pieces could not use" % o)
	h.add_child(UiKit.label(" · ".join(parts), 20, UiKit.MUTED))
	if g + o > 0:
		Audio.play("gold")
	return h


func _xp_summary() -> Control:
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", 26)
	box.add_theme_constant_override("v_separation", 6)
	box.alignment = FlowContainer.ALIGNMENT_CENTER
	var per: Dictionary = {}
	for e in outcome.get("xp", []):
		var id := int(e["unit"])
		if not per.has(id):
			per[id] = [0, 0]
		per[id][0] += int(e["amount"])
		per[id][1] += 1
	if per.is_empty():
		box.add_child(UiKit.label("No captures this fight: no XP gained.", 20, UiKit.MUTED))
	for id in per:
		var u := Run.unit(id)
		if u == null:
			continue
		var h := UiKit.hbox(8)
		h.add_child(UiKit.portrait(u.type, true, 44))
		h.add_child(UiKit.label("%s  +%d XP" % [UiKit.unit_name(u), per[id][0]], 20, UiKit.GOLD))
		box.add_child(h)
	return box


func _rebuild_levels() -> void:
	for c in _levels.get_children():
		c.queue_free()
	var pending := Run.pending_level_ups()
	if pending.is_empty():
		_levels.add_child(UiKit.label("No piece has enough XP to rise yet.", 19, UiKit.MUTED))
		return
	for u in pending:
		var block := UiKit.vbox(8)
		var row := UiKit.hbox(14)
		row.add_child(UiKit.portrait(u.type, true, 72))
		var info := UiKit.vbox(2)
		info.add_child(UiKit.heading(UiKit.unit_name(u), 24))
		info.add_child(UiKit.label("%d / %d XP · level %d → %d · choose what it becomes" % [u.xp, Run.xp_needed(u), u.level, u.level + 1], 18, UiKit.GOLD))
		row.add_child(info)
		block.add_child(row)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 14)
		flow.add_theme_constant_override("v_separation", 14)
		for opt in Run.upgrade_options(u):
			var t: StringName = opt
			flow.add_child(_upgrade_card(u, t))
		block.add_child(flow)
		_levels.add_child(block)


func _upgrade_card(u: Unit, t: StringName) -> Control:
	var def: PieceDef = Content.piece(t)
	var parts := UiKit.card(214, 236, func():
		Run.level_up(u, t)
		Audio.play("level_up")
		_rebuild_levels())
	var c: VBoxContainer = parts[1]
	c.add_theme_constant_override("separation", 4)
	c.add_child(UiKit.centered(UiKit.portrait(t, true, 84)))
	var n := UiKit.heading(UiKit.piece_name(t), 20)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(n)
	if def != null:
		c.add_child(UiKit.rarity_badge(def.rarity))
		var v := UiKit.label("Value %d%s" % [def.value, " · final form" if def.is_final() else ""], 16, UiKit.MUTED)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(v)
		parts[0].tooltip_text = "%s\n%s" % [def.moves_text, def.flavor]
	return parts[0]


func _build_recruits() -> void:
	for c in _recruit.get_children():
		c.queue_free()
	var row := UiKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_recruit.add_child(row)
	for opt in Run.reward_choices(kind):
		var t: StringName = opt
		var def: PieceDef = Content.piece(t)
		var parts := UiKit.card(270, 360, func(): _take_recruit(t))
		var c: VBoxContainer = parts[1]
		c.add_theme_constant_override("separation", 6)
		c.add_child(UiKit.centered(UiKit.portrait(t, true, 128)))
		var n := UiKit.heading(UiKit.piece_name(t), 24)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(n)
		c.add_child(UiKit.rarity_badge(def.rarity if def else &"common"))
		var v := UiKit.label("Value %d" % (def.value if def else 0), 17, UiKit.GOLD)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(v)
		var mv := UiKit.label(UiKit.moves_text(t), 16, UiKit.MUTED, true)
		mv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(mv)
		row.add_child(parts[0])
	row.add_child(UiKit.centered(UiKit.button("Skip", func(): _take_recruit(&""))))


func _take_recruit(t: StringName) -> void:
	for c in _recruit.get_children():
		c.queue_free()
	if t == &"":
		_recruit.add_child(UiKit.label("You march on without a recruit.", 20, UiKit.MUTED))
	else:
		var u := Run.add_unit(t)
		var h := UiKit.hbox(10)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(UiKit.portrait(t, true, 56))
		h.add_child(UiKit.label("%s joins your army." % UiKit.unit_name(u), 22, UiKit.SOUL))
		_recruit.add_child(h)
		Audio.play("piece_spawn")
	_recruit_done = true
	_update_continue()


func _build_relics() -> void:
	var n := Content.config.guardian_relic_choices if kind == &"guardian" else Content.config.elite_relic_choices
	var ids := Run.relic_choices(n)
	if ids.is_empty():
		_relic.add_child(UiKit.label("You already carry every relic.", 20, UiKit.MUTED))
		_relic_done = true
		return
	var row := UiKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_relic.add_child(row)
	for id in ids:
		var r: RelicDef = Content.relic(id)
		var parts := UiKit.card(340, 190, func(): _take_relic(r.id), UiKit.KIND_COLOR.get(r.kind, UiKit.EDGE))
		var c: VBoxContainer = parts[1]
		var h := UiKit.hbox(12)
		h.add_child(UiKit.icon(r.icon, 96))
		var info := UiKit.vbox(2)
		info.custom_minimum_size = Vector2(180, 0)
		info.add_child(UiKit.heading(r.display_name, 20))
		info.add_child(UiKit.caption(String(UiKit.KIND_LABEL.get(r.kind, r.kind)), 13, UiKit.KIND_COLOR.get(r.kind, UiKit.MUTED)))
		info.add_child(UiKit.label(r.description, 15, UiKit.MUTED, true))
		h.add_child(info)
		c.add_child(h)
		row.add_child(parts[0])
	row.add_child(UiKit.centered(UiKit.button("Skip", func(): _take_relic(&""))))


func _take_relic(id: StringName) -> void:
	for c in _relic.get_children():
		c.queue_free()
	if id != &"":
		Run.add_relic(id)
		Audio.play("relic")
		_relic.add_child(UiKit.label("You claim %s." % Content.relic(id).display_name, 22, UiKit.SOUL))
	else:
		_relic.add_child(UiKit.label("You leave the relic behind.", 20, UiKit.MUTED))
	_relic_done = true
	_update_continue()


func _update_continue() -> void:
	if _continue != null:
		_continue.disabled = not (_recruit_done and _relic_done)


func _auto() -> void:
	await get_tree().create_timer(0.2).timeout
	while not Run.pending_level_ups().is_empty():
		var u: Unit = Run.pending_level_ups()[0]
		Run.level_up(u, Run.upgrade_options(u)[0])
	_rebuild_levels()
	var choices := Run.reward_choices(kind)
	_take_recruit(choices[0] if not choices.is_empty() else &"")
	if _has_relic():
		var ids := Run.relic_choices(1)
		_take_relic(ids[0] if not ids.is_empty() else &"")
	await get_tree().create_timer(0.2).timeout
	done.emit()
