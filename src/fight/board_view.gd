class_name BoardView
extends Node3D
## The 3D board: pieces, square markers, mouse picking, and the presenter coroutines the
## FightController awaits (present_move, present_swap). Square index = rank * 8 + file; a1 sits at
## world (-3.5, 0, 3.5), the player (white) is nearest the camera (+Z).

signal square_clicked(sq: int)
signal square_hovered(sq: int)
signal right_clicked

const BOARD_GLB := "res://models/board/board.glb"
const MOVE_COLOR := Color(0.42, 0.74, 1.0)
const CAPTURE_COLOR := Color(1.0, 0.36, 0.1)
const SELECT_COLOR := Color(0.6, 0.85, 1.0)
const LAST_COLOR := Color(0.95, 0.72, 0.35)
const CHECK_COLOR := Color(1.0, 0.15, 0.1)
const SWAP_COLOR := Color(0.65, 0.5, 1.0)
const HIGHLIGHT := preload("res://shaders/highlight.gdshader")

var camera: Camera3D
var pieces: Dictionary = {}  # sq -> PieceView
var interactive := false
var hovered := -1

var _markers: Array[MeshInstance3D] = []
var _marker_used := 0
var _persistent: Array = []  # [sq, color, kind] that survive clear_marks (last move, check)
var _board_root: Node3D
var _pieces_root: Node3D
var _fx_root: Node3D
var _arena_root: Node3D


func _ready() -> void:
	_board_root = Node3D.new()
	_board_root.name = "Board"
	add_child(_board_root)
	_pieces_root = Node3D.new()
	_pieces_root.name = "Pieces"
	add_child(_pieces_root)
	_fx_root = Node3D.new()
	_fx_root.name = "Fx"
	add_child(_fx_root)
	_arena_root = Node3D.new()
	_arena_root.name = "Arena"
	add_child(_arena_root)
	_build_board()
	var mat := ShaderMaterial.new()
	mat.shader = HIGHLIGHT
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.96, 0.96)
	quad.material = mat
	for i in 72:
		var m := MeshInstance3D.new()
		m.mesh = quad
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_markers.append(m)


static func sq_pos(sq: int) -> Vector3:
	return Vector3(float(sq % 8) - 3.5, 0.0, 3.5 - float(sq / 8))


func _build_board() -> void:
	if ResourceLoader.exists(BOARD_GLB):
		var scene := load(BOARD_GLB) as PackedScene
		if scene != null:
			var b := scene.instantiate()
			_board_root.add_child(b)
			Mats.apply(b)
			return
	# Stand-in board until the Blender board exists.
	for sq in 64:
		var tile := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.2, 1.0)
		tile.mesh = box
		tile.position = sq_pos(sq) + Vector3(0, -0.1, 0)
		var dark := (sq % 8 + sq / 8) % 2 == 0
		tile.set_surface_override_material(0, Mats.world("board_dark" if dark else "board_light"))
		_board_root.add_child(tile)
	var rim := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(9.2, 0.4, 9.2)
	rim.mesh = rb
	rim.position = Vector3(0, -0.25, 0)
	rim.set_surface_override_material(0, Mats.world("board_rim"))
	_board_root.add_child(rim)
	var altar := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(10.2, 0.8, 10.2)
	altar.mesh = ab
	altar.position = Vector3(0, -0.85, 0)
	altar.set_surface_override_material(0, Mats.world("stone_dark"))
	_board_root.add_child(altar)


# --- arena --------------------------------------------------------------------------------------

## The fight's arena props: rubble on wall squares, a gold glow on zone squares (the summit).
## clear() removes them.
func set_arena(walls: Array, zone: PackedStringArray) -> void:
	for sq in walls:
		_arena_root.add_child(_rubble(int(sq)))
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.98, 0.98)
	var mat := ShaderMaterial.new()
	mat.shader = HIGHLIGHT
	quad.material = mat
	for s in zone:
		var m := MeshInstance3D.new()
		m.mesh = quad
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position = sq_pos(Fen.sq(s)) + Vector3(0, 0.008, 0)
		m.set_instance_shader_parameter(&"tint", LAST_COLOR)
		m.set_instance_shader_parameter(&"kind", 2.0)
		_arena_root.add_child(m)


