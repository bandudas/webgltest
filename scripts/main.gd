extends Node3D

## Pulau: jelajah kepulauan dengan perahu layar, siklus siang-malam, cari peti harta.
## Kontrol remote: atas = maju, bawah = rem/mundur, kiri/kanan = belok,
## OK = buka peti (jika dekat) / ganti kamera, Menu = kualitas grafis, Back 2x = keluar.

const DAY_LENGTH := 360.0     # detik untuk satu hari penuh
const SEED := 20261114
const OPEN_DIST := 13.0

# [waktu, langit atas, horizon, cahaya ambien]
const SKY_KEYS := [
	[0.00, Color(0.01, 0.02, 0.06), Color(0.03, 0.05, 0.11), Color(0.05, 0.08, 0.17)],
	[0.21, Color(0.03, 0.05, 0.14), Color(0.10, 0.10, 0.20), Color(0.07, 0.09, 0.18)],
	[0.26, Color(0.20, 0.30, 0.60), Color(1.00, 0.55, 0.35), Color(0.35, 0.30, 0.35)],
	[0.33, Color(0.22, 0.47, 0.85), Color(0.75, 0.82, 0.92), Color(0.45, 0.50, 0.60)],
	[0.50, Color(0.16, 0.42, 0.86), Color(0.68, 0.82, 0.96), Color(0.50, 0.56, 0.66)],
	[0.67, Color(0.22, 0.44, 0.80), Color(0.85, 0.80, 0.75), Color(0.48, 0.48, 0.55)],
	[0.75, Color(0.22, 0.20, 0.48), Color(1.00, 0.45, 0.25), Color(0.35, 0.28, 0.32)],
	[0.80, Color(0.05, 0.05, 0.16), Color(0.25, 0.14, 0.24), Color(0.08, 0.09, 0.18)],
	[1.00, Color(0.01, 0.02, 0.06), Color(0.03, 0.05, 0.11), Color(0.05, 0.08, 0.17)],
]

var tod := 0.30
var wave_t := 0.0
var night := 0.0
var cam_mode := 0
var quality := 0              # 0 = tinggi, 1 = rendah
var found := 0

var world: World
var boat: Boat
var cam: Camera3D
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var water: MeshInstance3D
var water_mat: ShaderMaterial

var hud_top: Label
var hud_right: Label
var hud_msg: Label
var _msg_time := 0.0
var _back_time := -10.0
var _fps_acc := 0.0
var _fps_frames := 0
var _fps := 0.0

# uji otomatis (screenshot)
var _shot_path := ""
var _shot_frames := 0
var _frame := 0
var _side_view := false


func _ready() -> void:
	get_tree().quit_on_go_back = false
	_setup_input()
	_parse_test_args()
	_setup_environment()

	world = World.new()
	add_child(world)
	world.generate(SEED)

	_setup_water()

	boat = Boat.new()
	add_child(boat)
	boat.setup()
	boat.position = Vector3(0, 0, 0)

	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.3
	cam.far = 420.0
	add_child(cam)
	_place_camera(1.0, true)

	_setup_hud()
	_apply_quality()
	_show_msg("Cari peti harta di setiap pulau. Ikuti pilar cahaya kuning.", 6.0)


# ------------------------------------------------------------------ input

func _add_action(name: String, keys: Array, buttons: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(name, e)
		var e2 := InputEventKey.new()
		e2.keycode = k
		InputMap.action_add_event(name, e2)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(name, j)


func _setup_input() -> void:
	_add_action("maju", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP])
	_add_action("mundur", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN])
	_add_action("kiri", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT])
	_add_action("kanan", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT])
	_add_action("ok", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], [JOY_BUTTON_A])
	_add_action("menu", [KEY_MENU, KEY_M, KEY_TAB], [JOY_BUTTON_START, JOY_BUTTON_Y])
	# stik analog gamepad (kalau ada)
	for pair in [["kiri", JOY_AXIS_LEFT_X, -1.0], ["kanan", JOY_AXIS_LEFT_X, 1.0],
			["maju", JOY_AXIS_LEFT_Y, -1.0], ["mundur", JOY_AXIS_LEFT_Y, 1.0]]:
		var m := InputEventJoypadMotion.new()
		m.axis = pair[1]
		m.axis_value = pair[2]
		InputMap.action_add_event(pair[0], m)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("ok"):
		if not _try_open_chest():
			cam_mode = (cam_mode + 1) % 3
			_show_msg(["Kamera: normal", "Kamera: jauh", "Kamera: dekat air"][cam_mode], 1.5)
	elif event.is_action_pressed("menu"):
		quality = 1 - quality
		_apply_quality()
		_show_msg("Grafis: " + ("tinggi (720p, bayangan)" if quality == 0 else "ringan (540p, tanpa bayangan)"), 2.0)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back_pressed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back_pressed()


func _back_pressed() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _back_time < 2.5:
		get_tree().quit()
	else:
		_back_time = now
		_show_msg("Tekan Back sekali lagi untuk keluar", 2.5)


