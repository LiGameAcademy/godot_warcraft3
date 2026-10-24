extends RefCounted
## 缓存原型、打包场景、动画标记与静态网格片段的唯一所有者。

const Assembly: GDScript = preload("model_scene_assembly.gd")
const Geometry: GDScript = preload("model_geometry.gd")
const Pose: GDScript = preload("model_animation_pose.gd")
const Queries: GDScript = preload("model_animation_queries.gd")
const Rules: GDScript = preload("model_material_rules.gd")
const Team: GDScript = preload("model_team_color.gd")
const Tracks: GDScript = preload("model_animation_tracks.gd")

var _scene_cache: Dictionary = {}
var _packed_cache: Dictionary = {}
var _anim_flags: Dictionary = {}
var _parts_cache: Dictionary = {}
var _lazy_bake_queue: PackedStringArray = PackedStringArray()
var _warned_preview_fail: Dictionary = {}
var last_scn_hits: int = 0
var last_gltf_loads: int = 0
var last_cache_hits: int = 0
var _preloader: RefCounted
var _team: RefCounted = Team.new()

func _init(preloader: RefCounted) -> void:
	_preloader = preloader


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	# 缓存原型不在 SceneTree 中，RefCounted 的 Dictionary 析构不会 free Node。
	# 仅释放原型；instance_glb 返回的副本由各自宿主负责。
	for prototype: Variant in _scene_cache.values():
		if prototype is Node and is_instance_valid(prototype):
			prototype.free()
	_scene_cache.clear()


func reset_load_stats() -> void:
	last_scn_hits = 0
	last_gltf_loads = 0
	last_cache_hits = 0


func instance_glb(path: String, unit_soft_blend: bool = false) -> Node3D:
	return _instance_glb_internal(path, true, unit_soft_blend)


## HUD 肖像热路径：跳过材质修正 / mesh 消毒（bake 过的 .scn 已处理）。
## 战场单位仍走 instance_glb，保证旧资产也安全。
func instance_glb_hud(path: String) -> Node3D:
	return _instance_glb_internal(path, false, false)


func _instance_glb_internal(path: String, sanitize: bool, unit_soft_blend: bool = false) -> Node3D:
	if has_cached(path):
		last_cache_hits += 1
	var packed: PackedScene = _ensure_packed(path)
	if packed != null:
		var inst: Node = packed.instantiate()
		if inst is Node3D:
			if sanitize:
				Rules._stamp_glb_model_meta(inst as Node3D, path, unit_soft_blend)
				Rules._mark_waterish_if_needed(inst as Node3D, path, unit_soft_blend)
				Rules._fix_wc3_blend_materials(inst as Node3D, unit_soft_blend)
				Geometry._sanitize_triangle_meshes(inst as Node3D)
			return inst as Node3D
		if inst != null:
			inst.free()
	var proto: Node3D = _ensure_scene(path)
	if proto == null:
		return null
	var dup: Node3D = proto.duplicate() as Node3D
	if dup != null and sanitize:
		Rules._stamp_glb_model_meta(dup, path, unit_soft_blend)
		Rules._mark_waterish_if_needed(dup, path, unit_soft_blend)
		Rules._fix_wc3_blend_materials(dup, unit_soft_blend)
		Geometry._sanitize_triangle_meshes(dup)
	return dup


## 是否已有可实例化的缓存（点选热路径可跳过磁盘/解析）。
func has_cached(path: String) -> bool:
	return not path.is_empty() and (_packed_cache.has(path) or _scene_cache.has(path))


## 拿 _scene_cache 里的 proto（导出拼装时改 proto 再 bake；不暴露 Dict 内部）
func get_proto(path: String) -> Node3D:
	if _scene_cache.has(path):
		return _scene_cache[path] as Node3D
	return null


## 磁盘上是否已有旁路 .scn（与 GLB 同目录 / 旧 model-scenes / user 懒烘焙）。
func has_model_scene(path: String) -> bool:
	return not path.is_empty() and not RuntimeAssets.resolve_model_scene(path).is_empty()


## 丢掉某路径的内存缓存（不删磁盘 .scn）。
func evict(path: String) -> void:
	if path.is_empty():
		return
	if _scene_cache.has(path):
		var proto: Variant = _scene_cache[path]
		_scene_cache.erase(path)
		if proto is Node and is_instance_valid(proto):
			(proto as Node).free()
	_packed_cache.erase(path)
	_anim_flags.erase(path)
	_parts_cache.erase(path)
	_preloader.evict_bytes(path)


