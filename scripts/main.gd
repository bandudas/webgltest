extends Node3D

## Gang Salju: scene noir malam bersalju, sudut pandang orang pertama.
## Remote: atas/bawah = jalan maju/mundur, kiri/kanan = menoleh, OK = gerak lambat,
## Menu = grafis, Back 2x = keluar.

const T := "res://textures/"
const WALK := 2.3
const TURN := 1.5
const EYE := 1.7

# [lebar, tinggi, nama]
const QUALITY := [[640, 360, "360p"], [854, 480, "480p"], [960, 540, "540p"], [1280, 720, "720p"]]
var quality := 1
var auto_quality := true
var _adapt_t := 0.0
var _adapt_n := 0
var _adapt_wait := 4.0

var cam: Camera3D
var yaw := 0.0
var pos := Vector3(0, 0, 2)
var _bob := 0.0
var slowmo := 0.0
var slowmo_on := false

# mode hantu: setelah diam beberapa detik, kamera melayang sendiri menyusuri jalan
const IDLE_TO_GHOST := 10.0
const GHOST_PATH := [
	Vector2(0, 0), Vector2(-3, -12), Vector2(-4, -26), Vector2(-4, -36), Vector2(4, -40.5), Vector2(9, -43.5),
	Vector2(17, -43.5), Vector2(19, -45), Vector2(12, -44), Vector2(5, -44), Vector2(-4, -55),
	Vector2(0, -70), Vector2(3, -85), Vector2(0, -96), Vector2(-4, -80), Vector2(2, -60),
	Vector2(-5, -36), Vector2(-2, -18), Vector2(0, -2),
]
var _idle_t := 0.0
var ghost_on := false
var ghost := 0.0
var _ghost_i := 0
var _ghost_time := 0.0
const MusicScript := preload("res://scripts/music.gd")
var music: Node

var post_mat: ShaderMaterial
var hud_hint: Label
var hud_fps: Label
var _hint_t := 9.0
var _back_t := -10.0
var _mats := {}
var _neons: Array = []   # [Label3D, OmniLight3D, energi dasar, fase]
var _snow: GPUParticles3D
var _glow_shader: Shader = preload("res://shaders/glow_pool.gdshader")
var _facade_shader: Shader = preload("res://shaders/facade.gdshader")
var rng := RandomNumberGenerator.new()
var _canopy_mats: Array = []
var _iron: ShaderMaterial
var _all_mats: Array = []
var _lights: Array = []
var _surface_shader: Shader = preload("res://shaders/surface.gdshader")

# uji otomatis
var _shot := ""
var _shot_frames := 0
var _frame := 0
var _nopost := false


func _ready() -> void:
	rng.seed = 7
	get_tree().quit_on_go_back = false
	_setup_input()
	_parse_args()
	_setup_env()
	_build_street()
	_build_alley()
	_build_end()
	_build_lamps()
	_build_props()
	_build_snow()
	_flush_batches()
	_apply_lights()
	_setup_camera()
	_setup_hud()
	_apply_quality()
	music = MusicScript.new()
	add_child(music)


# ------------------------------------------------------------------ input

func _add_action(n: String, keys: Array, buttons: Array) -> void:
	if not InputMap.has_action(n):
		InputMap.add_action(n, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(n, e)
		var e2 := InputEventKey.new()
		e2.keycode = k
		InputMap.action_add_event(n, e2)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(n, j)


func _setup_input() -> void:
	_add_action("maju", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP])
	_add_action("mundur", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN])
	_add_action("kiri", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT])
	_add_action("kanan", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT])
	_add_action("ok", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], [JOY_BUTTON_A])
	_add_action("menu", [KEY_MENU, KEY_M, KEY_TAB], [JOY_BUTTON_START, JOY_BUTTON_Y])


