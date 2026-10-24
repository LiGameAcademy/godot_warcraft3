extends RefCounted
## 解析骨骼rest和Geoset旁路数据，注入模型动画轨。

const Geometry: GDScript = preload("model_geometry.gd")
const Queries: GDScript = preload("model_animation_queries.gd")



## 将缓存中的原型打包为 .scn（优先写 asset-converted 同目录，失败则 user://）。
## force=true 时覆盖已有旁路 .scn（export --force / 补 geosetvis 轨后重烤）。
## 打包前套默认队伍色（TeamColor00），便于编辑器直接打开 .scn 即见染色；游戏侧仍会按 owner 重染。
## 旁路 JSON：优先与 glTF 同目录（含 tmp 拷贝），否则 asset-converted。
static func _resolve_bone_rest_disk(glb_path: String) -> String:
	var side: String = glb_path.replace("\\", "/")
	var rest_rel: String = ""
	if side.to_lower().ends_with(".gltf"):
		rest_rel = side.substr(0, side.length() - 5) + ".bone_rest.json"
	elif side.to_lower().ends_with(".glb"):
		rest_rel = side.substr(0, side.length() - 4) + ".bone_rest.json"
	else:
		return ""
	var candidates: PackedStringArray = []
	if rest_rel.begins_with("res://") or rest_rel.is_absolute_path():
		candidates.append(RuntimeAssets.project_abs(rest_rel))
	else:
		candidates.append(RuntimeAssets.project_abs("res://assets/asset-converted/" + rest_rel))
		candidates.append(RuntimeAssets.project_abs("res://" + rest_rel))
	for disk: String in candidates:
		if not disk.is_empty() and FileAccess.file_exists(disk):
			return disk
	return ""


## Stand 绑定 TRS → 骨 rest（pose 保持 I）。骑士 T-pose 顶点 × rest 才是坐姿；
## 不要 set_bone_pose_position：那会 rest*pose 叠两次。IBM 必须是单位阵。
static func apply_bone_rest_sidecar(proto: Node, glb_path: String) -> void:
	if proto == null or glb_path.is_empty():
		return
	var disk: String = _resolve_bone_rest_disk(glb_path)
	if disk.is_empty():
		return
	var raw: String = RuntimeAssets.read_utf8_text(disk)
	if raw.is_empty():
		return
	var parsed: Variant = RuntimeAssets.parse_json_text(raw)
	if not parsed is Dictionary:
		return
	var bones: Array = parsed.get("bones", [])
	var skeleton: Skeleton3D = null
	for c: Node in proto.find_children("*", "Skeleton3D", true, false):
		if c is Skeleton3D:
			skeleton = c as Skeleton3D
			break
	if skeleton == null:
		return
	var updated_bi: Array[int] = []
	for entry: Dictionary in bones:
		var nm: String = str(entry.get("name", ""))
		if nm.is_empty():
			continue
		var bi: int = skeleton.find_bone(nm)
		if bi < 0:
			continue
		var t: Variant = entry.get("translation", [])
		var pos: Vector3 = Vector3.ZERO
		if t is Array and t.size() >= 3:
			pos = Vector3(float(t[0]), float(t[1]), float(t[2]))
		var rot: Variant = entry.get("rotation", [])
		var q: Quaternion = Quaternion.IDENTITY
		if rot is Array and rot.size() >= 4:
			q = Quaternion(float(rot[0]), float(rot[1]), float(rot[2]), float(rot[3]))
		var sc: Variant = entry.get("scale", [])
		var basis: Basis = Basis(q)
		if sc is Array and sc.size() >= 3:
			basis = basis.scaled(Vector3(float(sc[0]), float(sc[1]), float(sc[2])))
		skeleton.set_bone_rest(bi, Transform3D(basis, pos))
		skeleton.reset_bone_pose(bi)
		updated_bi.append(bi)
	if not updated_bi.is_empty():
		skeleton.force_update_all_bone_transforms()
	for c: Node in proto.find_children("*", "BoneAttachment3D", true, false):
		if c is BoneAttachment3D:
			var ba: BoneAttachment3D = c as BoneAttachment3D
			if not ba.bone_name.is_empty():
				var idx2: int = skeleton.find_bone(ba.bone_name)
				if idx2 >= 0 and ba.get_bone_idx() != idx2:
					ba.set_bone_idx(idx2)


