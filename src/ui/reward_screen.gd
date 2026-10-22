class_name RewardScreen
extends Control
## After a won fight: XP summary, level-ups (the only place they happen), a recruit, and a relic
## after elites.

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
	_relic_done = p_kind != &"elite"
	return self


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0.02, 0.5)
	UiKit.full(shade)
	add_child(shade)
	add_child(UiKit.vignette())
	var p := UiKit.panel(UiKit.GOLD, Color(0.03, 0.025, 0.045, 0.94), 26)
	p.custom_minimum_size = Vector2(1180, 0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1130, 900)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var col := UiKit.vbox(14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	var cc := UiKit.centered(p)
	UiKit.full(cc)
	add_child(cc)
	var enc: EncounterDef = Content.encounter(outcome.get("encounter", &""))
	var t := UiKit.title("Spoils of Victory", 56, UiKit.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var sub := UiKit.label("%s · %s" % [enc.display_name if enc else "Fight", outcome.get("reason", "")], 22, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(_xp_summary())
	col.add_child(UiKit.heading("Level-ups", 28))
	_levels = UiKit.vbox(10)
	col.add_child(_levels)
	_rebuild_levels()
	col.add_child(UiKit.heading("Recruit a piece", 28))
	_recruit = UiKit.vbox(10)
	col.add_child(_recruit)
	_build_recruits()
	if kind == &"elite":
		col.add_child(UiKit.heading("The elite's relic", 28))
		_relic = UiKit.vbox(10)
		col.add_child(_relic)
		_build_relics()
	_continue = UiKit.button("Continue the descent", func(): done.emit(), 26)
	col.add_child(UiKit.spacer(6))
	col.add_child(UiKit.centered(_continue))
	_update_continue()
	UiKit.fade_in(self)
	if autoplay:
		_auto()


func _xp_summary() -> Control:
	var box := UiKit.vbox(4)
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
		var h := UiKit.hbox(10)
		h.add_child(UiKit.portrait(u.type, true, 40))
		h.add_child(UiKit.label("%s  +%d XP  (%d capture%s)" % [UiKit.unit_name(u), per[id][0], per[id][1], "" if per[id][1] == 1 else "s"], 21, UiKit.GOLD))
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
		var row := UiKit.hbox(14)
		row.add_child(UiKit.portrait(u.type, true, 72))
		var info := UiKit.vbox(2)
		info.custom_minimum_size = Vector2(330, 0)
		info.add_child(UiKit.heading(UiKit.unit_name(u), 22))
		info.add_child(UiKit.label("%d / %d XP · level %d → %d" % [u.xp, Run.xp_needed(u), u.level, u.level + 1], 18, UiKit.GOLD))
		row.add_child(info)
		for opt in Run.upgrade_options(u):
			var t: StringName = opt
			var parts := UiKit.card(190, 92, func():
				Run.level_up(u, t)
				_rebuild_levels(), UiKit.GOLD)
			var c: VBoxContainer = parts[1]
			var h := UiKit.hbox(8)
			h.add_child(UiKit.portrait(t, true, 52))
			h.add_child(UiKit.heading(UiKit.piece_name(t), 20))
			c.add_child(h)
			row.add_child(parts[0])
		_levels.add_child(row)


func _build_recruits() -> void:
	for c in _recruit.get_children():
		c.queue_free()
	var row := UiKit.hbox(18)
	_recruit.add_child(row)
	for opt in Run.reward_choices(kind):
		var t: StringName = opt
		var def: PieceDef = Content.piece(t)
		var parts := UiKit.card(250, 300, func(): _take_recruit(t))
		var c: VBoxContainer = parts[1]
		c.add_child(UiKit.centered(UiKit.portrait(t, true, 130)))
		var n := UiKit.heading(UiKit.piece_name(t), 24)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(n)
		var v := UiKit.label("Value %d" % (def.value if def else 0), 17, UiKit.GOLD)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(v)
		var m := UiKit.label(UiKit.MOVES.get(t, ""), 16, UiKit.MUTED, true)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(m)
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
		h.add_child(UiKit.portrait(t, true, 56))
		h.add_child(UiKit.label("%s joins your army." % UiKit.unit_name(u), 22, UiKit.SOUL))
		_recruit.add_child(h)
	_recruit_done = true
	_update_continue()


func _build_relics() -> void:
	var ids := Run.relic_choices(Content.config.elite_relic_choices)
	if ids.is_empty():
		_relic.add_child(UiKit.label("You already carry every relic.", 20, UiKit.MUTED))
		_relic_done = true
		return
	var row := UiKit.hbox(18)
	_relic.add_child(row)
	for id in ids:
		var r: RelicDef = Content.relic(id)
		var parts := UiKit.card(360, 150, func(): _take_relic(r.id), UiKit.KIND_COLOR.get(r.kind, UiKit.EDGE))
		var c: VBoxContainer = parts[1]
		var h := UiKit.hbox(12)
		h.add_child(UiKit.icon(r.icon, 100))
		var info := UiKit.vbox(2)
		info.custom_minimum_size = Vector2(200, 0)
		info.add_child(UiKit.heading(r.display_name, 20))
		info.add_child(UiKit.label(r.description, 16, UiKit.MUTED, true))
		h.add_child(info)
		c.add_child(h)
		row.add_child(parts[0])
	row.add_child(UiKit.centered(UiKit.button("Skip", func(): _take_relic(&""))))


func _take_relic(id: StringName) -> void:
	for c in _relic.get_children():
		c.queue_free()
	if id != &"":
		Run.add_relic(id)
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
	if kind == &"elite":
		var ids := Run.relic_choices(1)
		_take_relic(ids[0] if not ids.is_empty() else &"")
	await get_tree().create_timer(0.2).timeout
	done.emit()
