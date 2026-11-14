class_name Boat
extends Node3D

## Perahu layar pemain. Model Kenney menghadap +Z.

const MODEL := "res://assets/water/boat-sail-a.glb"
const MAX_SPEED := 9.0
const MAX_REVERSE := -2.5
const ACCEL := 2.6
const DRAG := 0.7
const TURN := 1.0
const RADIUS := 1.8

var yaw := PI          # menghadap -Z (ke pulau pertama)
var speed := 0.0
var yaw_vel := 0.0
var autopilot := false # untuk uji otomatis
var _tilt: Node3D
var _wake: CPUParticles3D
var _roll := 0.0


func setup() -> void:
	_tilt = Node3D.new()
	add_child(_tilt)
	var model: Node3D = load(MODEL).instantiate()
	model.position.y = -0.35
	_tilt.add_child(model)
	_wake = _make_wake()
	add_child(_wake)


func forward() -> Vector3:
	return Vector3(sin(yaw), 0, cos(yaw))


func step(delta: float, wave_t: float) -> void:
	var throttle := Input.get_action_strength("maju") - Input.get_action_strength("mundur")
	var steer := Input.get_action_strength("kiri") - Input.get_action_strength("kanan")
	if autopilot:
		throttle = 1.0
		steer = 0.25

	if throttle > 0.0:
		speed = move_toward(speed, MAX_SPEED * throttle, ACCEL * delta)
	elif throttle < 0.0:
		speed = move_toward(speed, MAX_REVERSE, ACCEL * 1.3 * delta)
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)

	var turn_rate := TURN * (0.4 + 0.6 * clampf(absf(speed) / 4.0, 0.0, 1.0))
	var dir_sign := -1.0 if speed < -0.1 else 1.0
	yaw_vel = lerpf(yaw_vel, steer * turn_rate * dir_sign, 1.0 - exp(-4.0 * delta))
	yaw += yaw_vel * delta

	position += forward() * speed * delta
	rotation.y = yaw

	# Ikuti gelombang: tinggi di tengah, kemiringan dari sampel depan/belakang/kiri/kanan.
	var f := forward() * 1.8
	var r := Vector3(f.z, 0, -f.x)
	var hc := Waves.height(position.x, position.z, wave_t)
	var hf := Waves.height(position.x + f.x, position.z + f.z, wave_t)
	var hb := Waves.height(position.x - f.x, position.z - f.z, wave_t)
	var hr := Waves.height(position.x + r.x, position.z + r.z, wave_t)
	var hl := Waves.height(position.x - r.x, position.z - r.z, wave_t)
	position.y = hc
	_roll = lerpf(_roll, -yaw_vel * speed * 0.035, 1.0 - exp(-3.0 * delta))
	_tilt.rotation.x = -atan2(hf - hb, 3.6)
	_tilt.rotation.z = atan2(hr - hl, 3.6) + _roll

	_wake.emitting = absf(speed) > 1.5


func _make_wake() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 45
	p.lifetime = 2.2
	p.local_coords = false
	p.position = Vector3(0, 0.05, -1.9)
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.4)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 0.5)
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var tg := Gradient.new()
	tg.set_color(0, Color(1, 1, 1, 1))
	tg.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = tg
	tex.width = 32
	tex.height = 32
	m.albedo_texture = tex
	q.material = m
	p.mesh = q
	p.direction = Vector3(0, 0, -1)
	p.spread = 35.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.gravity = Vector3.ZERO
	p.damping_min = 0.3
	p.damping_max = 0.6
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 2.2))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.8))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
