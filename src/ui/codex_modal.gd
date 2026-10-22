class_name CodexModal
extends RefCounted
## The codex: every promotion tree as rows of medallions (pawn, knight, ... and the uncommon
## lineages), plus every relic. Locked entries say what unlocks them.

const ROOTS := [&"pawn", &"knight", &"bishop", &"rook", &"queen", &"king"]


static func open_codex(parent: Node) -> UiModal:
	var m := UiModal.new().setup("Codex", 1500, true, "Every piece can rise along its tree. Hover a medallion for its moves.", 720)
	parent.add_child(m)
	m.body.add_child(UiKit.caption("Promotion trees", 20, UiKit.GOLD))
	var roots: Array = ROOTS.duplicate()
	for p in Content.pieces.values():
		if p.rarity == &"uncommon" and not _is_child(p.id) and not roots.has(p.id):
			roots.append(p.id)
	for r in roots:
		if Content.piece(r) != null:
			m.body.add_child(_tree_row(r))
	var legends: Array = Content.pieces.values().filter(func(p): return p.rarity == &"legendary")
	if not legends.is_empty():
		m.body.add_child(UiKit.divider(800, true))
		m.body.add_child(UiKit.caption("Legendary", 20, UiKit.RARITY_COLOR[&"legendary"]))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 18)
		for p in legends:
			row.add_child(_medallion(p.id, 96))
		m.body.add_child(row)
	m.body.add_child(UiKit.divider(800, true))
	m.body.add_child(UiKit.caption("Relics", 20, UiKit.GOLD))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 14)
	var relics: Array = Content.relics.values()
	relics.sort_custom(func(a, b): return String(a.id) < String(b.id))
	for r in relics:
		var locked := not Profile.is_unlocked(r.unlock)
		var h := UiKit.hbox(10)
		h.custom_minimum_size = Vector2(440, 0)
		h.add_child(UiKit.icon(r.icon, 72, 0.5 if locked else 0.0, 1.0 if locked else 0.0))
		var c := UiKit.vbox(0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(UiKit.heading(r.display_name, 19, UiKit.DIM if locked else UiKit.BONE))
		c.add_child(UiKit.label(("Locked: " + String(Profile.UNLOCKS.get(r.unlock, r.unlock))) if locked else r.description, 15, UiKit.MUTED, true))
		h.add_child(c)
		grid.add_child(h)
	m.body.add_child(grid)
	return m


static func _is_child(id: StringName) -> bool:
	for p in Content.pieces.values():
		if p.upgrades.has(id):
			return true
	return false


## One tree as columns by depth: root, its children, their children (each id once).
static func _tree_row(root: StringName) -> Control:
	var row := UiKit.hbox(10)
	var seen := {}
	var layer: Array = [root]
	var depth := 0
	while not layer.is_empty() and depth < 5:
		var colbox := UiKit.vbox(6)
		colbox.alignment = BoxContainer.ALIGNMENT_CENTER
		var next: Array = []
		for id in layer:
			if seen.has(id):
				continue
			seen[id] = true
			colbox.add_child(_medallion(id, 64 if depth > 0 else 80))
			var d: PieceDef = Content.piece(id)
			if d != null:
				for c in d.upgrades:
					if not seen.has(c) and not next.has(c):
						next.append(c)
		if colbox.get_child_count() == 0:
			break
		if depth > 0:
			var arrow := UiKit.label("›", 40, UiKit.DIM)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(arrow)
		row.add_child(colbox)
		layer = next
		depth += 1
	var wrap := UiKit.vbox(4)
	wrap.add_child(row)
	wrap.add_child(UiKit.spacer(6))
	return wrap


static func _medallion(id: StringName, size: int) -> Control:
	var d: PieceDef = Content.piece(id)
	var locked := d != null and not Profile.is_unlocked(d.unlock)
	var box := UiKit.vbox(2)
	box.custom_minimum_size = Vector2(maxi(size, 120), 0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(UiKit.centered(UiKit.portrait(id, true, size, 0.6 if locked else 0.0)))
	var n := UiKit.label(UiKit.piece_name(id), 15, UiKit.DIM if locked else UiKit.RARITY_COLOR.get(d.rarity if d else &"common", UiKit.BONE))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(n)
	if d != null:
		box.tooltip_text = "%s  (value %d%s)\n%s\n%s%s" % [d.display_name, d.value, ", %s" % d.rarity if d.rarity != &"common" else "",
			d.moves_text, d.flavor, "\nLocked: %s" % Profile.UNLOCKS.get(d.unlock, d.unlock) if locked else ""]
	return box
