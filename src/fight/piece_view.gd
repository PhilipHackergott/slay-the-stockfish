class_name PieceView
extends Node3D
## One chess piece on the board. Node layout: PieceView (horizontal position, tweened by BoardView)
## -> yaw (facing) -> glb root (its own clips animate height, pitch and scale).

const CLIP_LEN := {"move": 0.55, "leap": 0.75, "capture": 0.9, "drop": 0.6, "spawn": 0.5}
const STANDARD := [&"pawn", &"knight", &"bishop", &"rook", &"queen", &"king"]

var letter: String = ""
var white: bool = true
var type: StringName = &"pawn"
var def: PieceDef
var unit_id: int = 0
var rest_yaw: float = 0.0

var _yaw: Node3D
var _body: Node3D
var _anim: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _glow: float = 0.0
var _plate: Label3D
var _plate_mode := "off"

static var _scene_cache: Dictionary = {}
static var _fallback_cache: Dictionary = {}


func setup(p_letter: String, p_unit_id: int = 0) -> void:
	letter = p_letter
	white = p_letter == p_letter.to_upper()
	unit_id = p_unit_id
	def = Content.piece_by_letter(p_letter.to_lower(), white)
	type = def.id if def != null else &"pawn"
	_yaw = Node3D.new()
	_yaw.name = "Yaw"
	add_child(_yaw)
	rest_yaw = PI if white else 0.0
	if family() == &"knight":
		rest_yaw += -0.75 if white else 0.75
	_yaw.rotation.y = rest_yaw
	_build_body()


func height() -> float:
	return def.height if def != null else 1.0


## Fairy pieces (and stitched ones) wear their own model on a familiar silhouette.
func is_special() -> bool:
	return not STANDARD.has(type)


## A floating name over the piece: mode "fairy" (special pieces only), "all" or "off".
func set_nameplate(mode: String) -> void:
	_plate_mode = mode
	var on := mode == "all" or (mode == "fairy" and is_special())
	if not on:
		if _plate != null:
			_plate.visible = false
		return
	if _plate == null:
		_plate = Label3D.new()
		_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_plate.no_depth_test = true
		_plate.pixel_size = 0.0043
		_plate.font = UiKit.font_head
		_plate.font_size = 44
		_plate.outline_size = 16
		_plate.width = 1.85 / _plate.pixel_size
		_plate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_plate.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_plate.outline_modulate = Color(0.02, 0.015, 0.03, 0.95)
		_plate.render_priority = 10
		_plate.outline_render_priority = 9
		add_child(_plate)
	_plate.text = def.display_name if def != null else String(type).capitalize()
	_plate.modulate = Color(0.78, 0.86, 1.0) if white else Color(1.0, 0.62, 0.36)
	_plate.visible = true
	_place_plate()


## Plates on neighbouring squares sit at different heights (by square colour) so they never overlap.
func _place_plate() -> void:
	var f := roundi(global_position.x + 3.5)
	var r := roundi(global_position.z + 3.5)
	_plate.position = Vector3(0, height() + 0.12 + (0.3 if (f + r) % 2 == 1 else 0.0), 0)


func _process(_dt: float) -> void:
	if _plate != null and _plate.visible:
		_place_plate()


## The model family (pawn, knight, ...) used for stand-ins and facing.
func family() -> StringName:
	return def.base if def != null and def.base != &"" else type


func _build_body() -> void:
	if _body != null:
		_body.queue_free()
	_anim = null
	_meshes.clear()
	var scene: PackedScene = null
	var stand_in := false
	if def != null and def.model != "":
		scene = _load_scene(def.model)
	if scene == null and def != null and def.base != &"" and def.base != type:
		var base_def: PieceDef = Content.piece(def.base)
		if base_def != null:
			scene = _load_scene(base_def.model)
			stand_in = scene != null
	if scene != null:
		_body = scene.instantiate()
		_yaw.add_child(_body)
		var players := _body.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			_anim = players[0]
		Mats.apply(_body, 0 if white else 1)
	else:
		_body = _fallback_body()
		_yaw.add_child(_body)
	if stand_in or (def != null and def.look != &""):
		_add_halo()
	for mi in _body.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
	if _body is MeshInstance3D:
		_meshes.append(_body)
	_apply_glow()


