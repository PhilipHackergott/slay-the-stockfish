class_name CampfireScreen
extends Control
## Rest at the fire: choose one of Mend, Temper, Drill, Study, Rite of Ash, Kindle, Cleanse.

signal done

const ICON := "res://assets/ui/icons/icon_camp_%s_256.png"

var autoplay := false
var _body: VBoxContainer
var _leave: Button
var _mend: Array = []
var _burn: Unit


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UiModal.new().setup("The Campfire", 1560, false, "", 720).docked()
	m.accent = Color(1.0, 0.72, 0.45)
	add_child(m)
	var head := UiKit.hbox(18)
	head.add_child(UiKit.icon("res://assets/ui/icons/icon_campfire_256.png", 80))
	var l := UiKit.label("The fire burns low and blue. There is time for one thing before you descend. Choose it well.", 22, UiKit.BONE, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	m.body.add_child(head)
	m.body.add_child(UiKit.divider(560, true))
	_body = UiKit.vbox(12)
	m.body.add_child(_body)
	_menu()
	_leave = UiKit.button("Leave the fire", func(): done.emit(), 24)
	_leave.custom_minimum_size.x = 320
	m.footer.add_child(_leave)
	Audio.music("music_campfire")
	if autoplay:
		_auto()


## Opens one action's picker (screens, tests): mend, temper, rite, kindle, cleanse.
func open_step(key: String) -> void:
	match key:
		"mend":
			_pick_mend()
		"temper":
			_pick_temper()
		"rite":
			_pick_burn()
		"kindle":
			_pick_kindle()
		"cleanse":
			_pick_cleanse()


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()


## The actions as one row of equal cards; unavailable ones say why.
func _menu() -> void:
	_clear()
	var flow := GridContainer.new()
	flow.columns = 3
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	_body.add_child(flow)
	var c := Content.config
	var slain := Run.slain_units().size()
	var temper := Run.healthy_units().any(func(u): return not Run.upgrade_options(u).is_empty())
	var curses := Run.curses()
	flow.add_child(_card("mend", "Mend", "Raise up to %d fallen pieces, XP intact." % c.camp_mend_count,
		"No one has fallen." if slain == 0 else "", _pick_mend))
	flow.add_child(_card("temper", "Temper", "One piece rises a tier, no XP needed.",
		"" if temper else "No piece can rise further.", _pick_temper))
	flow.add_child(_card("drill", "Drill", "+%d XP to every deployed piece." % c.camp_drill_xp, "", func():
		var n := Run.drill()
		Audio.play("level_up")
		_finish("%d pieces drill by the fire: +%d XP each." % [n, c.camp_drill_xp], "drill")))
	var fin: EncounterDef = Content.encounter(Run.current_act().final_encounter) if Run.current_act() != null else null
	var study_why := ""
	if fin == null or fin.kind != &"guardian":
		study_why = "No guardian waits below."
	elif Run.studied():
		study_why = "You already know this guardian."
	flow.add_child(_card("study", "Study", "See the guardian's army. +%d s against it." % c.camp_study_clock_s,
		study_why, func(): _study(fin)))
	var burnable := Run.healthy_units().filter(func(u): return not Content.piece(u.type).is_royal())
	flow.add_child(_card("rite", "Rite of Ash", "Burn a piece. Another takes its XP and value.",
		"You need two pieces besides your king." if burnable.size() < 2 else "", _pick_burn))
	flow.add_child(_card("kindle", "Kindle", "One relic grows stronger for good.",
		"No relic can be kindled." if Run.kindle_options().is_empty() else "", _pick_kindle))
	if not curses.is_empty():
		flow.add_child(_card("cleanse", "Cleanse", "Burn away one curse.", "", _pick_cleanse))
	if Run.can_graft():
		flow.add_child(_card("graft", "Graft", "Fuse two pieces into one stronger piece.",
			"No two pieces fit together." if Run.fusion_pairs().is_empty() else "", _pick_graft))
	_same_size.call_deferred(flow)


## Every card as large as the largest, so rows and grids line up.
func _same_size(row: Container, height: bool = true) -> void:
	if not is_instance_valid(row):
		return
	var m := Vector2.ZERO
	for c in row.get_children():
		m = m.max((c as Control).get_combined_minimum_size())
	for c in row.get_children():
		(c as Control).custom_minimum_size = Vector2(m.x, m.y if height else (c as Control).custom_minimum_size.y)


func _card(key: String, title: String, text: String, why_not: String, cb: Callable) -> Control:
	var parts := UiKit.card(150, 0, cb, Color(1.0, 0.72, 0.45) if why_not == "" else UiKit.EDGE)
	parts[0].disabled = why_not != ""
	parts[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col: VBoxContainer = parts[1]
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_child(UiKit.centered(UiKit.icon(ICON % key, 84, 0.45 if why_not != "" else 0.0, 0.8 if why_not != "" else 0.0)))
	var n := UiKit.heading(title, 20, UiKit.BONE if why_not == "" else UiKit.DIM)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	var d := UiKit.label(text, 15, UiKit.MUTED, true)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(d)
	if why_not != "":
		var w := UiKit.label(why_not, 14, UiKit.BLOOD, true)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(w)
	return parts[0]


## A step's frame: Back (to the menu or the previous pick), the action's icon and title, a hint, and a
## centred flow for its cards.
func _step(key: String, title: String, hint: String, back: Callable = Callable()) -> HFlowContainer:
	_clear()
	var top := UiKit.hbox(14)
	top.add_child(UiKit.button("‹ Back", back if back.is_valid() else _menu, 18))
	top.add_child(UiKit.icon(ICON % key, 56))
	var t := UiKit.vbox(0)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_child(UiKit.heading(title, 24, UiKit.GOLD))
	if hint != "":
		t.add_child(UiKit.label(hint, 17, UiKit.MUTED, true))
	top.add_child(t)
	_body.add_child(top)
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	_body.add_child(flow)
	_same_size.call_deferred(flow)
	return flow


func _lv(u: Unit) -> String:
	return "Lv %d · %d XP" % [u.level, u.xp]


# --- mend -------------------------------------------------------------------------------------

func _pick_mend() -> void:
	var n := Content.config.camp_mend_count
	var flow := _step("mend", "Mend", "Choose up to %d fallen pieces. They rise with their XP. (%d chosen)" % [n, _mend.size()])
	for u in Run.slain_units():
		var unit: Unit = u
		var chosen := _mend.has(unit)
		flow.add_child(UiKit.unit_card(unit, ("Chosen" if chosen else "Fallen") + "\n" + _lv(unit), func():
			if _mend.has(unit):
				_mend.erase(unit)
			elif _mend.size() < n:
				_mend.append(unit)
			_pick_mend(), 180, chosen))
	var go := UiKit.button("Raise them" if _mend.size() != 1 else "Raise it", func():
		var names: Array = _mend.map(func(x): return UiKit.unit_name(x))
		var risen: Array = _mend.duplicate()
		for x in _mend:
			Run.restore(x)
		_mend.clear()
		Audio.play("piece_spawn")
		_finish("%s rise from the ashes, their XP intact." % " and ".join(names), "mend",
			risen.map(func(x): return x.type)), 20, true)
	go.disabled = _mend.is_empty()
	_body.add_child(UiKit.centered(go))


# --- temper -----------------------------------------------------------------------------------

func _pick_temper() -> void:
	var flow := _step("temper", "Temper", "Choose a piece. It rises one tier without spending XP.")
	for u in Run.healthy_units():
		var unit: Unit = u
		var opts := Run.upgrade_options(unit)
		if opts.is_empty():
			continue
		var into: Array = opts.map(func(t): return UiKit.piece_name(t))
		flow.add_child(UiKit.unit_card(unit, "%s\n→ %s" % [_lv(unit), ", ".join(into)], func(): _temper_into(unit), 200))


func _temper_into(unit: Unit) -> void:
	var flow := _step("temper", "Temper %s" % UiKit.unit_name(unit), "Choose its new form. It keeps its level, XP and perks.",
		_pick_temper)
	for t in Run.upgrade_options(unit):
		var target: StringName = t
		flow.add_child(UiKit.piece_card(target, func():
			var before := UiKit.unit_name(unit)
			Run.campfire_upgrade(unit, target)
			Audio.play("level_up")
			_finish("%s is tempered in the fire and becomes a %s." % [before, UiKit.piece_name(target).to_lower()], "temper",
				[target]), UiKit.command_note(unit, target)))


# --- study ------------------------------------------------------------------------------------

func _study(fin: EncounterDef) -> void:
	Run.study()
	Audio.play("relic")
	_clear()
	var h := UiKit.hbox(16)
	h.add_child(UiKit.icon(ICON % "study", 110))
	var col := UiKit.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UiKit.heading(fin.display_name, 26))
	col.add_child(UiKit.label(fin.flavor, 18, UiKit.MUTED, true))
	col.add_child(UiKit.label("+%d s on your clock against it." % Content.config.camp_study_clock_s, 18, UiKit.GOLD))
	h.add_child(col)
	_body.add_child(h)
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 8)
	var counts := {}
	for sq in fin.layout:
		var id := StringName(fin.layout[sq])
		counts[id] = int(counts.get(id, 0)) + 1
	for id in counts:
		var v := UiKit.vbox(2)
		v.add_child(UiKit.centered(UiKit.portrait(id, false, 64)))
		var n := UiKit.label("%s ×%d" % [UiKit.piece_name(id), counts[id]], 15, UiKit.BONE)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
		v.tooltip_text = UiKit.moves_text(id)
		flow.add_child(v)
	_body.add_child(flow)
	_leave.text = "Continue"


