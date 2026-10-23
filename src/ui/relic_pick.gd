class_name RelicPick
extends Control
## Choose one relic from a few cards (run start).

signal picked(id: StringName)

var title_text := "Choose a Relic"
var subtitle_text := ""
var ids: Array = []
var allow_skip := false


func setup(p_title: String, p_subtitle: String, p_ids: Array, p_allow_skip: bool) -> RelicPick:
	title_text = p_title
	subtitle_text = p_subtitle
	ids = p_ids
	allow_skip = p_allow_skip
	return self


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UiModal.new().setup(title_text, mini(1500, 380 * ids.size() + 120), false, subtitle_text)
	add_child(m)
	var row := UiKit.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	m.body.add_child(row)
	for id in ids:
		var r: RelicDef = Content.relic(id)
		if r == null:
			continue
		var kind_col: Color = UiKit.KIND_COLOR.get(r.kind, UiKit.BONE)
		var parts := UiKit.card(330, 480, func():
			Audio.play("relic")
			picked.emit(r.id), Color(kind_col, 0.7))
		var c: VBoxContainer = parts[1]
		c.add_child(UiKit.centered(UiKit.icon(r.icon, 170)))
		var n := UiKit.heading(r.display_name, 26)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(n)
		var k := UiKit.caption(UiKit.relic_tag(r), 15, kind_col)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(k)
		c.add_child(UiKit.divider(200, true))
		var d := UiKit.label(r.description, 19, UiKit.BONE, true)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.custom_minimum_size = Vector2(270, 0)
		c.add_child(d)
		row.add_child(parts[0])
	if allow_skip:
		m.footer.add_child(UiKit.button("Take nothing", func(): picked.emit(&"")))