## Marks a fairy piece that still borrows its family's model, or a stitched one: a glowing ring above it.
func _add_halo() -> void:
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.16
	t.outer_radius = 0.2
	t.rings = 24
	t.ring_segments = 8
	ring.mesh = t
	ring.position = Vector3(0, height() + 0.18, 0)
	ring.set_surface_override_material(0, Mats.piece("piece_glow", white))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(ring)


static func _load_scene(path: String) -> PackedScene:
	if path == "":
		return null
	if _scene_cache.has(path):
		return _scene_cache[path]
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	_scene_cache[path] = scene
	return scene


func set_glow(v: float) -> void:
	_glow = v
	_apply_glow()


func _apply_glow() -> void:
	for mi in _meshes:
		mi.set_instance_shader_parameter(&"glow_boost", _glow)


## Turns the piece towards a world-space direction (knights look where they jump).
func face(dir: Vector3, t: float = 0.15) -> void:
	if dir.length_squared() < 0.0001:
		return
	var target := atan2(dir.x, dir.z)
	var cur := _yaw.rotation.y
	target = cur + wrapf(target - cur, -PI, PI)
	create_tween().tween_property(_yaw, "rotation:y", target, t)


func unface(t: float = 0.3) -> void:
	var cur := _yaw.rotation.y
	var target := cur + wrapf(rest_yaw - cur, -PI, PI)
	create_tween().tween_property(_yaw, "rotation:y", target, t).set_trans(Tween.TRANS_SINE)


## Plays an authored clip if the glb has it, otherwise the procedural stand-in. Returns its length.
func play(clip: String) -> float:
	if _anim != null and _anim.has_animation(clip):
		_anim.stop()
		_anim.play(clip)
		return _anim.get_animation(clip).length
	return _procedural(clip)