# --- rite of ash ------------------------------------------------------------------------------

func _pick_burn() -> void:
	_burn = null
	var flow := _step("rite", "Rite of Ash", "Choose the piece that burns. Its XP and its value pass to another.")
	for u in Run.healthy_units():
		var unit: Unit = u
		if Content.piece(unit.type).is_royal():
			continue
		var gift := unit.xp + Content.piece(unit.type).value
		flow.add_child(UiKit.unit_card(unit, "%s\nAsh: %d XP" % [_lv(unit), gift], func(): _pick_heir(unit), 180))


func _pick_heir(burned: Unit) -> void:
	_burn = burned
	var gift := burned.xp + Content.piece(burned.type).value
	var flow := _step("rite", "Who takes in %s's ash?" % UiKit.unit_name(burned),
		"%s burns for good. The heir gains %d XP." % [UiKit.unit_name(burned), gift], _pick_burn)
	for u in Run.healthy_units():
		var unit: Unit = u
		if unit == burned:
			continue
		var need := Run.xp_needed(unit)
		var after := unit.xp + gift
		var note := "%d → %d XP" % [unit.xp, after]
		if need > 0 and after >= need:
			note += " · can rise"
		flow.add_child(UiKit.unit_card(unit, "%s\n%s" % [_lv(unit), note], func():
			var name_b := UiKit.unit_name(burned)
			var gain := Run.rite(burned, unit)
			_burn = null
			Audio.play("level_up")
			_finish("%s burns. %s takes in the ash: +%d XP." % [name_b, UiKit.unit_name(unit), gain], "rite", [unit.type]), 180))


