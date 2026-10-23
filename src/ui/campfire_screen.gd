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
	var m := UiModal.new().setup("The Campfire", 1240, false, "", 680)
	m.accent = Color(1.0, 0.72, 0.45)
	add_child(m)
	var head := UiKit.hbox(18)
	head.add_child(UiKit.icon("res://assets/ui/icons/icon_campfire_256.png", 104))
	var l := UiKit.label("The fire burns low and blue. There is time for one thing before you descend. Choose it well.", 22, UiKit.BONE, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	m.body.add_child(head)
	m.body.add_child(UiKit.divider(700, true))
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


## The actions as cards; unavailable ones say why.
func _menu() -> void:
	_clear()
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	_body.add_child(flow)
	var c := Content.config
	var slain := Run.slain_units().size()
	var temper := Run.healthy_units().any(func(u): return not Run.upgrade_options(u).is_empty())
	var curses := Run.curses()
	flow.add_child(_card("mend", "Mend", "Raise up to %d fallen pieces. They keep their XP." % c.camp_mend_count,
		"No one has fallen." if slain == 0 else "", _pick_mend))
	flow.add_child(_card("temper", "Temper", "One piece rises one tier, no XP needed.",
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
	flow.add_child(_card("study", "Study", "See how the guardian stands, and get +%d s on your clock against it." % c.camp_study_clock_s,
		study_why, func(): _study(fin)))
	var burnable := Run.healthy_units().filter(func(u): return not Content.piece(u.type).is_royal())
	flow.add_child(_card("rite", "Rite of Ash", "Burn one piece. Another gains its XP plus its value.",
		"You need two pieces besides your king." if burnable.size() < 2 else "", _pick_burn))
	flow.add_child(_card("kindle", "Kindle", "One relic grows stronger for the rest of the run.",
		"No relic can be kindled." if Run.kindle_options().is_empty() else "", _pick_kindle))
	if not curses.is_empty():
		flow.add_child(_card("cleanse", "Cleanse", "Burn away one curse.", "", _pick_cleanse))


func _card(key: String, title: String, text: String, why_not: String, cb: Callable) -> Control:
	var parts := UiKit.card(220, 0, cb, Color(1.0, 0.72, 0.45) if why_not == "" else UiKit.EDGE)
	parts[0].disabled = why_not != ""
	var col: VBoxContainer = parts[1]
	col.add_theme_constant_override("separation", 6)
	col.add_child(UiKit.centered(UiKit.icon(ICON % key, 110, 0.45 if why_not != "" else 0.0, 0.8 if why_not != "" else 0.0)))
	var n := UiKit.heading(title, 22, UiKit.BONE if why_not == "" else UiKit.DIM)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	var d := UiKit.label(text, 16, UiKit.MUTED, true)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(d)
	if why_not != "":
		var w := UiKit.label(why_not, 15, UiKit.BLOOD, true)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(w)
	return parts[0]


func _step(title: String) -> HFlowContainer:
	_clear()
	var top := UiKit.hbox(14)
	top.add_child(UiKit.button("‹ Back", _menu, 18))
	top.add_child(UiKit.caption(title, 20, UiKit.GOLD))
	_body.add_child(top)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	_body.add_child(flow)
	return flow


func _unit_button(u: Unit, detail: String, cb: Callable, dim: bool = false) -> Button:
	var b := UiKit.option_button(UiKit.unit_name(u), detail, cb, UiKit.MUTED, true, 270)
	if dim:
		b.modulate = Color(0.75, 0.7, 0.7)
	return b


# --- mend -------------------------------------------------------------------------------------

func _pick_mend() -> void:
	var flow := _step("Mend: choose up to %d (%d chosen)" % [Content.config.camp_mend_count, _mend.size()])
	for u in Run.slain_units():
		var unit: Unit = u
		var chosen := _mend.has(unit)
		var b := _unit_button(unit, ("chosen · " if chosen else "") + "Lv %d · %d XP" % [unit.level, unit.xp], func():
			if _mend.has(unit):
				_mend.erase(unit)
			elif _mend.size() < Content.config.camp_mend_count:
				_mend.append(unit)
			_pick_mend(), not chosen)
		flow.add_child(b)
	var go := UiKit.button("Raise them", func():
		var names: Array = _mend.map(func(x): return UiKit.unit_name(x))
		for x in _mend:
			Run.restore(x)
		Audio.play("piece_spawn")
		_finish("%s rise from the ashes, their XP intact." % " and ".join(names), "mend"), 20, true)
	go.disabled = _mend.is_empty()
	_body.add_child(UiKit.centered(go))


# --- temper -----------------------------------------------------------------------------------

func _pick_temper() -> void:
	var flow := _step("Temper: one piece rises one tier")
	for u in Run.healthy_units():
		var unit: Unit = u
		for t in Run.upgrade_options(unit):
			var target: StringName = t
			var d: PieceDef = Content.piece(target)
			var b := UiKit.option_button("%s → %s" % [UiKit.unit_name(unit), UiKit.piece_name(target)],
				"Tier %d · value %d · %s" % [d.tier, d.value, d.moves_text], func():
					var before := UiKit.unit_name(unit)
					Run.campfire_upgrade(unit, target)
					Audio.play("level_up")
					_finish("%s is tempered in the fire and becomes a %s." % [before, UiKit.piece_name(target).to_lower()], "temper"),
					UiKit.MUTED, true, 360)
			flow.add_child(b)


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
	var flow := _step("Rite of Ash: who burns?" if _burn == null else "Rite of Ash: who inherits %s's %d XP + %d?" % [
		UiKit.unit_name(_burn), _burn.xp, Content.piece(_burn.type).value])
	for u in Run.healthy_units():
		var unit: Unit = u
		if _burn == null and Content.piece(unit.type).is_royal():
			continue
		if unit == _burn:
			continue
		flow.add_child(_unit_button(unit, "Lv %d · %d XP" % [unit.level, unit.xp], func():
			if _burn == null:
				_burn = unit
				_pick_burn()
			else:
				var name_b := UiKit.unit_name(_burn)
				var gain := Run.rite(_burn, unit)
				Audio.play("level_up")
				_finish("%s burns. %s takes in the ash: +%d XP." % [name_b, UiKit.unit_name(unit), gain], "rite")))


# --- kindle and cleanse -----------------------------------------------------------------------

func _pick_kindle() -> void:
	var flow := _step("Kindle: one relic grows stronger")
	for id in Run.kindle_options():
		var r: RelicDef = Content.relic(id)
		var b := UiKit.option_button(r.display_name, "Now: %s\nKindled: %s" % [r.description, r.kindle_text], func():
			Run.kindle(r.id)
			Audio.play("relic")
			_finish("%s burns brighter: %s" % [r.display_name, r.kindle_text], "kindle"), UiKit.GOLD, true, 540)
		flow.add_child(b)


func _pick_cleanse() -> void:
	var flow := _step("Cleanse: burn away one curse")
	for id in Run.curses():
		var r: RelicDef = Content.relic(id)
		var b := UiKit.option_button(r.display_name, r.description, func():
			Run.remove_relic(r.id)
			Audio.play("relic")
			_finish("%s curls up in the flames and is gone." % r.display_name, "cleanse"), UiKit.MUTED, true, 420)
		flow.add_child(b)


func _finish(text: String, key: String) -> void:
	_clear()
	var h := UiKit.hbox(18)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UiKit.icon(ICON % key, 110))
	var l := UiKit.label(text, 24, UiKit.BONE, true)
	l.custom_minimum_size = Vector2(760, 0)
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