func _input(event: InputEvent) -> void:
	if event.is_pressed() and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventScreenTouch or event is InputEventMouseButton):
		_idle_t = 0.0
		if ghost_on:
			ghost_on = false
			get_viewport().set_input_as_handled()   # tombol pertama hanya membangunkan


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("ok"):
		slowmo_on = not slowmo_on
	elif event.is_action_pressed("menu"):
		if auto_quality:
			auto_quality = false
			quality = 0
		elif quality < QUALITY.size() - 1:
			quality += 1
		else:
			auto_quality = true
			quality = 1
			_adapt_wait = 3.0
		_apply_quality()
		_hint("Grafis: " + ("otomatis" if auto_quality else QUALITY[quality][2]), 2.0)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _back() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _back_t < 2.5:
		get_tree().quit()
	else:
		_back_t = now
		_hint("Tekan Back sekali lagi untuk keluar", 2.5)


func _apply_quality() -> void:
	var q: Array = QUALITY[quality]
	get_window().content_scale_size = Vector2i(q[0], q[1])
	if post_mat:
		post_mat.set_shader_parameter("res", Vector2(q[0], q[1]))
	var k: float = float(q[1]) / 720.0
	if hud_hint:
		hud_hint.add_theme_font_size_override("font_size", maxi(10, int(24 * k)))
		hud_fps.add_theme_font_size_override("font_size", maxi(9, int(16 * k)))
		hud_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, int(34 * k))
		hud_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		hud_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		hud_fps.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(14 * k))
		hud_fps.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _adapt(delta: float) -> void:
	if not auto_quality:
		return
	if _adapt_wait > 0.0:
		_adapt_wait -= delta
		_adapt_t = 0.0
		_adapt_n = 0
		return
	_adapt_t += delta
	_adapt_n += 1
	if _adapt_t < 3.0:
		return
	var fps := _adapt_n / _adapt_t
	_adapt_t = 0.0
	_adapt_n = 0
	if fps < 26.0 and quality > 0:
		quality -= 1
		_apply_quality()
		_adapt_wait = 2.0
	elif fps > 52.0 and quality < 2:
		quality += 1
		_apply_quality()
		_adapt_wait = 2.0


# ------------------------------------------------------------------ material & mesh

func _mat(id: String, tile: float, tint := Color(1, 1, 1), rough_mul := 1.0, metal := 0.0) -> ShaderMaterial:
	var key := "%s|%s|%s|%s|%s" % [id, tile, tint, rough_mul, metal]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _surface_shader
	m.set_shader_parameter("tex_albedo", load(T + id + "/diff.jpg"))
	m.set_shader_parameter("tex_normal", load(T + id + "/nor.jpg"))
	m.set_shader_parameter("tex_rough", load(T + id + "/rough.jpg"))
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("rough", rough_mul)
	m.set_shader_parameter("spec_amt", 0.35 + metal)
	_mats[key] = m
	_all_mats.append(m)
	return m