# --- graft ------------------------------------------------------------------------------------

func _pick_graft() -> void:
	var flow := _step("graft", "Graft", "Choose the first piece. Only pieces with a partner are shown.")
	var firsts := {}
	for p in Run.fusion_pairs():
		firsts[p[0]] = true
		firsts[p[1]] = true
	for u in Run.healthy_units():
		var unit: Unit = u
		if firsts.has(unit):
			flow.add_child(UiKit.unit_card(unit, _lv(unit), func(): _graft_with(unit), 180))


func _graft_with(first: Unit) -> void:
	var flow := _step("graft", "Graft %s with…" % UiKit.unit_name(first),
		"The one with more XP lives on: it keeps its XP plus half the other's, and one perk.", _pick_graft)
	for u in Run.healthy_units():
		var other: Unit = u
		var into := Run.fusion_result(first, other)
		if into == &"":
			continue
		var cost := maxi(Content.piece(first.type).value, Content.piece(other.type).value) + 1
		flow.add_child(UiKit.unit_card(other, "%s\n→ %s · Command %d" % [_lv(other), UiKit.piece_name(into), cost], func():
			var perks := Array(first.perks) + Array(other.perks)
			if perks.size() > 1:
				_graft_perk(first, other, perks)
			else:
				_graft(first, other, ""), 200))


