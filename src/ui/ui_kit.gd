class_name UiKit
extends RefCounted
## The design system. Frames, buttons, cards, medallions, bars and cursors are nine-slice textures
## rendered in Blender (tools/blender/ui -> assets/ui/kit + kit.json); fonts are Cinzel Decorative
## (titles), Cinzel (headings, buttons) and EB Garamond (body). Every screen is built from these.
## Without the kit (before the first render) flat styles stand in, so nothing breaks.

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
const BACKDROP := preload("res://shaders/ui_backdrop.gdshader")

const KIT_DIR := "res://assets/ui/kit/"
## On-screen scale per kit family: the textures are rendered at about 1.5x their display size.
const KIT_SCALE := {"modal": 0.78, "modal_crest": 0.62, "title_plaque": 0.7, "panel": 0.62, "card": 0.66,
	"button_primary": 0.66, "button": 0.62, "tooltip": 0.56, "divider_small": 0.6, "divider": 0.7,
	"medallion": 1.0, "slot": 0.56, "bar_frame": 0.6, "bar_fill": 0.6, "scroll": 0.6, "slider": 0.6,
	"check": 0.55, "close": 0.6, "coin_small": 1.0, "coin": 1.0, "cursor": 0.5, "menu_marker": 0.6,
	"node_ring": 1.0, "bg_slate": 1.0}
## Darkens the big stone fills (and their frames) so bone and gold text keep their contrast.
const KIT_TINT := {"modal": Color(0.7, 0.68, 0.72), "panel": Color(0.72, 0.7, 0.75), "card": Color(0.84, 0.82, 0.84)}

const RARITY_COLOR := {&"common": Color(0.78, 0.74, 0.66), &"uncommon": SOUL, &"legendary": Color(1.0, 0.62, 0.22)}
const KIND_LABEL := {&"rule": "Rule relic", &"pocket": "Pocket relic", &"edit": "Edit relic", &"clock": "Clock relic",
	&"hybrid": "Hybrid relic", &"gold": "Tithe relic"}
const KIND_COLOR := {&"rule": SOUL, &"pocket": GOLD, &"edit": Color(0.72, 0.56, 1.0), &"clock": Color(0.6, 0.9, 0.8),
	&"hybrid": Color(1.0, 0.62, 0.36), &"gold": Color(1.0, 0.84, 0.4)}
const GLYPH := {&"king": "♚", &"queen": "♛", &"rook": "♜", &"bishop": "♝", &"knight": "♞", &"pawn": "♟"}

static var _theme: Theme
static var font_title: Font
static var font_head: Font
static var font_body: Font
static var _tex_cache: Dictionary = {}
static var _kit: Dictionary = {}
static var _kit_loaded := false
static var _kit_cache: Dictionary = {}


# --- kit loading ----------------------------------------------------------------------------------

static func _load_kit() -> void:
	if _kit_loaded:
		return
	_kit_loaded = true
	var path := KIT_DIR + "kit.json"
	if not FileAccess.file_exists(path):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		var elems: Variant = d.get("elements", d)
		if elems is Dictionary:
			_kit = elems


static func has_kit() -> bool:
	_load_kit()
	return not _kit.is_empty() and ResourceLoader.exists(KIT_DIR + "panel.png")


static func _family(name: String) -> String:
	var best := ""
	for fam: String in KIT_SCALE:
		if name.begins_with(fam) and fam.length() > best.length():
			best = fam
	return best


static func _quad(v: Variant, scale: float) -> Array:
	if v == null:
		return []
	var a: Array = []
	if v is Array or v is PackedInt32Array or v is PackedFloat32Array:
		a = Array(v)
	elif v is Dictionary:
		a = [v.get("left", 0), v.get("top", 0), v.get("right", 0), v.get("bottom", 0)]
	else:
		a = [v, v, v, v]
	if a.size() == 2:
		a = [a[0], a[1], a[0], a[1]]
	if a.size() != 4:
		return []
	return a.map(func(x): return float(x) * scale)


static func _entry_value(e: Dictionary, keys: Array) -> Variant:
	for k: String in keys:
		if e.has(k):
			return e[k]
	return null


