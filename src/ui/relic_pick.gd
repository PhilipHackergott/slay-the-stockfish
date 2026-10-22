class_name RelicPick
extends Control
## Choose one relic from a few cards (run start and after elites).

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
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.02, 0.55)
	UiKit.full(shade)
	add_child(shade)
	add_child(UiKit.vignette())
	var col := UiKit.vbox(18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	UiKit.full(col)
	add_child(col)
	var t := UiKit.title(title_text, 64)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	if subtitle_text != "":
		var s := UiKit.label(subtitle_text, 24, UiKit.MUTED)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(s)
	col.add_child(UiKit.spacer(16))
	var row := UiKit.hbox(28)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for id in ids:
		var r: RelicDef = Content.relic(id)
		if r == null:
			continue
		var kind_col: Color = UiKit.KIND_COLOR.get(r.kind, UiKit.BONE)
		var parts := UiKit.card(330, 470, func(): picked.emit(r.id), Color(kind_col, 0.7))
		var c: VBoxContainer = parts[1]
		c.add_child(UiKit.centered(UiKit.icon(r.icon, 180)))
		var n := UiKit.heading(r.display_name, 28)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(n)
		var k := UiKit.label(String(UiKit.KIND_LABEL.get(r.kind, r.kind)).to_upper(), 16, kind_col)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(k)
		var d := UiKit.label(r.description, 20, UiKit.BONE, true)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.custom_minimum_size = Vector2(290, 0)
		c.add_child(d)
		row.add_child(parts[0])
	if allow_skip:
		var b := UiKit.button("Take nothing", func(): picked.emit(&""))
		col.add_child(UiKit.centered(b))
	UiKit.fade_in(self)
