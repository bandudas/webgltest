extends SceneTree
func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is MeshInstance3D and n.mesh:
		var a: AABB = (xf * n.transform) * n.mesh.get_aabb()
		out = a; first = false
	for c in n.get_children():
		if c is Node3D:
			var b := _aabb(c, xf * (n.transform if n is Node3D else Transform3D()))
			if b.size != Vector3.ZERO:
				out = b if first else out.merge(b); first = false
	return out
func _init():
	for kit in ["pirate", "water"]:
		var d := DirAccess.open("res://assets/%s" % kit)
		for f in d.get_files():
			if f.ends_with(".glb"):
				var s: Node = load("res://assets/%s/%s" % [kit, f]).instantiate()
				var a := _aabb(s, Transform3D())
				print("%s/%s pos=%s size=%s" % [kit, f, a.position.snapped(Vector3.ONE*0.01), a.size.snapped(Vector3.ONE*0.01)])
				s.free()
	quit()