func _flat(col: Color, rough := 0.6, metal := 0.0, emis := Color(0, 0, 0)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _surface_shader
	m.set_shader_parameter("use_normal", false)
	m.set_shader_parameter("use_rough_tex", false)
	m.set_shader_parameter("tint", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("spec_amt", 0.4 + metal)
	m.set_shader_parameter("emission", Vector3(emis.r, emis.g, emis.b))
	_all_mats.append(m)
	return m


## Daftarkan lampu (dihitung di shader, bukan OmniLight3D).
func _add_light(p: Vector3, col: Color, energy: float, rng_m: float, channel := -1) -> void:
	_lights.append([p, rng_m, Vector3(col.r, col.g, col.b) * energy, channel])


func _apply_lights() -> void:
	var lp := PackedVector4Array()
	var lc := PackedVector4Array()
	for L in _lights:
		var p: Vector3 = L[0]
		var c: Vector3 = L[2]
		lp.append(Vector4(p.x, p.y, p.z, L[1]))
		lc.append(Vector4(c.x, c.y, c.z, float(L[3])))
	while lp.size() < 10:
		lp.append(Vector4(0, -100, 0, 0.01))
		lc.append(Vector4(0, 0, 0, -1))
	for m in _all_mats:
		(m as ShaderMaterial).set_shader_parameter("light_count", mini(_lights.size(), 10))
		(m as ShaderMaterial).set_shader_parameter("lpos", lp)
		(m as ShaderMaterial).set_shader_parameter("lcol", lc)


## Kotak dengan UV dalam meter (supaya tekstur foto tidak melar di kotak berbagai ukuran).
func _box_mesh(size: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var faces := [
		[Vector3(-h.x, -h.y, h.z), Vector3(size.x, 0, 0), Vector3(0, size.y, 0), Vector3(0, 0, 1)],
		[Vector3(h.x, -h.y, -h.z), Vector3(-size.x, 0, 0), Vector3(0, size.y, 0), Vector3(0, 0, -1)],
		[Vector3(h.x, -h.y, h.z), Vector3(0, 0, -size.z), Vector3(0, size.y, 0), Vector3(1, 0, 0)],
		[Vector3(-h.x, -h.y, -h.z), Vector3(0, 0, size.z), Vector3(0, size.y, 0), Vector3(-1, 0, 0)],
		[Vector3(-h.x, h.y, h.z), Vector3(size.x, 0, 0), Vector3(0, 0, -size.z), Vector3(0, 1, 0)],
		[Vector3(-h.x, -h.y, -h.z), Vector3(size.x, 0, 0), Vector3(0, 0, size.z), Vector3(0, -1, 0)],
	]
	for f in faces:
		var o: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var n: Vector3 = f[3]
		var ul := u.length()
		var vl := v.length()
		var p := [o, o + u, o + u + v, o + v]
		var t := [Vector2(0, 0), Vector2(ul, 0), Vector2(ul, -vl), Vector2(0, -vl)]
		# urutan searah jarum jam dilihat dari depan (konvensi Godot)
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_uv(t[i])
			st.add_vertex(p[i])
	st.generate_tangents()
	return st.commit()


func _box(size: Vector3, center: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = mat
	mi.position = center
	mi.rotation = rot
	add_child(mi)
	return mi


## Gabungkan kotak statis bermaterial sama dalam satu mesh per blok 24 m
## (mengurangi draw call; blok tetap kecil supaya tiap mesh hanya kena sedikit lampu).
var _batches := {}
func _bbox(size: Vector3, center: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var chunk := int(floor(center.z / 24.0))
	var zone := 1 if center.x > 9.0 else 0
	var key := "%d|%d|%d" % [mat.get_instance_id(), chunk, zone]
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = [st, mat]
	var xf := Transform3D(Basis.from_euler(rot), center)
	(_batches[key][0] as SurfaceTool).append_from(_box_mesh(size), 0, xf)


func _flush_batches() -> void:
	for key in _batches:
		var st: SurfaceTool = _batches[key][0]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _batches[key][1]
		add_child(mi)
	_batches.clear()


func _cyl(r: float, h: float, center: Vector3, mat: Material, seg := 12) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	mi.position = center
	add_child(mi)
	return mi


func _facade(id: String, seed_v: float, height: float, tint := Color(1, 1, 1), lit := 0.3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _facade_shader
	m.set_shader_parameter("tex_albedo", load(T + id + "/diff.jpg"))
	m.set_shader_parameter("tex_normal", load(T + id + "/nor.jpg"))
	m.set_shader_parameter("tex_rough", load(T + id + "/rough.jpg"))
	m.set_shader_parameter("tile", 3.0)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("seed", seed_v)
	m.set_shader_parameter("top_h", height)
	m.set_shader_parameter("lit_ratio", lit)
	m.set_shader_parameter("win_w", rng.randf_range(2.4, 3.2))
	_all_mats.append(m)
	return m


# ------------------------------------------------------------------ lingkungan

func _setup_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.075, 0.07, 0.085)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.13, 0.15, 0.22)
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.11, 0.13)
	env.fog_density = 0.022
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)



# Jalan utama sepanjang -Z: aspal x[-5,5], trotoar x[-8,-5] dan [5,8].
func _build_street() -> void:
	var asphalt := _mat("asphalt_snow", 4.0, Color(0.85, 0.85, 0.9), 0.9)
	var walk := _mat("concrete_pavement", 2.5, Color(0.8, 0.8, 0.82))
	var curb := _mat("dirty_concrete", 1.5, Color(0.7, 0.7, 0.72))
	# dipotong per 12 m supaya tiap potong hanya kena 1-2 lampu (renderer Compatibility menggambar ulang per lampu)
	for i in 9:
		var z := 6.0 - 12.0 * i - 6.0
		_bbox(Vector3(10, 0.2, 12), Vector3(0, -0.1, z), asphalt)
		for sx in [-1.0, 1.0]:
			_bbox(Vector3(3, 0.35, 12), Vector3(sx * 6.5, -0.025, z), walk)
			_bbox(Vector3(0.25, 0.37, 12), Vector3(sx * 5.1, -0.02, z), curb)

	# gedung kiri dan kanan
	var bricks := ["dark_brick_wall", "red_brick_03", "dark_brick_wall", "dirty_concrete"]
	var tints := [Color(0.85, 0.85, 0.9), Color(0.8, 0.75, 0.72), Color(0.7, 0.72, 0.8), Color(0.75, 0.75, 0.78)]
	for side in [-1.0, 1.0]:
		var z := 6.0
		var idx := 0 if side < 0 else 1
		while z > -100.0:
			var w := rng.randf_range(12.0, 20.0)
			# celah gang di kanan, z -40 .. -47
			if side > 0 and z - w < -40.0 and z > -47.0:
				w = z + 40.0
				if w < 2.0:
					z = -47.0
					continue
			var hgt := rng.randf_range(11.0, 24.0)
			var b: int = (idx + rng.randi_range(0, 3)) % bricks.size()
			var m := _facade(bricks[b], rng.randf() * 100.0, hgt, tints[b], rng.randf_range(0.18, 0.4))
			var cz := z - w * 0.5
			_box(Vector3(12, hgt, w), Vector3(side * 14.0, hgt * 0.5, cz), m)
			_shopfront(side, cz, w)
			z -= w
			idx += 1


## Lantai dasar: rolling door berkarat, kanopi, papan nama kecil.
func _shopfront(side: float, cz: float, w: float) -> void:
	if w < 6.0:
		return
	var shutter := _mat("rusted_shutter", 2.0, Color(0.75, 0.75, 0.78), 1.0, 0.4)
	var sw := minf(w - 3.0, 6.0)
	_bbox(Vector3(0.15, 3.0, sw), Vector3(side * 7.98, 1.5, cz + rng.randf_range(-1.0, 1.0)), shutter)
	if rng.randf() < 0.6:
		if _canopy_mats.is_empty():
			_canopy_mats = [_flat(Color(0.12, 0.05, 0.05), 0.8), _flat(Color(0.05, 0.08, 0.06), 0.8)]
		var canopy: Material = _canopy_mats[rng.randi() % 2]
		_bbox(Vector3(1.4, 0.12, sw + 1.0), Vector3(side * 7.3, 3.35, cz), canopy, Vector3(0, 0, -side * 0.18))
		var snow := _mat("snow_floor", 2.0)
		_bbox(Vector3(1.3, 0.06, sw + 0.9), Vector3(side * 7.3, 3.44, cz), snow, Vector3(0, 0, -side * 0.18))


func _build_alley() -> void:
	# gang ke kanan antara z -40 .. -47
	var ground := _mat("dirty_concrete", 3.0, Color(0.6, 0.6, 0.63), 0.7)
	_box(Vector3(14, 0.2, 7), Vector3(15, -0.1, -43.5), ground)
	var fence := _mat("corrugated_iron", 2.0, Color(0.7, 0.72, 0.75), 1.0, 0.5)
	_box(Vector3(0.1, 4.0, 7), Vector3(21.5, 2.0, -43.5), fence)
	# tangga darurat besi di dinding gedung sisi utara gang
	_iron = _flat(Color(0.08, 0.08, 0.09), 0.45, 0.7)
	var iron := _iron
	var wall_z := -40.0 + 0.6
	for lvl in 4:
		var y := 4.6 + lvl * 3.3
		_bbox(Vector3(5.0, 0.08, 1.1), Vector3(14.5, y, wall_z - 0.55), iron)
		_bbox(Vector3(5.0, 0.05, 0.05), Vector3(14.5, y + 1.0, wall_z - 1.08), iron)
		for k in 6:
			_bbox(Vector3(0.04, 1.0, 0.04), Vector3(12.0 + k, y + 0.5, wall_z - 1.08), iron)
		if lvl < 3:
			_bbox(Vector3(3.9, 0.06, 0.7), Vector3(14.4, y + 1.65, wall_z - 0.5), iron,
				Vector3(0, 0, atan2(3.3, 3.0) * (1.0 if lvl % 2 == 0 else -1.0)))
	# lampu dinding di atas pintu belakang
	var bulb := _flat(Color(0.3, 0.3, 0.3), 0.4, 0.0, Color(1.0, 0.75, 0.45) * 1.5)
	_box(Vector3(0.35, 0.25, 0.25), Vector3(18.5, 3.3, -46.6), bulb)
	_box(Vector3(1.2, 2.4, 0.08), Vector3(18.5, 1.2, -46.95), _mat("rusty_metal_02", 1.5, Color(0.35, 0.4, 0.45), 1.0, 0.6))
	_add_light(Vector3(18.5, 3.0, -46.0), Color(1.0, 0.7, 0.42), 1.6, 9.0)


func _build_end() -> void:
	# gedung melintang di ujung jalan, dengan papan neon
	var m := _facade("red_brick_03", 42.0, 26.0, Color(0.75, 0.7, 0.68), 0.35)
	_box(Vector3(40, 26, 12), Vector3(0, 13, -108), m)
	var m2 := _facade("dark_brick_wall", 11.0, 18.0, Color(0.75, 0.75, 0.82), 0.25)
	_box(Vector3(24, 18, 12), Vector3(0, 9, 14), m2)
	_box(Vector3(10, 0.2, 14), Vector3(0, -0.1, -96), _mat("asphalt_snow", 4.0, Color(0.85, 0.85, 0.9), 0.9))
	_neon("HOTEL", Vector3(-7.85, 9.0, -60.0), PI * 0.5, Color(1.0, 0.18, 0.28), true, 1.4)
	_neon("BAR", Vector3(7.85, 4.6, -27.0), -PI * 0.5, Color(0.25, 0.55, 1.0), false, 1.0)
	_neon("BUKA", Vector3(-7.85, 4.2, -80.0), PI * 0.5, Color(0.3, 1.0, 0.45), false, 0.7)


func _neon(text: String, p: Vector3, yaw_v: float, col: Color, vertical: bool, size: float) -> void:
	var l := Label3D.new()
	l.text = "\n".join(text.split("")) if vertical else text
	l.font_size = 96
	l.pixel_size = 0.012 * size
	l.modulate = col.lightened(0.35)
	l.outline_modulate = Color(col.r, col.g, col.b, 0.55)
	l.outline_size = 22
	l.shaded = false
	l.double_sided = false
	l.line_spacing = -18.0
	l.position = p
	l.rotation.y = yaw_v
	add_child(l)
	var backing := _flat(Color(0.03, 0.03, 0.03), 0.4, 0.5)
	var dims := Vector3(0.12, 7.5, 1.8) if vertical else Vector3(0.12, 1.4, 1.2 * text.length() * size + 0.6)
	var bp := p + Vector3(-signf(sin(yaw_v)) * 0.08, 0, 0)
	_box(dims, bp, backing)
	var ch := _neons.size()
	_add_light(p + Vector3(sin(yaw_v) * 1.5, 0, cos(yaw_v) * 1.5), col, 1.3, 9.0, ch)
	_neons.append([l, ch, rng.randf() * 10.0])


func _build_lamps() -> void:
	var pole := _flat(Color(0.06, 0.06, 0.07), 0.5, 0.6)
	var head := _flat(Color(0.2, 0.2, 0.2), 0.4, 0.5, Color(1.0, 0.7, 0.38) * 1.4)
	var zs := [-2.0, -22.0, -44.0, -66.0, -88.0]
	for i in zs.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * 6.6
		var z: float = zs[i]
		_cyl(0.09, 6.4, Vector3(x, 3.2, z), pole, 8)
		_bbox(Vector3(1.6, 0.08, 0.08), Vector3(x - side * 0.8, 6.35, z), pole)
		_box(Vector3(0.7, 0.18, 0.35), Vector3(x - side * 1.5, 6.25, z), head)
		_add_light(Vector3(x - side * 1.5, 5.9, z), Color(1.0, 0.62, 0.3), 3.0, 17.0)
		var pool := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(11, 11)
		q.orientation = PlaneMesh.FACE_Y
		pool.mesh = q
		var pm := ShaderMaterial.new()
		pm.shader = _glow_shader
		pool.material_override = pm
		pool.position = Vector3(x - side * 1.5, 0.03, z)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pool)


func _build_props() -> void:
	var rusty := _mat("rusty_metal_02", 1.5, Color(0.45, 0.55, 0.5), 1.0, 0.6)
	var snow := _mat("snow_floor", 2.0)
	var bag := _flat(Color(0.02, 0.02, 0.025), 0.22, 0.0)
	var plate := _mat("metal_plate", 1.0, Color(0.5, 0.5, 0.52), 0.8, 0.8)
	# tong sampah dan kantong sampah di gang
	for d in [[14.0, -46.0], [17.5, -46.2], [7.2, -15.0]]:
		var x: float = d[0]
		var z: float = d[1]
		_bbox(Vector3(1.9, 1.25, 1.1), Vector3(x, 0.625, z), rusty)
		_bbox(Vector3(1.95, 0.08, 1.15), Vector3(x, 1.3, z), rusty)
		_bbox(Vector3(1.85, 0.08, 1.05), Vector3(x, 1.38, z), snow)
		for k in 3:
			var s := SphereMesh.new()
			s.radius = 0.4
			s.height = 0.6
			s.radial_segments = 10
			s.rings = 5
			var mi := MeshInstance3D.new()
			mi.mesh = s
			mi.material_override = bag
			mi.position = Vector3(x + rng.randf_range(-1.2, 1.2), 0.28, z + rng.randf_range(0.7, 1.2) * (1.0 if z > -45.0 else 1.0))
			mi.scale = Vector3(rng.randf_range(0.8, 1.2), rng.randf_range(0.7, 1.0), rng.randf_range(0.8, 1.2))
			add_child(mi)
	# tutup saluran + uap
	_cyl(0.45, 0.03, Vector3(1.5, 0.01, -33.0), plate, 16)
	_steam(Vector3(1.5, 0.05, -33.0))
	_steam(Vector3(16.0, 0.05, -43.0))
	# hidran
	var red := _flat(Color(0.35, 0.03, 0.03), 0.5, 0.2)
	_cyl(0.16, 0.75, Vector3(-5.6, 0.53, -36.0), red, 10)
	_cyl(0.2, 0.1, Vector3(-5.6, 0.95, -36.0), red, 10)
	# kabel listrik melintang
	var wire := _flat(Color(0.02, 0.02, 0.02), 0.6)
	for z in [-12.0, -51.0, -78.0]:
		_bbox(Vector3(16, 0.04, 0.04), Vector3(0, 9.2, z), wire, Vector3(0, 0, rng.randf_range(-0.03, 0.03)))


func _steam(p: Vector3) -> void:
	var g := GPUParticles3D.new()
	g.amount = 24
	g.lifetime = 4.0
	g.position = p
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0.25, 0.15, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	var sc := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 2.4))
	sc.curve = c
	pm.scale_curve = sc
	var ramp := GradientTexture1D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.0))
	gr.add_point(0.15, Color(1, 1, 1, 0.22))
	gr.set_color(1, Color(1, 1, 1, 0.0))
	ramp.gradient = gr
	pm.color_ramp = ramp
	g.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.75, 0.75, 0.8)
	m.albedo_texture = _soft_dot()
	# memudar saat kamera menembus uap, supaya layar tidak memutih
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.6
	m.distance_fade_max_distance = 3.5
	q.material = m
	g.draw_pass_1 = q
	g.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 8, 6))
	add_child(g)


