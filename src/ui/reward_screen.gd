class_name RewardScreen
extends Control
## After a won fight: gold and XP, level-ups (a next-tier promotion or a perk), recruits from one
## tier (or a Train slot), an Ascension after guardians, and a relic after elites and guardians.

signal done

var outcome: Dictionary = {}
var kind: StringName = &"fight"
var autoplay := false

var _levels: VBoxContainer
var _recruit: VBoxContainer
var _ascend: VBoxContainer
var _relic: VBoxContainer
var _command: Label
var _continue: Button
var _offer: Dictionary = {}
var _relic_ids: Array = []
var _recruit_done := false
var _ascend_done := true
var _relic_done := true


func setup(p_outcome: Dictionary, p_kind: StringName) -> RewardScreen:
	outcome = p_outcome
	kind = p_kind
	_relic_done = not _has_relic()
	_ascend_done = kind != &"guardian"
	return self


func _has_relic() -> bool:
	return kind == &"elite" or kind == &"guardian" or kind == &"roamer" or bool(outcome.get("flawless_relic", false))


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offer = Run.reward_offer(kind)
	var enc: EncounterDef = Content.encounter(outcome.get("encounter", &""))
	var title := "The Guardian Falls" if kind == &"guardian" else "Spoils of Victory"
	var m := UiModal.new().setup(title, 1280, false,
		"%s · %s" % [enc.display_name if enc else "Fight", outcome.get("reason", "")], 720)
	add_child(m)
	var col := m.body
	var head := _xp_summary()
	head.add_child(_gold_summary())
	head.move_child(head.get_child(-1), 0)
	_command = UiKit.label("", 19, UiKit.GOLD)
	head.add_child(_command)
	col.add_child(head)
	col.add_child(UiKit.divider(700, true))
	col.add_child(UiKit.caption("Level-ups", 20, UiKit.GOLD))
	_levels = UiKit.vbox(12)
	col.add_child(_levels)
	_rebuild_levels()
	col.add_child(UiKit.divider(700, true))
	col.add_child(UiKit.caption("Recruit · tier %d" % int(_offer["tier"]), 20, UiKit.GOLD))
	_recruit = UiKit.vbox(10)
	col.add_child(_recruit)
	_build_recruits()
	if kind == &"guardian":
		col.add_child(UiKit.divider(700, true))
		col.add_child(UiKit.caption("Ascension", 20, UiKit.RARITY_COLOR[&"legendary"]))
		_ascend = UiKit.vbox(10)
		col.add_child(_ascend)
		_build_ascension()
	if _has_relic():
		col.add_child(UiKit.divider(700, true))
		col.add_child(UiKit.caption(_relic_caption(), 20, UiKit.GOLD))
		_relic = UiKit.vbox(10)
		col.add_child(_relic)
		_build_relics()
	_continue = UiKit.button("Continue the descent" if kind != &"guardian" else "Descend further", func(): done.emit(), 26, true)
	_continue.custom_minimum_size.x = 380
	m.footer.add_child(_continue)
	Run.changed.connect(_refresh_command)
	_refresh_command()
	_update_continue()
	if autoplay:
		_auto()


func _exit_tree() -> void:
	if Run.changed.is_connected(_refresh_command):
		Run.changed.disconnect(_refresh_command)


func _refresh_command() -> void:
	if _command == null:
		return
	var cap := Run.command_cap()
	_command.text = "Command %d / %d · %d on the bench" % [Run.command_used(), cap, Run.benched_units().size()] if cap > 0 else ""


func _gold_summary() -> Control:
	var h := UiKit.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var g := int(outcome.get("gold", 0))
	var o := int(outcome.get("overflow_gold", 0))
	var b := int(outcome.get("bounty_gold", 0))
	var t := int(outcome.get("time_gold", 0))
	h.add_child(UiKit.gold_label(g + o + b + t, 30))
	var parts: Array = ["%d for the victory" % g]
	if t > 0:
		parts.append("%d from your clock" % t)
	if o > 0:
		parts.append("%d from XP your finished pieces could not use" % o)
	if b > 0:
		parts.append("%d in bounties" % b)
	h.add_child(UiKit.label(" · ".join(parts), 20, UiKit.MUTED))
	if g + o + b + t > 0:
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
	for id in outcome.get("saved", []):
		var u := Run.unit(int(id))
		if u != null and u.has_perk(&"bulwark"):
			box.add_child(UiKit.label("%s gets back up (Bulwark)" % UiKit.unit_name(u), 20, UiKit.SOUL))
	for note in outcome.get("relic_notes", []):
		box.add_child(UiKit.label(String(note), 19, UiKit.SOUL))
	return box


