extends RefCounted

## Compatibility geometry for scenes produced before the unified compiler.
static func align(inst: Node3D, missile_root: Node3D) -> void:
	if missile_root == null or inst == null:
		return
	var aabb: AABB = _missile_local_aabb(inst)
	if aabb.size.length_squared() < 1e-8:
		missile_root.rotation.x = -PI * 0.5
		return
	var sx: float = aabb.size.x
	var sy: float = aabb.size.y
	var sz: float = aabb.size.z
	var model_fwd: Vector3 = Vector3.UP
	if sx >= sy and sx >= sz:
		model_fwd = Vector3.RIGHT
	elif sz >= sx and sz >= sy:
		model_fwd = Vector3.BACK # +Z
	else:
		model_fwd = Vector3.UP
	var want: Vector3 = Vector3(0.0, 0.0, -1.0) # look_at 前向
	missile_root.basis = _basis_aligning(model_fwd, want)


static func _missile_local_aabb(inst: Node3D) -> AABB:
	var aabb: AABB = AABB()
	var first: bool = true
	for c: Node in inst.find_children("*", "VisualInstance3D", true, false):
		var vi: VisualInstance3D = c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		if str(vi.name) == "FxBillboard":
			continue
		var la: AABB = vi.get_aabb()
		var xf: Transform3D = inst.global_transform.affine_inverse() * vi.global_transform
		var world_box: AABB = xf * la
		if first:
			aabb = world_box
			first = false
		else:
			aabb = aabb.merge(world_box)
	return aabb if not first else AABB()


static func _basis_aligning(from_dir: Vector3, to_dir: Vector3) -> Basis:
	var f: Vector3 = from_dir.normalized()
	var t: Vector3 = to_dir.normalized()
	if f.length_squared() < 1e-8 or t.length_squared() < 1e-8:
		return Basis.IDENTITY
	var d: float = f.dot(t)
	if d > 0.9999:
		return Basis.IDENTITY
	if d < -0.9999:
		var axis: Vector3 = f.cross(Vector3.UP)
		if axis.length_squared() < 1e-6:
			axis = f.cross(Vector3.RIGHT)
		return Basis(axis.normalized(), PI)
	return Basis(f.cross(t).normalized(), f.angle_to(t))


static func fit_scale(inst: Node3D) -> void:
	if inst == null:
		return
	var aabb: AABB = AABB()
	var first: bool = true
	for c: Node in inst.find_children("*", "VisualInstance3D", true, false):
		var vi: VisualInstance3D = c as VisualInstance3D
		if vi == null:
			continue
		var la: AABB = vi.get_aabb()
		var xf: Transform3D = vi.global_transform
		for i: int in range(8):
			var local: Vector3 = la.position + la.size * Vector3(
				float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1)
			)
			var p: Vector3 = inst.to_local(xf * local)
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	if aabb.size.length() > 2.0:
		inst.scale = Vector3.ONE * Wc3Coords.WORLD_SCALE


