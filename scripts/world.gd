class_name World
extends Node3D

## Membangun kepulauan secara prosedural dari seed, lalu menghiasnya dengan aset Kenney (CC0).

const P := "res://assets/pirate/"
const W := "res://assets/water/"
const COAST_SAMPLES := 64
const WORLD_RADIUS := 330.0
const DECOR_RANGE := 170.0
const SMALL_RANGE := 90.0

var rng := RandomNumberGenerator.new()
var islands: Array = []      # Dictionary per pulau
var npcs: Array = []         # kapal lain
var ghost: Node3D
var _mesh_cache := {}
var _terrain_mat: StandardMaterial3D
var _beacon_shader: Shader = preload("res://shaders/beacon.gdshader")


func generate(seed_value: int) -> void:
	rng.seed = seed_value
	_terrain_mat = StandardMaterial3D.new()
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.roughness = 1.0
	_terrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_place_islands()
	for i in islands.size():
		_build_island(islands[i], i)
	_spawn_npcs()


# ------------------------------------------------------------------ penempatan pulau

func _place_islands() -> void:
	# Pulau pertama selalu di depan titik awal pemain.
	islands.append(_new_island(Vector3(0, 0, -75), 24.0, "desa"))
	var types := ["liar", "liar", "menara", "desa", "kecil", "karam", "liar", "kecil"]
	var tries := 0
	while islands.size() < 14 and tries < 4000:
		tries += 1
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * WORLD_RADIUS
		var c := Vector3(cos(a) * d, 0, sin(a) * d)
		var t: String = types[rng.randi() % types.size()]
		var r := rng.randf_range(9.0, 14.0) if t == "kecil" else rng.randf_range(18.0, 38.0)
		if c.length() < r + 35.0:
			continue # jangan menutupi titik awal
		var ok := true
		for other in islands:
			if c.distance_to(other.center) < r * 1.5 + other.R * 1.5 + 30.0:
				ok = false
				break
		if ok:
			islands.append(_new_island(c, r, t))


func _new_island(c: Vector3, r: float, t: String) -> Dictionary:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.035
	var h := rng.randf_range(2.0, 4.0) if t == "kecil" else rng.randf_range(r * 0.18, r * 0.42)
	return {
		"center": c, "R": r, "H": h, "type": t, "noise": n,
		"coast": PackedFloat32Array(), "coast_avg": r,
		"chest": null, "beacon": null, "opened": false,
	}


## Tinggi daratan pada koordinat lokal pulau (meter, air = 0).
func land_h(isl: Dictionary, lx: float, lz: float) -> float:
	var n: FastNoiseLite = isl.noise
	var R: float = isl.R
	var r2 := sqrt(lx * lx + lz * lz) / R * (1.0 + 0.22 * n.get_noise_2d(lx, lz))
	if r2 < 1.0:
		var h: float = isl.H * pow(1.0 - r2 * r2, 1.5) + 1.0 * (1.0 - r2)
		h += n.get_noise_2d(lx * 3.0 + 100.0, lz * 3.0) * 0.15 * isl.H * (1.0 - r2)
		return h
	return -5.0 * (r2 - 1.0)


func _compute_coast(isl: Dictionary) -> void:
	var arr := PackedFloat32Array()
	arr.resize(COAST_SAMPLES)
	var sum := 0.0
	for k in COAST_SAMPLES:
		var a := TAU * k / COAST_SAMPLES
		var dir := Vector2(cos(a), sin(a))
		var lo := 0.0
		var hi: float = isl.R * 1.6
		# cari titik terjauh yang masih daratan
		var r := hi
		while r > 0.0 and land_h(isl, dir.x * r, dir.y * r) <= 0.0:
			r -= 0.5
		lo = r
		hi = r + 0.5
		for _i in 6:
			var m := (lo + hi) * 0.5
			if land_h(isl, dir.x * m, dir.y * m) > 0.0:
				lo = m
			else:
				hi = m
		arr[k] = lo
		sum += lo
	isl.coast = arr
	isl.coast_avg = sum / COAST_SAMPLES


func coast_radius(isl: Dictionary, angle: float) -> float:
	var f := fposmod(angle, TAU) / TAU * COAST_SAMPLES
	var i := int(f) % COAST_SAMPLES
	var j := (i + 1) % COAST_SAMPLES
	return lerpf(isl.coast[i], isl.coast[j], f - floor(f))


# ------------------------------------------------------------------ mesh pulau

func _terrain_color(h: float, ny: float, jitter: float) -> Color:
	if h < -0.25:
		return Color(0.78, 0.70, 0.52)
	if h < 0.9 + jitter * 0.6:
		return Color(0.91, 0.79, 0.56).darkened(0.03 + jitter * 0.04)
	if ny < 0.72:
		return Color(0.62, 0.57, 0.52).lightened(jitter * 0.08)
	return Color(0.44, 0.72, 0.33).lightened(jitter * 0.07)


