class_name RallyFlagFx
extends Node3D
## 建筑集结旗：WC3 `UI/Feedback/RallyPoint`。
## 选中可训建筑且已设集结点时显示；换点/取消选中时更新或隐藏。

## 与 MoveConfirmFx 一致：逻辑键写 .glb，由 MapModelCache 解析旁路 .scn / .gltf
const FLAG_HUMAN := "UI/Feedback/RallyPoint/RallyPoint.glb"
const FLAG_ORC := "UI/Feedback/RallyPoint/OrcRallyFlag.glb"
const FLAG_UNDEAD := "UI/Feedback/RallyPoint/UndeadRallyFlag.glb"
const FLAG_NIGHTELF := "UI/Feedback/RallyPoint/NightElfRallyFlag.glb"
const GROUND_LIFT_WC3 := 8.0
const OVERLAY_SHADER := preload("res://assets/shaders/wc3_rally_flag_overlay.gdshader")
## 与 MoveConfirmFx 同档：反馈层压在场景几何之上
const OVERLAY_RENDER_PRIORITY := 30
const OVERLAY_SORTING_OFFSET := 12.0

var _cache: MapModelCache = null
var _inst: Node3D = null
var _rel_path: String = ""
var _team_color: int = -1
var _shown: bool = false


func setup(cache: MapModelCache) -> void:
	_cache = cache


func hide_flag() -> void:
	_clear_inst()
	visible = false
	_shown = false
	set_process(false)


func show_at_wc3(
	wc3_xy: Vector2,
	race_id: String,
	team_color_index: int,
	heightfield: Wc3Heightfield = null
) -> void:
	if wc3_xy == Vector2.INF:
		hide_flag()
		return
	var z := 0.0
	if heightfield != null and heightfield.is_valid():
		z = heightfield.interpolated_height(wc3_xy.x, wc3_xy.y)
	global_position = Wc3Coords.wc3_xy_to_godot(wc3_xy.x, wc3_xy.y, z + GROUND_LIFT_WC3)
	var rel := _flag_rel_for_race(race_id)
	var need_respawn := _inst == null or not is_instance_valid(_inst) or _rel_path != rel
	if need_respawn:
		_clear_inst()
		_rel_path = rel
		_inst = _spawn(rel)
		if _inst == null:
			push_warning("RallyFlagFx: model spawn failed path=%s — using fallback pole" % rel)
			_inst = _spawn_fallback_pole()
		if _inst == null:
			hide_flag()
			return
		# 旁路 .scn 子节点已带 MODEL_SCALE(0.01)；勿再给根乘 WORLD_SCALE（会缩成看不见）
		add_child(_inst)
		_team_color = -1
	_prepare_flag_visual(_inst, team_color_index)
	_play_stand_loop(_inst)
	_force_meshes_visible(_inst)
	_apply_overlay_draw(_inst)
	_shown = true
	visible = true
	# 动画轨可能每帧再藏 geoset：显示期间持续压可见
	set_process(true)


func _process(_delta: float) -> void:
	if not _shown or _inst == null or not is_instance_valid(_inst):
		set_process(false)
		return
	_force_meshes_visible(_inst)


func _flag_rel_for_race(race_id: String) -> String:
	match race_id.strip_edges().to_lower():
		"orc":
			return FLAG_ORC
		"undead":
			return FLAG_UNDEAD
		"nightelf", "night_elf", "night-elf":
			return FLAG_NIGHTELF
		_:
			return FLAG_HUMAN


func _spawn(rel: String) -> Node3D:
	var path := RuntimeAssets.converted_path(rel)
	var n := _instance_flag(path)
	if n != null:
		return n
	# 磁盘多为 .gltf：换扩展再试
	var lower := path.to_lower()
	if lower.ends_with(".glb"):
		n = _instance_flag(path.substr(0, path.length() - 4) + ".gltf")
		if n != null:
			return n
	elif lower.ends_with(".gltf"):
		n = _instance_flag(path.substr(0, path.length() - 5) + ".glb")
		if n != null:
			return n
	var scn := RuntimeAssets.resolve_model_scene(path)
	if not scn.is_empty():
		var packed: PackedScene = RuntimeAssets.load_packed_scene(scn)
		if packed != null:
			return packed.instantiate() as Node3D
	return null


func _instance_flag(path: String) -> Node3D:
	if _cache == null or path.is_empty():
		return null
	if _cache.has_method("instance_glb_hud"):
		return _cache.instance_glb_hud(path)
	return _cache.instance_glb(path)


