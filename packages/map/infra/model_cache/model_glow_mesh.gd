extends RefCounted
## 按三角法线划分队伍光晕网格，不保存实例状态。


const TEAM_GLOW_FOOT_NY: float = 0.65


## 按三角法线拆脚底 / 杖尖；返回 {foot, tip, tip_aabb, has_tip}。
static func _split_team_glow_by_normal(mesh: Mesh) -> Dictionary:
	var empty: Dictionary = {"foot": null, "tip": null, "tip_aabb": AABB(), "has_tip": false}
	if mesh == null or not (mesh is ArrayMesh):
		return empty
	var am: ArrayMesh = mesh as ArrayMesh
	if am.get_surface_count() <= 0:
		return empty
	var arrays: Array = am.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return empty
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = (
		arrays[Mesh.ARRAY_NORMAL]
		if arrays[Mesh.ARRAY_NORMAL] != null
		else PackedVector3Array()
	)
	var uvs: PackedVector2Array = (
		arrays[Mesh.ARRAY_TEX_UV]
		if arrays[Mesh.ARRAY_TEX_UV] != null
		else PackedVector2Array()
	)
	var idx: PackedInt32Array = (
		arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	)
	var bones: PackedInt32Array = (
		arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	)
	var weights: PackedFloat32Array = (
		arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	)
	var tri_count: int = int((idx.size() if idx.size() > 0 else verts.size()) / 3.0)
	var foot_idx: PackedInt32Array = PackedInt32Array()
	var tip_idx: PackedInt32Array = PackedInt32Array()
	var tip_aabb: AABB = AABB()
	var tip_has: bool = false
	for t: int in range(tri_count):
		var i0: int
		var i1: int
		var i2: int
		if idx.size() > 0:
			i0 = idx[t * 3]
			i1 = idx[t * 3 + 1]
			i2 = idx[t * 3 + 2]
		else:
			i0 = t * 3
			i1 = t * 3 + 1
			i2 = t * 3 + 2
		var nrm: Vector3
		if norms.size() > i0:
			nrm = (norms[i0] + norms[i1] + norms[i2]).normalized()
		else:
			nrm = (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]).normalized()
		var is_foot: bool = absf(nrm.y) >= TEAM_GLOW_FOOT_NY
		if is_foot:
			foot_idx.append(i0)
			foot_idx.append(i1)
			foot_idx.append(i2)
		else:
			tip_idx.append(i0)
			tip_idx.append(i1)
			tip_idx.append(i2)
			for iv: int in [i0, i1, i2]:
				if not tip_has:
					tip_aabb = AABB(verts[iv], Vector3.ZERO)
					tip_has = true
				else:
					tip_aabb = tip_aabb.expand(verts[iv])
	var foot_mesh: ArrayMesh = _rebuild_glow_surface(verts, norms, uvs, bones, weights, foot_idx)
	var tip_mesh: ArrayMesh = _rebuild_glow_surface(verts, norms, uvs, bones, weights, tip_idx)
	return {
		"foot": foot_mesh,
		"tip": tip_mesh,
		"tip_aabb": tip_aabb,
		"has_tip": tip_has and tip_idx.size() > 0,
	}


static func _rebuild_glow_surface(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	uvs: PackedVector2Array,
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	tri_idx: PackedInt32Array
) -> ArrayMesh:
	if tri_idx.is_empty():
		return null
	# 紧凑重映射顶点
	var remap_: Dictionary = {}
	var new_v: PackedVector3Array = PackedVector3Array()
	var new_n: PackedVector3Array = PackedVector3Array()
	var new_uv: PackedVector2Array = PackedVector2Array()
	var new_bones: PackedInt32Array = PackedInt32Array()
	var new_weights: PackedFloat32Array = PackedFloat32Array()
	var new_idx: PackedInt32Array = PackedInt32Array()
	var has_skin: bool = bones.size() >= verts.size() * 4 and weights.size() >= verts.size() * 4
	for i: int in tri_idx:
		if not remap_.has(i):
			var ni: int = new_v.size()
			remap_[i] = ni
			new_v.append(verts[i])
			if norms.size() > i:
				new_n.append(norms[i])
			if uvs.size() > i:
				new_uv.append(uvs[i])
			if has_skin:
				var b0: int = i * 4
				for k: int in range(4):
					new_bones.append(bones[b0 + k])
					new_weights.append(weights[b0 + k])
		new_idx.append(int(remap_[i]))
	var out_arrays: Array = []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = new_v
	if new_n.size() == new_v.size():
		out_arrays[Mesh.ARRAY_NORMAL] = new_n
	if new_uv.size() == new_v.size():
		out_arrays[Mesh.ARRAY_TEX_UV] = new_uv
	out_arrays[Mesh.ARRAY_INDEX] = new_idx
	if has_skin and new_bones.size() == new_v.size() * 4:
		out_arrays[Mesh.ARRAY_BONES] = new_bones
		out_arrays[Mesh.ARRAY_WEIGHTS] = new_weights
	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	return am
