class_name UiModal
extends Control
## A modal: blurred backdrop, forged frame, crest and title plaque on its top edge, a body and a
## footer. Screens (reward, campfire, shop, ...) use it as their frame; popups (pause, settings,
## codex, confirm) open it over anything with UiModal.open().

signal closed

var title_text := ""
var subtitle_text := ""
var width := 1100
## > 0: the body scrolls beyond this height. It always scrolls once the modal would leave the window.
var max_body_height := 0
## Close button and Esc.
var closable := false
var accent := UiKit.GOLD
var backdrop_dim := 0.55
## Docked: a panel on the right edge over the board (places, the draft); no backdrop, and clicks
## outside the panel reach the board.
var dock := false
const DOCK_WIDTH := 700
var body: VBoxContainer
var footer: HBoxContainer

var _root: CenterContainer
var _frame: PanelContainer
var _overlay: Control
var _plaque: Control
var _crest: TextureRect
var _close: BaseButton
var _edge := 0.0
var _closing := false
var _scroll: ScrollContainer
var _fade: Control
var _fitting := false
## Space kept free above and below the frame (the plaque and crest stick out of its top edge).
const SCREEN_MARGIN := 150.0


func setup(p_title: String, p_width: int = 1100, p_closable: bool = false, p_subtitle: String = "",
		p_max_body_height: int = 0) -> UiModal:
	title_text = p_title
	width = p_width
	closable = p_closable
	subtitle_text = p_subtitle
	max_body_height = p_max_body_height
	return self


func docked() -> UiModal:
	dock = true
	width = DOCK_WIDTH
	return self


static func open(parent: Node, p_title: String, p_width: int = 900, p_closable: bool = true) -> UiModal:
	var m := UiModal.new().setup(p_title, p_width, p_closable)
	parent.add_child(m)
	return m


## A yes/no question; on_yes runs after the modal closes.
static func confirm(parent: Node, p_title: String, text: String, yes_text: String, on_yes: Callable,
		no_text: String = "Not yet") -> UiModal:
	var m := open(parent, p_title, 760, true)
	var l := UiKit.label(text, 23, UiKit.BONE, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.body.add_child(l)
	m.footer.add_child(UiKit.button(no_text, m.close, 22))
	m.footer.add_child(UiKit.button(yes_text, func():
		m.closed.connect(on_yes)
		m.close(), 22, true))
	return m


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if dock else Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not dock:
		add_child(UiKit.backdrop(backdrop_dim))
	_root = CenterContainer.new()
	UiKit.full(_root)
	if dock:
		_root.anchor_left = 1.0
		_root.offset_left = -width - 70.0
		_root.offset_right = -30.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_frame = PanelContainer.new()
	var fs := UiKit.frame("modal")
	if fs != null:
		_edge = fs.texture_margin_top * 0.3
		_frame.add_theme_stylebox_override("panel", fs)
	else:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.03, 0.025, 0.045, 0.96)
		f.border_color = Color(accent, 0.75)
		f.set_border_width_all(2)
		f.set_corner_radius_all(4)
		f.shadow_color = Color(0, 0, 0, 0.6)
		f.shadow_size = 16
		f.set_content_margin_all(30)
		_frame.add_theme_stylebox_override("panel", f)
	_frame.custom_minimum_size = Vector2(width, 0)
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_frame)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)
	var col := UiKit.vbox(14)
	_frame.add_child(col)
	var top_margin := _frame.get_theme_stylebox("panel").get_margin(SIDE_TOP)
	if title_text != "":
		_plaque = UiKit.plaque(title_text, 40, accent)
		_overlay.add_child(_plaque)
		var ps := _plaque.get_combined_minimum_size()
		var spacer := UiKit.spacer(int(maxf(0.0, _edge + ps.y * 0.5 - top_margin + 10.0)))
		col.add_child(spacer)
		var crest := UiKit.kit_tex("modal_crest")
		if crest != null:
			_crest = TextureRect.new()
			_crest.texture = crest
			_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_overlay.add_child(_crest)
			_overlay.move_child(_crest, 0)
	if subtitle_text != "":
		var s := UiKit.label(subtitle_text, 21, UiKit.MUTED, true)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(s)
	body = UiKit.vbox(14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(holder)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(_scroll)
	_scroll.add_child(body)
	_fade = Control.new()
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.draw.connect(_draw_fade)
	holder.add_child(_fade)
	body.minimum_size_changed.connect(_queue_fit)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float): _fade.queue_redraw())
	_scroll.get_v_scroll_bar().changed.connect(_fade.queue_redraw)
	get_viewport().size_changed.connect(_queue_fit)
	footer = UiKit.hbox(22)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(footer)
	if closable:
		_close = UiKit.close_button(close)
		_overlay.add_child(_close)
	_frame.resized.connect(_place)
	_place.call_deferred()
	_fit()
	# Buttons and labels settle their size a frame after the theme applies; measure again then.
	get_tree().process_frame.connect(_queue_fit, CONNECT_ONE_SHOT)
	UiKit.pop_in(_root)
	Audio.play("ui_open")