func _procedural(clip: String) -> float:
	var d: float = CLIP_LEN.get(clip, 0.5)
	var tw := create_tween()
	match clip:
		"move":
			tw.tween_property(_body, "position:y", 0.22, d * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(_body, "position:y", 0.0, d * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"leap":
			tw.tween_property(_body, "position:y", 0.95, d * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(_body, "rotation:x", -0.35, d * 0.45)
			tw.tween_property(_body, "position:y", 0.0, d * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(_body, "rotation:x", 0.0, d * 0.4)
			tw.tween_property(_body, "scale", Vector3(1.12, 0.86, 1.12), d * 0.06)
			tw.tween_property(_body, "scale", Vector3.ONE, d * 0.09)
		"capture":
			tw.tween_property(_body, "rotation:z", 0.5, d * 0.35).set_trans(Tween.TRANS_BACK)
			tw.parallel().tween_property(_body, "position:y", 0.15, d * 0.35)
			tw.tween_property(_body, "position:y", -0.8, d * 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(_body, "scale", Vector3(0.2, 0.2, 0.2), d * 0.65)
		"drop":
			_body.position.y = 3.0
			tw.tween_property(_body, "position:y", 0.0, d * 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(_body, "scale", Vector3(1.2, 0.78, 1.2), d * 0.12)
			tw.tween_property(_body, "scale", Vector3.ONE, d * 0.18).set_trans(Tween.TRANS_BACK)
		"spawn":
			_body.position.y = -0.9
			_body.scale = Vector3(0.6, 0.6, 0.6)
			tw.tween_property(_body, "position:y", 0.0, d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(_body, "scale", Vector3.ONE, d)
		_:
			tw.tween_interval(d)
	return d


## Promotion: shrink, swap the model, grow back.
func morph(new_letter: String) -> void:
	var tw := create_tween()
	tw.tween_property(_yaw, "scale", Vector3(0.05, 1.3, 0.05), 0.18).set_trans(Tween.TRANS_QUAD)
	await tw.finished
	letter = new_letter
	var nd: PieceDef = Content.piece_by_letter(new_letter.to_lower(), white)
	if nd != null:
		def = nd
		type = nd.id
	_build_body()
	set_nameplate(_plate_mode)
	var tw2 := create_tween()
	tw2.tween_property(_yaw, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw2.finished


# --- procedural stand-in (used until a glb exists) -------------------------------------------------

const PROFILES := {
	&"pawn": [[0.0, 0.37], [0.08, 0.37], [0.12, 0.3], [0.2, 0.2], [0.42, 0.13], [0.48, 0.2], [0.52, 0.13],
		[0.56, 0.2], [0.68, 0.22], [0.78, 0.17], [0.85, 0.0]],
	&"rook": [[0.0, 0.38], [0.1, 0.38], [0.14, 0.31], [0.24, 0.25], [0.7, 0.23], [0.74, 0.32], [1.0, 0.32], [1.0, 0.0]],
	&"knight": [[0.0, 0.38], [0.1, 0.38], [0.14, 0.31], [0.22, 0.27], [0.45, 0.2], [0.5, 0.0]],
	&"bishop": [[0.0, 0.37], [0.1, 0.37], [0.14, 0.3], [0.24, 0.22], [0.62, 0.14], [0.68, 0.22], [0.72, 0.14],
		[0.95, 0.18], [1.1, 0.06], [1.16, 0.06], [1.2, 0.0]],
	&"queen": [[0.0, 0.39], [0.1, 0.39], [0.14, 0.31], [0.26, 0.24], [0.95, 0.15], [1.02, 0.25], [1.07, 0.16],
		[1.3, 0.27], [1.36, 0.1], [1.45, 0.0]],
	&"king": [[0.0, 0.39], [0.1, 0.39], [0.14, 0.31], [0.26, 0.25], [1.0, 0.16], [1.07, 0.26], [1.12, 0.17],
		[1.32, 0.25], [1.38, 0.08], [1.6, 0.0]],
}


func _fallback_body() -> MeshInstance3D:
	var fam := family()
	var key := "%s/%s" % [fam, white]
	var mi := MeshInstance3D.new()
	if not _fallback_cache.has(key):
		_fallback_cache[key] = _lathe(PROFILES.get(fam, PROFILES[&"pawn"]))
	mi.mesh = _fallback_cache[key]
	mi.set_surface_override_material(0, Mats.piece("piece_body", white))
	if fam == &"knight":
		var head := MeshInstance3D.new()
		var box := PrismMesh.new()
		box.size = Vector3(0.26, 0.55, 0.5)
		head.mesh = box
		head.position = Vector3(0, 0.72, 0.06)
		head.rotation.x = -0.5
		head.set_surface_override_material(0, Mats.piece("piece_body", white))
		mi.add_child(head)
	var glow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.045
	sphere.height = 0.09
	glow.mesh = sphere
	glow.position = Vector3(0, height() * 0.72, 0.17)
	glow.set_surface_override_material(0, Mats.piece("piece_glow", white))
	mi.add_child(glow)
	return mi


static func _lathe(profile: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 28
	for i in profile.size() - 1:
		var a: Array = profile[i]
		var b: Array = profile[i + 1]
		for s in seg:
			var t0 := TAU * s / seg
			var t1 := TAU * (s + 1) / seg
			var p00 := Vector3(cos(t0) * a[1], a[0], sin(t0) * a[1])
			var p01 := Vector3(cos(t1) * a[1], a[0], sin(t1) * a[1])
			var p10 := Vector3(cos(t0) * b[1], b[0], sin(t0) * b[1])
			var p11 := Vector3(cos(t1) * b[1], b[0], sin(t1) * b[1])
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p10)
			st.add_vertex(p00)
			st.add_vertex(p01)
			st.add_vertex(p11)
	st.generate_normals()
	return st.commit()
