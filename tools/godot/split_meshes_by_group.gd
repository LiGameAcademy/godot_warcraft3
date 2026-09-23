class_name SplitMeshesByGroup
extends RefCounted
## 按 VertexGroup 拆 geoset mesh（可选工具；bake:scn 默认不调用）。
##
## 用途：城墙旗子等 equal-weight 错位。原 m2g 一个 geoset = 1 个 mesh，
## skin joints = group 内所有 bone，weight equal 分 → 配件位置 = mesh 中心。
## 拆开后每 group 单独绑一个 bone。独立测试：tests/unit/selftest_c3_split.gd。
##
## 用法:
##   var n := SplitMeshesByGroup.split(proto, att_data)
##   if n > 0: print("split %d groups" % n)
##
## 输入:
##   proto:  .gltf 实例化后的 Node3D（含 Skeleton3D + Geoset_<i> MeshInstance3D）
##   att_data: 读 attachments.json 后的 Dictionary（含 geoset_expansions[]）
## 输出:
##   拆出的 group 数量（>= 0）

static func split(proto: Node, att_data: Dictionary) -> int:
	if proto == null or att_data.is_empty():
		return 0
	var expansions: Array = att_data.get("geoset_expansions", [])
	if expansions.is_empty():
		return 0
	var skeleton: Skeleton3D = null
	for c in proto.find_children("*", "Skeleton3D", true, false):
		if c is Skeleton3D:
			skeleton = c
			break
	if skeleton == null:
		push_warning("split_meshes_by_group: no Skeleton3D, skip")
		return 0
	var total_split := 0
	var total_geosets := 0
	for exp in expansions:
		var groups: Array = exp.get("groups", [])
		if groups.is_empty():
			continue
		var gi: int = int(exp.get("geoset_index", -1))
		if gi < 0:
			continue
		var geoset_name := "Geoset_%d" % gi
		var orig_mesh_node: MeshInstance3D = null
		for c in proto.find_children(geoset_name, "MeshInstance3D", true, false):
			if c is MeshInstance3D and c.name == geoset_name:
				orig_mesh_node = c
				break
		if orig_mesh_node == null or orig_mesh_node.mesh == null:
			continue
		var src_mesh: ArrayMesh = orig_mesh_node.mesh
		if src_mesh.get_surface_count() == 0:
			continue
		var arrays: Array = src_mesh.surface_get_arrays(0)
		var src_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if src_verts.is_empty():
			continue
		var src_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var src_tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var src_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var src_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var has_indices := src_indices.size() > 0
		var orig_material: Material = src_mesh.surface_get_material(0)
		var orig_parent: Node = orig_mesh_node.get_parent()
		if orig_parent == null:
			continue
		var split_count := 0
		for group in groups:
			var group_idx: int = int(group.get("group_index", -1))
			var bone_names: PackedStringArray = group.get("bones", [])
			if bone_names.is_empty():
				continue
			var bone_name: String = bone_names[0]
			var joint_idx := skeleton.find_bone(bone_name)
			if joint_idx == -1:
				push_warning("split: geoset_%d group_%d bone missing: %s" % [gi, group_idx, bone_name])
				continue
			var vert_indices_raw = group.get("vertex_indices", [])
			if vert_indices_raw.size() == 0:
				continue
			var vert_set: Dictionary = {} # old_idx → true（本 group 原始顶点）
			for v in vert_indices_raw:
				vert_set[int(v)] = true
			# subset 顶点（先放本 group；跨 group 三角面再补齐缺失角点）
			var new_verts := PackedVector3Array()
			var new_normals := PackedVector3Array()
			var new_tangents := PackedFloat32Array()
			var new_uvs := PackedVector2Array()
			var old_to_new := {}
			var new_indices := PackedInt32Array()
			if has_indices:
				# 任一角点属本 group 即收录该三角；缺角点补进 subset。
				# 旧逻辑要求三角三顶点都在 group 内 → 缝上三角全丢 → 身体破洞 + 非法面。
				for i in range(0, src_indices.size(), 3):
					if i + 2 >= src_indices.size():
						break
					var i0 := src_indices[i]
					var i1 := src_indices[i + 1]
					var i2 := src_indices[i + 2]
					if not (vert_set.has(i0) or vert_set.has(i1) or vert_set.has(i2)):
						continue
					for old_idx in [i0, i1, i2]:
						if old_to_new.has(old_idx):
							continue
						if old_idx < 0 or old_idx >= src_verts.size():
							continue
						old_to_new[old_idx] = new_verts.size()
						new_verts.append(src_verts[old_idx])
						if src_normals.size() > old_idx:
							new_normals.append(src_normals[old_idx])
						if src_tangents.size() > old_idx * 4:
							for t in range(4):
								new_tangents.append(src_tangents[old_idx * 4 + t])
						if src_uvs.size() > old_idx:
							new_uvs.append(src_uvs[old_idx])
					if not (old_to_new.has(i0) and old_to_new.has(i1) and old_to_new.has(i2)):
						continue
					new_indices.append(old_to_new[i0])
					new_indices.append(old_to_new[i1])
					new_indices.append(old_to_new[i2])
			else:
				for old_idx_v in vert_set.keys():
					var old_idx: int = int(old_idx_v)
					if old_idx < 0 or old_idx >= src_verts.size():
						continue
					old_to_new[old_idx] = new_verts.size()
					new_verts.append(src_verts[old_idx])
					if src_normals.size() > old_idx:
						new_normals.append(src_normals[old_idx])
					if src_tangents.size() > old_idx * 4:
						for t in range(4):
							new_tangents.append(src_tangents[old_idx * 4 + t])
					if src_uvs.size() > old_idx:
						new_uvs.append(src_uvs[old_idx])
			# 无合法三角则跳过：避免 PRIMITIVE_TRIANGLES + 非 3 倍数顶点刷屏
			if has_indices:
				if new_indices.size() < 3:
					continue
			elif new_verts.size() < 3 or new_verts.size() % 3 != 0:
				continue
			var new_mesh := ArrayMesh.new()
			var new_arrays := []
			new_arrays.resize(Mesh.ARRAY_MAX)
			# 顶点变到 bone-local：BoneAttachment 会再乘骨变换；切勿再带 skin 权重
			# （有 ARRAY_BONES 但 skeleton 为空时 Godot 常直接不画 → 步兵“身体消失”）
			var bone_rest := skeleton.get_bone_global_rest(joint_idx)
			var to_bone := bone_rest.affine_inverse()
			var bone_basis_inv := bone_rest.basis.inverse()
			var local_verts := PackedVector3Array()
			local_verts.resize(new_verts.size())
			for vi in range(new_verts.size()):
				local_verts[vi] = to_bone * new_verts[vi]
			new_arrays[Mesh.ARRAY_VERTEX] = local_verts
			if new_normals.size() == new_verts.size():
				var local_normals := PackedVector3Array()
				local_normals.resize(new_normals.size())
				for vi in range(new_normals.size()):
					local_normals[vi] = (bone_basis_inv * new_normals[vi]).normalized()
				new_arrays[Mesh.ARRAY_NORMAL] = local_normals
			if new_tangents.size() == new_verts.size() * 4:
				var local_tangents := PackedFloat32Array()
				local_tangents.resize(new_tangents.size())
				for vi in range(new_verts.size()):
					var t := Vector3(
						new_tangents[vi * 4],
						new_tangents[vi * 4 + 1],
						new_tangents[vi * 4 + 2]
					)
					t = bone_basis_inv * t
					local_tangents[vi * 4] = t.x
					local_tangents[vi * 4 + 1] = t.y
					local_tangents[vi * 4 + 2] = t.z
					local_tangents[vi * 4 + 3] = new_tangents[vi * 4 + 3]
				new_arrays[Mesh.ARRAY_TANGENT] = local_tangents
			if new_uvs.size() == new_verts.size():
				new_arrays[Mesh.ARRAY_TEX_UV] = new_uvs
			# 故意不写 ARRAY_BONES / ARRAY_WEIGHTS：由 BoneAttachment 刚性跟骨
			if has_indices and new_indices.size() > 0:
				new_arrays[Mesh.ARRAY_INDEX] = new_indices
			var flags := 0
			new_mesh.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES,
				new_arrays,
				[],
				{},
				flags
			)
			# Godot 4.6 严格不允许 surface_set_material 传 null（之前的 .gltf geoset 无 material 时会触发）
			# 防御：仅当 orig_material 非 null 时绑定；null 时新 mesh 走默认无材质
			if orig_material != null:
				new_mesh.surface_set_material(0, orig_material)
			var ba := BoneAttachment3D.new()
			ba.name = "Geoset_%d_Group_%d" % [gi, group_idx]
			ba.bone_name = bone_name
			orig_parent.add_child(ba)
			ba.owner = proto
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = new_mesh
			# 静态网格 + BoneAttachment，不挂 Skeleton
			mi.skeleton = NodePath()
			ba.add_child(mi)
			mi.owner = proto
			# 继承原 geoset 显隐（Stand rest 可能 scale=0 / visible=false）
			ba.visible = orig_mesh_node.visible and orig_mesh_node.scale.length_squared() > 1e-8
			split_count += 1
		if split_count > 0:
			orig_parent.remove_child(orig_mesh_node)
			orig_mesh_node.queue_free()
			total_split += split_count
			total_geosets += 1
	return total_split