## 外部加载的 PackedScene（如 ResourceLoader 线程结果）写入缓存。
## 开图热路径：直接缓存，避免 instantiate→修材质→再 pack（大 .scn 可达数秒/个）。
## 材质修正仍在 instance_glb 时对实例做；geosetvis 依赖 bake 时已写入旁路 .scn。
func register_external_packed(glb_path: String, packed: PackedScene) -> void:
	if glb_path.is_empty() or packed == null:
		return
	_packed_cache[glb_path] = packed
	last_scn_hits += 1
	_preloader.complete(glb_path)


func _finish_gltf_preload(path: String) -> bool:
	_preloader.complete(path)
	var proto: Node3D = null
	# .gltf：必须走文件加载；bytes 路径会因非 GLB 魔数误入黑名单，永久粉胶囊
	if path.to_lower().ends_with(".gltf"):
		proto = _ensure_scene(path)
	else:
		var bytes: PackedByteArray = PackedByteArray()
		if _preloader.has_bytes_cached(path):
			bytes = _preloader.take_cached_bytes(path)
		if bytes.is_empty():
			return false
		proto = _ensure_scene_from_bytes(path, bytes)
	if proto == null:
		return false
	# 确保有 PackedScene 供后续 instance
	if not _packed_cache.has(path):
		var packed: PackedScene = PackedScene.new()
		if packed.pack(proto) == OK:
			_packed_cache[path] = packed
	return true


## Inspect 预览：只 ensure 场景 + duplicate，**不做 PackedScene.pack**（首次点选少一半主线程成本）。
## prefer_visuals=false：跳过 assets/visuals（导出 visuals 时避免套娃）。
func instance_glb_preview(
	path: String, prefer_visuals: bool = true, unit_soft_blend: bool = false
) -> Node3D:
	if path.is_empty():
		return null
	if prefer_visuals and _packed_cache.has(path):
		var packed: PackedScene = _packed_cache[path] as PackedScene
		var inst: Node = packed.instantiate()
		if inst is Node3D:
			Rules._mark_waterish_if_needed(inst as Node3D, path, unit_soft_blend)
			Rules._fix_wc3_blend_materials(inst as Node3D, unit_soft_blend)
			Geometry._sanitize_triangle_meshes(inst as Node3D)
			return inst as Node3D
		if inst != null:
			inst.free()
	var proto: Node3D = _ensure_scene(path, prefer_visuals)
	if proto == null:
		var disk_abs: String = RuntimeAssets.project_abs(path)
		var exists: bool = not disk_abs.is_empty() and FileAccess.file_exists(disk_abs)
		if not _warned_preview_fail.has(path):
			_warned_preview_fail[path] = true
			push_warning(
				"MapModelCache.instance_glb_preview failed: path=%s prefer_visuals=%s disk_abs=%s exists=%s"
				% [path, prefer_visuals, disk_abs, exists]
			)
		return null
	var dup: Node3D = proto.duplicate() as Node3D
	if dup != null:
		Rules._mark_waterish_if_needed(dup, path, unit_soft_blend)
		Rules._fix_wc3_blend_materials(dup, unit_soft_blend)
		Geometry._sanitize_triangle_meshes(dup)
	return dup


## 用已读字节灌入场景缓存并 duplicate（预览用，不 pack）。
func instance_glb_from_bytes_preview(path: String, bytes: PackedByteArray) -> Node3D:
	if path.is_empty() or bytes.is_empty():
		return null
	if has_cached(path):
		return instance_glb_preview(path)
	_preloader.store_bytes(path, bytes)
	var proto: Node3D = _ensure_scene_from_bytes(path, bytes)
	if proto == null:
		return null
	return proto.duplicate() as Node3D


## 用已读字节灌入缓存并实例化（地图层等需要 PackedScene 时用）。
func instance_glb_from_bytes(path: String, bytes: PackedByteArray) -> Node3D:
	if path.is_empty() or bytes.is_empty():
		return null
	if has_cached(path):
		return instance_glb(path)
	_preloader.store_bytes(path, bytes)
	var proto: Node3D = _ensure_scene_from_bytes(path, bytes)
	if proto == null:
		return null
	var packed: PackedScene = PackedScene.new()
	if packed.pack(proto) == OK:
		_packed_cache[path] = packed
		var inst: Node = packed.instantiate()
		if inst is Node3D:
			Rules._fix_wc3_blend_materials(inst as Node3D, false)
			return inst as Node3D
		if inst != null:
			inst.free()
	var dup: Node3D = proto.duplicate() as Node3D
	if dup != null:
		Rules._fix_wc3_blend_materials(dup, false)
	return dup