## A heap of fallen stone filling one square. Shapes vary by square, the same every fight.
func _rubble(sq: int) -> Node3D:
	var heap := Node3D.new()
	heap.position = sq_pos(sq)
	for i in 4:
		var k := float(sq * 7 + i * 13)
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		var s := 0.34 + 0.12 * absf(sin(k))
		box.size = Vector3(s * 1.3, s * (0.55 + 0.3 * absf(cos(k))), s)
		block.mesh = box
		var at := Vector2(0.2 * sin(k * 1.7), 0.2 * cos(k * 2.3)) if i > 0 else Vector2.ZERO
		block.position = Vector3(at.x, box.size.y * 0.5 + (0.18 if i == 3 else 0.0), at.y)
		block.rotation = Vector3(0.25 * sin(k), k, 0.2 * cos(k))
		block.set_surface_override_material(0, Mats.world("stone_dark"))
		heap.add_child(block)
	return heap


# --- pieces -------------------------------------------------------------------------------------

func clear() -> void:
	for p in pieces.values():
		p.queue_free()
	pieces.clear()
	for c in _arena_root.get_children():
		c.queue_free()
	_persistent.clear()
	clear_marks()


## board: {sq: letter}. units: UnitMap for the player's pieces (may be null).
func setup_position(board: Dictionary, units: UnitMap = null, animate: bool = true) -> void:
	clear()
	var order := board.keys()
	var depth := func(sq: int) -> int:
		return sq / 8 if board[sq] == board[sq].to_upper() else 7 - sq / 8
	order.sort_custom(func(a, b): return depth.call(a) < depth.call(b))
	for sq in order:
		var p := _spawn(String(board[sq]), int(sq), units.unit_at(int(sq)) if units != null else 0)
		if animate:
			p.visible = false
			var tw := p.create_tween()
			tw.tween_interval(0.04 * float(order.find(sq)))
			tw.tween_callback(func():
				p.visible = true
				p.play("spawn")
				Fx.burst(_fx_root, p.global_position + Vector3(0, 0.1, 0), MOVE_COLOR if p.white else CAPTURE_COLOR, "spawn"))


func _spawn(letter: String, sq: int, unit_id: int = 0) -> PieceView:
	var p := PieceView.new()
	_pieces_root.add_child(p)
	p.setup(letter, unit_id)
	p.position = sq_pos(sq)
	pieces[sq] = p
	return p


func piece_at(sq: int) -> PieceView:
	return pieces.get(sq)


## Makes the view match a board dictionary (after edits or if an animation was skipped).
func sync(board: Dictionary) -> void:
	for sq in pieces.keys():
		var want := String(board.get(sq, ""))
		var p: PieceView = pieces[sq]
		if want == p.letter:
			continue
		if want != "" and (want == want.to_upper()) == p.white:
			p.morph(want)
			continue
		p.queue_free()
		pieces.erase(sq)
	for sq in board:
		if not pieces.has(sq):
			_spawn(String(board[sq]), int(sq))


# --- presenter ----------------------------------------------------------------------------------