## A kit texture at its display scale: {tex, margin [l,t,r,b], content [l,t,r,b], entry, scale}, or {}.
static func kit(name: String, scale: float = -1.0) -> Dictionary:
	_load_kit()
	if scale < 0.0:
		scale = float(KIT_SCALE.get(_family(name), 0.7))
	var key := "%s@%.3f" % [name, scale]
	if _kit_cache.has(key):
		return _kit_cache[key]
	var out := {}
	var e: Dictionary = _kit.get(name, {})
	var file := String(_entry_value(e, ["file", "path", "png"]) if _entry_value(e, ["file", "path", "png"]) != null else name + ".png")
	var p := KIT_DIR + file.get_file()
	if ResourceLoader.exists(p):
		var src := load(p) as Texture2D
		var tex: Texture2D = src
		if src != null and absf(scale - 1.0) > 0.01:
			var img := src.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.resize(maxi(1, roundi(img.get_width() * scale)), maxi(1, roundi(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
				tex = ImageTexture.create_from_image(img)
		if tex != null:
			var margin := _quad(_entry_value(e, ["margin", "margins", "slice", "texture_margin"]), scale)
			var content := _quad(_entry_value(e, ["content", "padding", "content_margin"]), scale)
			out = {"tex": tex, "margin": margin if not margin.is_empty() else [0.0, 0.0, 0.0, 0.0],
				"content": content if not content.is_empty() else margin, "entry": e, "scale": scale}
	_kit_cache[key] = out
	return out


static func kit_tex(name: String, scale: float = -1.0) -> Texture2D:
	var k := kit(name, scale)
	return k.get("tex") if not k.is_empty() else null


## A nine-slice frame from the kit, or null when the kit lacks it.
static func frame(name: String, scale: float = -1.0, pad: float = -1.0) -> StyleBoxTexture:
	var k := kit(name, scale)
	if k.is_empty():
		return null
	var s := StyleBoxTexture.new()
	s.texture = k["tex"]
	s.modulate_color = KIT_TINT.get(_family(name), Color.WHITE)
	var m: Array = k["margin"]
	s.texture_margin_left = m[0]
	s.texture_margin_top = m[1]
	s.texture_margin_right = m[2]
	s.texture_margin_bottom = m[3]
	var c: Array = k["content"] if k["content"] != null and not k["content"].is_empty() else m
	s.content_margin_left = c[0] if pad < 0.0 else pad
	s.content_margin_top = c[1] if pad < 0.0 else pad
	s.content_margin_right = c[2] if pad < 0.0 else pad
	s.content_margin_bottom = c[3] if pad < 0.0 else pad
	return s


## The kit frame for a state ("hover", "pressed", "disabled"), falling back to the base frame.
static func frame_state(base: String, state: String, scale: float = -1.0) -> StyleBox:
	if state != "" and state != "normal":
		for n in [base + "_" + state, base + "_" + state.substr(0, 5)]:
			var s := frame(n, scale)
			if s != null:
				return s
	var b := frame(base, scale)
	if b == null:
		b = frame(base + "_normal", scale)
	return b


# --- theme ----------------------------------------------------------------------------------------

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
	t.set_stylebox("panel", "TooltipPanel", _or(frame("tooltip"), panel_style(Color(0.03, 0.025, 0.045, 0.96), EDGE, 10)))
	t.set_color("font_color", "TooltipLabel", BONE)
	t.set_font("font", "TooltipLabel", font_body)
	t.set_font_size("font_size", "TooltipLabel", 20)
	t.set_font("font", "Button", font_head)
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", BONE)
	t.set_color("font_hover_color", "Button", Color(0.9, 0.97, 1.0))
	t.set_color("font_pressed_color", "Button", Color(1.0, 0.78, 0.55))
	t.set_color("font_hover_pressed_color", "Button", Color(1.0, 0.78, 0.55))
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("font_focus_color", "Button", BONE)
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Button", 5)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "Button", _button_box("button", st))
	t.set_stylebox("hover_pressed", "Button", _button_box("button", "pressed"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("background", "ProgressBar", _bar_back())
	t.set_stylebox("fill", "ProgressBar", bar_fill("soul"))
	t.set_font_size("font_size", "ProgressBar", 1)
	t.set_color("font_color", "LineEdit", BONE)
	t.set_stylebox("normal", "LineEdit", _or(frame("slot", -1.0, 12.0), button_style(Color(0.06, 0.05, 0.08, 0.9), EDGE)))
	t.set_stylebox("focus", "LineEdit", _or(frame("slot_selected", -1.0, 12.0), StyleBoxEmpty.new()))
	t.set_font_size("font_size", "LineEdit", 20)
	_scrollbar(t, "VScrollBar")
	_scrollbar(t, "HScrollBar")
	_slider(t)
	_checkbox(t)
	_theme = t
	return t


static func _or(a: StyleBox, b: StyleBox) -> StyleBox:
	return a if a != null else b


static func _button_box(base: String, state: String) -> StyleBox:
	var s := frame_state(base, state)
	if s != null:
		return s
	match state:
		"hover":
			return button_style(Color(0.12, 0.11, 0.16, 0.95), SOUL)
		"pressed":
			return button_style(Color(0.1, 0.06, 0.06, 0.95), EMBER)
		"disabled":
			return button_style(Color(0.05, 0.05, 0.06, 0.7), Color(0.3, 0.3, 0.32, 0.6))
	return button_style(Color(0.08, 0.07, 0.1, 0.92), EDGE)


static func _bar_back() -> StyleBox:
	var s := frame("bar_frame")
	if s != null:
		return s
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.1, 0.09, 0.12, 0.9)
	f.set_corner_radius_all(2)
	return f


## The liquid fill of a bar: "soul" (XP), "ember" (clock) or "gold".
static func bar_fill(kind: String) -> StyleBox:
	var s := frame("bar_fill_" + kind)
	if s != null:
		return s
	var f := StyleBoxFlat.new()
	f.bg_color = {"soul": SOUL, "ember": EMBER, "gold": GOLD}.get(kind, SOUL)
	f.set_corner_radius_all(2)
	return f


static func _scrollbar(t: Theme, type: String) -> void:
	var track := frame("scroll_track")
	var grab := frame("scroll_grabber")
	if track == null or grab == null:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(0.4, 0.37, 0.36, 0.6)
		g.set_corner_radius_all(3)
		g.content_margin_left = 4
		g.content_margin_right = 4
		t.set_stylebox("scroll", type, StyleBoxEmpty.new())
		t.set_stylebox("grabber", type, g)
		t.set_stylebox("grabber_highlight", type, g)
		t.set_stylebox("grabber_pressed", type, g)
		return
	t.set_stylebox("scroll", type, track)
	t.set_stylebox("grabber", type, grab)
	var hover := _or(frame("scroll_grabber_hover"), grab)
	t.set_stylebox("grabber_highlight", type, hover)
	t.set_stylebox("grabber_pressed", type, hover)


static func _slider(t: Theme) -> void:
	var track := frame("slider_track")
	if track != null:
		t.set_stylebox("slider", "HSlider", track)
		t.set_stylebox("grabber_area", "HSlider", StyleBoxEmpty.new())
		t.set_stylebox("grabber_area_highlight", "HSlider", StyleBoxEmpty.new())
	var g := kit_tex("slider_grabber")
	if g != null:
		t.set_icon("grabber", "HSlider", g)
		t.set_icon("grabber_highlight", "HSlider", _or_tex(kit_tex("slider_grabber_hover"), g))


static func _or_tex(a: Texture2D, b: Texture2D) -> Texture2D:
	return a if a != null else b


static func _checkbox(t: Theme) -> void:
	var on := kit_tex("check_on")
	var off := kit_tex("check_off")
	if on != null and off != null:
		for type in ["CheckBox", "CheckButton"]:
			t.set_icon("checked", type, on)
			t.set_icon("unchecked", type, off)
			t.set_icon("checked_disabled", type, on)
			t.set_icon("unchecked_disabled", type, off)
	for type in ["CheckBox", "CheckButton"]:
		t.set_font("font", type, font_head)
		t.set_font_size("font_size", type, 22)
		t.set_color("font_color", type, BONE)
		t.set_color("font_hover_color", type, Color(0.9, 0.97, 1.0))
		t.set_color("font_pressed_color", type, BONE)
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			t.set_stylebox(st, type, StyleBoxEmpty.new())


# --- flat fallbacks -------------------------------------------------------------------------------

static func panel_style(bg: Color = PANEL_BG, edge: Color = EDGE, margin: int = 18) -> StyleBox:
	var k := frame("panel")
	if k != null:
		return k
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


# --- widgets --------------------------------------------------------------------------------------

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
	l.add_theme_constant_override("outline_size", maxi(6, size / 7))
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.0, 0.03, 0.92))
	return l


## Small caps label in Cinzel with letter spacing feel (section captions, badges).
static func caption(text: String, size: int = 16, color: Color = MUTED) -> Label:
	var l := heading(text.to_upper(), size, color)
	l.add_theme_constant_override("outline_size", 4)
	return l


static func _wire_sfx(b: BaseButton) -> void:
	b.mouse_entered.connect(func():
		if not b.disabled:
			Audio.play("ui_hover", -10.0))
	b.pressed.connect(func(): Audio.play("ui_click", -3.0))


static func button(text: String, cb: Callable, size: int = 22, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if primary:
		for st in ["normal", "hover", "pressed", "disabled"]:
			var s := frame_state("button_primary", st)
			if s != null:
				b.add_theme_stylebox_override(st, s)
		var hp := frame_state("button_primary", "pressed")
		if hp != null:
			b.add_theme_stylebox_override("hover_pressed", hp)
		b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.78))
		if not has_kit():
			b.add_theme_stylebox_override("normal", button_style(Color(0.16, 0.06, 0.03, 0.95), EMBER))
	var min_h := 0.0
	var nb := b.get_theme_stylebox("normal")
	if nb is StyleBoxTexture:
		min_h = (nb as StyleBoxTexture).texture_margin_top + (nb as StyleBoxTexture).texture_margin_bottom + 4.0
	b.custom_minimum_size = Vector2(0, maxf(min_h, size * 2.4))
	b.pressed.connect(cb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_wire_sfx(b)
	return b


## Title-screen style menu entry: bare text, thorn markers on both sides on hover.
static func menu_button(text: String, cb: Callable, size: int = 34) -> Control:
	var row := hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var left := _marker(false)
	var right := _marker(true)
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.7))
	b.add_theme_color_override("font_pressed_color", EMBER)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	b.add_theme_constant_override("outline_size", 8)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	_wire_sfx(b)
	var show := func(on: bool):
		left.modulate.a = 1.0 if on else 0.0
		right.modulate.a = 1.0 if on else 0.0
	b.mouse_entered.connect(show.bind(true))
	b.mouse_exited.connect(show.bind(false))
	b.focus_entered.connect(show.bind(true))
	b.focus_exited.connect(show.bind(false))
	row.add_child(left)
	row.add_child(b)
	row.add_child(right)
	row.set_meta("button", b)
	return row