func _queue_fit() -> void:
	if not _fitting:
		_fitting = true
		_fit.call_deferred()


## The body is as tall as its content, but never so tall that the frame leaves the window.
func _fit() -> void:
	_fitting = false
	if _scroll == null or not is_inside_tree():
		return
	var content := body.get_combined_minimum_size().y
	var chrome := _frame.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	var room := get_viewport_rect().size.y - SCREEN_MARGIN - chrome
	var cap := room if max_body_height <= 0 else minf(room, float(max_body_height))
	var h := clampf(content, 0.0, maxf(cap, 120.0))
	if absf(_scroll.custom_minimum_size.y - h) > 0.5:
		_scroll.custom_minimum_size.y = h
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if content > h + 0.5 else ScrollContainer.SCROLL_MODE_DISABLED
	_fade.queue_redraw()


func can_scroll() -> bool:
	var bar := _scroll.get_v_scroll_bar()
	return _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and bar.max_value - bar.page > 1.0


## A dark fade with a chevron at the bottom of the body while there is more to scroll to.
func _draw_fade() -> void:
	if not can_scroll():
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar.value >= bar.max_value - bar.page - 2.0:
		return
	var s := _fade.size
	var w := s.x - bar.size.x - 6.0
	var h := minf(70.0, s.y * 0.4)
	var clear := Color(0.02, 0.015, 0.03, 0.0)
	var dark := Color(0.02, 0.015, 0.03, 0.85)
	_fade.draw_polygon(PackedVector2Array([Vector2(0, s.y - h), Vector2(w, s.y - h), Vector2(w, s.y), Vector2(0, s.y)]),
		PackedColorArray([clear, clear, dark, dark]))
	var c := Vector2(w * 0.5, s.y - 16.0)
	_fade.draw_polyline(PackedVector2Array([c + Vector2(-14, -7), c, c + Vector2(14, -7)]), Color(accent, 0.9), 3.0, true)


## The ornaments sit on the frame's top edge; the overlay is a zero-size control at its centre.
func _place() -> void:
	if _frame == null:
		return
	if dock:
		_root.offset_left = _root.offset_right - maxf(_frame.size.x, float(width)) - 40.0
	var half := _frame.size * 0.5
	if _plaque != null:
		var ps := _plaque.get_combined_minimum_size()
		_plaque.size = ps
		_plaque.position = Vector2(-ps.x * 0.5, -half.y + _edge - ps.y * 0.5)
		if _crest != null:
			var cs := _crest.texture.get_size()
			_crest.size = cs
			_crest.position = Vector2(-cs.x * 0.5, _plaque.position.y - cs.y * 0.62)
	if _close != null:
		var bs := _close.get_combined_minimum_size()
		var st := _frame.get_theme_stylebox("panel")
		_close.size = bs
		_close.position = Vector2(half.x - st.get_margin(SIDE_RIGHT) * 0.55 - bs.x * 0.5,
			-half.y + st.get_margin(SIDE_TOP) * 0.55 - bs.y * 0.5)


func close() -> void:
	if _closing:
		return
	_closing = true
	Audio.play("ui_close")
	_root.pivot_offset = _root.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_property(_root, "scale", Vector2(0.97, 0.97), 0.18)
	await tw.finished
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if closable and not _closing and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