# --- level-ups --------------------------------------------------------------------------------

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
		row.add_child(UiKit.portrait(u.type, true, 56))
		var info := UiKit.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.heading(UiKit.unit_name(u), 22))
		var bench := " · on the bench" if u.is_benched() else ""
		info.add_child(UiKit.label("%d / %d XP · level %d → %d · rise one tier, or keep its form and take a perk%s" % [
			u.xp, Run.xp_needed(u), u.level, u.level + 1, bench], 18, UiKit.GOLD, true))
		row.add_child(info)
		block.add_child(row)
		var flow := _flow()
		for opt in Run.upgrade_options(u):
			var t: StringName = opt
			flow.add_child(UiKit.piece_card(t, func():
				Run.level_up(u, t)
				Audio.play("level_up")
				_rebuild_levels(), UiKit.command_note(u, t)))
		var perk := Run.perk_option(u)
		if perk != &"":
			flow.add_child(_perk_card(perk, func():
				Run.take_perk(u, perk)
				Audio.play("level_up")
				_rebuild_levels()))
		block.add_child(flow)
		_levels.add_child(block)


func _flow() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	return flow


func _perk_card(perk: StringName, cb: Callable) -> Control:
	var p: PerkDef = Content.perk(perk)
	var parts := UiKit.card(236, 0, cb, UiKit.SOUL)
	var c: VBoxContainer = parts[1]
	c.add_theme_constant_override("separation", 6)
	c.add_child(UiKit.centered(UiKit.icon(p.icon, 96)))
	var n := UiKit.heading(p.display_name, 20)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(n)
	var k := UiKit.caption("Perk · keeps its form", 14, UiKit.SOUL)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(k)
	var d := UiKit.label(p.description, 16, UiKit.BONE, true)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(d)
	return parts[0]


# --- recruits ---------------------------------------------------------------------------------

func _build_recruits() -> void:
	for c in _recruit.get_children():
		c.queue_free()
	var flow := _flow()
	_recruit.add_child(flow)
	for opt in _offer["pieces"]:
		var t: StringName = opt
		flow.add_child(UiKit.piece_card(t, func(): _take_recruit(t), _fit_note(t), 260))
	if int(_offer["train"]) > 0:
		flow.add_child(_train_card(int(_offer["train"])))
	var skip := UiKit.button("Skip  ·  +%d gold" % Content.config.skip_gold, func(): _take_recruit(&""), 20)
	flow.add_child(UiKit.centered(skip))


func _fit_note(t: StringName) -> String:
	var cap := Run.command_cap()
	if cap <= 0:
		return ""
	var cost := Content.piece(t).value
	if Run.command_used() + cost <= cap:
		return "Deploys · Command %d → %d / %d" % [Run.command_used(), Run.command_used() + cost, cap]
	return "Joins the bench · no Command left for it"


func _train_card(xp: int) -> Control:
	var parts := UiKit.card(260, 0, func(): _choose_train(xp), UiKit.GOLD)
	var c: VBoxContainer = parts[1]
	c.add_child(UiKit.centered(UiKit.icon("res://assets/ui/icons/icon_reward_train_256.png", 110)))
	var n := UiKit.heading("Train", 22)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(n)
	var d := UiKit.label("+%d XP to one piece you already have." % xp, 17, UiKit.BONE, true)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(d)
	return parts[0]


func _choose_train(xp: int) -> void:
	for c in _recruit.get_children():
		c.queue_free()
	_recruit.add_child(UiKit.label("Who trains? (+%d XP)" % xp, 20, UiKit.GOLD))
	var flow := _flow()
	_recruit.add_child(flow)
	for u in Run.healthy_units():
		var unit: Unit = u
		var b := UiKit.option_button(UiKit.unit_name(unit), "%d XP · %s" % [unit.xp, "bench" if unit.is_benched() else "deployed"], func():
			Run.train(unit, xp)
			Audio.play("level_up")
			_finish_recruit("%s trains hard: +%d XP." % [UiKit.unit_name(unit), xp], unit.type)
			_rebuild_levels(), UiKit.MUTED, true, 260)
		flow.add_child(b)


func _take_recruit(t: StringName) -> void:
	if t == &"":
		Run.add_gold(Content.config.skip_gold)
		_finish_recruit("You march on without a recruit (+%d gold)." % Content.config.skip_gold, &"")
		return
	var u := Run.add_unit(t)
	Audio.play("piece_spawn")
	_finish_recruit("%s joins your army%s." % [UiKit.unit_name(u), " on the bench" if u.is_benched() else ""], t)