func _prepare_flag_visual(root: Node3D, team_color_index: int) -> void:
	if root == null:
		return
	if root.has_meta("rally_fallback"):
		_apply_overlay_draw(root)
		return
	if _cache != null:
		if _cache.has_method("reveal_hidden_geosets_public"):
			_cache.reveal_hidden_geosets_public(root)
		# hide_team_glow=false：人族旗布是队色垫底，不能当 Team Glow 藏掉
		_cache.apply_team_color(root, clampi(team_color_index, 0, 15), false)
		_team_color = clampi(team_color_index, 0, 15)
	_force_meshes_visible(root)


## 反馈层：关深度测试 + 高 render_priority，避免被地形/建筑挡住。
func _apply_overlay_draw(root: Node) -> void:
	if root == null:
		return
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.sorting_offset = OVERLAY_SORTING_OFFSET
		if mi.material_override != null:
			mi.material_override = _promote_overlay_material(mi.material_override)
			continue
		for si in range(mi.mesh.get_surface_count()):
			var base: Material = mi.get_active_material(si)
			if base == null:
				continue
			mi.set_surface_override_material(si, _promote_overlay_material(base))


func _promote_overlay_material(src: Material) -> Material:
	if src == null:
		return null
	if src is StandardMaterial3D:
		var sm := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
		sm.no_depth_test = true
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		sm.render_priority = OVERLAY_RENDER_PRIORITY
		return sm
	if src is ShaderMaterial:
		var shm := (src as ShaderMaterial).duplicate() as ShaderMaterial
		# 队色垫底 → 专用 overlay shader（depth_test_disabled）
		if _is_team_underlay_shader(shm):
			shm.shader = OVERLAY_SHADER
		shm.render_priority = OVERLAY_RENDER_PRIORITY
		return shm
	var dup := src.duplicate() as Material
	if dup != null:
		dup.render_priority = OVERLAY_RENDER_PRIORITY
	return dup if dup != null else src


func _is_team_underlay_shader(mat: ShaderMaterial) -> bool:
	if mat == null or mat.shader == null:
		return false
	var p := str(mat.shader.resource_path).replace("\\", "/").to_lower()
	return p.contains("wc3_team_color_underlay") or p.contains("wc3_rally_flag_overlay")


## 播 Stand 并保持循环；勿 stop/deactive，否则蒙皮偶发塌成不可见。
func _play_stand_loop(root: Node) -> void:
	var ap := _find_ap(root)
	if ap == null:
		return
	var stand := ""
	var birth := ""
	for n in ap.get_animation_list():
		var leaf := str(n)
		var slash := leaf.rfind("/")
		if slash >= 0:
			leaf = leaf.substr(slash + 1)
		var low := leaf.to_lower()
		if stand.is_empty() and low.begins_with("stand"):
			stand = str(n)
		if birth.is_empty() and low.begins_with("birth"):
			birth = str(n)
	ap.active = true
	if not stand.is_empty():
		ap.play(stand)
	elif not birth.is_empty():
		ap.play(birth)


func _force_meshes_visible(root: Node) -> void:
	if root == null:
		return
	if root is Node3D:
		var r3 := root as Node3D
		r3.visible = true
		if r3.scale.length_squared() < 1e-8:
			r3.scale = Vector3.ONE
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		mi.visible = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.scale.length_squared() < 1e-8:
			mi.scale = Vector3.ONE
	for c in root.find_children("*", "BoneAttachment3D", true, false):
		var ba := c as BoneAttachment3D
		if ba == null:
			continue
		ba.visible = true
		if ba.scale.length_squared() < 1e-8:
			ba.scale = Vector3.ONE
	for c in root.find_children("Geoset_*", "Node3D", true, false):
		var n3 := c as Node3D
		if n3 == null:
			continue
		n3.visible = true
		if n3.scale.length_squared() < 1e-8:
			n3.scale = Vector3.ONE
	# 蒙皮骨偶发被轨缩到 0
	for c in root.find_children("*", "Skeleton3D", true, false):
		var sk := c as Skeleton3D
		if sk == null:
			continue
		for bi in range(sk.get_bone_count()):
			var bs := sk.get_bone_pose_scale(bi)
			if bs.length_squared() < 1e-8:
				sk.set_bone_pose_scale(bi, Vector3.ONE)


func _spawn_fallback_pole() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "RallyFallback"
	mi.set_meta("rally_fallback", true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = OVERLAY_SORTING_OFFSET
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.06
	mesh.height = 1.6
	mi.mesh = mesh
	mi.position = Vector3(0.0, mesh.height * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.15, 0.85, 0.25, 1.0)
	mat.no_depth_test = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = OVERLAY_RENDER_PRIORITY
	mi.material_override = mat
	return mi


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := _find_ap(c)
		if f:
			return f
	return null


func _clear_inst() -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.queue_free()
	_inst = null
	_rel_path = ""
	_team_color = -1


func _exit_tree() -> void:
	_clear_inst()
