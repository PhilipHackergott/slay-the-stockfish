class_name Fx
extends RefCounted
## One-shot particle bursts and light flashes.

static var _dot: Texture2D
static var _mats: Dictionary = {}


static func dot_texture() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_dot = t
	return _dot


static func _draw_mat(additive: bool) -> StandardMaterial3D:
	var key := "add" if additive else "mix"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = dot_texture()
		m.disable_receive_shadows = true
		_mats[key] = m
	return _mats[key]


## kind: "land" (sparks ring on landing), "capture" (embers up), "smoke" (dark puff), "spawn" (soul motes).
static func burst(parent: Node3D, pos: Vector3, color: Color, kind: String = "land") -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	var quad := QuadMesh.new()
	var additive := kind != "smoke" and kind != "slam"
	quad.material = _draw_mat(additive)
	var ramp := Gradient.new()
	var energy := 3.0 if additive else 1.0
	ramp.set_color(0, Color(color.r * energy, color.g * energy, color.b * energy, 1.0))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	match kind:
		"land":
			p.amount = 28
			p.lifetime = 0.6
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = 0.38
			pm.emission_ring_inner_radius = 0.3
			pm.emission_ring_height = 0.02
			pm.direction = Vector3.UP
			pm.spread = 70.0
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.4
			pm.gravity = Vector3(0, -1.5, 0)
			quad.size = Vector2(0.06, 0.06)
		"capture":
			p.amount = 60
			p.lifetime = 1.4
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.3
			pm.direction = Vector3.UP
			pm.spread = 45.0
			pm.initial_velocity_min = 0.8
			pm.initial_velocity_max = 2.6
			pm.gravity = Vector3(0, 0.6, 0)
			pm.damping_min = 0.6
			pm.damping_max = 1.4
			quad.size = Vector2(0.05, 0.05)
		"smoke":
			p.amount = 18
			p.lifetime = 1.6
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.25
			pm.direction = Vector3.UP
			pm.spread = 30.0
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 0.8
			pm.gravity = Vector3(0, 0.3, 0)
			pm.scale_min = 0.8
			pm.scale_max = 1.6
			quad.size = Vector2(0.5, 0.5)
		"slam":
			p.amount = 90
			p.lifetime = 1.8
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = 1.2
			pm.emission_ring_inner_radius = 0.6
			pm.emission_ring_height = 0.05
			pm.direction = Vector3.UP
			pm.spread = 15.0
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.5
			pm.radial_velocity_min = 2.0
			pm.radial_velocity_max = 4.5
			pm.damping_min = 2.5
			pm.damping_max = 4.0
			pm.gravity = Vector3(0, 0.15, 0)
			pm.scale_min = 0.8
			pm.scale_max = 2.0
			quad.size = Vector2(0.6, 0.6)
		"debris":
			p.amount = 50
			p.lifetime = 1.1
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(1.1, 0.05, 0.5)
			pm.direction = Vector3.UP
			pm.spread = 60.0
			pm.initial_velocity_min = 1.5
			pm.initial_velocity_max = 4.0
			pm.gravity = Vector3(0, -9.0, 0)
			quad.size = Vector2(0.05, 0.05)
		_:
			p.amount = 36
			p.lifetime = 1.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.4
			pm.direction = Vector3.UP
			pm.spread = 25.0
			pm.initial_velocity_min = 0.4
			pm.initial_velocity_max = 1.2
			pm.gravity = Vector3(0, 0.4, 0)
			quad.size = Vector2(0.05, 0.05)
	p.process_material = pm
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## A steady stream of embers rising from a fire (parented, lives as long as the parent).
static func embers(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 2.2
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.direction = Vector3.UP
	pm.spread = 18.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.25, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(3.0, 1.3, 0.35, 1.0))
	ramp.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	quad.material = _draw_mat(true)
	p.process_material = pm
	p.draw_pass_1 = quad
	parent.add_child(p)
	return p


static func flash(parent: Node3D, pos: Vector3, color: Color, energy: float = 4.0, dur: float = 0.5) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 3.5
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)
