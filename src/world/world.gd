class_name World
extends Node3D
## The scene around the board: sky, moonlight, candles, fog, the cathedral ruin and the camera.
## Every glb is optional; stand-ins keep the game playable while the Blender assets are missing.

const ENV_GLB := "res://models/env/environment.glb"
const CANDELABRA_GLB := "res://models/props/candelabra.glb"
const SKY := preload("res://shaders/sky.gdshader")
const FLOOR_Y := -1.25
const CANDLE_SPOTS := [Vector3(-6.1, FLOOR_Y, 6.1), Vector3(6.1, FLOOR_Y, 6.1), Vector3(-6.1, FLOOR_Y, -6.1), Vector3(6.1, FLOOR_Y, -6.1)]

var board_view: BoardView
var rig: CameraRig
var env: Environment
var moon: DirectionalLight3D
var _candles: Array[OmniLight3D] = []
var _candle_base: Array[float] = []
var _t := 0.0


func _ready() -> void:
	_build_environment()
	_build_lights()
	board_view = BoardView.new()
	board_view.name = "BoardView"
	add_child(board_view)
	_build_ruin()
	_build_candelabras()
	_build_ground_mist()
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	board_view.camera = rig.cam


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.38
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.07, 0.15)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.1
	env.fog_height = -4.0
	env.fog_height_density = 0.05
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.01
	env.volumetric_fog_albedo = Color(0.45, 0.42, 0.62)
	env.volumetric_fog_emission = Color(0.004, 0.003, 0.01)
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.62, 1.0)
	moon.light_energy = 1.05
	moon.shadow_enabled = true
	moon.shadow_blur = 1.5
	moon.directional_shadow_max_distance = 45.0
	moon.light_volumetric_fog_energy = 0.6
	add_child(moon)
	moon.transform.basis = Basis.looking_at(Vector3(0.45, -0.72, 0.52).normalized(), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.42, 0.34, 0.62)
	fill.light_energy = 0.18
	fill.shadow_enabled = false
	add_child(fill)
	fill.transform.basis = Basis.looking_at(Vector3(-0.4, -0.5, -0.75).normalized(), Vector3.UP)


func _load_glb(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null


func _build_ruin() -> void:
	var ruin := _load_glb(ENV_GLB)
	if ruin != null:
		add_child(ruin)
		Mats.apply(ruin)
		# Hanging chains would stripe the board with moon shadows; the far backdrop is beyond the shadow range anyway.
		for mi in ruin.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).begins_with("env_chains") or String(mi.name).begins_with("env_far"):
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var floor_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 15.0
	cyl.bottom_radius = 9.0
	cyl.height = 4.0
	cyl.radial_segments = 48
	floor_mesh.mesh = cyl
	floor_mesh.position = Vector3(0, FLOOR_Y - 2.0, 0)
	floor_mesh.set_surface_override_material(0, Mats.world("floor_tiles"))
	add_child(floor_mesh)
	for i in 9:
		var a := PI + TAU * float(i) / 12.0 + 0.6
		var pillar := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.55
		pm.bottom_radius = 0.7
		pm.height = 6.0 + float(i % 3) * 2.5
		pillar.mesh = pm
		pillar.position = Vector3(cos(a) * 12.5, FLOOR_Y + pm.height * 0.5, sin(a) * 12.5)
		pillar.set_surface_override_material(0, Mats.world("stone"))
		add_child(pillar)
	var rose := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.4
	torus.outer_radius = 4.0
	rose.mesh = torus
	rose.rotation.x = PI / 2
	rose.position = Vector3(0, 7.0, -14.0)
	rose.set_surface_override_material(0, Mats.world("stone_dark"))
	add_child(rose)


func _build_candelabras() -> void:
	for spot in CANDLE_SPOTS:
		var holder := Node3D.new()
		add_child(holder)
		holder.position = spot
		holder.rotation.y = atan2(-spot.x, -spot.z)
		var c := _load_glb(CANDELABRA_GLB)
		var flame_pos := Vector3(0, 2.3, 0)
		if c != null:
			holder.add_child(c)
			Mats.apply(c)
			var flames := c.find_children("flame_*", "Node3D", true, false)
			if not flames.is_empty():
				var sum := Vector3.ZERO
				for f in flames:
					sum += holder.to_local(f.global_position) if f.is_inside_tree() else f.position
				flame_pos = sum / float(flames.size())
		else:
			_standin_candelabra(holder)
		var l := OmniLight3D.new()
		l.light_color = Mats.CANDLE
		l.light_energy = 4.6
		l.omni_range = 12.5
		l.omni_attenuation = 1.3
		l.shadow_enabled = true
		l.shadow_blur = 2.0
		l.light_volumetric_fog_energy = 2.0
		holder.add_child(l)
		l.position = flame_pos + Vector3(0, 0.12, 0)
		_candles.append(l)
		_candle_base.append(l.light_energy)


func _standin_candelabra(holder: Node3D) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.12
	pm.height = 2.1
	pole.mesh = pm
	pole.position.y = 1.05
	pole.set_surface_override_material(0, Mats.world("iron"))
	holder.add_child(pole)
	for i in 3:
		var x := (float(i) - 1.0) * 0.32
		var candle := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.045
		cm.bottom_radius = 0.05
		cm.height = 0.3
		candle.mesh = cm
		candle.position = Vector3(x, 2.15 + (0.1 if i == 1 else 0.0), 0)
		candle.set_surface_override_material(0, Mats.world("candle_wax"))
		holder.add_child(candle)
		var flame := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.035
		fm.height = 0.12
		flame.mesh = fm
		flame.position = candle.position + Vector3(0, 0.21, 0)
		flame.set_surface_override_material(0, Mats.world("candle_flame"))
		holder.add_child(flame)


func _build_ground_mist() -> void:
	var fv := FogVolume.new()
	fv.size = Vector3(40, 2.2, 40)
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var fm := FogMaterial.new()
	fm.density = 0.22
	fm.albedo = Color(0.3, 0.28, 0.42)
	fm.height_falloff = 1.6
	fm.edge_fade = 0.6
	var noise := NoiseTexture3D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.06
	noise.noise = fn
	noise.width = 64
	noise.height = 32
	noise.depth = 64
	noise.seamless = true
	fm.density_texture = noise
	fv.material = fm
	add_child(fv)
	fv.position = Vector3(0, FLOOR_Y - 0.2, 0)


func _process(delta: float) -> void:
	_t += delta
	for i in _candles.size():
		var f := 0.86 + 0.08 * sin(_t * 9.0 + float(i) * 1.7) + 0.06 * sin(_t * 23.0 + float(i) * 4.1)
		_candles[i].light_energy = _candle_base[i] * f
