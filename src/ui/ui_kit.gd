class_name UiKit
extends RefCounted
## Theme and widget helpers. All UI is built in code from these.

const BONE := Color(0.89, 0.85, 0.75)
const MUTED := Color(0.62, 0.6, 0.6)
const DIM := Color(0.42, 0.4, 0.42)
const EMBER := Color(1.0, 0.5, 0.2)
const SOUL := Color(0.52, 0.8, 1.0)
const GOLD := Color(0.94, 0.77, 0.44)
const BLOOD := Color(0.85, 0.18, 0.14)
const PANEL_BG := Color(0.04, 0.035, 0.06, 0.9)
const EDGE := Color(0.55, 0.5, 0.44, 0.85)
const ROUND := preload("res://shaders/ui_round.gdshader")

const KIND_LABEL := {&"rule": "Rule relic", &"pocket": "Pocket relic", &"edit": "Edit relic", &"clock": "Clock relic"}
const KIND_COLOR := {&"rule": SOUL, &"pocket": GOLD, &"edit": Color(0.72, 0.56, 1.0), &"clock": Color(0.6, 0.9, 0.8)}
const GLYPH := {&"king": "♚", &"queen": "♛", &"rook": "♜", &"bishop": "♝", &"knight": "♞", &"pawn": "♟"}
const MOVES := {&"pawn": "Steps forward, captures diagonally, promotes.", &"knight": "Leaps in an L, over anything.",
	&"bishop": "Slides along diagonals.", &"rook": "Slides along ranks and files.",
	&"queen": "Slides in every direction.", &"king": "Your life. If it falls, the run ends."}

static var _theme: Theme
static var font_title: Font
static var font_head: Font
static var font_body: Font
static var _tex_cache: Dictionary = {}


static func theme() -> Theme:
	if _theme != null:
		return _theme
	font_title = load("res://assets/fonts/CinzelDecorative-Bold.ttf")
	font_head = load("res://assets/fonts/Cinzel.ttf")
	font_body = load("res://assets/fonts/EBGaramond.ttf")
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 22
	t.set_color("font_color", "Label", BONE)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 6)
	t.set_color("default_color", "RichTextLabel", BONE)
	t.set_color("font_outline_color", "RichTextLabel", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "RichTextLabel", 4)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "TooltipPanel", panel_style(Color(0.03, 0.025, 0.045, 0.96), EDGE, 10))
	t.set_color("font_color", "TooltipLabel", BONE)
	t.set_font("font", "TooltipLabel", font_body)
	t.set_font_size("font_size", "TooltipLabel", 20)
	t.set_font("font", "Button", font_head)
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", BONE)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", EMBER)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("font_focus_color", "Button", BONE)
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Button", 4)
	t.set_stylebox("normal", "Button", button_style(Color(0.08, 0.07, 0.1, 0.92), EDGE))
	t.set_stylebox("hover", "Button", button_style(Color(0.12, 0.11, 0.16, 0.95), SOUL))
	t.set_stylebox("pressed", "Button", button_style(Color(0.1, 0.06, 0.06, 0.95), EMBER))
	t.set_stylebox("disabled", "Button", button_style(Color(0.05, 0.05, 0.06, 0.7), Color(0.3, 0.3, 0.32, 0.6)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.09, 0.12, 0.9)
	bar_bg.set_corner_radius_all(2)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = SOUL
	bar_fg.set_corner_radius_all(2)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fg)
	t.set_font_size("font_size", "ProgressBar", 1)
	t.set_color("font_color", "LineEdit", BONE)
	t.set_stylebox("normal", "LineEdit", button_style(Color(0.06, 0.05, 0.08, 0.9), EDGE))
	t.set_font_size("font_size", "LineEdit", 20)
	_theme = t
	return t


static func panel_style(bg: Color = PANEL_BG, edge: Color = EDGE, margin: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 12
	s.set_content_margin_all(margin)
	return s


static func button_style(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(1)
	s.border_width_bottom = 2
	s.set_corner_radius_all(3)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func panel(edge: Color = EDGE, bg: Color = PANEL_BG, margin: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, edge, margin))
	return p


static func label(text: String, size: int = 22, color: Color = BONE, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func heading(text: String, size: int = 34, color: Color = BONE) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", font_head if font_head != null else theme().default_font)
	return l


static func title(text: String, size: int = 96, color: Color = BONE) -> Label:
	var l := label(text, size, color)
	theme()
	l.add_theme_font_override("font", font_title)
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.0, 0.03, 0.9))
	return l