func present_move(ev: Dictionary) -> void:
	var to := int(ev["to"])
	var side_color := MOVE_COLOR if ev["side"] == "w" else CAPTURE_COLOR
	if String(ev.get("drop", "")) != "":
		var dropped := _spawn(String(ev["drop"]), to, int(ev.get("mover_unit", 0)))
		var dd := dropped.play("drop")
		get_tree().create_timer(dd * 0.6).timeout.connect(Audio.play.bind("piece_drop"))
		await get_tree().create_timer(dd * 0.75).timeout
		Fx.burst(_fx_root, sq_pos(to) + Vector3(0, 0.05, 0), side_color, "land")
		Fx.flash(_fx_root, sq_pos(to) + Vector3(0, 0.6, 0), side_color, 2.5, 0.4)
		await get_tree().create_timer(dd * 0.25).timeout
		_after_move(ev)
		return
	var from := int(ev["from"])
	var piece: PieceView = pieces.get(from)
	if piece == null:
		_after_move(ev)
		return
	if ev.get("pass", false):
		Audio.play("pass")
		Fx.flash(_fx_root, sq_pos(from) + Vector3(0, 1.0, 0), side_color, 2.0, 0.5)
		await get_tree().create_timer(piece.play("move")).timeout
		_after_move(ev)
		return
	pieces.erase(from)
	var cap_sq := int(ev.get("captured_sq", -1))
	var victim: PieceView = pieces.get(cap_sq) if cap_sq >= 0 else null
	if victim != null:
		pieces.erase(cap_sq)
	var start := sq_pos(from)
	var end := sq_pos(to)
	var df := absi(to % 8 - from % 8)
	var dr := absi(to / 8 - from / 8)
	var leap := piece.type == &"knight" or (df != dr and df != 0 and dr != 0)
	piece.set_glow(0.0)
	piece.face(end - start)
	var dur := piece.play("leap" if leap else "move")
	Audio.play("piece_leap" if leap else "piece_move", 0.0, randf_range(0.94, 1.06))
	var tw := create_tween()
	tw.tween_property(piece, "position", end, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if victim != null:
		get_tree().create_timer(dur * 0.55).timeout.connect(_kill.bind(victim, ev["side"] == "w"))
	await tw.finished
	Fx.burst(_fx_root, end + Vector3(0, 0.03, 0), side_color, "land")
	piece.unface()
	pieces[to] = piece
	if String(ev.get("promotion", "")) != "":
		Fx.burst(_fx_root, end + Vector3(0, 0.4, 0), side_color, "spawn")
		Fx.flash(_fx_root, end + Vector3(0, 1.0, 0), side_color, 4.0, 0.6)
		var promo := String(ev["promotion"])
		Audio.play("promote")
		await piece.morph(promo.to_upper() if ev["side"] == "w" else promo.to_lower())
	_after_move(ev)


func _after_move(ev: Dictionary) -> void:
	if ev.has("fen"):
		sync(Fen.parse(String(ev["fen"]))["board"])
	_persistent.clear()
	if String(ev.get("drop", "")) == "":
		_persistent.append([int(ev["from"]), LAST_COLOR, 2.0])
	_persistent.append([int(ev["to"]), LAST_COLOR, 2.0])
	if ev.get("check", false):
		Audio.play("check_bell")
		var king := "k" if ev["side"] == "w" else VariantGen.PLAYER_KING.to_upper()
		for sq in pieces:
			if pieces[sq].letter == king:
				_persistent.append([int(sq), CHECK_COLOR, 1.0])
	clear_marks()


func _kill(victim: PieceView, by_player: bool) -> void:
	var pos := victim.global_position
	var col := Color(1.0, 0.45, 0.12) if by_player else Color(0.5, 0.75, 1.0)
	var d := victim.play("capture")
	Audio.play("piece_capture", 0.0, randf_range(0.92, 1.05))
	Fx.burst(_fx_root, pos + Vector3(0, 0.5, 0), col, "capture")
	Fx.burst(_fx_root, pos + Vector3(0, 0.3, 0), Color(0.08, 0.06, 0.1, 0.8), "smoke")
	Fx.flash(_fx_root, pos + Vector3(0, 0.8, 0), col, 5.0, 0.7)
	get_tree().create_timer(d + 0.1).timeout.connect(victim.queue_free)


func present_swap(a: int, b: int) -> void:
	var pa: PieceView = pieces.get(a)
	var pb: PieceView = pieces.get(b)
	if pa == null or pb == null:
		return
	var d := maxf(pa.play("leap"), pb.play("leap"))
	Audio.play("swap")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(pa, "position", sq_pos(b), d).set_trans(Tween.TRANS_SINE)
	tw.tween_property(pb, "position", sq_pos(a), d).set_trans(Tween.TRANS_SINE)
	await tw.finished
	pieces[a] = pb
	pieces[b] = pa
	for sq in [a, b]:
		Fx.burst(_fx_root, sq_pos(sq), SWAP_COLOR, "land")
	Fx.flash(_fx_root, (sq_pos(a) + sq_pos(b)) * 0.5 + Vector3(0, 1, 0), SWAP_COLOR, 3.0, 0.6)


## The move edit: the piece dissolves on one square and lands on another.
func present_teleport(from: int, to: int) -> void:
	var p: PieceView = pieces.get(from)
	if p == null:
		return
	pieces.erase(from)
	Audio.play("swap")
	Fx.burst(_fx_root, sq_pos(from) + Vector3(0, 0.4, 0), SWAP_COLOR, "spawn")
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector3(0.05, 1.6, 0.05), 0.25).set_trans(Tween.TRANS_QUAD)
	await tw.finished
	p.position = sq_pos(to)
	pieces[to] = p
	var tw2 := create_tween()
	tw2.tween_property(p, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var d := p.play("drop")
	await get_tree().create_timer(d * 0.7).timeout
	Fx.burst(_fx_root, sq_pos(to) + Vector3(0, 0.05, 0), SWAP_COLOR, "land")
	Fx.flash(_fx_root, sq_pos(to) + Vector3(0, 0.8, 0), SWAP_COLOR, 3.0, 0.5)
	clear_marks()


## The hybrid: the piece rises into the pocket and is gone from the board.
func present_lift(sq: int) -> void:
	var p: PieceView = pieces.get(sq)
	if p == null:
		return
	pieces.erase(sq)
	Audio.play("piece_spawn")
	Fx.burst(_fx_root, sq_pos(sq) + Vector3(0, 0.3, 0), Color(0.94, 0.77, 0.44), "spawn")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "position:y", 2.6, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "scale", Vector3(0.2, 0.2, 0.2), 0.55)
	await tw.finished
	p.queue_free()
	clear_marks()