var _dot_tex: GradientTexture2D
func _soft_dot() -> GradientTexture2D:
	if _dot_tex:
		return _dot_tex
	_dot_tex = GradientTexture2D.new()
	_dot_tex.fill = GradientTexture2D.FILL_RADIAL
	_dot_tex.fill_from = Vector2(0.5, 0.5)
	_dot_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_dot_tex.gradient = g
	_dot_tex.width = 32
	_dot_tex.height = 32
	return _dot_tex


func _build_snow() -> void:
	_snow = GPUParticles3D.new()
	_snow.amount = 700
	_snow.lifetime = 9.0
	_snow.preprocess = 9.0
	_snow.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 0.5, 18)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.35, -0.55, 0.1)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	_snow.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.85, 0.86, 0.92, 0.85)
	m.albedo_texture = _soft_dot()
	q.material = m
	_snow.draw_pass_1 = q
	_snow.visibility_aabb = AABB(Vector3(-20, -15, -22), Vector3(40, 30, 44))
	add_child(_snow)


# ------------------------------------------------------------------ kamera & HUD

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.1
	cam.far = 120.0
	add_child(cam)
	_update_camera(0.0)


func _setup_hud() -> void:
	var post_layer := CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = preload("res://shaders/post.gdshader")
	rect.material = post_mat
	post_layer.add_child(rect)
	rect.visible = not _nopost

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	hud_hint = Label.new()
	hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_hint.add_theme_color_override("font_color", Color(0.92, 0.9, 0.85))
	hud_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hud_hint.add_theme_constant_override("outline_size", 5)
	hud_hint.text = "Atas/Bawah: jalan    Kiri/Kanan: menoleh    OK: gerak lambat    Menu: grafis\nDiam 10 detik: mode hantu"
	layer.add_child(hud_hint)
	hud_fps = Label.new()
	hud_fps.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.7))
	layer.add_child(hud_fps)