func _build_terrain(isl: Dictionary) -> MeshInstance3D:
	var rings := 14
	var segs := 34
	var outer: float = isl.R * 1.5
	var pts := []
	for i in rings + 1:
		var row := []
		for j in segs:
			if i == 0:
				row.append(Vector3(0, land_h(isl, 0, 0), 0))
				continue
			var a := TAU * (j + (0.5 if i % 2 == 1 else 0.0)) / segs
			a += rng.randf_range(-0.04, 0.04)
			var r := outer * float(i) / rings * rng.randf_range(0.96, 1.04)
			var x := cos(a) * r
			var z := sin(a) * r
			row.append(Vector3(x, land_h(isl, x, z), z))
		pts.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		for j in segs:
			var j2 := (j + 1) % segs
			if i == 0:
				_tri(st, pts[0][0], pts[1][j], pts[1][j2])
			else:
				var a: Vector3 = pts[i][j]
				var b: Vector3 = pts[i][j2]
				var c: Vector3 = pts[i + 1][j]
				var d: Vector3 = pts[i + 1][j2]
				if i % 2 == 1:
					_tri(st, a, c, d)
					_tri(st, a, d, b)
				else:
					_tri(st, a, c, b)
					_tri(st, b, c, d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _terrain_mat
	return mi


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var h := (a.y + b.y + c.y) / 3.0
	var col := _terrain_color(h, n.y, rng.randf_range(-1.0, 1.0))
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


# ------------------------------------------------------------------ dekorasi

## Ambil satu-satunya mesh dari sebuah .glb (untuk MultiMesh). Kosong jika glb berisi >1 mesh.
func _single_mesh(path: String) -> Array:
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var root: Node = load(path).instantiate()
	var found: Array = []
	_collect_meshes(root, Transform3D(), found)
	root.free()
	var res: Array = found[0] if found.size() == 1 else []
	_mesh_cache[path] = res
	return res


func _collect_meshes(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append([(n as MeshInstance3D).mesh, here])
	for c in n.get_children():
		_collect_meshes(c, here, out)


func _rand_land(isl: Dictionary, rmin: float, rmax: float, hmin: float, hmax: float) -> Variant:
	for _t in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(rmin, rmax) * float(isl.R)
		var x := cos(a) * r
		var z := sin(a) * r
		var h := land_h(isl, x, z)
		if h >= hmin and h <= hmax:
			return Vector3(x, h, z)
	return null


## Sebar banyak salinan model dalam satu MultiMesh (1 draw call per jenis per pulau).
func _scatter(parent: Node3D, isl: Dictionary, paths: Array, count: int,
		rmin: float, rmax: float, hmin: float, hmax: float,
		smin: float, smax: float, vis: float) -> void:
	var groups := {}
	for _k in count:
		var p = _rand_land(isl, rmin, rmax, hmin, hmax)
		if p == null:
			continue
		var path: String = paths[rng.randi() % paths.size()]
		var s := rng.randf_range(smin, smax)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p - Vector3(0, 0.08, 0))
		if not groups.has(path):
			groups[path] = []
		groups[path].append(xf)
	for path in groups:
		var m := _single_mesh(path)
		var xfs: Array = groups[path]
		if m.is_empty():
			for xf in xfs:
				var inst: Node3D = load(path).instantiate()
				inst.transform = xf
				parent.add_child(inst)
				_set_range(inst, vis)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m[0]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i] * m[1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = vis
		mmi.visibility_range_end_margin = 10.0
		parent.add_child(mmi)


func _set_range(n: Node, vis: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = vis
		(n as GeometryInstance3D).visibility_range_end_margin = 10.0
	for c in n.get_children():
		_set_range(c, vis)


func _put(parent: Node3D, path: String, pos: Vector3, yaw: float, s: float = 1.0, vis: float = DECOR_RANGE) -> Node3D:
	var inst: Node3D = load(path).instantiate()
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * s
	parent.add_child(inst)
	_set_range(inst, vis)
	return inst


func _shore_point(isl: Dictionary, angle: float, offset: float) -> Vector3:
	var r := coast_radius(isl, angle) + offset
	return Vector3(cos(angle) * r, 0.0, sin(angle) * r)


func _build_island(isl: Dictionary, index: int) -> void:
	_compute_coast(isl)
	var node := Node3D.new()
	node.name = "Pulau%d" % index
	node.position = isl.center
	add_child(node)
	node.add_child(_build_terrain(isl))
	isl.node = node

	var R: float = isl.R
	var t: String = isl.type
	var palms := [P + "palm-straight.glb", P + "palm-bend.glb", P + "palm-detailed-straight.glb", P + "palm-detailed-bend.glb"]
	var grass := [P + "grass-plant.glb", P + "grass-patch.glb", P + "grass.glb"]
	var shore_rocks := [P + "rocks-sand-a.glb", P + "rocks-sand-b.glb", P + "rocks-sand-c.glb"]
	var hill_rocks := [P + "rocks-a.glb", P + "rocks-b.glb", P + "rocks-c.glb"]

	var palm_n := int(R / 3.5) + rng.randi_range(1, 4)
	if t == "kecil":
		palm_n = rng.randi_range(1, 3)
	_scatter(node, isl, palms, palm_n, 0.1, 0.8, 0.4, 99.0, 1.5, 2.4, DECOR_RANGE)
	_scatter(node, isl, grass, int(R * 0.6), 0.1, 0.85, 0.7, 99.0, 1.2, 2.2, SMALL_RANGE)
	_scatter(node, isl, shore_rocks, rng.randi_range(1, 4), 0.85, 1.05, -0.6, 0.7, 0.8, 1.6, DECOR_RANGE)
	if t != "kecil":
		_scatter(node, isl, hill_rocks, rng.randi_range(1, 3), 0.0, 0.6, isl.H * 0.45, 99.0, 0.9, 1.7, DECOR_RANGE)

	match t:
		"menara":
			var top := Vector3(0, land_h(isl, 0, 0) - 0.2, 0)
			_put(node, P + "tower-complete-large.glb", top, rng.randf() * TAU, 1.2)
			_put(node, P + "flag-high.glb", top + Vector3(4.5, -0.5, 0), 0.0, 1.2)
		"desa":
			_build_village(node, isl)
		"karam":
			var a := rng.randf() * TAU
			var wp := _shore_point(isl, a, 3.0)
			var wreck := _put(node, P + "ship-wreck.glb", wp + Vector3(0, -1.4, 0), a + PI * 0.5 + rng.randf_range(-0.4, 0.4), 1.0, 220.0)
			wreck.rotation.z = deg_to_rad(14)
			var bp = _rand_land(isl, 0.3, 0.75, 0.6, 99.0)
			if bp != null:
				_put(node, P + "flag-pirate.glb", bp, rng.randf() * TAU, 1.3)

	if t == "liar" and rng.randf() < 0.5:
		var cp = _rand_land(isl, 0.4, 0.8, 0.5, 99.0)
		if cp != null:
			_put(node, P + "barrel.glb", cp, rng.randf() * TAU, 1.0, SMALL_RANGE)

	_place_chest(node, isl)


func _build_village(node: Node3D, isl: Dictionary) -> void:
	var a := rng.randf() * TAU
	# dermaga: dua potong platform dari pantai ke laut
	for k in 3:
		var p := _shore_point(isl, a, -1.0 + k * 2.4)
		_put(node, P + "structure-platform-dock.glb" if k < 2 else P + "structure-platform-dock-small.glb",
			p + Vector3(0, -0.35, 0), -a + PI * 0.5, 1.0)
	_put(node, P + "boat-row-small.glb", _shore_point(isl, a + 0.12, 4.0) + Vector3(0, -0.25, 0), -a, 1.0, SMALL_RANGE)
	# menara kecil dan barang-barang di dekat dermaga
	var inland: float = coast_radius(isl, a) * 0.55
	var hp := Vector3(cos(a) * inland, 0, sin(a) * inland)
	hp.y = land_h(isl, hp.x, hp.z) - 0.2
	_put(node, P + "tower-complete-small.glb", hp, -a + PI * 0.5, 1.0)
	for item in [P + "barrel.glb", P + "crate.glb", P + "crate-bottles.glb"]:
		var off := Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		var ip := hp + Vector3(cos(a) * 4.5, 0, sin(a) * 4.5) + off
		ip.y = land_h(isl, ip.x, ip.z) - 0.05
		if ip.y > 0.1:
			_put(node, item, ip, rng.randf() * TAU, 1.0, SMALL_RANGE)
	var fp := hp + Vector3(cos(a + 1.2) * 4.0, 0, sin(a + 1.2) * 4.0)
	fp.y = land_h(isl, fp.x, fp.z) - 0.1
	_put(node, P + "flag-high-pennant.glb", fp, rng.randf() * TAU, 1.2)


func _place_chest(node: Node3D, isl: Dictionary) -> void:
	# di pasir dekat pantai, supaya bisa dicapai dari perahu
	var pos: Vector3
	var found := false
	for _t in 60:
		var a := rng.randf() * TAU
		var r := coast_radius(isl, a) - rng.randf_range(2.0, 4.0)
		if r < 2.0:
			continue
		var x := cos(a) * r
		var z := sin(a) * r
		var h := land_h(isl, x, z)
		if h > 0.15 and h < 1.6:
			pos = Vector3(x, h - 0.05, z)
			found = true
			break
	if not found:
		pos = Vector3(0, land_h(isl, 0, 0), 0)
	var chest := _put(node, P + "chest.glb", pos, -atan2(pos.z, pos.x) - PI * 0.5, 1.4, 220.0)
	isl.chest = chest

	var beacon := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 1.0
	cyl.height = 40.0
	cyl.radial_segments = 10
	cyl.cap_top = false
	cyl.cap_bottom = false
	beacon.mesh = cyl
	var mat := ShaderMaterial.new()
	mat.shader = _beacon_shader
	mat.set_shader_parameter("height", 40.0)
	beacon.material_override = mat
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.position = pos + Vector3(0, 20.5, 0)
	node.add_child(beacon)
	isl.beacon = beacon


# ------------------------------------------------------------------ kapal lain

func _spawn_npcs() -> void:
	var defs := [
		[W + "ship-cargo-a.glb", 365.0, 4.5, -0.7],
		[P + "ship-pirate-medium.glb", 390.0, -5.5, -0.9],
		[W + "ship-ocean-liner-small.glb", 410.0, 3.5, -0.8],
		[W + "boat-sail-b.glb", 350.0, -4.0, -0.35],
	]
	for d in defs:
		_add_npc(d[0], Vector3.ZERO, d[1], d[2], d[3], rng.randf() * TAU)
	# perahu nelayan berputar di sekitar pulau pertama
	var first: Dictionary = islands[0]
	_add_npc(W + "boat-fishing-small.glb", first.center, first.coast_avg + 22.0, 2.5, -0.35, 1.0)
	# kapal hantu: hanya muncul malam hari
	var g := _add_npc(P + "ship-ghost.glb", Vector3.ZERO, 170.0, 3.0, -0.9, PI)
	ghost = g.node


func _add_npc(path: String, center: Vector3, radius: float, speed: float, sink: float, phase: float) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var model: Node3D = load(path).instantiate()
	model.position.y = sink
	root.add_child(model)
	_set_range(model, 300.0)
	var d := {"node": root, "center": center, "radius": radius, "speed": speed, "angle": phase}
	npcs.append(d)
	return d


func update(delta: float, wave_t: float, night: float) -> void:
	for d in npcs:
		d.angle += d.speed / d.radius * delta
		var a: float = d.angle
		var c: Vector3 = d.center
		var p := c + Vector3(cos(a) * d.radius, 0, sin(a) * d.radius)
		var n: Node3D = d.node
		p.y = Waves.height(p.x, p.z, wave_t)
		n.position = p
		# model Kenney menghadap +Z; arah gerak = turunan posisi melingkar
		var dir: Vector3 = Vector3(-sin(a), 0, cos(a)) * signf(float(d.speed))
		n.rotation.y = atan2(dir.x, dir.z)
		n.rotation.z = sin(wave_t * 0.9 + a * 7.0) * 0.04
	if ghost:
		ghost.visible = night > 0.55
	for isl in islands:
		if isl.beacon and not isl.opened:
			var m: ShaderMaterial = isl.beacon.material_override
			m.set_shader_parameter("strength", 0.45 + night * 1.4)


# ------------------------------------------------------------------ fisika sederhana

## Dorong posisi keluar dari daratan. Mengembalikan [posisi_baru, menabrak?].
func push_out(pos: Vector3, radius: float) -> Array:
	var hit := false
	for isl in islands:
		var c: Vector3 = isl.center
		var d := Vector2(pos.x - c.x, pos.z - c.z)
		var dist := d.length()
		if dist > float(isl.R) * 1.7 + radius:
			continue
		var a := atan2(d.y, d.x)
		var limit := coast_radius(isl, a) + radius
		if dist < limit:
			var dir: Vector2 = d / maxf(dist, 0.001)
			pos.x = c.x + dir.x * limit
			pos.z = c.z + dir.y * limit
			hit = true
	return [pos, hit]


func nearest_chest(pos: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for isl in islands:
		if isl.opened:
			continue
		var cp: Vector3 = isl.chest.global_position
		var d := Vector2(cp.x - pos.x, cp.z - pos.z).length()
		if d < bd:
			bd = d
			best = isl
	return best


func remaining() -> int:
	var n := 0
	for isl in islands:
		if not isl.opened:
			n += 1
	return n


func island_uniforms() -> PackedVector4Array:
	var arr := PackedVector4Array()
	for isl in islands:
		var c: Vector3 = isl.center
		arr.append(Vector4(c.x, c.z, isl.coast_avg, 0.0))
	while arr.size() < 16:
		arr.append(Vector4(0, 0, -1000.0, 0))
	return arr
