class_name CameraRig
extends Node3D
## Fight view (fixed framing, small orbit and zoom on right-drag and wheel) and a slow menu orbit.

var cam: Camera3D
var mode := "orbit"
var target := Vector3(0, 0, 0.35)
var yaw := 0.0
var pitch := deg_to_rad(44.0)
var dist := 13.4
var allow_control := false

var _yaw := 0.6
var _pitch := deg_to_rad(24.0)
var _dist := 19.0
var _target := Vector3(0, -0.4, 0)
var _dragging := false
var _shake := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.1
	cam.far = 400.0
	add_child(cam)
	cam.current = true
	set_mode("orbit", true)


func set_mode(m: String, snap: bool = false) -> void:
	mode = m
	allow_control = m == "fight"
	if m == "fight":
		yaw = 0.0
		pitch = deg_to_rad(53.0)
		dist = 15.2
		target = Vector3(0, 0, 0.75)
	elif m == "map":
		yaw = 0.0
		pitch = deg_to_rad(62.0)
		dist = 16.5
		target = Vector3(0, 0, -0.5)
	else:
		pitch = deg_to_rad(22.0)
		dist = 18.5
		target = Vector3(0, -0.2, 0)
	if snap:
		_yaw = yaw
		_pitch = pitch
		_dist = dist
		_target = target
		_apply()


func shake(amount: float = 0.12) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if mode == "orbit":
		yaw += delta * 0.045
	var k := 1.0 - exp(-delta * 3.0)
	_yaw = lerp_angle(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = lerpf(_dist, dist, k)
	_target = _target.lerp(target, k)
	_shake = maxf(_shake - delta * 0.6, 0.0)
	_apply()


func _apply() -> void:
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	cam.position = _target + off
	cam.look_at(_target, Vector3.UP)
	if _shake > 0.0:
		var t := Time.get_ticks_msec() * 0.05
		cam.position += Vector3(sin(t * 1.3), sin(t * 1.7), 0) * _shake * 0.3


func _unhandled_input(event: InputEvent) -> void:
	if not allow_control:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist - 0.8, 9.0, 18.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist + 0.8, 9.0, 18.0)
	elif event is InputEventMouseMotion and _dragging:
		yaw = clampf(yaw - event.relative.x * 0.004, -0.7, 0.7)
		pitch = clampf(pitch + event.relative.y * 0.003, deg_to_rad(26.0), deg_to_rad(70.0))