func _hint(t: String, secs: float) -> void:
	hud_hint.text = t
	_hint_t = secs


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	# pemain bergerak dengan waktu normal; dunia ikut Engine.time_scale (gerak lambat)
	var real := minf(delta / maxf(Engine.time_scale, 0.01), 0.1)
	slowmo = move_toward(slowmo, 1.0 if slowmo_on else 0.0, real * 2.5)
	Engine.time_scale = lerpf(1.0, 0.25, slowmo)
	post_mat.set_shader_parameter("slowmo", slowmo)
	post_mat.set_shader_parameter("time_s", Time.get_ticks_msec() / 1000.0)

	var walk := Input.get_action_strength("maju") - Input.get_action_strength("mundur")
	var turn := Input.get_action_strength("kiri") - Input.get_action_strength("kanan")
	if absf(walk) > 0.01 or absf(turn) > 0.01:
		_idle_t = 0.0
	else:
		_idle_t += real
	if not ghost_on and _idle_t > IDLE_TO_GHOST:
		_start_ghost()
	ghost = move_toward(ghost, 1.0 if ghost_on else 0.0, real * 0.5)
	if ghost_on:
		_ghost_step(real)
	else:
		yaw += turn * TURN * real
		var f := Vector3(-sin(yaw), 0, -cos(yaw))
		pos += f * walk * WALK * real
		_bob += absf(walk) * real * 7.5
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	_clamp_pos()
	post_mat.set_shader_parameter("ghost", ghost)
	music.set("slowmo", slowmo)
	_update_camera(real)
	_snow.global_position = Vector3(pos.x, 12.0, pos.z) + fwd * 6.0

	var t := Time.get_ticks_msec() / 1000.0 * lerpf(1.0, 0.25, slowmo)
	for n in _neons:
		var ph: float = n[2]
		var flick := 1.0
		var s := sin(t * 23.0 + ph) * sin(t * 3.1 + ph * 2.0)
		if s > 0.93:
			flick = 0.25
		(n[0] as Label3D).modulate.a = flick
		RenderingServer.global_shader_parameter_set("neon%d" % int(n[1]), flick)

	_adapt(real)
	if _hint_t > 0.0:
		_hint_t -= real
		hud_hint.modulate.a = clampf(_hint_t, 0.0, 1.0)
	hud_fps.text = "%d FPS  %s%s" % [Engine.get_frames_per_second(), QUALITY[quality][2], " oto" if auto_quality else ""]
	_test_hook()