func _graft_perk(a: Unit, b: Unit, perks: Array) -> void:
	var flow := _step("graft", "Which perk survives?", "A fused piece keeps one perk.", func(): _graft_with(a))
	for p in perks:
		var perk: PerkDef = Content.perks.get(StringName(p))
		var parts := UiKit.card(300, 0, func(): _graft(a, b, String(p)), UiKit.GOLD)
		parts[1].add_child(UiKit.heading(perk.display_name if perk != null else String(p), 20))
		if perk != null:
			parts[1].add_child(UiKit.label(perk.description, 15, UiKit.MUTED, true))
		flow.add_child(parts[0])


func _graft(a: Unit, b: Unit, perk: String) -> void:
	var names := "%s and %s" % [UiKit.unit_name(a), UiKit.unit_name(b)]
	var fused := Run.fuse(a, b, perk)
	if fused == null:
		_menu()
		return
	Audio.play("level_up")
	_finish("%s are grafted together and become one %s." % [names, UiKit.piece_name(fused.type).to_lower()], "graft", [fused.type])


# --- kindle and cleanse -----------------------------------------------------------------------

func _pick_kindle() -> void:
	var flow := _step("kindle", "Kindle", "Choose a relic. It burns brighter for the rest of the run; drawbacks stay.")
	for id in Run.kindle_options():
		var r: RelicDef = Content.relic(id)
		var parts := UiKit.card(380, 0, func():
			Run.kindle(r.id)
			Audio.play("relic")
			_finish("%s burns brighter: %s" % [r.display_name, r.kindle_text], "kindle"), UiKit.GOLD)
		var h := UiKit.hbox(12)
		h.add_child(UiKit.icon(r.icon, 84))
		var c := UiKit.vbox(3)
		c.custom_minimum_size = Vector2(250, 0)
		c.add_child(UiKit.heading(r.display_name, 20))
		c.add_child(UiKit.label("Now: " + r.description, 15, UiKit.MUTED, true))
		c.add_child(UiKit.label("Kindled: " + r.kindle_text, 15, UiKit.GOLD, true))
		h.add_child(c)
		parts[1].add_child(h)
		flow.add_child(parts[0])


func _pick_cleanse() -> void:
	var flow := _step("cleanse", "Cleanse", "Choose a curse to burn away.")
	for id in Run.curses():
		var r: RelicDef = Content.relic(id)
		flow.add_child(UiKit.relic_card(r, func():
			Run.remove_relic(r.id)
			Audio.play("relic")
			_finish("%s curls up in the flames and is gone." % r.display_name, "cleanse")))


## The outcome: the action's icon (or the pieces it touched) and one line.
func _finish(text: String, key: String, pieces: Array = []) -> void:
	_clear()
	var h := UiKit.hbox(18)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	if pieces.is_empty():
		h.add_child(UiKit.icon(ICON % key, 110))
	for t in pieces:
		h.add_child(UiKit.portrait(StringName(t), true, 110))
	var l := UiKit.label(text, 24, UiKit.BONE, true)
	l.custom_minimum_size = Vector2(400, 0)
	h.add_child(l)
	_body.add_child(h)
	_leave.text = "Continue"


func _auto() -> void:
	await get_tree().create_timer(0.2).timeout
	var slain := Run.slain_units()
	if not slain.is_empty():
		for u in slain.slice(0, Content.config.camp_mend_count):
			Run.restore(u)
		_finish("mended", "mend")
	elif not Run.curses().is_empty():
		Run.remove_relic(Run.curses()[0])
		_finish("cleansed", "cleanse")
	elif Run.can_graft() and not Run.fusion_pairs().is_empty():
		var best := Run.best_fusion_pair()
		var fused := Run.fuse(best[0], best[1])
		print("STS GRAFT %s" % fused.type)
		_finish("grafted", "graft", [fused.type])
	else:
		var done_it := false
		for u in Run.healthy_units():
			var opts := Run.upgrade_options(u)
			if not opts.is_empty():
				Run.campfire_upgrade(u, opts[0])
				done_it = true
				break
		if not done_it:
			Run.drill()
		_finish("tempered", "temper")
	await get_tree().create_timer(0.2).timeout
	done.emit()
