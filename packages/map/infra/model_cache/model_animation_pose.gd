extends RefCounted
## Geoset显隐与动画采样，不推进播放时钟。

const Queries: GDScript = preload("model_animation_queries.gd")
const Tracks: GDScript = preload("model_animation_tracks.gd")



static func _snap_geoset_visibility_pose(
	root: Node, anim_name: String, at_time: float = 0.0, hide_zero_scale: bool = true
) -> void:
	var ap: AnimationPlayer = Queries._find_animation_player(root)
	if ap == null:
		return
	var resolved: String = Queries._resolve_animation_name(ap, anim_name)
	if resolved.is_empty():
		return
	var anim: Animation = ap.get_animation(resolved)
	if anim == null:
		return
	var anim_root: Node = ap.get_node_or_null(ap.root_node)
	if anim_root == null:
		anim_root = ap.get_parent()
	if anim_root == null:
		return
	var any_vis_track: bool = false
	for i: int in anim.get_track_count():
		var tpath: NodePath = anim.track_get_path(i)
		var ps: String = str(tpath)
		if not ps.contains("Geoset_"):
			continue
		if anim.track_get_key_count(i) <= 0:
			continue
		var target: Node3D = null
		if ps.ends_with(":visible"):
			any_vis_track = true
			var vis: bool = _track_bool_at(anim, i, at_time)
			target = _geoset_node_from_track(anim_root, tpath)
			if target != null:
				target.visible = vis
		elif ps.ends_with(":modulate"):
			target = _geoset_node_from_track(anim_root, tpath)
			if target != null:
				target.modulate = _track_color_at(anim, i, at_time)
	# 无 :visible 轨时仍尝试按 rest scale=0 藏（旧 GLB）；肖像用 scale 轨显隐，须跳过
	if not any_vis_track and hide_zero_scale:
		_hide_zero_scale_geosets(root)


static func _geoset_node_from_track(anim_root: Node, tpath: NodePath) -> Node3D:
	if anim_root == null:
		return null
	var ps: String = str(tpath)
	for suffix: String in [":visible", ":modulate"]:
		if ps.ends_with(suffix):
			ps = ps.substr(0, ps.length() - suffix.length())
			break
	var n: Node = anim_root.get_node_or_null(NodePath(ps))
	if n is Node3D:
		return n as Node3D
	var leaf: String = ps.get_file()
	if leaf.is_empty():
		leaf = ps
	if leaf.contains("/"):
		leaf = leaf.substr(leaf.rfind("/") + 1)
	var found: Node = anim_root.find_child(leaf, true, false)
	if found is Node3D:
		return found as Node3D
	return null


static func _track_bool_at(anim: Animation, track_i: int, time_sec: float) -> bool:
	var n: int = anim.track_get_key_count(track_i)
	if n <= 0:
		return true
	var vis: bool = bool(anim.track_get_key_value(track_i, 0))
	for k: int in range(n):
		if anim.track_get_key_time(track_i, k) <= time_sec + 0.0001:
			vis = bool(anim.track_get_key_value(track_i, k))
		else:
			break
	return vis


static func _track_color_at(anim: Animation, track_i: int, time_sec: float) -> Color:
	var n: int = anim.track_get_key_count(track_i)
	if n <= 0:
		return Color.WHITE
	var col: Color = anim.track_get_key_value(track_i, 0)
	for k: int in range(n):
		if anim.track_get_key_time(track_i, k) <= time_sec + 0.0001:
			col = anim.track_get_key_value(track_i, k)
		else:
			break
	return col


static func _hide_zero_scale_geosets(root: Node) -> void:
	if root == null:
		return
	# 旧路径：Geoset_N MeshInstance scale=0
	for c: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi == null:
			continue
		var nm: String = str(mi.name)
		if not nm.begins_with("Geoset_"):
			continue
		if mi.scale.length_squared() < 1e-8:
			mi.visible = false
	# 可选拆组：Geoset_N_Group_* BoneAttachment（无 scale 轨，靠 visible）
	for c: Node in root.find_children("*", "BoneAttachment3D", true, false):
		var ba: BoneAttachment3D = c as BoneAttachment3D
		if ba == null:
			continue
		var nm2: String = Tracks._strip_ba_geoset_prefix(str(ba.name))
		if not nm2.begins_with("Geoset_") or not nm2.contains("_Group_"):
			continue
		if ba.scale.length_squared() < 1e-8:
			ba.visible = false


static func _reveal_hidden_geosets(n: Node) -> void:
	if n is Node3D:
		var n3: Node3D = n as Node3D
		if n3.scale.length_squared() < 1e-8:
			n3.scale = Vector3.ONE
	for c: Node in n.get_children():
		_reveal_hidden_geosets(c)


## 供 MapDoodadLayer.ensure_promoted 等：GeosetAnim rest 全隐时强制可见。
static func reveal_hidden_geosets_public(root: Node) -> void:
	if root == null:
		return
	_reveal_hidden_geosets(root)
	for c: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi == null:
			continue
		mi.visible = true
		if mi.scale.length_squared() < 1e-8:
			mi.scale = Vector3.ONE


## 按 Stand 的 :visible 轨定格（树=藏树桩 Geoset；主城=默认档）。
## 树/可破坏物 promote 必须走这里，禁止 reveal_all（否则桩与活树同亮）。
static func snap_stand_geoset_visibility(root: Node) -> void:
	if root == null:
		return
	var ap: AnimationPlayer = Queries._find_animation_player(root)
	var leaf: String = "Stand"
	if ap != null:
		var picked: String = Queries._pick_stand_name(ap)
		if not picked.is_empty():
			leaf = Queries._anim_leaf_name(picked)
	_snap_geoset_visibility_pose(root, leaf)


## 按任意 Sequence（如 Stand_Work / Decay_Flesh）指定时刻的 :visible 定格 geoset。
static func snap_geoset_visibility_for(
	root: Node, anim_name: String, at_time: float = 0.0, hide_zero_scale: bool = true
) -> void:
	if root == null or anim_name.is_empty():
		return
	_snap_geoset_visibility_pose(root, anim_name, at_time, hide_zero_scale)