func _start_ghost() -> void:
	ghost_on = true
	# mulai dari titik jalur terdekat yang ada di depan
	var best := 0
	var bd := INF
	for i in GHOST_PATH.size():
		var w: Vector2 = GHOST_PATH[i]
		var d := Vector2(pos.x, pos.z).distance_to(w)
		if d < bd and d > 3.0:
			bd = d
			best = i
	_ghost_i = best
	_hint("Mode hantu. Tekan tombol apa saja untuk kembali.", 4.0)


func _ghost_step(dt: float) -> void:
	_ghost_time += dt
	var target: Vector2 = GHOST_PATH[_ghost_i]
	var to := target - Vector2(pos.x, pos.z)
	if to.length() < 2.5:
		_ghost_i = (_ghost_i + 1) % GHOST_PATH.size()
		return
	var want := atan2(-to.x, -to.y)
	yaw = lerp_angle(yaw, want, 1.0 - exp(-0.7 * dt))
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	pos += f * 1.1 * dt * ghost


func _clamp_pos() -> void:
	var in_alley := pos.z < -40.6 and pos.z > -46.4
	pos.x = clampf(pos.x, -7.6, 20.8 if in_alley else 7.6)
	if pos.x > 7.6:
		pos.z = clampf(pos.z, -46.4, -40.6)
	pos.z = clampf(pos.z, -101.0, 7.0)