# --- markers ------------------------------------------------------------------------------------

func clear_marks() -> void:
	for i in _marker_used:
		_markers[i].visible = false
	_marker_used = 0
	for p in _persistent:
		mark(p[0], p[1], p[2])


## kind: 0 = dot, 1 = ring, 2 = square glow.
func mark(sq: int, color: Color, kind: float = 0.0) -> void:
	if _marker_used >= _markers.size():
		return
	var m := _markers[_marker_used]
	_marker_used += 1
	var lift := 0.012 + 0.002 * float(_marker_used % 4)
	m.position = sq_pos(sq) + Vector3(0, lift, 0)
	m.set_instance_shader_parameter(&"tint", color)
	m.set_instance_shader_parameter(&"kind", kind)
	m.visible = true


## targets: {sq: is_capture}. from_sq < 0 for drops.
func show_selection(from_sq: int, targets: Dictionary) -> void:
	clear_marks()
	if from_sq >= 0:
		mark(from_sq, SELECT_COLOR, 2.0)
	for sq in targets:
		var is_capture: bool = targets[sq]
		mark(int(sq), CAPTURE_COLOR if is_capture else MOVE_COLOR, 1.0 if is_capture else 0.0)


func set_selected(sq: int) -> void:
	for s in pieces:
		pieces[s].set_glow(1.0 if s == sq else 0.0)


# --- input --------------------------------------------------------------------------------------

func pick(screen_pos: Vector2) -> int:
	if camera == null:
		return -1
	var o := camera.project_ray_origin(screen_pos)
	var n := camera.project_ray_normal(screen_pos)
	if absf(n.y) < 0.0001:
		return -1
	var t := -o.y / n.y
	if t < 0.0:
		return -1
	var hit := o + n * t
	var file := int(floor(hit.x + 4.0))
	var rank := int(floor(4.0 - hit.z))
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return -1
	return rank * 8 + file


func _unhandled_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		var sq := pick(event.position)
		if sq != hovered:
			hovered = sq
			square_hovered.emit(sq)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var sq := pick(event.position)
			if sq >= 0:
				square_clicked.emit(sq)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit()
