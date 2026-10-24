extends RefCounted
## 模型几何查询、网格消毒和静态片段抽取。




## 按指定动画 at_time 的 :visible 轨立刻设 Geoset 显隐（不依赖正在播放）。
static func _node_visual_aabb(root: Node3D) -> AABB:
	if root == null:
		return AABB()
	var aabb: AABB = AABB()
	var first: bool = true
	for c: Node in root.find_children("*", "VisualInstance3D", true, false):
		var vi: VisualInstance3D = c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var la: AABB = vi.get_aabb()
		# 离树时没有 global_transform；用相对 root 的局部累积。
		var xf: Transform3D = _xform_to_ancestor(vi, root)
		for i: int in range(8):
			var corner: Vector3 = la.position + la.size * Vector3(
				float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1)
			)
			var p: Vector3 = xf * corner
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb


## node 相对 ancestor 的 Transform（含中间父链；ancestor 不含自身）。
static func _xform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## 旧 .scn / 错误拆 mesh：PRIMITIVE_TRIANGLES 但顶点数非 3 倍数 → 引擎每帧刷 ERROR。
## 丢掉非法 surface；全非法则隐藏该 MeshInstance。
static func _sanitize_triangle_meshes(root: Node) -> void:
	if root == null:
		return
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if bool(mi.get_meta("is_runtime_uber_splat", false)):
			continue
		if not (mi.mesh is ArrayMesh):
			continue
		var am: ArrayMesh = mi.mesh as ArrayMesh
		var sc: int = am.get_surface_count()
		if sc <= 0:
			continue
		var kept: int = 0
		var rebuilt: ArrayMesh = ArrayMesh.new()
		var any_bad: bool = false
		for si: int in range(sc):
			var arrays: Array = am.surface_get_arrays(si)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				any_bad = true
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices_v: Variant = arrays[Mesh.ARRAY_INDEX]
			var ok: bool = false
			if indices_v is PackedInt32Array and (indices_v as PackedInt32Array).size() > 0:
				var indices: PackedInt32Array = indices_v as PackedInt32Array
				ok = indices.size() >= 3 and indices.size() % 3 == 0
			else:
				ok = verts.size() >= 3 and verts.size() % 3 == 0
			if not ok:
				any_bad = true
				continue
			var mat: Material = am.surface_get_material(si)
			rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			if mat != null:
				rebuilt.surface_set_material(kept, mat)
			kept += 1
		if not any_bad:
			continue
		if kept <= 0:
			mi.visible = false
			mi.mesh = null
		else:
			mi.mesh = rebuilt


static func _collect_mesh_parts(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n as MeshInstance3D
		# 跳过 Stand 下应隐藏的 Geoset（树桩）；否则 MultiMesh 会把桩和活树一起画
		if mi.mesh != null and mi.visible:
			out.append({
				"mesh": mi.mesh,
				"material": mi.get_active_material(0),
			})
	for c: Node in n.get_children():
		_collect_mesh_parts(c, out)


## 无共同祖先时 `Node.get_path_to` 会引擎 ERROR。
static func _nodes_share_tree(a: Node, b: Node) -> bool:
	if a == null or b == null:
		return false
	var walk: Node = a
	var seen: Dictionary = {}
	while walk != null:
		seen[walk] = true
		walk = walk.get_parent()
	walk = b
	while walk != null:
		if seen.has(walk):
			return true
		walk = walk.get_parent()
	return false


static func node_has_mesh(root: Node) -> bool:
	return MapPlaceholders.node_has_mesh(root)
