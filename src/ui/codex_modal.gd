class_name CodexModal
extends RefCounted
## The codex: every piece on its tier (a level-up raises a piece one tier, a guardian's Ascension
## turns a tier-5 piece into a legend), a detail panel with the move diagram, and every relic.
## Locked entries say what unlocks them.

const RELIC_TIERS := [&"common", &"uncommon", &"rare", &"boss", &"curse"]
const TIER_NAMES := ["King", "Tier 1 · recruits", "Tier 2", "Tier 3", "Tier 4", "Tier 5 · queens", "Legends · Ascension only"]


static func open_codex(parent: Node) -> UiModal:
	var m := UiModal.new().setup("Codex", 1500, true, "Hover a piece for how it moves and what it can become.", 720)
	parent.add_child(m)
	var split := UiKit.hbox(24)
	m.body.add_child(split)
	var ladder := UiKit.vbox(8)
	ladder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(ladder)
	var detail := UiKit.vbox(6)
	detail.custom_minimum_size = Vector2(380, 0)
	split.add_child(detail)
	var by_tier: Dictionary = {}
	for p in Content.pieces.values():
		var t: int = 6 if p.rarity == &"legendary" else (0 if p.is_royal() else p.tier)
		if not by_tier.has(t):
			by_tier[t] = []
		by_tier[t].append(p)
	for t in range(1, 7) + [0]:
		if not by_tier.has(t):
			continue
		var list: Array = by_tier[t]
		list.sort_custom(func(a, b): return a.value < b.value if a.value != b.value else String(a.id) < String(b.id))
		ladder.add_child(UiKit.caption(TIER_NAMES[t], 18, UiKit.RARITY_COLOR[&"legendary"] if t == 6 else UiKit.GOLD))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 10)
		row.add_theme_constant_override("v_separation", 8)
		for p in list:
			var med := _medallion(p.id, 64)
			var id: StringName = p.id
			med.mouse_entered.connect(func(): _show(detail, id))
			row.add_child(med)
		ladder.add_child(row)
	_show(detail, &"pawn")
	m.body.add_child(UiKit.divider(800, true))
	for tier in RELIC_TIERS:
		var relics: Array = Content.relics.values().filter(func(r): return r.tier == tier)
		if relics.is_empty():
			continue
		relics.sort_custom(func(a, b): return a.display_name < b.display_name)
		var title := "%s relics" % UiKit.TIER_LABEL[tier] if tier != &"curse" else "Curses · from pacts, cleansed at campfires"
		m.body.add_child(UiKit.caption(title, 20, UiKit.RARITY_COLOR.get(tier, UiKit.GOLD)))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 14)
		for r in relics:
			var locked := not Profile.is_unlocked(r.unlock)
			var h := UiKit.hbox(10)
			h.custom_minimum_size = Vector2(440, 0)
			h.add_child(UiKit.icon(r.icon, 72, 0.5 if locked else 0.0, 1.0 if locked else 0.0))
			var c := UiKit.vbox(0)
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.add_child(UiKit.heading(r.display_name, 19, UiKit.DIM if locked else UiKit.BONE))
			c.add_child(UiKit.caption(UiKit.relic_tag(r), 13, UiKit.KIND_COLOR.get(r.kind, UiKit.MUTED)))
			c.add_child(UiKit.label(("Locked: " + String(Profile.UNLOCKS.get(r.unlock, r.unlock))) if locked else r.description, 15, UiKit.MUTED, true))
			h.add_child(c)
			grid.add_child(h)
		m.body.add_child(grid)
	return m


static func _names(ids: Array) -> String:
	return ", ".join(ids.map(func(i): return UiKit.piece_name(StringName(i))))


static func _show(box: VBoxContainer, id: StringName) -> void:
	for c in box.get_children():
		c.queue_free()
	var d: PieceDef = Content.piece(id)
	if d == null:
		return
	var locked := not Profile.is_unlocked(d.unlock)
	var h := UiKit.hbox(12)
	h.add_child(UiKit.portrait(id, true, 96, 0.6 if locked else 0.0))
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiKit.heading(d.display_name, 24))
	var tier := "Legend" if d.rarity == &"legendary" else ("Royal" if d.is_royal() else "Tier %d" % d.tier)
	info.add_child(UiKit.label("%s · value %d" % [tier, d.value], 17, UiKit.RARITY_COLOR.get(d.rarity, UiKit.GOLD)))
	if locked:
		info.add_child(UiKit.label("Locked: %s" % Profile.UNLOCKS.get(d.unlock, d.unlock), 16, UiKit.BLOOD, true))
	h.add_child(info)
	box.add_child(h)
	box.add_child(UiKit.centered(MoveDiagram.make(id, 18.0)))
	box.add_child(UiKit.label(d.moves_text, 17, UiKit.BONE, true))
	if not d.upgrades.is_empty():
		box.add_child(UiKit.label("Rises to: " + _names(Array(d.upgrades)), 16, UiKit.GOLD, true))
	if not d.ascensions.is_empty():
		box.add_child(UiKit.label("Ascends to: " + _names(Array(d.ascensions)), 16, UiKit.RARITY_COLOR[&"legendary"], true))
	if d.flavor != "":
		box.add_child(UiKit.label(d.flavor, 15, UiKit.MUTED, true))


static func _medallion(id: StringName, size: int) -> Control:
	var d: PieceDef = Content.piece(id)
	var locked := d != null and not Profile.is_unlocked(d.unlock)
	var box := UiKit.vbox(2)
	box.custom_minimum_size = Vector2(maxi(size, 104), 0)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(UiKit.centered(UiKit.portrait(id, true, size, 0.6 if locked else 0.0)))
	var n := UiKit.label(UiKit.piece_name(id), 15, UiKit.DIM if locked else UiKit.RARITY_COLOR.get(d.rarity if d else &"common", UiKit.BONE), true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.custom_minimum_size = Vector2(maxi(size, 104), 0)
	box.add_child(n)
	return box