func _update_camera(delta: float) -> void:
	var ground := 0.15 if absf(pos.x) > 5.0 and pos.x < 8.0 else 0.0
	var gt := _ghost_time
	var float_h := ghost * (0.45 + 0.3 * sin(gt * 0.5))
	var glance := ghost * sin(gt * 0.13) * 0.45
	var look_up := ghost * 0.09 * sin(gt * 0.21)
	cam.position = Vector3(pos.x, ground + EYE + float_h + sin(_bob) * 0.035, pos.z)
	cam.rotation = Vector3(-0.04 + look_up + sin(_bob * 0.5) * 0.004, yaw + glance,
		sin(_bob * 0.5) * 0.006 + ghost * 0.035 * sin(gt * 0.3))


# ------------------------------------------------------------------ uji otomatis
# -- shot=/tmp/a.png frames=60 pos=x,z yaw=deg slow=1 q=1

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"shot": _shot = kv[1]
			"frames": _shot_frames = int(kv[1])
			"pos":
				var p := kv[1].split(",")
				pos = Vector3(float(p[0]), 0, float(p[1]))
			"yaw": yaw = deg_to_rad(float(kv[1]))
			"slow":
				slowmo_on = kv[1] == "1"
				slowmo = 1.0 if slowmo_on else 0.0
			"nopost": _nopost = kv[1] == "1"
			"ghost":
				if kv[1] == "1":
					_idle_t = 999.0
			"q":
				quality = int(kv[1])
				auto_quality = false


func _test_hook() -> void:
	_frame += 1
	if _shot != "" and _frame == max(_shot_frames, 5):
		get_viewport().get_texture().get_image().save_png(_shot)
		print("SHOT ", _shot, " fps=", Engine.get_frames_per_second(),
			" draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			" objs=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			" prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		get_tree().quit()