func _apply_quality() -> void:
	var w := get_window()
	if quality == 0:
		w.content_scale_size = Vector2i(1280, 720)
		sun.shadow_enabled = true
	else:
		w.content_scale_size = Vector2i(960, 540)
		sun.shadow_enabled = false


# ------------------------------------------------------------------ lingkungan

func _setup_environment() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0032
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.08
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.shadow_enabled = false
	add_child(moon)


func _setup_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(720, 720)
	plane.subdivide_width = 119
	plane.subdivide_depth = 119
	water_mat = ShaderMaterial.new()
	water_mat.shader = preload("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("island_count", world.islands.size())
	water_mat.set_shader_parameter("islands", world.island_uniforms())
	water = MeshInstance3D.new()
	water.mesh = plane
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.extra_cull_margin = 2.0
	add_child(water)


func _sample_sky(t: float) -> Array:
	for i in SKY_KEYS.size() - 1:
		var a: Array = SKY_KEYS[i]
		var b: Array = SKY_KEYS[i + 1]
		if t >= a[0] and t <= b[0]:
			var f := smoothstep(a[0], b[0], t)
			return [(a[1] as Color).lerp(b[1], f), (a[2] as Color).lerp(b[2], f), (a[3] as Color).lerp(b[3], f)]
	return [SKY_KEYS[0][1], SKY_KEYS[0][2], SKY_KEYS[0][3]]


func _update_sky() -> void:
	var ang := (tod - 0.25) * TAU
	var sun_dir := Vector3(cos(ang), sin(ang), 0.35).normalized()
	var moon_dir := Vector3(-sun_dir.x, -sun_dir.y, 0.2).normalized()
	night = 1.0 - clampf((sun_dir.y + 0.08) * 4.0, 0.0, 1.0)
	var day := 1.0 - night

	var cols := _sample_sky(tod)
	var top: Color = cols[0]
	var hor: Color = cols[1]
	var amb: Color = cols[2]

	var sun_col := Color(1.0, 0.55, 0.3).lerp(Color(1.0, 0.96, 0.88), clampf(sun_dir.y * 2.5, 0.0, 1.0))
	if sun_dir.y > -0.05:
		sun.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)
	sun.light_energy = clampf(sun_dir.y * 4.0, 0.0, 1.0) * 0.85
	sun.light_color = sun_col
	sun.visible = sun.light_energy > 0.01
	if moon_dir.y > 0.05:
		moon.global_transform = Transform3D(Basis.looking_at(-moon_dir, Vector3.UP), Vector3.ZERO)
	moon.light_energy = 0.35 * night
	moon.visible = night > 0.02

	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("sun_color", sun_col)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("star_amount", night)

	env.ambient_light_color = amb
	env.ambient_light_energy = 0.55
	env.fog_light_color = hor

	water_mat.set_shader_parameter("deep_color", Color(0.02, 0.05, 0.12).lerp(Color(0.04, 0.27, 0.42), clampf(day * 1.4, 0.0, 1.0)))
	water_mat.set_shader_parameter("shallow_color", Color(0.03, 0.10, 0.14).lerp(Color(0.16, 0.60, 0.62), day))
	water_mat.set_shader_parameter("sky_color", hor.lerp(top, 0.3))


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	wave_t += delta
	tod = fposmod(tod + delta / DAY_LENGTH, 1.0)
	_update_sky()

	boat.step(delta, wave_t)
	var res: Array = world.push_out(boat.position, Boat.RADIUS)
	if res[1]:
		boat.position = res[0]
		boat.speed *= 0.6
	var dist_center := Vector2(boat.position.x, boat.position.z).length()
	if dist_center > 430.0:
		var back := -Vector3(boat.position.x, 0, boat.position.z).normalized()
		boat.position += back * (dist_center - 430.0)
		_show_msg("Laut terlalu jauh. Kembali ke kepulauan.", 2.0)

	world.update(delta, wave_t, night)

	water.position = Vector3(snappedf(cam.global_position.x, 6.0), 0, snappedf(cam.global_position.z, 6.0))
	water_mat.set_shader_parameter("wave_time", wave_t)

	_place_camera(delta, false)
	_update_hud(delta)
	_test_hook()


func _place_camera(delta: float, snap: bool) -> void:
	if _side_view:
		# uji: perahu menghadap +X, kamera di +Z -> haluan harus di KANAN layar
		cam.global_position = boat.position + Vector3(0, 2.0, 11.0)
		cam.look_at(boat.position + Vector3(0, 1.5, 0), Vector3.UP)
		return
	var f := boat.forward()
	var back_dist: float = [11.0, 24.0, 6.5][cam_mode]
	var up: float = [4.5, 11.0, 1.6][cam_mode]
	var target: Vector3 = boat.position - f * back_dist + Vector3(0, up, 0)
	target.y = maxf(target.y, Waves.height(target.x, target.z, wave_t) + 0.8)
	var k := 1.0 if snap else 1.0 - exp(-2.5 * delta)
	cam.global_position = cam.global_position.lerp(target, k)
	var look_h: float = [2.0, 1.0, 2.2][cam_mode]
	var look: Vector3 = boat.position + Vector3(0, look_h, 0) + f * 3.0
	if cam.global_position.distance_to(look) > 0.5:
		cam.look_at(look, Vector3.UP)