func _finish_recruit(text: String, t: StringName) -> void:
	for c in _recruit.get_children():
		c.queue_free()
	var h := UiKit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	if t != &"":
		h.add_child(UiKit.portrait(t, true, 56))
	h.add_child(UiKit.label(text, 22, UiKit.SOUL if t != &"" else UiKit.MUTED))
	_recruit.add_child(h)
	_recruit_done = true
	_update_continue()


# --- ascension --------------------------------------------------------------------------------

func _build_ascension() -> void:
	for c in _ascend.get_children():
		c.queue_free()
	var cands := Run.healthy_units().filter(func(u): return not Run.ascension_options(u).is_empty())
	if cands.is_empty():
		_ascend.add_child(UiKit.label("None of your pieces stands at tier 5 yet. A tier-5 piece could rise to a legend here.", 19, UiKit.MUTED, true))
		_ascend_done = true
		return
	_ascend_done = false
	_ascend.add_child(UiKit.label("The guardian's power seeps into the board. One tier-5 piece may become a legend.", 19, UiKit.BONE, true))
	for u in cands:
		var unit: Unit = u
		_ascend.add_child(UiKit.heading(UiKit.unit_name(unit), 20))
		var flow := _flow()
		for t in Run.ascension_options(unit):
			var legend: StringName = t
			flow.add_child(UiKit.piece_card(legend, func(): _take_ascension(unit, legend)))
		_ascend.add_child(flow)
	_ascend.add_child(UiKit.centered(UiKit.button("Not now", func(): _take_ascension(null, &""), 20)))


func _take_ascension(u: Unit, legend: StringName) -> void:
	for c in _ascend.get_children():
		c.queue_free()
	if u == null:
		_ascend.add_child(UiKit.label("The power fades back into the stone.", 20, UiKit.MUTED))
	else:
		var before := UiKit.unit_name(u)
		Run.ascend(u, legend)
		Audio.play("level_up")
		var h := UiKit.hbox(10)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(UiKit.portrait(legend, true, 64))
		h.add_child(UiKit.label("%s ascends: %s." % [before, UiKit.piece_name(legend)], 22, UiKit.RARITY_COLOR[&"legendary"]))
		_ascend.add_child(h)
	_ascend_done = true
	_update_continue()


# --- relics -----------------------------------------------------------------------------------

func _flawless() -> bool:
	return bool(outcome.get("flawless", false))


func _relic_caption() -> String:
	match kind:
		&"guardian":
			return "The guardian's relic"
		&"elite", &"roamer":
			return "The elite's relic" + (" · flawless: one more card" if _flawless() else "")
	return "A flawless victory: a relic"


func _relic_ids_for_kind() -> Array:
	var c := Content.config
	match kind:
		&"guardian":
			return Run.relic_choices(Run.relic_card_count(c.guardian_relic_choices), "guardian")
		&"elite", &"roamer":
			return Run.relic_choices(Run.relic_card_count(c.elite_relic_choices + (1 if _flawless() else 0)), String(kind))
	return Run.relic_choices(Run.relic_card_count(2), "flawless")


func _build_relics() -> void:
	_relic_ids = _relic_ids_for_kind()
	if _relic_ids.is_empty():
		_relic.add_child(UiKit.label("You already carry every relic.", 20, UiKit.MUTED))
		_relic_done = true
		return
	var flow := _flow()
	_relic.add_child(flow)
	for id in _relic_ids:
		var r: RelicDef = Content.relic(id)
		flow.add_child(UiKit.relic_card(r, func(): _take_relic(r.id)))
	flow.add_child(UiKit.centered(UiKit.button("Skip", func(): _take_relic(&""))))


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
		_continue.disabled = not (_recruit_done and _relic_done and _ascend_done)


func _auto() -> void:
	await get_tree().create_timer(0.2).timeout
	var guard := 0
	while not Run.pending_level_ups().is_empty() and guard < 40:
		guard += 1
		var u: Unit = Run.pending_level_ups()[0]
		var opts := Run.upgrade_options(u)
		if not opts.is_empty():
			Run.level_up(u, opts[0])
		else:
			Run.take_perk(u, Run.perk_option(u))
	_rebuild_levels()
	var pieces: Array = _offer["pieces"]
	if not pieces.is_empty():
		_take_recruit(pieces[0])
	elif int(_offer["train"]) > 0:
		Run.train(Run.healthy_units()[0], int(_offer["train"]))
		_finish_recruit("trained", &"")
	else:
		_take_recruit(&"")
	if kind == &"guardian" and not _ascend_done:
		for u in Run.healthy_units():
			var opts := Run.ascension_options(u)
			if not opts.is_empty():
				_take_ascension(u, opts[0])
				break
	if _has_relic() and not _relic_done:
		_take_relic(_relic_ids[0] if not _relic_ids.is_empty() else &"")
	await get_tree().create_timer(0.2).timeout
	done.emit()