func _ensure_packed(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _packed_cache.has(path):
		return _packed_cache[path] as PackedScene
	# 经 _ensure_scene：注入 geosetvis 后再 pack，避免直接吃未补轨的 .scn
	var proto: Node3D = _ensure_scene(path)
	if proto == null:
		return null
	if _packed_cache.has(path):
		return _packed_cache[path] as PackedScene
	var packed: PackedScene = PackedScene.new()
	if packed.pack(proto) != OK:
		return null
	_packed_cache[path] = packed
	return packed


func _ensure_scene(path: String, prefer_visuals: bool = true) -> Node3D:
	if path.is_empty():
		return null
	if prefer_visuals and _scene_cache.has(path):
		return _scene_cache[path] as Node3D
	# prefer_visuals=false：export/bake 基座必须从 glTF 重读。
	# 若吃旧 .scn，表面 override 可能丢 _fm1 名，单位 soft 修复会失效并写回错误材质。
	if prefer_visuals:
		var from_scn: PackedScene = Assembly._try_load_scn_packed(path, true)
		if from_scn != null:
			var inst: Node = from_scn.instantiate()
			if inst is Node3D:
				return _register_loaded_scene(path, inst as Node3D, false)
			if inst != null:
				inst.free()
	var loaded: Node3D = RuntimeAssets.load_gltf_scene(path)
	if loaded == null:
		return null
	return _register_loaded_scene(path, loaded, true)


func _ensure_scene_from_bytes(path: String, bytes: PackedByteArray) -> Node3D:
	if path.is_empty() or bytes.is_empty():
		return null
	if _scene_cache.has(path):
		return _scene_cache[path] as Node3D
	# 已有 .scn 时忽略 bytes，直接吃烘焙
	var from_scn: PackedScene = Assembly._try_load_scn_packed(path)
	if from_scn != null:
		var inst: Node = from_scn.instantiate()
		if inst is Node3D:
			return _register_loaded_scene(path, inst as Node3D, false)
		if inst != null:
			inst.free()
	# JSON .gltf 禁止 append_from_buffer（外链 URI + 会误入 fail 黑名单）
	if path.to_lower().ends_with(".gltf"):
		var from_file: Node3D = RuntimeAssets.load_gltf_scene(path)
		return _register_loaded_scene(path, from_file, true)
	var loaded: Node3D = RuntimeAssets.load_gltf_scene_from_bytes(bytes, path)
	return _register_loaded_scene(path, loaded, true)


## from_gltf=true 时排队懒烘焙 .scn，供下次点选走 ResourceLoader。
func _register_loaded_scene(path: String, loaded: Node3D, from_gltf: bool = true) -> Node3D:
	if loaded == null:
		return null
	if from_gltf:
		last_gltf_loads += 1
	else:
		last_scn_hits += 1
	var logical: String = path.replace("\\", "/").trim_prefix("res://assets/asset-converted/")
	Rules._fix_wc3_blend_materials(loaded, Rules.glb_path_uses_unit_soft_blend(logical))
	Geometry._sanitize_triangle_meshes(loaded)
	# 原型上清掉 autoplay，避免实例化瞬间播 Attack
	var ap: AnimationPlayer = Queries._find_animation_player(loaded)
	if ap != null:
		ap.autoplay = ""
		ap.stop()
	Tracks._inject_geoset_vis_tracks(path, loaded)
	var has_anim: bool = Queries._scene_has_skeletal_stand(loaded)
	_anim_flags[path] = has_anim
	# 有 Stand 就按 :visible 定格（树=藏树桩）。勿用「是否骨骼 Stand」门闩：
	# 树 Stand 常几乎无 pos/rot 轨，旧逻辑会走 reveal，桩与活树同亮。
	var ap_snap: AnimationPlayer = Queries._find_animation_player(loaded)
	var stand_full: String = ""
	if ap_snap != null:
		stand_full = Queries._pick_stand_name(ap_snap)
	if not stand_full.is_empty():
		Pose._snap_geoset_visibility_pose(loaded, Queries._anim_leaf_name(stand_full))
	elif not has_anim:
		# 静物：GeosetAnim 在 rest 可能 scale=0，强制可见
		Pose._reveal_hidden_geosets(loaded)
	_scene_cache[path] = loaded
	var packed: PackedScene = PackedScene.new()
	if packed.pack(loaded) == OK:
		_packed_cache[path] = packed
	if from_gltf and RuntimeAssets.resolve_model_scene(path).is_empty():
		_enqueue_lazy_bake(path)
	return loaded


func _enqueue_lazy_bake(glb_path: String) -> void:
	if glb_path.is_empty():
		return
	for p: String in _lazy_bake_queue:
		if str(p) == glb_path:
			return
	_lazy_bake_queue.append(glb_path)


## 空闲时调用：把已解析 GLB 原型写入与 GLB 同目录 *.scn（失败则 user://）。
func process_lazy_bake_one() -> bool:
	if _lazy_bake_queue.is_empty():
		return false
	var glb_path: String = str(_lazy_bake_queue[0])
	_lazy_bake_queue.remove_at(0)
	return bake_model_scene(glb_path)


func bake_model_scene(glb_path: String, force: bool = false) -> bool:
	if glb_path.is_empty():
		return false
	if not force and not RuntimeAssets.resolve_model_scene(glb_path).is_empty():
		return true
	var proto: Node3D = null
	if _scene_cache.has(glb_path):
		proto = _scene_cache[glb_path] as Node3D
	if proto == null:
		return false
	var saved_path: String = Assembly._save_model_scene(proto, glb_path, _team)
	if not saved_path.is_empty():
		var packed: PackedScene = RuntimeAssets.load_packed_scene(saved_path)
		if packed != null:
			_packed_cache[glb_path] = packed
		return true
	return false


## bake 在 split Geoset→Group 之后调用：清掉旧 Geoset_N 轨，按 Group 节点重注。
func reinject_geoset_vis_tracks(glb_path: String) -> bool:
	if glb_path.is_empty() or not _scene_cache.has(glb_path):
		return false
	var root: Node = _scene_cache[glb_path] as Node
	if root == null:
		return false
	var ok: bool = Tracks._inject_geoset_vis_tracks(glb_path, root)
	if ok:
		var ap: AnimationPlayer = Queries._find_animation_player(root)
		if ap != null:
			var stand_full: String = Queries._pick_stand_name(ap)
			if not stand_full.is_empty():
				Pose._snap_geoset_visibility_pose(root, Queries._anim_leaf_name(stand_full))
		# 拆组后重注，需重 pack
		var packed: PackedScene = PackedScene.new()
		if packed.pack(root) == OK:
			_packed_cache[glb_path] = packed
	return ok


## GLB 是否含「会动」的循环骨骼动画（空 Stand / 仅 GeosetAnim 不算）
func glb_has_animation(path: String) -> bool:
	if path.is_empty():
		return false
	# 已知坏文件：跳过，避免引擎刷 Buffer 0 ERROR
	if _anim_flags.has(path):
		return bool(_anim_flags[path])
	var disk: String = RuntimeAssets.project_abs(path)
	if disk.is_empty() or not FileAccess.file_exists(disk):
		_anim_flags[path] = false
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(disk)
	if not RuntimeAssets.is_plausible_gltf_bytes(bytes):
		_anim_flags[path] = false
		return false
	_ensure_scene(path)
	# 解析失败时 _register_loaded_scene 不会写 flag，在此落盘避免反复打引擎 ERROR
	if not _anim_flags.has(path):
		_anim_flags[path] = false
	return bool(_anim_flags.get(path, false))


## GLB / 实例是否含可见网格（空壳 PE2-only GLB → false）。
func glb_has_mesh(path: String) -> bool:
	if path.is_empty():
		return false
	var parts: Array = mesh_parts_from_glb(path)
	return not parts.is_empty()


## 兼容旧调用：取第一个可见网格
func mesh_from_glb(path: String) -> Mesh:
	var parts: Array = mesh_parts_from_glb(path)
	if parts.is_empty():
		return null
	return parts[0]["mesh"] as Mesh


## 所有 Geoset 网格（含材质），供 MultiMesh 分片实例化
func mesh_parts_from_glb(path: String) -> Array:
	if path.is_empty():
		return []
	if _parts_cache.has(path):
		return _parts_cache[path]
	# 带动画模型不应抽静态网格；调用方应先 glb_has_animation
	var root: Node3D = instance_glb(path)
	if root == null:
		return []
	var parts: Array = []
	Geometry._collect_mesh_parts(root, parts)
	root.free()
	_parts_cache[path] = parts
	return parts


func apply_team_color(root: Node, color_index: int = 0, hide_team_glow: bool = false) -> void:
	_team.apply_team_color(root, color_index, hide_team_glow)