## Godot 导入丢弃蒙皮 Geoset / 空父节点上的 scale 轨；用旁路 *.geosetvis.json 补 `:visible`。
static func _inject_geoset_vis_tracks(glb_path: String, root: Node) -> bool:
	if root == null or glb_path.is_empty():
		return false
	var json_res: String = _geoset_vis_json_path(glb_path)
	if json_res.is_empty() or not RuntimeAssets.file_exists(json_res):
		return false
	var disk: String = RuntimeAssets.project_abs(json_res)
	var text: String = RuntimeAssets.read_utf8_text(disk)
	if text.is_empty():
		return false
	var data: Variant = RuntimeAssets.parse_json_text(text)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var sequences: Variant = (data as Dictionary).get("sequences", [])
	if typeof(sequences) != TYPE_ARRAY or (sequences as Array).is_empty():
		return false
	var ap: AnimationPlayer = Queries._find_animation_player(root)
	if ap == null:
		return false
	var anim_root: Node = ap.get_node_or_null(ap.root_node)
	if anim_root == null:
		anim_root = ap.get_parent()
	if anim_root == null:
		return false
	var geoset_nodes: Dictionary = _index_geoset_meshes(root)
	if geoset_nodes.is_empty():
		return false
	var injected: bool = false
	for seq_v: Variant in sequences as Array:
		if typeof(seq_v) != TYPE_DICTIONARY:
			continue
		var seq: Dictionary = seq_v
		var anim_name: String = str(seq.get("name", "")).strip_edges()
		if anim_name.is_empty():
			continue
		# geosetvis 与 Godot 动画名可能大小写不一致（stand vs Stand）
		var resolved: String = Queries._resolve_animation_name(ap, anim_name)
		if resolved.is_empty():
			continue
		var anim: Animation = ap.get_animation(resolved)
		if anim == null:
			continue
		_remove_geoset_presentation_tracks(anim)
		var geosets: Variant = seq.get("geosets", {})
		if typeof(geosets) != TYPE_DICTIONARY:
			continue
		for gi_key: Variant in (geosets as Dictionary).keys():
			var nodes_v: Variant = geoset_nodes.get(str(gi_key), [])
			var targets: Array = []
			if typeof(nodes_v) == TYPE_ARRAY:
				targets = nodes_v as Array
			elif nodes_v is Node:
				targets = [nodes_v]
			if targets.is_empty():
				continue
			var keys_v: Variant = (geosets as Dictionary)[gi_key]
			if typeof(keys_v) != TYPE_ARRAY or (keys_v as Array).is_empty():
				continue
			for mesh_n_v: Variant in targets:
				if not (mesh_n_v is Node):
					continue
				var mesh_n: Node = mesh_n_v
				# 轨路径相对 AnimationPlayer.root_node（默认 ..），不是相对 AP 自身
				if anim_root == null or not Geometry._nodes_share_tree(anim_root, mesh_n):
					continue
				var rel: NodePath = anim_root.get_path_to(mesh_n)
				if str(rel).is_empty() or str(rel) == ".":
					continue
				var track_path: NodePath = NodePath("%s:visible" % str(rel))
				var ti: int = anim.add_track(Animation.TYPE_VALUE)
				anim.track_set_path(ti, track_path)
				anim.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)
				anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_NEAREST)
				var mod_path: NodePath = NodePath("%s:modulate" % str(rel))
				var ti_mod: int = anim.add_track(Animation.TYPE_VALUE)
				anim.track_set_path(ti_mod, mod_path)
				anim.value_track_set_update_mode(ti_mod, Animation.UPDATE_CONTINUOUS)
				anim.track_set_interpolation_type(ti_mod, Animation.INTERPOLATION_LINEAR)
				var need_modulate: bool = false
				for key_v: Variant in keys_v as Array:
					if typeof(key_v) != TYPE_DICTIONARY:
						continue
					var kd: Dictionary = key_v
					var t: float = float(kd.get("t", 0.0))
					var alpha: float = float(kd.get("alpha", -1.0))
					if alpha < 0.0:
						alpha = 1.0 if int(kd.get("v", 1)) != 0 else 0.0
					var vis: bool = alpha > 0.004
					anim.track_insert_key(ti, t, vis)
					anim.track_insert_key(ti_mod, t, Color(1.0, 1.0, 1.0, alpha))
					if alpha > 0.004 and alpha < 0.996:
						need_modulate = true
				if not need_modulate:
					anim.remove_track(ti_mod)
				injected = true
	return injected


static func _geoset_vis_json_path(glb_path: String) -> String:
	var logical: String = RuntimeAssets.relative_or_res_to_logical(glb_path)
	var lower: String = logical.to_lower()
	if lower.ends_with(".glb"):
		logical = logical.substr(0, logical.length() - 4) + ".geosetvis.json"
	elif lower.ends_with(".gltf"):
		logical = logical.substr(0, logical.length() - 5) + ".geosetvis.json"
	elif lower.ends_with(".scn"):
		logical = logical.substr(0, logical.length() - 4) + ".geosetvis.json"
	else:
		logical = logical + ".geosetvis.json"
	return RuntimeAssets.converted_path(logical)


## 索引 geoset 显隐目标：gi → Array[Node]
## - 默认：MeshInstance3D 名 `Geoset_N`（SkinMeshes 桶）
## - 可选拆组：BoneAttachment3D 名 `Geoset_N_Group_M` 或 `BA_Geoset_N_Group_M`
static func _index_geoset_meshes(root: Node) -> Dictionary:
	var out: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		var nm: String = _strip_ba_geoset_prefix(str(n.name))
		if not nm.begins_with("Geoset_"):
			continue
		var rest: String = nm.substr("Geoset_".length())
		var gi_str: String = ""
		if rest.is_valid_int():
			# Geoset_12
			gi_str = rest
		else:
			# Geoset_12_Group_0
			var gpos: int = rest.find("_Group_")
			if gpos > 0:
				var head: String = rest.substr(0, gpos)
				if head.is_valid_int():
					gi_str = head
		if gi_str.is_empty():
			continue
		# 优先绑 BoneAttachment；纯 MeshInstance Geoset_N 也收
		if n is BoneAttachment3D or (n is MeshInstance3D and rest.is_valid_int()):
			if not out.has(gi_str):
				out[gi_str] = []
			(out[gi_str] as Array).append(n)
	return out


static func _strip_ba_geoset_prefix(nm: String) -> String:
	if nm.begins_with("BA_"):
		return nm.substr(3)
	return nm


static func _remove_geoset_presentation_tracks(anim: Animation) -> void:
	for i: int in range(anim.get_track_count() - 1, -1, -1):
		var p: String = str(anim.track_get_path(i))
		if not p.contains("Geoset_"):
			continue
		if p.ends_with(":visible") or p.ends_with(":modulate"):
			anim.remove_track(i)


static func _remove_geoset_visible_tracks(anim: Animation) -> void:
	_remove_geoset_presentation_tracks(anim)