static func button(text: String, cb: Callable, size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func vbox(sep: int = 10) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func hbox(sep: int = 10) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func spacer(h: int = 0, w: int = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = load(path) if path != "" and ResourceLoader.exists(path) else null
	_tex_cache[path] = t
	return t


## Round medallion icon (Gemini icons have no alpha).
static func icon(path: String, size: int, dim: float = 0.0, desat: float = 0.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(path)
	if r.texture == null:
		r.texture = tex("res://assets/ui/icons/icon_unknown_256.png")
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	var m := ShaderMaterial.new()
	m.shader = ROUND
	m.set_shader_parameter("dim", dim)
	m.set_shader_parameter("desat", desat)
	r.material = m
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func portrait_path(type: StringName, white: bool) -> String:
	var side_names := ["player", "white", "bone"] if white else ["engine", "black", "obsidian"]
	for s in side_names:
		for pattern in ["res://art/portraits/%s_%s.png", "res://art/portraits/%s_%s.PNG"]:
			var p: String = pattern % [s, type]
			if ResourceLoader.exists(p):
				return p
		var p2 := "res://art/portraits/%s_%s.png" % [type, s]
		if ResourceLoader.exists(p2):
			return p2
	return ""


## A piece portrait (rendered in Blender) or a glyph medallion while portraits are missing.
static func portrait(type: StringName, white: bool, size: int, dim: float = 0.0) -> Control:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.065, 0.09, 1.0) if white else Color(0.1, 0.03, 0.02, 1.0)
	st.border_color = SOUL if white else EMBER
	st.set_border_width_all(2)
	st.set_corner_radius_all(size / 2)
	st.set_content_margin_all(size * 0.06)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.modulate = Color(1, 1, 1, 1.0 - dim * 0.6)
	var path := portrait_path(type, white)
	if path != "":
		# Renders are 512 px with the piece in the middle ~80 %; crop to it so small sizes stay legible.
		var tex := load(path) as Texture2D
		var crop := AtlasTexture.new()
		crop.atlas = tex
		crop.region = Rect2(tex.get_size() * Vector2(0.1, 0.12), tex.get_size() * 0.8)
		var tr := TextureRect.new()
		tr.texture = crop
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tr)
		return p
	var l := label(GLYPH.get(type, "?"), int(size * 0.62), BONE if white else Color(0.25, 0.2, 0.2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not white:
		l.add_theme_color_override("font_outline_color", EMBER)
		l.add_theme_constant_override("outline_size", 3)
	p.add_child(l)
	return p


static func piece_name(type: StringName) -> String:
	var d: PieceDef = Content.piece(type)
	return d.display_name if d != null else String(type).capitalize()


static func unit_name(u: Unit) -> String:
	return "%s #%d" % [piece_name(u.type), u.id]


## A big clickable card (Button with a content column inside).
static func card(width: int, height: int, cb: Callable, edge: Color = EDGE) -> Array:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, height)
	b.add_theme_stylebox_override("normal", panel_style(Color(0.05, 0.045, 0.07, 0.94), edge, 18))
	b.add_theme_stylebox_override("hover", panel_style(Color(0.08, 0.07, 0.11, 0.97), SOUL, 18))
	b.add_theme_stylebox_override("pressed", panel_style(Color(0.08, 0.05, 0.05, 0.97), EMBER, 18))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := vbox(10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	full(col)
	col.offset_left = 18
	col.offset_right = -18
	col.offset_top = 18
	col.offset_bottom = -18
	b.add_child(col)
	return [b, col]


static func centered(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(c)
	return cc


static func fade_in(c: CanvasItem, dur: float = 0.35) -> void:
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, dur)


static func vignette() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.0, 0.0, 0.02, 0.75))
	g.add_point(0.55, Color(0, 0, 0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 1.05)
	var r := TextureRect.new()
	r.texture = t
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full(r)
	return r
