class_name MoveDiagram
extends Control
## A small board around one piece showing where it can go: filled = moves and captures, ring =
## moves only, red = captures only, ember ring = cannon captures over a screen, faint = first move.

const RADIUS := 3

var type: StringName
var cell := 14.0
var _squares: Dictionary = {}


static func make(p_type: StringName, p_cell: float = 14.0) -> MoveDiagram:
	var m := MoveDiagram.new()
	m.type = p_type
	m.cell = p_cell
	m._squares = Betza.squares(Betza.of(p_type), RADIUS)
	var side := p_cell * (RADIUS * 2 + 1)
	m.custom_minimum_size = Vector2(side, side)
	m.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


func _draw() -> void:
	var n := RADIUS * 2 + 1
	for y in n:
		for x in n:
			var dark := (x + y) % 2 == 1
			draw_rect(_rect(Vector2i(x - RADIUS, RADIUS - y)), Color(0.16, 0.15, 0.19, 0.9) if dark else Color(0.27, 0.25, 0.3, 0.9))
	for v: Vector2i in _squares:
		var e: Dictionary = _squares[v]
		var r := _rect(v).grow(-cell * 0.16)
		var a := 0.45 if e["initial"] else 1.0
		if e["hop"] and not e["move"] and not e["capture"]:
			draw_arc(r.get_center(), r.size.x * 0.42, 0.0, TAU, 16, Color(UiKit.EMBER, a), 2.0, true)
		elif e["move"] and e["capture"]:
			draw_rect(r, Color(UiKit.SOUL, 0.85 * a))
		elif e["move"]:
			draw_rect(r, Color(UiKit.SOUL, 0.9 * a), false, 2.0)
		else:
			draw_rect(r, Color(UiKit.BLOOD, 0.9 * a))
		if e["hop"] and (e["move"] or e["capture"]):
			draw_arc(r.get_center(), r.size.x * 0.3, 0.0, TAU, 12, Color(UiKit.EMBER, a), 1.5, true)
	var c := _rect(Vector2i.ZERO)
	draw_circle(c.get_center(), cell * 0.32, UiKit.GOLD)
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.EDGE, 0.8), false, 1.0)


func _rect(v: Vector2i) -> Rect2:
	var origin := (size - Vector2.ONE * cell * (RADIUS * 2 + 1)) * 0.5
	return Rect2(origin + Vector2(v.x + RADIUS, RADIUS - v.y) * cell, Vector2(cell, cell))