func _try_open_chest() -> bool:
	var isl := world.nearest_chest(boat.position)
	if isl.is_empty():
		return false
	var cp: Vector3 = isl.chest.global_position
	if Vector2(cp.x - boat.position.x, cp.z - boat.position.z).length() > OPEN_DIST:
		return false
	isl.opened = true
	isl.beacon.queue_free()
	isl.beacon = null
	found += 1
	_burst(cp + Vector3(0, 1.2, 0))
	var tw := create_tween()
	tw.tween_property(isl.chest, "rotation:y", isl.chest.rotation.y + TAU * 2.0, 1.2).set_trans(Tween.TRANS_CUBIC)
	if world.remaining() == 0:
		_show_msg("Semua %d peti harta ditemukan! Selamat berlayar santai." % found, 8.0)
	else:
		_show_msg("Peti harta dibuka! %d lagi." % world.remaining(), 3.0)
	return true


func _burst(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 40
	p.lifetime = 1.6
	p.explosiveness = 0.9
	p.local_coords = false
	var m := SphereMesh.new()
	m.radius = 0.12
	m.height = 0.24
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 1.5
	m.material = mat
	p.mesh = m
	p.direction = Vector3.UP
	p.spread = 50.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -9.0, 0)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)


# ------------------------------------------------------------------ HUD

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_top = _make_label(22)
	hud_top.position = Vector2(24, 16)
	layer.add_child(hud_top)
	hud_right = _make_label(22)
	hud_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_right.position = Vector2(-24, 16)
	hud_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(hud_right)
	hud_msg = _make_label(26)
	hud_msg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_msg.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud_msg.position.y = -40
	layer.add_child(hud_msg)


func _show_msg(text: String, secs: float) -> void:
	if hud_msg == null:
		return
	hud_msg.text = text
	_msg_time = secs


func _update_hud(delta: float) -> void:
	_fps_acc += delta
	_fps_frames += 1
	if _fps_acc >= 0.5:
		_fps = _fps_frames / _fps_acc
		_fps_acc = 0.0
		_fps_frames = 0

	var hours := int(tod * 24.0)
	var mins := int(fposmod(tod * 24.0 * 60.0, 60.0))
	var total := world.islands.size()
	hud_top.text = "Harta %d/%d     %02d:%02d     %d km/j" % [found, total, hours, mins, int(absf(boat.speed) * 3.6)]

	var isl := world.nearest_chest(boat.position)
	if isl.is_empty():
		hud_right.text = "Semua harta ditemukan\nFPS %d" % int(_fps)
	else:
		var cp: Vector3 = isl.chest.global_position
		var to := Vector3(cp.x - boat.position.x, 0, cp.z - boat.position.z)
		var dist := to.length()
		var f := boat.forward()
		var right := Vector3(-f.z, 0, f.x)
		var ang := rad_to_deg(atan2(to.dot(right), to.dot(f)))
		var arah := "lurus"
		if absf(ang) > 150.0:
			arah = "putar balik"
		elif ang > 20.0:
			arah = "belok kanan"
		elif ang < -20.0:
			arah = "belok kiri"
		if dist <= OPEN_DIST:
			hud_right.text = "Peti di dekatmu!\nFPS %d" % int(_fps)
			if _msg_time <= 0.0:
				hud_msg.text = "Tekan OK untuk membuka peti"
				hud_msg.modulate.a = 1.0
		else:
			hud_right.text = "Peti terdekat: %d m, %s\nFPS %d" % [int(dist), arah, int(_fps)]

	if _msg_time > 0.0:
		_msg_time -= delta
		hud_msg.modulate.a = clampf(_msg_time, 0.0, 1.0)
	elif not (not isl.is_empty() and Vector2(isl.chest.global_position.x - boat.position.x, isl.chest.global_position.z - boat.position.z).length() <= OPEN_DIST):
		hud_msg.modulate.a = 0.0


# ------------------------------------------------------------------ uji otomatis
# Argumen: -- shot=/tmp/a.png frames=120 tod=0.5 cam=0 pos=x,z yaw=deg auto=1

func _parse_test_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"shot": _shot_path = kv[1]
			"frames": _shot_frames = int(kv[1])
			"tod": tod = float(kv[1])
			"cam": cam_mode = int(kv[1])
			"side": _side_view = kv[1] == "1"


func _apply_late_test_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"pos":
				var p := kv[1].split(",")
				boat.position = Vector3(float(p[0]), 0, float(p[1]))
			"yaw": boat.yaw = deg_to_rad(float(kv[1]))
			"auto": boat.autopilot = kv[1] == "1"
			"open": _try_open_chest()


func _test_hook() -> void:
	_frame += 1
	if _frame == 1:
		_apply_late_test_args()
		_place_camera(1.0, true)
	if _shot_path != "" and _frame == max(_shot_frames, 5):
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("SHOT ", _shot_path, " fps=", Engine.get_frames_per_second(), " islands=", world.islands.size())
		get_tree().quit()
