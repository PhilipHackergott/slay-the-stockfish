class_name Mats
extends RefCounted
## Material library. Blender assets name their material slots; the game swaps them by name so the
## look (shaders, side colours) lives in one place.

const BONE := preload("res://shaders/piece_bone.gdshader")
const OBSIDIAN := preload("res://shaders/piece_obsidian.gdshader")
const GLOW := preload("res://shaders/glow.gdshader")
const STONE := preload("res://shaders/board_stone.gdshader")

const SOUL_BLUE := Color(0.42, 0.74, 1.0)
const EMBER := Color(1.0, 0.36, 0.08)
const CANDLE := Color(1.0, 0.62, 0.28)

static var _cache: Dictionary = {}


## Strips Blender's ".001" suffixes.
static func base_name(n: String) -> String:
	var i := n.find(".")
	return n.substr(0, i) if i > 0 else n


static func piece(slot: String, white: bool) -> Material:
	var key := "piece/%s/%s" % [base_name(slot), "w" if white else "b"]
	if _cache.has(key):
		return _cache[key]
	var m: Material
	match base_name(slot):
		"piece_trim":
			m = _metal(Color(0.72, 0.74, 0.8) if white else Color(0.16, 0.14, 0.15), 0.32 if white else 0.45)
		"piece_glow":
			m = _glow(SOUL_BLUE if white else EMBER, 4.5 if white else 5.0)
		_:
			var s := ShaderMaterial.new()
			s.shader = BONE if white else OBSIDIAN
			m = s
	_cache[key] = m
	return m


static func world(slot: String) -> Material:
	var n := base_name(slot)
	if _cache.has(n):
		return _cache[n]
	var m: Material
	match n:
		"board_light":
			m = _stone(Color(0.80, 0.78, 0.74), Color(0.38, 0.36, 0.40), 0.75, 0.0, 0.3, 1.0, 0.0)
		"board_dark":
			m = _stone(Color(0.085, 0.08, 0.095), Color(0.22, 0.2, 0.26), 0.35, 1.0, 0.42, 1.0, 0.0)
		"board_rune":
			m = _glow(Color(0.5, 0.4, 1.0), 0.75, 0.6, 0.35)
		"board_rim", "stone":
			m = _stone(Color(0.30, 0.29, 0.31), Color(0.17, 0.16, 0.18), 0.25, 0.3, 0.8, 0.8, 0.5)
		"board_trim":
			m = _metal(Color(0.42, 0.40, 0.44), 0.45)
		"stone_dark":
			m = _stone(Color(0.15, 0.14, 0.16), Color(0.08, 0.075, 0.085), 0.2, 0.4, 0.85, 0.8, 0.6)
		"floor_tiles":
			m = _stone(Color(0.145, 0.14, 0.155), Color(0.08, 0.075, 0.085), 0.35, 0.2, 0.6, 0.6, 0.5)
		"iron":
			m = _metal(Color(0.09, 0.085, 0.09), 0.5)
		"wood_dead":
			m = _flat(Color(0.14, 0.12, 0.11), 0.92)
		"crow":
			m = _flat(Color(0.03, 0.03, 0.04), 0.45)
		"moss":
			m = _flat(Color(0.12, 0.16, 0.09), 0.95)
		"bone":
			m = _flat(Color(0.74, 0.70, 0.60), 0.6)
		"candle_wax":
			var w := _flat(Color(0.88, 0.82, 0.68), 0.55)
			w.emission_enabled = true
			w.emission = Color(1.0, 0.6, 0.3)
			w.emission_energy_multiplier = 0.25
			m = w
		"candle_flame":
			m = _glow(CANDLE, 7.0, 0.0, 0.0, 0.35)
		_:
			m = _stone(Color(0.25, 0.24, 0.27), Color(0.15, 0.14, 0.16), 0.2, 0.3, 0.8, 0.8, 0.3)
	_cache[n] = m
	return m


## Applies piece or world materials to every MeshInstance3D under root by slot name.
static func apply(root: Node, piece_side: int = -1) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mi as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var src := mesh_instance.mesh.surface_get_material(i)
			var slot := src.resource_name if src != null and src.resource_name != "" else "piece_body"
			var mat := piece(slot, piece_side == 0) if piece_side >= 0 else world(slot)
			mesh_instance.set_surface_override_material(i, mat)


static func _stone(base: Color, vein: Color, veins: float, speck: float, rough: float, scale: float, moss: float) -> ShaderMaterial:
	var s := ShaderMaterial.new()
	s.shader = STONE
	s.set_shader_parameter("base_color", base)
	s.set_shader_parameter("vein_color", vein)
	s.set_shader_parameter("vein_amount", veins)
	s.set_shader_parameter("speckle", speck)
	s.set_shader_parameter("roughness_base", rough)
	s.set_shader_parameter("scale", scale)
	s.set_shader_parameter("moss", moss)
	return s


static func _glow(c: Color, energy: float, pulse_depth: float = 0.18, pulse_speed: float = 2.2, flicker: float = 0.0) -> ShaderMaterial:
	var s := ShaderMaterial.new()
	s.shader = GLOW
	s.set_shader_parameter("color", c)
	s.set_shader_parameter("energy", energy)
	s.set_shader_parameter("pulse_depth", pulse_depth)
	s.set_shader_parameter("pulse_speed", pulse_speed)
	s.set_shader_parameter("flicker", flicker)
	return s


static func _metal(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.9
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	return m


static func _flat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	return m