static func _marker(flip: bool) -> Control:
	var t := kit_tex("menu_marker")
	var c: Control
	if t != null:
		var r := TextureRect.new()
		r.texture = t
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.flip_h = flip
		r.custom_minimum_size = t.get_size()
		c = r
	else:
		c = label("❖", 26, EMBER)
	c.modulate.a = 0.0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


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


## A horizontal ornament (thorned iron bar with a sigil).
static func divider(width: int = 0, small: bool = false) -> Control:
	var t := kit_tex("divider_small" if small else "divider")
	if t == null:
		var line := ColorRect.new()
		line.color = Color(EDGE, 0.5)
		line.custom_minimum_size = Vector2(width, 2)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return centered(line)
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var w: float = float(width) if width > 0 else float(t.get_width())
	r.custom_minimum_size = Vector2(w, t.get_height() * w / t.get_width())
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return centered(r)


## A title on an engraved plaque.
static func plaque(text: String, size: int = 40, color: Color = GOLD) -> PanelContainer:
	var p := PanelContainer.new()
	var s := frame("title_plaque")
	if s == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.07, 0.05, 0.06, 0.96)
		f.border_color = Color(GOLD, 0.7)
		f.set_border_width_all(2)
		f.set_corner_radius_all(3)
		f.content_margin_left = 40
		f.content_margin_right = 40
		f.content_margin_top = 8
		f.content_margin_bottom = 10
		p.add_theme_stylebox_override("panel", f)
	else:
		p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := title(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


static func coin(size: int = 28) -> Control:
	var t := kit_tex("coin_small" if size <= 32 else "coin")
	if t == null:
		return label("◉", size, GOLD)
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Coin plus amount, e.g. for prices and the gold counter.
static func gold_label(amount: int, size: int = 24, color: Color = GOLD) -> HBoxContainer:
	var h := hbox(6)
	h.add_child(coin(int(size * 1.25)))
	var l := heading(str(amount), size, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h


static func bar(value: float, max_value: float, fill: String = "soul", width: int = 150, height: int = 0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.max_value = maxf(1.0, max_value)
	b.value = value
	var back := _bar_back()
	var h := height
	if h <= 0:
		h = int(back.texture_margin_top + back.texture_margin_bottom + 2) if back is StyleBoxTexture else 8
	b.custom_minimum_size = Vector2(width, h)
	if fill != "soul":
		b.add_theme_stylebox_override("fill", bar_fill(fill))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func close_button(cb: Callable) -> BaseButton:
	var t := kit_tex("close")
	if t == null:
		var b := button("✕", cb, 20)
		b.custom_minimum_size = Vector2(48, 48)
		return b
	var tb := TextureButton.new()
	tb.texture_normal = t
	tb.texture_hover = _or_tex(kit_tex("close_hover"), t)
	tb.texture_pressed = tb.texture_hover
	tb.ignore_texture_size = false
	tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tb.pressed.connect(cb)
	_wire_sfx(tb)
	return tb


## A small rarity tag ("UNCOMMON") in the rarity colour.
static func rarity_badge(rarity: StringName) -> Label:
	var col: Color = RARITY_COLOR.get(rarity, MUTED)
	var l := caption(String(rarity) if rarity != &"" else "common", 15, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func portrait_path(type: StringName, white: bool) -> String:
	var side_names := ["player", "white", "bone"] if white else ["engine", "black", "obsidian"]
	for s in side_names:
		var p := "res://art/portraits/%s_%s.png" % [s, type]
		if ResourceLoader.exists(p):
			return p
	var d: PieceDef = Content.piece(type)
	if d != null and d.base != &"" and d.base != type:
		return portrait_path(d.base, white)
	return ""


## A piece portrait (rendered in Blender) inside a forged medallion ring.
static func portrait(type: StringName, white: bool, size: int, dim: float = 0.0) -> Control:
	var ring := kit_tex("medallion_player" if white else "medallion_engine")
	var root := Control.new()
	root.custom_minimum_size = Vector2(size, size)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.modulate = Color(1, 1, 1, 1.0 - dim * 0.6)
	var hole := 0.47
	if ring != null:
		var k := kit("medallion_player" if white else "medallion_engine")
		var hr: Variant = k["entry"].get("hole_radius")
		hole = clampf(float(hr) * float(k["scale"]) / ring.get_width(), 0.2, 0.48) if hr != null else 0.36
	var bg := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.065, 0.09, 1.0) if white else Color(0.1, 0.03, 0.02, 1.0)
	st.set_corner_radius_all(size)
	if ring == null:
		st.border_color = SOUL if white else EMBER
		st.set_border_width_all(2)
	bg.add_theme_stylebox_override("panel", st)
	var inset := size * (0.5 - hole)
	bg.position = Vector2(inset, inset)
	bg.size = Vector2(size - inset * 2.0, size - inset * 2.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var path := portrait_path(type, white)
	if path != "":
		# Renders are 512 px with the piece in the middle ~80 %; crop to it so small sizes stay legible.
		var t := tex(path)
		var crop := AtlasTexture.new()
		crop.atlas = t
		crop.region = Rect2(t.get_size() * Vector2(0.1, 0.1), t.get_size() * 0.8)
		var tr := TextureRect.new()
		tr.texture = crop
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = bg.position
		tr.size = bg.size
		var m := ShaderMaterial.new()
		m.shader = ROUND
		m.set_shader_parameter("radius", 0.5)
		tr.material = m
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
	else:
		var l := label(GLYPH.get(Content.piece(type).base if Content.piece(type) != null else type, "?"), int(size * 0.55), BONE if white else Color(0.25, 0.2, 0.2))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		full(l)
		root.add_child(l)
	if ring != null:
		var rr := TextureRect.new()
		rr.texture = ring
		rr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rr.stretch_mode = TextureRect.STRETCH_SCALE
		full(rr)
		rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(rr)
	return root


static func piece_name(type: StringName) -> String:
	var d: PieceDef = Content.piece(type)
	return d.display_name if d != null else String(type).capitalize()


static func unit_name(u: Unit) -> String:
	return "%s #%d" % [piece_name(u.type), u.id]


static func moves_text(type: StringName) -> String:
	var d: PieceDef = Content.piece(type)
	return d.moves_text if d != null else ""


## A big clickable card (Button with a content column inside): bone frame, soul glow on hover.
static func card(width: int, height: int, cb: Callable, edge: Color = EDGE) -> Array:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, height)
	var pad := [18.0, 18.0, 18.0, 18.0]
	if frame("card") != null:
		for st in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(st, frame_state("card", st))
		b.add_theme_stylebox_override("hover_pressed", frame_state("card", "pressed"))
		var c: Array = kit("card")["content"]
		pad = c
	else:
		b.add_theme_stylebox_override("normal", panel_style(Color(0.05, 0.045, 0.07, 0.94), edge, 18))
		b.add_theme_stylebox_override("hover", panel_style(Color(0.08, 0.07, 0.11, 0.97), SOUL, 18))
		b.add_theme_stylebox_override("pressed", panel_style(Color(0.08, 0.05, 0.05, 0.97), EMBER, 18))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_wire_sfx(b)
	var col := vbox(10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	full(col)
	col.offset_left = pad[0]
	col.offset_top = pad[1]
	col.offset_right = -pad[2]
	col.offset_bottom = -pad[3]
	b.add_child(col)
	b.pivot_offset = Vector2(width, height) * 0.5
	b.mouse_entered.connect(func():
		if not b.disabled:
			b.create_tween().tween_property(b, "scale", Vector2(1.03, 1.03), 0.12))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
	return [b, col]


## An iron slot frame for small items (relics in the HUD, shop wares).
static func slot(child: Control, state: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	var s: StyleBox = frame("slot" if state == "" else "slot_" + state)
	if s == null:
		s = button_style(Color(0.05, 0.045, 0.07, 0.9), SOUL if state == "selected" else EDGE)
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(child)
	return p


static func centered(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(c)
	return cc


static func fade_in(c: CanvasItem, dur: float = 0.35) -> void:
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, dur)


## Scale + fade in from the centre (modals, cards).
static func pop_in(c: Control, dur: float = 0.28) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(0.94, 0.94)
	var go := func():
		c.pivot_offset = c.size * 0.5
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, dur)
		tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	go.call_deferred()


## Blurred, darkened copy of whatever is behind (modal backdrop).
static func backdrop(dim: float = 0.55, blur: float = 2.6) -> ColorRect:
	var r := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = BACKDROP
	m.set_shader_parameter("dim", 0.0)
	m.set_shader_parameter("blur", 0.0)
	r.material = m
	full(r)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := r.create_tween().set_parallel(true)
	tw.tween_method(func(v: float): m.set_shader_parameter("dim", v), 0.0, dim, 0.3)
	tw.tween_method(func(v: float): m.set_shader_parameter("blur", v), 0.0, blur, 0.3)
	return r


## The slate texture tiled over a rect (screen backgrounds behind menus).
static func slate() -> TextureRect:
	var r := TextureRect.new()
	r.texture = kit_tex("bg_slate")
	r.stretch_mode = TextureRect.STRETCH_TILE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.modulate = Color(0.55, 0.52, 0.6)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full(r)
	return r


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


## The bone-and-iron mouse cursors.
static func install_cursor() -> void:
	for pair in [["cursor", Input.CURSOR_ARROW], ["cursor_point", Input.CURSOR_POINTING_HAND]]:
		var k := kit(pair[0])
		if k.is_empty():
			continue
		var hs: Variant = k["entry"].get("hotspot", [4, 4])
		var hot := Vector2(float(hs[0]), float(hs[1])) * float(k["scale"]) if hs is Array else Vector2(4, 4)
		Input.set_custom_mouse_cursor(k["tex"], pair[1], hot)
