class_name MapModelCache
extends RefCounted

## 运行时 GLB 场景 / Mesh 缓存，供单位与装饰层共用。

var _scene_cache: Dictionary = {}
## path → PackedScene（避免每次 instance_glb 都 pack）
var _packed_cache: Dictionary = {}
## path → bool（是否含 AnimationPlayer 动画）
var _anim_flags: Dictionary = {}
## path → Array[{ "mesh": Mesh, "material": Material }]
var _parts_cache: Dictionary = {}
## owner_id → TeamColor Texture2D
var _team_color_tex: Dictionary = {}
## bake .scn 时写入的默认队伍色（0 = TeamColor00 红）；运行时仍按 owner 重染
const DEFAULT_BAKE_TEAM_COLOR := 0
## path → PackedByteArray（空闲预读；点选可跳过磁盘 IO）
var _bytes_cache: Dictionary = {}
## GLB 解析后待懒烘焙为 .scn 的队列
var _lazy_bake_queue: PackedStringArray = PackedStringArray()
## 后台预载：path → { kind, scn_path|holder|task_id }
var _preload: Dictionary = {}
## 开图统计：.scn 命中 / 同步 GLTF 解析 / 内存缓存命中
var last_scn_hits: int = 0
var last_gltf_loads: int = 0
var last_cache_hits: int = 0
var _warned_preview_fail: Dictionary = {}


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
		var inst := packed.instantiate()
		if inst is Node3D:
			if sanitize:
				_stamp_glb_model_meta(inst as Node3D, path, unit_soft_blend)
				_mark_waterish_if_needed(inst as Node3D, path, unit_soft_blend)
				_fix_wc3_blend_materials(inst as Node3D, unit_soft_blend)
				_sanitize_triangle_meshes(inst as Node3D)
			return inst as Node3D
		if inst != null:
			inst.free()
	var proto := _ensure_scene(path)
	if proto == null:
		return null
	var dup := proto.duplicate() as Node3D
	if dup != null and sanitize:
		_stamp_glb_model_meta(dup, path, unit_soft_blend)
		_mark_waterish_if_needed(dup, path, unit_soft_blend)
		_fix_wc3_blend_materials(dup, unit_soft_blend)
		_sanitize_triangle_meshes(dup)
	return dup


func _stamp_glb_model_meta(root: Node3D, path: String, unit_soft_blend: bool) -> void:
	if root == null or path.is_empty():
		return
	var logical := path.replace("\\", "/").trim_prefix("res://assets/asset-converted/")
	root.set_meta("wc3_glb_logical", logical)
	if unit_soft_blend and glb_path_uses_unit_soft_blend(logical):
		root.set_meta("wc3_unit_model", true)


func _mark_waterish_if_needed(root: Node, path: String, unit_soft_blend: bool) -> void:
	if root == null or not unit_soft_blend:
		return
	var logical := path.replace("\\", "/").to_lower()
	if logical.contains("water"):
		root.set_meta("wc3_waterish_model", true)


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
	_bytes_cache.erase(path)


## 外部加载的 PackedScene（如 ResourceLoader 线程结果）写入缓存。
## 开图热路径：直接缓存，避免 instantiate→修材质→再 pack（大 .scn 可达数秒/个）。
## 材质修正仍在 instance_glb 时对实例做；geosetvis 依赖 bake 时已写入旁路 .scn。
func register_external_packed(glb_path: String, packed: PackedScene) -> void:
	if glb_path.is_empty() or packed == null:
		return
	_packed_cache[glb_path] = packed
	last_scn_hits += 1
	_preload.erase(glb_path)


## 批量请求后台预载（.scn 走 ResourceLoader 线程；无 .scn 则 Worker 读 GLB 字节）。
func request_preload_many(paths: PackedStringArray) -> void:
	for p in paths:
		request_preload(str(p))


func request_preload(glb_path: String) -> void:
	var path := glb_path.strip_edges()
	if path.is_empty() or has_cached(path) or _preload.has(path):
		return
	var scn_path := RuntimeAssets.resolve_model_scene(path)
	if not scn_path.is_empty():
		var err := ResourceLoader.load_threaded_request(scn_path, "PackedScene", true)
		# OK / ERR_BUSY（已在加载）均可轮询
		if err == OK or err == ERR_BUSY:
			_preload[path] = {"kind": "scn", "scn_path": scn_path}
			return
	# JSON .gltf 必须主线程 append_from_file（外链贴图）；勿读字节走 GLB 校验
	if path.to_lower().ends_with(".gltf"):
		_preload[path] = {"kind": "gltf_pending"}
		return
	_start_bytes_preload(path)


func is_preload_pending(glb_path: String) -> bool:
	return not glb_path.is_empty() and _preload.has(glb_path)


func preload_pending_count() -> int:
	return _preload.size()


func cancel_preloads() -> void:
	_preload.clear()


## 主线程每帧调用：收割线程结果；gltf_budget=本帧最多解析几个无 .scn 的 GLB。
## 返回本帧新写入缓存的路径数。
func poll_preloads(gltf_budget: int = 1) -> int:
	if _preload.is_empty():
		return 0
	var newly: int = 0
	var gltf_left: int = maxi(gltf_budget, 0)
	var paths: Array = _preload.keys()
	for path_v in paths:
		var path := str(path_v)
		if has_cached(path):
			_preload.erase(path)
			newly += 1
			continue
		var info: Dictionary = _preload[path]
		var kind := str(info.get("kind", ""))
		match kind:
			"scn":
				newly += _poll_scn_preload(path, info)
			"bytes":
				_poll_bytes_preload(path, info)
			"gltf_pending":
				if gltf_left <= 0:
					continue
				if _finish_gltf_preload(path):
					gltf_left -= 1
					newly += 1
			_:
				_preload.erase(path)
	return newly


func _start_bytes_preload(path: String) -> void:
	var disk_path := RuntimeAssets.project_abs(path)
	var holder := {"bytes": PackedByteArray(), "done": false, "ok": false}
	WorkerThreadPool.add_task(
		func() -> void:
			if FileAccess.file_exists(disk_path):
				var b := FileAccess.get_file_as_bytes(disk_path)
				holder["bytes"] = b
				holder["ok"] = not b.is_empty()
			holder["done"] = true
	)
	_preload[path] = {"kind": "bytes", "holder": holder}


func _poll_scn_preload(path: String, info: Dictionary) -> int:
	var scn_path := str(info.get("scn_path", ""))
	if scn_path.is_empty():
		_preload.erase(path)
		_start_bytes_preload(path)
		return 0
	var status := ResourceLoader.load_threaded_get_status(scn_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return 0
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var res: Resource = ResourceLoader.load_threaded_get(scn_path)
		if res is PackedScene:
			register_external_packed(path, res as PackedScene)
			return 1
		_preload.erase(path)
		_start_bytes_preload(path)
		return 0
	# FAILED / INVALID → 回退读 GLB
	_preload.erase(path)
	_start_bytes_preload(path)
	return 0


func _poll_bytes_preload(path: String, info: Dictionary) -> void:
	var holder: Variant = info.get("holder", null)
	if typeof(holder) != TYPE_DICTIONARY:
		_preload.erase(path)
		return
	var h: Dictionary = holder
	if not bool(h.get("done", false)):
		return
	if bool(h.get("ok", false)):
		store_bytes(path, h.get("bytes", PackedByteArray()) as PackedByteArray)
		info["kind"] = "gltf_pending"
		_preload[path] = info
	else:
		_preload.erase(path)


func _finish_gltf_preload(path: String) -> bool:
	_preload.erase(path)
	var proto: Node3D = null
	# .gltf：必须走文件加载；bytes 路径会因非 GLB 魔数误入黑名单，永久粉胶囊
	if path.to_lower().ends_with(".gltf"):
		proto = _ensure_scene(path)
	else:
		var bytes: PackedByteArray = PackedByteArray()
		if _bytes_cache.has(path):
			bytes = _bytes_cache[path] as PackedByteArray
		if bytes.is_empty():
			return false
		proto = _ensure_scene_from_bytes(path, bytes)
	if proto == null:
		return false
	# 确保有 PackedScene 供后续 instance
	if not _packed_cache.has(path):
		var packed := PackedScene.new()
		if packed.pack(proto) == OK:
			_packed_cache[path] = packed
	return true


func has_bytes_cached(path: String) -> bool:
	return not path.is_empty() and _bytes_cache.has(path)


func store_bytes(path: String, bytes: PackedByteArray) -> void:
	if path.is_empty() or bytes.is_empty():
		return
	_bytes_cache[path] = bytes


func take_cached_bytes(path: String) -> PackedByteArray:
	if path.is_empty() or not _bytes_cache.has(path):
		return PackedByteArray()
	return _bytes_cache[path] as PackedByteArray


## Inspect 预览：只 ensure 场景 + duplicate，**不做 PackedScene.pack**（首次点选少一半主线程成本）。
## prefer_visuals=false：跳过 assets/visuals（导出 visuals 时避免套娃）。
func instance_glb_preview(
	path: String, prefer_visuals: bool = true, unit_soft_blend: bool = false
) -> Node3D:
	if path.is_empty():
		return null
	if prefer_visuals and _packed_cache.has(path):
		var packed: PackedScene = _packed_cache[path] as PackedScene
		var inst := packed.instantiate()
		if inst is Node3D:
			_mark_waterish_if_needed(inst as Node3D, path, unit_soft_blend)
			_fix_wc3_blend_materials(inst as Node3D, unit_soft_blend)
			_sanitize_triangle_meshes(inst as Node3D)
			return inst as Node3D
		if inst != null:
			inst.free()
	var proto := _ensure_scene(path, prefer_visuals)
	if proto == null:
		var disk_abs := RuntimeAssets.project_abs(path)
		var exists := not disk_abs.is_empty() and FileAccess.file_exists(disk_abs)
		if not _warned_preview_fail.has(path):
			_warned_preview_fail[path] = true
			push_warning(
				"MapModelCache.instance_glb_preview failed: path=%s prefer_visuals=%s disk_abs=%s exists=%s"
				% [path, prefer_visuals, disk_abs, exists]
			)
		return null
	var dup := proto.duplicate() as Node3D
	if dup != null:
		_mark_waterish_if_needed(dup, path, unit_soft_blend)
		_fix_wc3_blend_materials(dup, unit_soft_blend)
		_sanitize_triangle_meshes(dup)
	return dup


## 烘焙 .scn 时无 typeId：Units/ 下非建筑目录名 → 单位软混合（fm2 保留 alpha）。
static func glb_path_uses_unit_soft_blend(logical_path: String) -> bool:
	var p := logical_path.replace("\\", "/").strip_edges().to_lower()
	if not p.begins_with("units/"):
		return false
	const BUILDING_MARKERS: Array[String] = [
		"townhall", "greathall", "stronghold", "fortress", "hall",
		"barracks", "altar", "blacksmith", "workshop", "arcanevault",
		"sanctuary", "tavern", "market", "guild", "tower", "temple",
		"crypt", "slaughterhouse", "beastiary", "goldmine", "mine",
		"farm", "house", "keep", "castle", "lumbermill", "mill",
		"foundry", "vault", "armory", "arcane", "shipyard", "foundry",
		"spirit", "lodge", "den", "voodoo", "troll", "hatchery",
		"spawning", "cannibal", "burrow", "ziggurat", "necropolis",
		"crypt", "slaughter", "temple", "treeoflife", "ancient",
		"hunters", "chimaera", "moonwell", "altarof", "huntershall",
	]
	for m in BUILDING_MARKERS:
		if p.contains("/%s" % m) or p.ends_with("/%s" % m):
			return false
	return true


## 用已读字节灌入场景缓存并 duplicate（预览用，不 pack）。
func instance_glb_from_bytes_preview(path: String, bytes: PackedByteArray) -> Node3D:
	if path.is_empty() or bytes.is_empty():
		return null
	if has_cached(path):
		return instance_glb_preview(path)
	store_bytes(path, bytes)
	var proto := _ensure_scene_from_bytes(path, bytes)
	if proto == null:
		return null
	return proto.duplicate() as Node3D


## 用已读字节灌入缓存并实例化（地图层等需要 PackedScene 时用）。
func instance_glb_from_bytes(path: String, bytes: PackedByteArray) -> Node3D:
	if path.is_empty() or bytes.is_empty():
		return null
	if has_cached(path):
		return instance_glb(path)
	store_bytes(path, bytes)
	var proto := _ensure_scene_from_bytes(path, bytes)
	if proto == null:
		return null
	var packed := PackedScene.new()
	if packed.pack(proto) == OK:
		_packed_cache[path] = packed
		var inst := packed.instantiate()
		if inst is Node3D:
			_fix_wc3_blend_materials(inst as Node3D, false)
			return inst as Node3D
		if inst != null:
			inst.free()
	var dup := proto.duplicate() as Node3D
	if dup != null:
		_fix_wc3_blend_materials(dup, false)
	return dup


func _ensure_packed(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _packed_cache.has(path):
		return _packed_cache[path] as PackedScene
	# 经 _ensure_scene：注入 geosetvis 后再 pack，避免直接吃未补轨的 .scn
	var proto := _ensure_scene(path)
	if proto == null:
		return null
	if _packed_cache.has(path):
		return _packed_cache[path] as PackedScene
	var packed := PackedScene.new()
	if packed.pack(proto) != OK:
		return null
	_packed_cache[path] = packed
	return packed


func _try_load_scn_packed(glb_path: String, prefer_visuals: bool = true) -> PackedScene:
	# visuals/*.tscn 常 ExtResource pe2.tscn（贴图在 .gdignore），ResourceLoader 会刷屏失败。
	# 优先：同目录 .scn + pe2.json 运行时组装（等价 visuals 配方，无 ExtResource）。
	if prefer_visuals:
		var vis_path := RuntimeAssets.resolve_visual_scene(glb_path)
		if not vis_path.is_empty():
			var composed := _compose_visual_packed(glb_path)
			if composed != null:
				return composed
	var scn_path := RuntimeAssets.resolve_model_scene(glb_path)
	if scn_path.is_empty():
		return null
	return RuntimeAssets.load_packed_scene(scn_path)


## 磁盘上有 visuals/*.tscn 但 ResourceLoader 拉不下 gdignore 基座时：scn + PE2 + sync。
func _compose_visual_packed(glb_path: String) -> PackedScene:
	var scn_path := RuntimeAssets.resolve_model_scene(glb_path)
	if scn_path.is_empty():
		return null
	var base := RuntimeAssets.load_packed_scene(scn_path)
	if base == null:
		return null
	var root_n := base.instantiate()
	if root_n == null or not (root_n is Node3D):
		if root_n:
			root_n.free()
		return null
	var root := root_n as Node3D
	var logical := glb_path.replace("\\", "/").trim_prefix("res://assets/asset-converted/")
	_fix_wc3_blend_materials(root, glb_path_uses_unit_soft_blend(logical))
	var ap := _find_animation_player(root)
	if ap != null:
		ap.autoplay = ""
		ap.stop()
		const _Anim := preload("res://scripts/presentation/wc3_model/wc3_anim_player.gd")
		if ap.get_script() != _Anim:
			ap.set_script(_Anim)
	_inject_geoset_vis_tracks(glb_path, root)
	const _Pe2 := preload("res://scripts/map/presentation/effects/wc3_pe2_particles.gd")
	const _Model := preload("res://scripts/presentation/wc3_model/wc3_model_scene.gd")
	if _Pe2.has_emitters(glb_path):
		_Pe2.attach_to(root, glb_path)
	# PE2 就位后再剪悬空轨（含旧 bake 写进 Stand 的 Death-only :emitting）
	if ap != null and ap.has_method("prune_unresolved_tracks"):
		ap.call("prune_unresolved_tracks")
	root.set_script(_Model)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return null
	root.free()
	return packed


func _ensure_scene(path: String, prefer_visuals: bool = true) -> Node3D:
	if path.is_empty():
		return null
	if prefer_visuals and _scene_cache.has(path):
		return _scene_cache[path] as Node3D
	# prefer_visuals=false：export/bake 基座必须从 glTF 重读。
	# 若吃旧 .scn，表面 override 可能丢 _fm1 名，单位 soft 修复会失效并写回错误材质。
	if prefer_visuals:
		var from_scn := _try_load_scn_packed(path, true)
		if from_scn != null:
			var inst := from_scn.instantiate()
			if inst is Node3D:
				return _register_loaded_scene(path, inst as Node3D, false)
			if inst != null:
				inst.free()
	var loaded := RuntimeAssets.load_gltf_scene(path)
	if loaded == null:
		return null
	return _register_loaded_scene(path, loaded, true)


func _ensure_scene_from_bytes(path: String, bytes: PackedByteArray) -> Node3D:
	if path.is_empty() or bytes.is_empty():
		return null
	if _scene_cache.has(path):
		return _scene_cache[path] as Node3D
	# 已有 .scn 时忽略 bytes，直接吃烘焙
	var from_scn := _try_load_scn_packed(path)
	if from_scn != null:
		var inst := from_scn.instantiate()
		if inst is Node3D:
			return _register_loaded_scene(path, inst as Node3D, false)
		if inst != null:
			inst.free()
	# JSON .gltf 禁止 append_from_buffer（外链 URI + 会误入 fail 黑名单）
	if path.to_lower().ends_with(".gltf"):
		var from_file := RuntimeAssets.load_gltf_scene(path)
		return _register_loaded_scene(path, from_file, true)
	var loaded := RuntimeAssets.load_gltf_scene_from_bytes(bytes, path)
	return _register_loaded_scene(path, loaded, true)


## from_gltf=true 时排队懒烘焙 .scn，供下次点选走 ResourceLoader。
func _register_loaded_scene(path: String, loaded: Node3D, from_gltf: bool = true) -> Node3D:
	if loaded == null:
		return null
	if from_gltf:
		last_gltf_loads += 1
	else:
		last_scn_hits += 1
	var logical := path.replace("\\", "/").trim_prefix("res://assets/asset-converted/")
	_fix_wc3_blend_materials(loaded, glb_path_uses_unit_soft_blend(logical))
	_sanitize_triangle_meshes(loaded)
	# 原型上清掉 autoplay，避免实例化瞬间播 Attack
	var ap := _find_animation_player(loaded)
	if ap != null:
		ap.autoplay = ""
		ap.stop()
	_inject_geoset_vis_tracks(path, loaded)
	var has_anim := _scene_has_skeletal_stand(loaded)
	_anim_flags[path] = has_anim
	# 有 Stand 就按 :visible 定格（树=藏树桩）。勿用「是否骨骼 Stand」门闩：
	# 树 Stand 常几乎无 pos/rot 轨，旧逻辑会走 reveal，桩与活树同亮。
	var ap_snap := _find_animation_player(loaded)
	var stand_full := ""
	if ap_snap != null:
		stand_full = _pick_stand_name(ap_snap)
	if not stand_full.is_empty():
		_snap_geoset_visibility_pose(loaded, _anim_leaf_name(stand_full))
	elif not has_anim:
		# 静物：GeosetAnim 在 rest 可能 scale=0，强制可见
		_reveal_hidden_geosets(loaded)
	_scene_cache[path] = loaded
	var packed := PackedScene.new()
	if packed.pack(loaded) == OK:
		_packed_cache[path] = packed
	if from_gltf and RuntimeAssets.resolve_model_scene(path).is_empty():
		_enqueue_lazy_bake(path)
	return loaded


## 按指定动画 at_time 的 :visible 轨立刻设 Geoset 显隐（不依赖正在播放）。
func _node_visual_aabb(root: Node3D) -> AABB:
	if root == null:
		return AABB()
	var aabb := AABB()
	var first := true
	for c in root.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var la := vi.get_aabb()
		# 离树时没有 global_transform；用相对 root 的局部累积。
		var xf := _xform_to_ancestor(vi, root)
		for i in range(8):
			var corner := la.position + la.size * Vector3(
				float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1)
			)
			var p := xf * corner
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb


## node 相对 ancestor 的 Transform（含中间父链；ancestor 不含自身）。
func _xform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _snap_geoset_visibility_pose(
	root: Node, anim_name: String, at_time: float = 0.0, hide_zero_scale: bool = true
) -> void:
	var ap := _find_animation_player(root)
	if ap == null:
		return
	var resolved := _resolve_animation_name(ap, anim_name)
	if resolved.is_empty():
		return
	var anim := ap.get_animation(resolved)
	if anim == null:
		return
	var anim_root: Node = ap.get_node_or_null(ap.root_node)
	if anim_root == null:
		anim_root = ap.get_parent()
	if anim_root == null:
		return
	var any_vis_track := false
	for i in anim.get_track_count():
		var tpath := anim.track_get_path(i)
		var ps := str(tpath)
		if not ps.contains("Geoset_"):
			continue
		if anim.track_get_key_count(i) <= 0:
			continue
		var target: Node3D = null
		if ps.ends_with(":visible"):
			any_vis_track = true
			var vis := _track_bool_at(anim, i, at_time)
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


func _geoset_node_from_track(anim_root: Node, tpath: NodePath) -> Node3D:
	if anim_root == null:
		return null
	var ps := str(tpath)
	for suffix in [":visible", ":modulate"]:
		if ps.ends_with(suffix):
			ps = ps.substr(0, ps.length() - suffix.length())
			break
	var n := anim_root.get_node_or_null(NodePath(ps))
	if n is Node3D:
		return n as Node3D
	var leaf := ps.get_file()
	if leaf.is_empty():
		leaf = ps
	if leaf.contains("/"):
		leaf = leaf.substr(leaf.rfind("/") + 1)
	var found := anim_root.find_child(leaf, true, false)
	if found is Node3D:
		return found as Node3D
	return null


func _track_bool_at(anim: Animation, track_i: int, time_sec: float) -> bool:
	var n := anim.track_get_key_count(track_i)
	if n <= 0:
		return true
	var vis := bool(anim.track_get_key_value(track_i, 0))
	for k in range(n):
		if anim.track_get_key_time(track_i, k) <= time_sec + 0.0001:
			vis = bool(anim.track_get_key_value(track_i, k))
		else:
			break
	return vis


func _track_color_at(anim: Animation, track_i: int, time_sec: float) -> Color:
	var n := anim.track_get_key_count(track_i)
	if n <= 0:
		return Color.WHITE
	var col: Color = anim.track_get_key_value(track_i, 0)
	for k in range(n):
		if anim.track_get_key_time(track_i, k) <= time_sec + 0.0001:
			col = anim.track_get_key_value(track_i, k)
		else:
			break
	return col


## AnimationPlayer 动画名解析：精确 → 叶名大小写不敏感 → 驼峰/去空格 → 库前缀。
func _resolve_animation_name(ap: AnimationPlayer, anim_name: String) -> String:
	if ap == null or anim_name.is_empty():
		return ""
	if ap.has_animation(anim_name):
		return anim_name
	var want := _anim_leaf_name(anim_name).to_lower()
	var want_c := AnimPlayback.compact_seq_name(anim_name)
	for n in ap.get_animation_list():
		var full := str(n)
		var leaf := _anim_leaf_name(full)
		if leaf.to_lower() == want:
			return full
		if AnimPlayback.compact_seq_name(full) == want_c:
			return full
	return ""


func _hide_zero_scale_geosets(root: Node) -> void:
	if root == null:
		return
	# 旧路径：Geoset_N MeshInstance scale=0
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var nm := str(mi.name)
		if not nm.begins_with("Geoset_"):
			continue
		if mi.scale.length_squared() < 1e-8:
			mi.visible = false
	# 可选拆组：Geoset_N_Group_* BoneAttachment（无 scale 轨，靠 visible）
	for c in root.find_children("*", "BoneAttachment3D", true, false):
		var ba := c as BoneAttachment3D
		if ba == null:
			continue
		var nm2 := _strip_ba_geoset_prefix(str(ba.name))
		if not nm2.begins_with("Geoset_") or not nm2.contains("_Group_"):
			continue
		if ba.scale.length_squared() < 1e-8:
			ba.visible = false


func _enqueue_lazy_bake(glb_path: String) -> void:
	if glb_path.is_empty():
		return
	for p in _lazy_bake_queue:
		if str(p) == glb_path:
			return
	_lazy_bake_queue.append(glb_path)


## 空闲时调用：把已解析 GLB 原型写入与 GLB 同目录 *.scn（失败则 user://）。
func process_lazy_bake_one() -> bool:
	if _lazy_bake_queue.is_empty():
		return false
	var glb_path := str(_lazy_bake_queue[0])
	_lazy_bake_queue.remove_at(0)
	return bake_model_scene(glb_path)


## 将缓存中的原型打包为 .scn（优先写 asset-converted 同目录，失败则 user://）。
## force=true 时覆盖已有旁路 .scn（export --force / 补 geosetvis 轨后重烤）。
## 打包前套默认队伍色（TeamColor00），便于编辑器直接打开 .scn 即见染色；游戏侧仍会按 owner 重染。
## 旁路 JSON：优先与 glTF 同目录（含 tmp 拷贝），否则 asset-converted。
static func _resolve_bone_rest_disk(glb_path: String) -> String:
	var side := glb_path.replace("\\", "/")
	var rest_rel := ""
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
	for disk in candidates:
		if not disk.is_empty() and FileAccess.file_exists(disk):
			return disk
	return ""


## Stand 绑定 TRS → 骨 rest（pose 保持 I）。骑士 T-pose 顶点 × rest 才是坐姿；
## 不要 set_bone_pose_position：那会 rest*pose 叠两次。IBM 必须是单位阵。
static func apply_bone_rest_sidecar(proto: Node, glb_path: String) -> void:
	if proto == null or glb_path.is_empty():
		return
	var disk := _resolve_bone_rest_disk(glb_path)
	if disk.is_empty():
		return
	var raw := RuntimeAssets.read_utf8_text(disk)
	if raw.is_empty():
		return
	var parsed: Variant = RuntimeAssets.parse_json_text(raw)
	if not parsed is Dictionary:
		return
	var bones: Array = parsed.get("bones", [])
	var skeleton: Skeleton3D = null
	for c in proto.find_children("*", "Skeleton3D", true, false):
		if c is Skeleton3D:
			skeleton = c as Skeleton3D
			break
	if skeleton == null:
		return
	var updated_bi: Array[int] = []
	for entry in bones:
		var nm := str(entry.get("name", ""))
		if nm.is_empty():
			continue
		var bi := skeleton.find_bone(nm)
		if bi < 0:
			continue
		var t: Variant = entry.get("translation", [])
		var pos := Vector3.ZERO
		if t is Array and t.size() >= 3:
			pos = Vector3(float(t[0]), float(t[1]), float(t[2]))
		var rot: Variant = entry.get("rotation", [])
		var q := Quaternion.IDENTITY
		if rot is Array and rot.size() >= 4:
			q = Quaternion(float(rot[0]), float(rot[1]), float(rot[2]), float(rot[3]))
		var sc: Variant = entry.get("scale", [])
		var basis := Basis(q)
		if sc is Array and sc.size() >= 3:
			basis = basis.scaled(Vector3(float(sc[0]), float(sc[1]), float(sc[2])))
		skeleton.set_bone_rest(bi, Transform3D(basis, pos))
		skeleton.reset_bone_pose(bi)
		updated_bi.append(bi)
	if not updated_bi.is_empty():
		skeleton.force_update_all_bone_transforms()
	for c in proto.find_children("*", "BoneAttachment3D", true, false):
		if c is BoneAttachment3D:
			var ba := c as BoneAttachment3D
			if not ba.bone_name.is_empty():
				var idx2 := skeleton.find_bone(ba.bone_name)
				if idx2 >= 0 and ba.get_bone_idx() != idx2:
					ba.set_bone_idx(idx2)


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
	# 材质修正必须进 .scn：编辑器直接打开 scn 不会再走 instance_glb 修正。
	# （export 里 instance_glb_preview 修的是临时 dup，bake 烤的是 proto。）
	var logical := glb_path.replace("\\", "/").trim_prefix("res://assets/asset-converted/")
	var unit_soft := glb_path_uses_unit_soft_blend(logical)
	if unit_soft and logical.to_lower().contains("water"):
		proto.set_meta("wc3_waterish_model", true)
	_stamp_glb_model_meta(proto, glb_path, unit_soft)
	_fix_wc3_blend_materials(proto, unit_soft)
	# 飞弹/技能特效：语义 present（软球 / 广告牌）；PE2 已由 pe2 bake 写入
	if FireballMissileModern.wants(logical, proto):
		FireballMissileModern.apply(proto)
		proto.set_meta("wc3_fx_scaled", true)
	elif Wc3FxPresenter.path_wants_fx_present(logical):
		Wc3FxPresenter.present(proto)
		Wc3FxPresenter.maybe_apply_plan_b(proto, logical)
		proto.set_meta("wc3_fx_scaled", true)
	Wc3MdxOmni.snap_all(proto)
	apply_bone_rest_sidecar(proto, glb_path)
	apply_team_color(proto, DEFAULT_BAKE_TEAM_COLOR, false)
	# 门面脚本必须在 pack 直前挂上（export 里 set_script 曾未写入 .scn）
	_ensure_model_scene_scripts(proto)
	var res_p := RuntimeAssets.model_scene_path(glb_path)
	var user_p := RuntimeAssets.model_scene_user_path(glb_path)
	var saved_path := ""
	var err := RuntimeAssets.save_packed_scene(proto, res_p)
	if err == OK:
		saved_path = res_p
	else:
		err = RuntimeAssets.save_packed_scene(proto, user_p)
		if err == OK:
			saved_path = user_p
	if err == OK and not saved_path.is_empty():
		var packed := RuntimeAssets.load_packed_scene(saved_path)
		if packed != null:
			_packed_cache[glb_path] = packed
		return true
	return false


## bake 直前：根挂 Wc3ModelScene，AP 挂 Wc3AnimPlayer。
func _ensure_model_scene_scripts(root: Node) -> void:
	if root == null:
		return
	const _Model := preload("res://scripts/presentation/wc3_model/wc3_model_scene.gd")
	const _Anim := preload("res://scripts/presentation/wc3_model/wc3_anim_player.gd")
	if root.get_script() != _Model:
		root.set_script(_Model)
	var ap := _find_animation_player(root)
	if ap != null and ap.get_script() != _Anim:
		ap.set_script(_Anim)


## Godot 导入丢弃蒙皮 Geoset / 空父节点上的 scale 轨；用旁路 *.geosetvis.json 补 `:visible`。
func _inject_geoset_vis_tracks(glb_path: String, root: Node) -> bool:
	if root == null or glb_path.is_empty():
		return false
	var json_res := _geoset_vis_json_path(glb_path)
	if json_res.is_empty() or not RuntimeAssets.file_exists(json_res):
		return false
	var disk := RuntimeAssets.project_abs(json_res)
	var text := RuntimeAssets.read_utf8_text(disk)
	if text.is_empty():
		return false
	var data: Variant = RuntimeAssets.parse_json_text(text)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var sequences: Variant = (data as Dictionary).get("sequences", [])
	if typeof(sequences) != TYPE_ARRAY or (sequences as Array).is_empty():
		return false
	var ap := _find_animation_player(root)
	if ap == null:
		return false
	var anim_root: Node = ap.get_node_or_null(ap.root_node)
	if anim_root == null:
		anim_root = ap.get_parent()
	if anim_root == null:
		return false
	var geoset_nodes := _index_geoset_meshes(root)
	if geoset_nodes.is_empty():
		return false
	var injected := false
	for seq_v in sequences as Array:
		if typeof(seq_v) != TYPE_DICTIONARY:
			continue
		var seq: Dictionary = seq_v
		var anim_name := str(seq.get("name", "")).strip_edges()
		if anim_name.is_empty():
			continue
		# geosetvis 与 Godot 动画名可能大小写不一致（stand vs Stand）
		var resolved := _resolve_animation_name(ap, anim_name)
		if resolved.is_empty():
			continue
		var anim := ap.get_animation(resolved)
		if anim == null:
			continue
		_remove_geoset_presentation_tracks(anim)
		var geosets: Variant = seq.get("geosets", {})
		if typeof(geosets) != TYPE_DICTIONARY:
			continue
		for gi_key in (geosets as Dictionary).keys():
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
			for mesh_n_v in targets:
				if not (mesh_n_v is Node):
					continue
				var mesh_n: Node = mesh_n_v
				# 轨路径相对 AnimationPlayer.root_node（默认 ..），不是相对 AP 自身
				if anim_root == null or not _nodes_share_tree(anim_root, mesh_n):
					continue
				var rel := anim_root.get_path_to(mesh_n)
				if str(rel).is_empty() or str(rel) == ".":
					continue
				var track_path := NodePath("%s:visible" % str(rel))
				var ti := anim.add_track(Animation.TYPE_VALUE)
				anim.track_set_path(ti, track_path)
				anim.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)
				anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_NEAREST)
				var mod_path := NodePath("%s:modulate" % str(rel))
				var ti_mod := anim.add_track(Animation.TYPE_VALUE)
				anim.track_set_path(ti_mod, mod_path)
				anim.value_track_set_update_mode(ti_mod, Animation.UPDATE_CONTINUOUS)
				anim.track_set_interpolation_type(ti_mod, Animation.INTERPOLATION_LINEAR)
				var need_modulate := false
				for key_v in keys_v as Array:
					if typeof(key_v) != TYPE_DICTIONARY:
						continue
					var kd: Dictionary = key_v
					var t := float(kd.get("t", 0.0))
					var alpha := float(kd.get("alpha", -1.0))
					if alpha < 0.0:
						alpha = 1.0 if int(kd.get("v", 1)) != 0 else 0.0
					var vis := alpha > 0.004
					anim.track_insert_key(ti, t, vis)
					anim.track_insert_key(ti_mod, t, Color(1.0, 1.0, 1.0, alpha))
					if alpha > 0.004 and alpha < 0.996:
						need_modulate = true
				if not need_modulate:
					anim.remove_track(ti_mod)
				injected = true
	return injected


## bake 在 split Geoset→Group 之后调用：清掉旧 Geoset_N 轨，按 Group 节点重注。
func reinject_geoset_vis_tracks(glb_path: String) -> bool:
	if glb_path.is_empty() or not _scene_cache.has(glb_path):
		return false
	var root := _scene_cache[glb_path] as Node
	if root == null:
		return false
	var ok := _inject_geoset_vis_tracks(glb_path, root)
	if ok:
		var ap := _find_animation_player(root)
		if ap != null:
			var stand_full := _pick_stand_name(ap)
			if not stand_full.is_empty():
				_snap_geoset_visibility_pose(root, _anim_leaf_name(stand_full))
		# 拆组后重注，需重 pack
		var packed := PackedScene.new()
		if packed.pack(root) == OK:
			_packed_cache[glb_path] = packed
	return ok


func _geoset_vis_json_path(glb_path: String) -> String:
	var logical := RuntimeAssets.relative_or_res_to_logical(glb_path)
	var lower := logical.to_lower()
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
func _index_geoset_meshes(root: Node) -> Dictionary:
	var out: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var nm := _strip_ba_geoset_prefix(str(n.name))
		if not nm.begins_with("Geoset_"):
			continue
		var rest := nm.substr("Geoset_".length())
		var gi_str := ""
		if rest.is_valid_int():
			# Geoset_12
			gi_str = rest
		else:
			# Geoset_12_Group_0
			var gpos := rest.find("_Group_")
			if gpos > 0:
				var head := rest.substr(0, gpos)
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


func _strip_ba_geoset_prefix(nm: String) -> String:
	if nm.begins_with("BA_"):
		return nm.substr(3)
	return nm


func _remove_geoset_presentation_tracks(anim: Animation) -> void:
	for i in range(anim.get_track_count() - 1, -1, -1):
		var p := str(anim.track_get_path(i))
		if not p.contains("Geoset_"):
			continue
		if p.ends_with(":visible") or p.ends_with(":modulate"):
			anim.remove_track(i)


func _remove_geoset_visible_tracks(anim: Animation) -> void:
	_remove_geoset_presentation_tracks(anim)


## 把 replaceable 队伍色占位贴图换成 TeamColorXX（对齐 WE / HiveWE 预览染色）。
## color_index: 0..15（TeamColor 序号）。中立建筑常由 unitUI.teamColor 固定为 0（红），
## 与地图 owner（如 15 Neutral Passive）无关。
## hide_team_glow：兼容旧调用；有正确 TeamGlow 贴图后默认不再隐藏英雄光晕。
## 仍隐藏预览不该出现的 UberSplat / Death 烟雾 / Portrait BackGround geoset。
##
## 两类 _rep1：
## - 纯队色占位：整面换成 TeamColorXX（步兵肩甲等）
## - 队色垫底（建筑旗帜等）：漫反射 alpha 下透队伍色 → ShaderMaterial
## _rep2 Team Glow：保留 TeamGlow 软圆贴图，用队伍色乘 albedo（Additive）。
func apply_team_color(root: Node, color_index: int = 0, hide_team_glow: bool = false) -> void:
	if root == null:
		return
	var idx := clampi(color_index, 0, 15)
	var tex := _team_color_texture(idx)
	var body_aabb := _non_team_color_aabb(root)
	var fallback := MapPlaceholders.PLAYER_COLORS[
		clampi(idx, 0, MapPlaceholders.PLAYER_COLORS.size() - 1)
	]
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		if _should_hide_preview_mesh(mi):
			mi.visible = false
			continue
		# 旧资源：纯队色占位被误当成 glow 的大面片 → 仍可隐藏
		if hide_team_glow and _is_exclusive_team_color_mesh(mi) and _looks_like_team_glow(mi, body_aabb):
			mi.visible = false
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(si)
			if mat == null:
				continue
			# 已 bake 过的队色垫底 ShaderMaterial：只换 team_color_tex，保留漫反射
			if mat is ShaderMaterial:
				var shm := mat as ShaderMaterial
				if _is_team_color_underlay_shader(shm):
					var sh_out := shm.duplicate() as ShaderMaterial
					if tex != null:
						sh_out.set_shader_parameter("team_color_tex", tex)
						sh_out.set_shader_parameter("use_team_texture", true)
					else:
						sh_out.set_shader_parameter("use_team_texture", false)
					sh_out.set_shader_parameter("team_color_fallback", fallback)
					mi.set_surface_override_material(si, sh_out)
				elif _is_team_glow_shader(shm):
					if not bool(mi.get_meta(META_GLOW_PRESENTED, false)):
						# 旧 bake：整片 glow shader，尚未拆脚底/杖尖
						var fake := StandardMaterial3D.new()
						fake.albedo_texture = shm.get_shader_parameter("glow_tex") as Texture2D
						fake.resource_name = "Material_fm3_rep2"
						_present_team_glow_mesh(mi, fake, fallback, root)
					else:
						var glow_out := shm.duplicate() as ShaderMaterial
						glow_out.set_shader_parameter(
							"team_color", Color(fallback.r, fallback.g, fallback.b, 1.0)
						)
						mi.set_surface_override_material(si, glow_out)
						# 已挂杖尖 billboard 的源十字面片应保持隐藏
						if _root_has_team_glow_billboard(root):
							mi.visible = false
				continue
			if not (mat is StandardMaterial3D):
				continue
			var sm := mat as StandardMaterial3D
			if _is_team_glow_material(sm):
				# 脚底贴地 + 杖尖 billboard（平行面片无法糊成球）
				_present_team_glow_mesh(mi, sm, fallback, root)
				break
			if not _is_team_color_material(sm):
				continue
			if _is_team_color_underlay_material(sm):
				mi.set_surface_override_material(
					si, _make_team_color_underlay(sm, tex, fallback)
				)
			elif tex != null:
				var out := sm.duplicate() as StandardMaterial3D
				out.albedo_texture = tex
				out.albedo_color = Color.WHITE
				mi.set_surface_override_material(si, out)
	_recolor_team_glow_billboards(root, fallback)


## 双层队色垫底：材质名 _rep1 且漫反射不是纯占位 team_color。
func _is_team_color_underlay_material(sm: StandardMaterial3D) -> bool:
	var key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	if not key.contains("_rep1"):
		return false
	var tex: Texture2D = sm.albedo_texture
	if tex == null:
		return false
	return not _is_placeholder_team_color_texture(tex)


func _is_placeholder_team_color_texture(tex: Texture2D) -> bool:
	var p := str(tex.resource_path).replace("\\", "/").to_lower()
	var n := str(tex.resource_name).to_lower()
	return (
		p.contains("team_color")
		or p.contains("placeholders/team_color")
		or n.contains("team_color")
		or n.contains("teamcolor")
	)


func _material_resource_key(mat: Material) -> String:
	if mat == null:
		return ""
	return (str(mat.resource_name) + " " + str(mat.get_name())).to_lower()


func _make_team_color_underlay(
	src: StandardMaterial3D, team_tex: Texture2D, fallback: Color
) -> ShaderMaterial:
	var sh: Shader = load("res://assets/shaders/wc3_team_color_underlay.gdshader") as Shader
	var out := ShaderMaterial.new()
	out.shader = sh
	# 与袍体同优先级即可；shader 已不进透明队列，勿靠提高 priority 治深度。
	out.render_priority = 0
	out.set_shader_parameter("diffuse_tex", src.albedo_texture)
	if team_tex != null:
		out.set_shader_parameter("team_color_tex", team_tex)
		out.set_shader_parameter("use_team_texture", true)
	else:
		out.set_shader_parameter("use_team_texture", false)
	out.set_shader_parameter("team_color_fallback", fallback)
	return out


## 飞弹 / 命中 FX：材质修正 + 语义 present（软球/广告牌）+ 必要时 WORLD_SCALE。
## 已 bake 的 .scn（子节点 scale=0.01）不要二次缩放。
## source_path：逻辑路径（如 Abilities/Weapons/FireBallMissile/...），用于选型 modern present。
func prepare_fx_model(root: Node3D, source_path: String = "") -> void:
	if root == null:
		return
	_fix_wc3_blend_materials(root, false)
	var path := source_path.strip_edges()
	if path.is_empty():
		path = str(root.get_meta("wc3_source_path", ""))
	if FireballMissileModern.wants(path, root):
		FireballMissileModern.apply(root)
	else:
		Wc3FxPresenter.present(root)
	if bool(root.get_meta("wc3_fx_scaled", false)):
		return
	# 已有 MODEL_SCALE 子根（convert 写入）→ 世界 AABB 应 < ~2m
	var worldish := _node_visual_aabb(root)
	if worldish.size.length() <= 2.5:
		root.set_meta("wc3_fx_scaled", true)
		return
	root.scale = root.scale * Wc3Coords.WORLD_SCALE
	root.set_meta("wc3_fx_scaled", true)


## 兼容旧调用：转交 Wc3FxPresenter。
func _present_fx_sphere_billboards(root: Node) -> void:
	if root is Node3D:
		Wc3FxPresenter.present(root as Node3D)


const META_FX_SPHERE_PRESENTED := "wc3_fx_presented"


func _is_team_color_underlay_shader(mat: ShaderMaterial) -> bool:
	if mat == null or mat.shader == null:
		return false
	var p := str(mat.shader.resource_path).replace("\\", "/").to_lower()
	return p.contains("wc3_team_color_underlay")


func _is_team_glow_shader(mat: ShaderMaterial) -> bool:
	if mat == null or mat.shader == null:
		return false
	var p := str(mat.shader.resource_path).replace("\\", "/").to_lower()
	return p.contains("wc3_team_glow")


func _is_exclusive_team_color_mesh(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.mesh.get_surface_count() <= 0:
		return false
	for si in range(mi.mesh.get_surface_count()):
		var mat: Material = mi.get_active_material(si)
		if mat == null:
			return false
		# 队色垫底（漫反射+队色，如人族集结旗）：有实体贴图，不是纯 Team Glow
		if mat is ShaderMaterial and _is_team_color_underlay_shader(mat as ShaderMaterial):
			return false
		if not (mat is StandardMaterial3D):
			return false
		var sm := mat as StandardMaterial3D
		if _is_team_color_underlay_material(sm):
			return false
		if not _is_team_color_material(sm):
			return false
	return true


func _non_team_color_aabb(root: Node) -> AABB:
	var acc := AABB()
	var has := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null or _is_exclusive_team_color_mesh(mi):
			continue
		var local := mi.mesh.get_aabb()
		var xf := mi.global_transform if mi.is_inside_tree() else mi.transform
		var world := xf * local
		if not has:
			acc = world
			has = true
		else:
			acc = acc.merge(world)
	return acc if has else AABB()


func _looks_like_team_glow(mi: MeshInstance3D, body_aabb: AABB) -> bool:
	if mi.mesh == null:
		return false
	var local := mi.mesh.get_aabb()
	var glow_size: float = local.size.length()
	if body_aabb.size.length() < 1e-4:
		# 无身体对照时：大面片（对角线偏大）视为 glow
		return glow_size > 1.5
	var body_size: float = body_aabb.size.length()
	# 圣骑士 glow geoset bbox 明显大于身体
	return glow_size > body_size * 1.15


## 旧 .scn / 错误拆 mesh：PRIMITIVE_TRIANGLES 但顶点数非 3 倍数 → 引擎每帧刷 ERROR。
## 丢掉非法 surface；全非法则隐藏该 MeshInstance。
func _sanitize_triangle_meshes(root: Node) -> void:
	if root == null:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if bool(mi.get_meta("is_runtime_uber_splat", false)):
			continue
		if not (mi.mesh is ArrayMesh):
			continue
		var am := mi.mesh as ArrayMesh
		var sc := am.get_surface_count()
		if sc <= 0:
			continue
		var kept := 0
		var rebuilt := ArrayMesh.new()
		var any_bad := false
		for si in range(sc):
			var arrays: Array = am.surface_get_arrays(si)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				any_bad = true
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices_v: Variant = arrays[Mesh.ARRAY_INDEX]
			var ok := false
			if indices_v is PackedInt32Array and (indices_v as PackedInt32Array).size() > 0:
				var indices := indices_v as PackedInt32Array
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


func _should_hide_preview_mesh(mi: MeshInstance3D) -> bool:
	# 运行时挂上的地面贴花（Art - Ground Texture）必须保留
	if mi != null and (
		bool(mi.get_meta("is_runtime_uber_splat", false))
		or str(mi.name) == "UberSplat"
	):
		return false
	for si in range(mi.mesh.get_surface_count()):
		var mat: Material = mi.get_active_material(si)
		if mat == null or not (mat is StandardMaterial3D):
			continue
		var sm := mat as StandardMaterial3D
		var tex: Texture2D = sm.albedo_texture
		var blob := (str(sm.resource_name) + " " + str(sm.get_name()) + " " + str(mi.name)).to_lower()
		if tex != null:
			blob += " " + str(tex.resource_path).to_lower()
			blob += " " + str(tex.resource_name).to_lower()
		# 建筑脚底 UberSplat / 死亡烟雾 / 肖像背景板 — 游戏与 WE 场景不展示
		# （仅隐藏模型内嵌 geoset；运行时贴花见上方 early-out）
		# 注意：勿用笼统 "_portrait"——会把 peasant_Portrait 全身 mesh 全藏掉，HUD 只剩队色底。
		if (
			blob.contains("ubersplat")
			or blob.contains("/splats/")
			or blob.contains("deathsmug")
			or blob.contains("death_smug")
			or blob.contains("portraitbackground")
			or blob.contains("portrait_background")
			or blob.contains("portrait bg")
			or blob.contains("portraitback")
		):
			return true
		# 模型内嵌 Textures\Shadow.blp（地精商店脚底实心黑盘等）；真正建筑阴影走 unitUI.buildingShadow
		if _is_embedded_blob_shadow_tex(tex, blob):
			return true
		# Team Glow（_rep2）保留显示：法杖/脚底英雄光晕
	return false


## ReplaceableId=2 / TeamGlow 软圆光晕材质。
func _is_team_glow_material(sm: StandardMaterial3D) -> bool:
	if sm == null:
		return false
	var key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	if key.contains("_rep2") or key.contains("team_glow"):
		return true
	var tex: Texture2D = sm.albedo_texture
	if tex == null:
		return false
	var p := str(tex.resource_path).replace("\\", "/").to_lower()
	var n := str(tex.resource_name).to_lower()
	return p.contains("team_glow") or n.contains("team_glow") or p.contains("/teamglow/")


func _make_team_glow_shader_material(
	glow_tex: Texture2D, team_color: Color, intensity: float, billboard: bool
) -> ShaderMaterial:
	var sh: Shader = load("res://assets/shaders/wc3_team_glow.gdshader") as Shader
	var out := ShaderMaterial.new()
	out.shader = sh
	out.set_shader_parameter("glow_tex", glow_tex)
	out.set_shader_parameter(
		"team_color", Color(team_color.r, team_color.g, team_color.b, 1.0)
	)
	out.set_shader_parameter("intensity", intensity)
	out.set_shader_parameter("use_billboard", billboard)
	out.resource_local_to_scene = true
	return out


## 脚底 TeamGlow：贴地软圆（Additive + 贴图 RGB 软边）。
func _make_team_glow_material(src: StandardMaterial3D, team_color: Color) -> ShaderMaterial:
	return _make_team_glow_shader_material(src.albedo_texture, team_color, 2.4, false)


## 杖尖：同一 shader，允许 albedo>1；billboard 在 vertex 里做。
func _make_team_glow_billboard_material(glow_tex: Texture2D, team_color: Color) -> ShaderMaterial:
	return _make_team_glow_shader_material(glow_tex, team_color, 3.6, true)


const META_GLOW_PRESENTED := "wc3_team_glow_presented"
const META_GLOW_BILLBOARD := "wc3_team_glow_billboard"
## 三角法线 |Y| 大于此值 → 脚底贴地盘；其余视为杖尖/武器平行面片。
const TEAM_GLOW_FOOT_NY := 0.65


func _root_has_team_glow_billboard(root: Node) -> bool:
	if root == null:
		return false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi != null and bool(mi.get_meta(META_GLOW_BILLBOARD, false)):
			return true
	return false


## 把 Team Glow geoset 拆成：脚底贴地网格 + 杖尖 billboard。
## MDX 杖尖是多张平行四边形，斜看必露卡片；billboard 软圆才像球形光晕。
func _present_team_glow_mesh(
	mi: MeshInstance3D, src_mat: StandardMaterial3D, team_color: Color, root: Node
) -> void:
	if mi == null or src_mat == null:
		return
	if bool(mi.get_meta(META_GLOW_PRESENTED, false)):
		mi.set_surface_override_material(0, _make_team_glow_material(src_mat, team_color))
		return
	var glow_tex: Texture2D = src_mat.albedo_texture
	var split := _split_team_glow_by_normal(mi.mesh)
	var foot_mesh: ArrayMesh = split.get("foot", null) as ArrayMesh
	var tip_aabb: AABB = split.get("tip_aabb", AABB()) as AABB
	var has_tip: bool = bool(split.get("has_tip", false))
	var has_foot := foot_mesh != null and foot_mesh.get_surface_count() > 0
	mi.set_meta(META_GLOW_PRESENTED, true)
	var host: Node3D = null
	if has_tip and tip_aabb.size.length() >= 1e-4:
		host = _resolve_team_glow_tip_host(root, mi)
	# 有武器挂点 + 杖尖：整片十字面片改 billboard，不再保留「误判脚底」残留
	if host != null and has_tip:
		mi.visible = false
		var side := maxf(12.0, tip_aabb.size.length() * 0.55)
		var quad := QuadMesh.new()
		quad.size = Vector2(side, side)
		var tip_bb := MeshInstance3D.new()
		tip_bb.name = "TeamGlowBillboard"
		tip_bb.mesh = quad
		tip_bb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tip_bb.set_meta(META_GLOW_BILLBOARD, true)
		tip_bb.set_surface_override_material(0, _make_team_glow_billboard_material(glow_tex, team_color))
		var tip := host.get_node_or_null("Tip") as Node3D
		if tip != null:
			tip.add_child(tip_bb)
			tip_bb.owner = root
			tip_bb.transform = Transform3D.IDENTITY
		else:
			host.add_child(tip_bb)
			tip_bb.owner = root
			tip_bb.position = _team_glow_tip_local_offset(host, tip_aabb, root)
		return
	if has_foot:
		mi.mesh = foot_mesh
		mi.set_surface_override_material(0, _make_team_glow_material(src_mat, team_color))
		mi.visible = true
	elif has_tip:
		# 无武器挂点的 tip-only（少见）：保留 mesh，避免光晕直接消失
		mi.set_surface_override_material(0, _make_team_glow_material(src_mat, team_color))
		mi.visible = true
	else:
		# 肖像背景板等
		mi.set_surface_override_material(0, _make_team_glow_material(src_mat, team_color))
		mi.visible = true


## BoneAttachment 跟骨原点；杖尖在 pivot_delta / tip AABB。
func _team_glow_tip_local_offset(host: Node3D, tip_aabb: AABB, root: Node) -> Vector3:
	if host == null:
		return tip_aabb.get_center()
	if host.has_meta("wc3_pivot_delta"):
		var d: Variant = host.get_meta("wc3_pivot_delta")
		if d is Vector3:
			return d as Vector3
	var tip_node := host.get_node_or_null("Tip") as Node3D
	if tip_node != null and tip_node.position != Vector3.ZERO:
		return tip_node.position
	var center := tip_aabb.get_center()
	if not (host is BoneAttachment3D):
		return center
	var ba := host as BoneAttachment3D
	var skeleton: Skeleton3D = null
	if ba.use_external_skeleton:
		var sk_path: NodePath = ba.external_skeleton
		if not sk_path.is_empty():
			skeleton = ba.get_node_or_null(sk_path) as Skeleton3D
	else:
		skeleton = ba.get_parent() as Skeleton3D
	if skeleton == null and root != null:
		for c in root.find_children("*", "Skeleton3D", true, false):
			if c is Skeleton3D:
				skeleton = c as Skeleton3D
				break
	if skeleton == null:
		return center
	var bi := skeleton.find_bone(ba.bone_name)
	if bi < 0:
		return center
	var bone_rest: Transform3D = skeleton.get_bone_global_rest(bi)
	return bone_rest.affine_inverse() * center


func _recolor_team_glow_billboards(root: Node, team_color: Color) -> void:
	if root == null:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or not bool(mi.get_meta(META_GLOW_BILLBOARD, false)):
			continue
		var mat: Material = mi.get_active_material(0)
		var glow_tex: Texture2D = null
		if mat is StandardMaterial3D:
			glow_tex = (mat as StandardMaterial3D).albedo_texture
		elif mat is ShaderMaterial:
			glow_tex = (mat as ShaderMaterial).get_shader_parameter("glow_tex") as Texture2D
		if glow_tex == null:
			glow_tex = RuntimeAssets.load_converted_texture(
				"ReplaceableTextures/TeamGlow/TeamGlow00.png"
			)
		mi.set_surface_override_material(0, _make_team_glow_billboard_material(glow_tex, team_color))


## 优先：Weapon / Staff，再 Hand Right。必须扫完全部 BA 再按 prefer 排名，
## 不能「第一个匹配就 return」——Paladin 树里 Hand Right 在 Weapon 前面。
func _resolve_team_glow_tip_host(root: Node, glow_mi: MeshInstance3D) -> Node3D:
	if root == null:
		return null
	var prefer := [
		"attachweaponref",
		"attachweapon",
		"weaponref",
		"weapon",
		"magestaff",
		"attachhandrightref",
		"handrightref",
	]
	var best: BoneAttachment3D = null
	var best_rank := prefer.size()
	for n in root.find_children("*", "BoneAttachment3D", true, false):
		var ba := n as BoneAttachment3D
		if ba == null:
			continue
		var key := str(ba.name).replace(" ", "").replace("-", "").replace("_", "").to_lower()
		var bone_key := str(ba.bone_name).replace(" ", "").replace("-", "").replace("_", "").to_lower()
		for i in range(prefer.size()):
			var p: String = str(prefer[i])
			if key.contains(p) or bone_key.contains(p):
				if i < best_rank:
					best_rank = i
					best = ba
				break
	if best != null:
		return best
	# 按骨名直接建 BoneAttachment
	var skeleton: Skeleton3D = null
	for c in root.find_children("*", "Skeleton3D", true, false):
		if c is Skeleton3D:
			skeleton = c as Skeleton3D
			break
	if skeleton == null:
		return null
	for bone_want in ["Mage_Staff", "Weapon", "Bone_Hand_R", "Hand Right"]:
		var bi := skeleton.find_bone(bone_want)
		if bi < 0:
			continue
		var ba2 := BoneAttachment3D.new()
		ba2.name = "BA_TeamGlowTip"
		ba2.bone_name = bone_want
		ba2.use_external_skeleton = true
		var pe2 := root.find_child("Pe2Root", true, false)
		var parent: Node = pe2 if pe2 != null else glow_mi.get_parent()
		if parent == null:
			parent = root
		parent.add_child(ba2)
		ba2.owner = root
		var skel_path := NodePath()
		var walk: Node = ba2
		var seen: Dictionary = {}
		while walk != null:
			seen[walk] = true
			walk = walk.get_parent()
		walk = skeleton
		while walk != null:
			if seen.has(walk):
				skel_path = ba2.get_path_to(skeleton)
				break
			walk = walk.get_parent()
		if skel_path.is_empty():
			ba2.queue_free()
			return null
		ba2.external_skeleton = skel_path
		return ba2
	return null


## 按三角法线拆脚底 / 杖尖；返回 {foot, tip, tip_aabb, has_tip}。
func _split_team_glow_by_normal(mesh: Mesh) -> Dictionary:
	var empty := {"foot": null, "tip": null, "tip_aabb": AABB(), "has_tip": false}
	if mesh == null or not (mesh is ArrayMesh):
		return empty
	var am := mesh as ArrayMesh
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
	var tri_count := int((idx.size() if idx.size() > 0 else verts.size()) / 3)
	var foot_idx := PackedInt32Array()
	var tip_idx := PackedInt32Array()
	var tip_aabb := AABB()
	var tip_has := false
	for t in range(tri_count):
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
		var is_foot := absf(nrm.y) >= TEAM_GLOW_FOOT_NY
		if is_foot:
			foot_idx.append(i0)
			foot_idx.append(i1)
			foot_idx.append(i2)
		else:
			tip_idx.append(i0)
			tip_idx.append(i1)
			tip_idx.append(i2)
			for iv in [i0, i1, i2]:
				if not tip_has:
					tip_aabb = AABB(verts[iv], Vector3.ZERO)
					tip_has = true
				else:
					tip_aabb = tip_aabb.expand(verts[iv])
	var foot_mesh := _rebuild_glow_surface(verts, norms, uvs, bones, weights, foot_idx)
	var tip_mesh := _rebuild_glow_surface(verts, norms, uvs, bones, weights, tip_idx)
	return {
		"foot": foot_mesh,
		"tip": tip_mesh,
		"tip_aabb": tip_aabb,
		"has_tip": tip_has and tip_idx.size() > 0,
	}


func _rebuild_glow_surface(
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
	var remap: Dictionary = {}
	var new_v := PackedVector3Array()
	var new_n := PackedVector3Array()
	var new_uv := PackedVector2Array()
	var new_bones := PackedInt32Array()
	var new_weights := PackedFloat32Array()
	var new_idx := PackedInt32Array()
	var has_skin := bones.size() >= verts.size() * 4 and weights.size() >= verts.size() * 4
	for i in tri_idx:
		if not remap.has(i):
			var ni := new_v.size()
			remap[i] = ni
			new_v.append(verts[i])
			if norms.size() > i:
				new_n.append(norms[i])
			if uvs.size() > i:
				new_uv.append(uvs[i])
			if has_skin:
				var b0 := i * 4
				for k in range(4):
					new_bones.append(bones[b0 + k])
					new_weights.append(weights[b0 + k])
		new_idx.append(int(remap[i]))
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
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	return am


## 识别 MDX 内嵌的半透明阴影盘贴图（非 ReplaceableTextures/Shadows 单位阴影）。
func _is_embedded_blob_shadow_tex(tex: Texture2D, blob: String) -> bool:
	if blob.contains("replaceabletextures/shadows"):
		return false
	if blob.contains("merchant_shadow") or blob.contains("/textures/shadow"):
		return true
	if tex == null:
		return false
	var n := str(tex.resource_name).to_lower().get_file().get_basename()
	var p := str(tex.resource_path).replace("\\", "/").to_lower().get_file().get_basename()
	return n == "shadow" or p == "shadow" or n.ends_with("_shadow") or p.ends_with("_shadow")


func _is_team_color_material(sm: StandardMaterial3D) -> bool:
	var tex: Texture2D = sm.albedo_texture
	var key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	# Team Glow 不当作可染色队伍色
	if key.contains("_rep2") or key.contains("team_glow"):
		return false
	if tex == null:
		return key.contains("_rep1")
	var p := str(tex.resource_path).replace("\\", "/").to_lower()
	var n := str(tex.resource_name).to_lower()
	if p.contains("team_glow") or n.contains("team_glow"):
		return false
	# GLB 内嵌图常见 name: _placeholders/team_color.png
	return (
		key.contains("_rep1")
		or p.contains("team_color")
		or p.contains("/teamcolor/")
		or p.contains("placeholders/team_color")
		or n.contains("team_color")
		or n.contains("teamcolor")
	)


func _team_color_texture(owner_id: int) -> Texture2D:
	if _team_color_tex.has(owner_id):
		return _team_color_tex[owner_id] as Texture2D
	var logical := "ReplaceableTextures/TeamColor/TeamColor%02d.png" % owner_id
	var tex: Texture2D = RuntimeAssets.load_converted_texture(logical)
	if tex == null:
		# 无贴图时用玩家色纯色 1x1
		var c: Color = MapPlaceholders.PLAYER_COLORS[clampi(owner_id, 0, MapPlaceholders.PLAYER_COLORS.size() - 1)]
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(c)
		tex = ImageTexture.create_from_image(img)
	_team_color_tex[owner_id] = tex
	return tex


## GLB 是否含「会动」的循环骨骼动画（空 Stand / 仅 GeosetAnim 不算）
func glb_has_animation(path: String) -> bool:
	if path.is_empty():
		return false
	# 已知坏文件：跳过，避免引擎刷 Buffer 0 ERROR
	if _anim_flags.has(path):
		return bool(_anim_flags[path])
	var disk := RuntimeAssets.project_abs(path)
	if disk.is_empty() or not FileAccess.file_exists(disk):
		_anim_flags[path] = false
		return false
	var bytes := FileAccess.get_file_as_bytes(disk)
	if not RuntimeAssets.is_plausible_gltf_bytes(bytes):
		_anim_flags[path] = false
		return false
	_ensure_scene(path)
	# 解析失败时 _register_loaded_scene 不会写 flag，在此落盘避免反复打引擎 ERROR
	if not _anim_flags.has(path):
		_anim_flags[path] = false
	return bool(_anim_flags.get(path, false))


## 优先播 Stand（及 Stand -1 等变体），否则空闲回退；循环。
## random_phase：多实例错开相位，避免蝙蝠/鸟群齐刷刷扑翅。
func autoplay_stand(root: Node, random_phase: bool = true) -> bool:
	if root == null:
		return false
	var ap := _find_animation_player(root)
	if ap == null:
		return false
	# 节点已入树时写 autoplay 无效果且会警告；直接 stop + play 即可盖掉 GLTF 默认轨。
	ap.stop()
	var chosen := _pick_stand_name(ap)
	if chosen.is_empty():
		chosen = _pick_idle_fallback(ap)
	if chosen.is_empty():
		return false
	if not play_animation(root, chosen, true):
		return false
	if random_phase and not str(ap.current_animation).is_empty():
		var anim_len: float = ap.current_animation_length
		if anim_len > 0.05:
			ap.seek(randf() * anim_len, true)
	return true


## 模型上全部动画名（含 Death / Birth 等；不限骨骼 Stand）。
func list_animations(root: Node, _for_preview: bool = false) -> PackedStringArray:
	var ap := _find_animation_player(root)
	if ap == null:
		return PackedStringArray()
	return ap.get_animation_list()


## 播放指定动画；loop=true 时强制线性循环（预览用）。
func play_animation(root: Node, anim_name: String, loop: bool = true) -> bool:
	if root == null or anim_name.is_empty():
		return false
	var ap := _find_animation_player(root)
	if ap == null or not ap.has_animation(anim_name):
		return false
	ap.active = true
	var anim := ap.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = (
			Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		)
	ap.play(anim_name)
	return true


## GLB / 实例是否含可见网格（空壳 PE2-only GLB → false）。
func glb_has_mesh(path: String) -> bool:
	if path.is_empty():
		return false
	var parts := mesh_parts_from_glb(path)
	return not parts.is_empty()


func node_has_mesh(root: Node) -> bool:
	return MapPlaceholders.node_has_mesh(root)


## 兼容旧调用：取第一个可见网格
func mesh_from_glb(path: String) -> Mesh:
	var parts := mesh_parts_from_glb(path)
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
	var root := instance_glb(path)
	if root == null:
		return []
	var parts: Array = []
	_collect_mesh_parts(root, parts)
	root.free()
	_parts_cache[path] = parts
	return parts


## WC3 材质在 glTF/Godot 中的修正：
## - FilterMode Additive/AddAlpha：glTF 只能标 BLEND，需改成 ADD（否则黑底 Glow 变实心牌）
## - FilterMode Blend（建筑）：改 ALPHA_SCISSOR，避免酒馆/市场透视
## - FilterMode Blend（单位 _fm2）：DEPTH_PRE_PASS + 双面（水元素体、火枪披风等软 alpha）
## - FilterMode Transparent（单位 _fm1）：保持 MASK≈0.75 + 双面（贴近 WC3 Transparent；
##   勿 DEPTH_PRE_PASS——Priest 等与队色层共用图集，软 alpha 会把胸前镂空）
## - 默认双面（旧 convert）→ 非 TwoSided/非 Additive/非 fm1/fm2 强制 cull_back
func _fix_wc3_blend_materials(root: Node, unit_soft_blend: bool = false) -> void:
	if root == null:
		return
	var waterish_model := unit_soft_blend and _node_tree_looks_waterish(root)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(si)
			if mat == null:
				continue
			var fixed := _as_wc3_material_fix(mat, unit_soft_blend, waterish_model)
			if fixed != null and fixed != mat:
				mi.set_surface_override_material(si, fixed)


## 模型名 / 贴图路径 / meta 含 water（WaterElemental、WaterEnv…）；bake 内嵌贴图后仍可靠。
func _node_tree_looks_waterish(root: Node) -> bool:
	if root == null:
		return false
	if bool(root.get_meta("wc3_waterish_model", false)):
		return true
	var key := str(root.name).to_lower()
	if key.contains("water"):
		return true
	var p := str(root.get_path()).to_lower() if root.is_inside_tree() else ""
	return p.contains("water")


func _as_wc3_material_fix(
	mat: Material, unit_soft_blend: bool = false, waterish_model: bool = false
) -> Material:
	var add := _as_wc3_additive_material(mat)
	if add != mat:
		return add
	if unit_soft_blend:
		var soft := _as_wc3_unit_fm2_soft_fix(mat, waterish_model)
		# _fm2 已软化时 soft 可能 == mat；绝不能再落入建筑 scissor。
		if soft != mat:
			return soft
		if mat is StandardMaterial3D:
			var key := (
				str((mat as StandardMaterial3D).resource_name)
				+ " "
				+ str((mat as StandardMaterial3D).get_name())
			).to_lower()
			if key.contains("_fm2"):
				return mat
		# 单位袍体 _fm1：WC3 Transparent ≈ MASK@0.75 + 双面（可从旧 DEPTH_PRE_PASS 拉回）。
		var fm1 := _as_wc3_unit_fm1_mask_fix(mat)
		if fm1 != mat:
			return fm1
		# 已是 MASK 目标态：勿再落入建筑 scissor（阈值 0.08 会误伤）。
		if mat is StandardMaterial3D:
			var sm_done := mat as StandardMaterial3D
			var k_done := (
				str(sm_done.resource_name) + " " + str(sm_done.get_name())
			).to_lower()
			if k_done.contains("_fm1"):
				return mat
			# 仅保留 _fm2 soft 目标态短路（DEPTH_PRE_PASS + 双面）；_fm1 不再走 soft。
			if (
				sm_done.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				and sm_done.cull_mode == BaseMaterial3D.CULL_DISABLED
				and sm_done.blend_mode != BaseMaterial3D.BLEND_MODE_ADD
			):
				return mat
	var scissor := _as_wc3_blend_scissor_fix(mat)
	var cull := _as_wc3_cull_back_fix(scissor)
	return _as_wc3_transparent_two_sided_fix(cull)


## 单位 FilterMode=1 Transparent（_fm1）：贴近 war3-model / convert 的 MASK@0.75。
## 袍体与队色层常共用一张 BLP：软混合会把「队色窗」alpha 当成胸口镂空。
## 单面壳仍强制双面（MDX 常不标 TwoSided）。
const WC3_TRANSPARENT_MASK_THRESHOLD := 0.75


func _as_wc3_unit_fm1_mask_fix(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm := mat as StandardMaterial3D
	if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return mat
	var key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	var looks_fm1 := key.contains("_fm1")
	# bake 吃旧 scn 时 override 可能丢名；高阈值 MASK 也可识别为 Transparent
	if (
		not looks_fm1
		and sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		and sm.alpha_scissor_threshold >= 0.5
	):
		looks_fm1 = true
	if not looks_fm1:
		return mat
	var want_transp := BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	if (
		sm.transparency == want_transp
		and sm.cull_mode == BaseMaterial3D.CULL_DISABLED
		and absf(sm.alpha_scissor_threshold - WC3_TRANSPARENT_MASK_THRESHOLD) < 0.001
	):
		return mat
	var out := sm.duplicate() as StandardMaterial3D
	if out.resource_name.is_empty() and not key.strip_edges().is_empty():
		out.resource_name = sm.resource_name if not sm.resource_name.is_empty() else sm.get_name()
	out.transparency = want_transp
	out.alpha_scissor_threshold = WC3_TRANSPARENT_MASK_THRESHOLD
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	out.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	out.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	return out


## 单位 FilterMode=2 Blend（_fm2）：保留软 alpha，对齐 WC3 水元素/披风。
## 水体模型/贴图走真 Alpha Blend，比 DEPTH_PRE_PASS 更通透。
func _as_wc3_unit_fm2_soft_fix(mat: Material, waterish_model: bool = false) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm := mat as StandardMaterial3D
	if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return mat
	var key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	if not key.contains("_fm2"):
		return mat
	var needs := (
		sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	)
	if not needs:
		return mat
	var tex_key := ""
	if sm.albedo_texture != null:
		tex_key = (
			str(sm.albedo_texture.resource_path) + " " + str(sm.albedo_texture.resource_name)
		).to_lower()
	var waterish := (
		waterish_model
		or tex_key.contains("water")
		or key.contains("water")
	)
	var want_transp := (
		BaseMaterial3D.TRANSPARENCY_ALPHA
		if waterish
		else BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	)
	var want_depth := (
		BaseMaterial3D.DEPTH_DRAW_DISABLED
		if waterish
		else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	)
	var want_a := sm.albedo_color.a
	if waterish:
		# WC3 Blend 中段 alpha 偏「实」；略压整体 alpha 更像流体体积
		want_a = clampf(sm.albedo_color.a * 0.48, 0.22, 0.62)
	if (
		sm.transparency == want_transp
		and sm.cull_mode == BaseMaterial3D.CULL_DISABLED
		and sm.depth_draw_mode == want_depth
		and absf(sm.albedo_color.a - want_a) < 0.01
	):
		return mat
	var out := sm.duplicate() as StandardMaterial3D
	out.transparency = want_transp
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	out.depth_draw_mode = want_depth
	out.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	if waterish:
		var c := out.albedo_color
		c.a = want_a
		out.albedo_color = c
		out.roughness = minf(out.roughness, 0.22)
		out.metallic = 0.05
		# 略抬高 albedo 亮度，半透明下更像水体折射
		out.albedo_color = Color(
			minf(c.r * 1.08, 1.0),
			minf(c.g * 1.12, 1.0),
			minf(c.b * 1.15, 1.0),
			want_a
		)
	return out


## FilterMode=2 Blend → Alpha Scissor（写深度），避免酒馆/市场/雇佣兵营地等建筑透视。
## DEPTH_PRE_PASS 对中段 alpha 偏多的 WC3 贴图仍不够稳，故统一 scissor。
const WC3_BLEND_SCISSOR_THRESHOLD := 0.08


func _as_wc3_blend_scissor_fix(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm := mat as StandardMaterial3D
	# Additive 由另一路径处理
	if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return mat
	var needs := (
		sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	)
	if not needs:
		return mat
	# 已是目标 scissor 且阈值合适 → 跳过
	if (
		sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		and absf(sm.alpha_scissor_threshold - WC3_BLEND_SCISSOR_THRESHOLD) < 0.001
	):
		return mat
	var out := sm.duplicate() as StandardMaterial3D
	out.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	out.alpha_scissor_threshold = WC3_BLEND_SCISSOR_THRESHOLD
	out.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	out.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	return out


## 旧 GLB 一律 doubleSided；非 Additive / 非 Transparent 改回 cull_back（屋顶背面不再透出发黑）。
func _as_wc3_cull_back_fix(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm := mat as StandardMaterial3D
	if sm.cull_mode != BaseMaterial3D.CULL_DISABLED:
		return mat
	if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return mat
	var key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	# fm1 Transparent / fm2 软混合 / Additive：保留双面
	if key.contains("_fm1") or key.contains("_fm2") or key.contains("_fm3") or key.contains("_fm4") or key.contains("_rep2"):
		return mat
	var out := sm.duplicate() as StandardMaterial3D
	out.cull_mode = BaseMaterial3D.CULL_BACK
	return out


## FilterMode=1 Transparent：MDX 常不标 TwoSided，但袍/披风是单面壳；
## cull_back 会把前胸多数三角剔掉，只剩侧面轮廓，并能透视到背后披风（hmpr 等）。
func _as_wc3_transparent_two_sided_fix(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm := mat as StandardMaterial3D
	var key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	if not key.contains("_fm1"):
		return mat
	if sm.cull_mode == BaseMaterial3D.CULL_DISABLED:
		return mat
	var out := sm.duplicate() as StandardMaterial3D
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	return out


func _as_wc3_additive_material(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm := mat as StandardMaterial3D
	var key := str(sm.resource_name) + " " + str(sm.get_name())
	var key_l := key.to_lower()
	var tex: Texture2D = sm.albedo_texture
	var tex_path := ""
	if tex != null:
		tex_path = (str(tex.resource_path) + " " + str(tex.resource_name)).to_lower()
	var is_team_glow := (
		key_l.contains("_rep2")
		or key_l.contains("team_glow")
		or tex_path.contains("team_glow")
		or tex_path.contains("teamglow")
		or tex_path.contains("/teamglow/")
	)
	var want_add := (
		is_team_glow
		or key_l.contains("_fm3")
		or key_l.contains("_fm4")
		or tex_path.contains("glow")
	)
	if not want_add:
		return mat
	# 已是目标态则跳过（避免 instance 时反复 duplicate）
	var want_alpha := BaseMaterial3D.TRANSPARENCY_ALPHA
	var want_no_depth := is_team_glow
	if (
		sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
		and sm.transparency == want_alpha
		and sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		and sm.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED
		and sm.no_depth_test == want_no_depth
		and sm.cull_mode == BaseMaterial3D.CULL_DISABLED
	):
		return mat
	var out := sm.duplicate() as StandardMaterial3D
	out.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	out.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# 必须开 ALPHA：TeamGlow / 软边 Additive 贴图靠 alpha 藏面片边；
	# DISABLED 时只会按 RGB 叠加，交叉四边形棱线从斜角非常明显。
	out.transparency = want_alpha
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	out.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# 英雄脚底/杖尖 TeamGlow 是多片交叉面：关深度测试减轻片间遮挡棱线
	out.no_depth_test = want_no_depth
	return out


## 真正会动的 Stand：pos/rot 轨足够多（空 Stand、树的微动轨排除）
const _MIN_SKELETAL_TRACKS := 6


func _scene_has_skeletal_stand(n: Node) -> bool:
	var ap := _find_animation_player(n)
	if ap == null:
		return false
	var stand := _pick_stand_name(ap)
	if stand.is_empty():
		return false
	return _is_skeletal_motion(ap.get_animation(stand))


func _pick_stand_name(ap: AnimationPlayer) -> String:
	var names := ap.get_animation_list()
	if names.is_empty():
		return ""
	# 精确 Stand / stand（含 AnimationLibrary 前缀 lib/Stand）
	for n in names:
		var leaf := _anim_leaf_name(str(n))
		if leaf == "Stand" or leaf == "stand":
			return str(n)
	# Stand 变体：Stand - 1 / Stand Ready / Stand Work…
	for n in names:
		var leaf2 := _anim_leaf_name(str(n))
		var low := leaf2.to_lower()
		if low.begins_with("stand"):
			return str(n)
	return ""


## 无 Stand 时回退：Walk / Portrait / 其它非战斗动作；绝不首选 Attack。
func _pick_idle_fallback(ap: AnimationPlayer) -> String:
	var names := ap.get_animation_list()
	if names.is_empty():
		return ""
	var prefer := ["walk", "portrait", "stand", "ready", "idle"]
	for key in prefer:
		for n in names:
			var low := _anim_leaf_name(str(n)).to_lower()
			if low.begins_with(key) or low.contains(key):
				if _is_combat_anim_name(low):
					continue
				return str(n)
	for n in names:
		var low2 := _anim_leaf_name(str(n)).to_lower()
		if not _is_combat_anim_name(low2):
			return str(n)
	return str(names[0])


func _anim_leaf_name(full: String) -> String:
	# Godot 4：库内动画名为 "LibraryName/AnimName"
	var slash := full.rfind("/")
	if slash >= 0 and slash + 1 < full.length():
		return full.substr(slash + 1)
	return full


func _is_combat_anim_name(low: String) -> bool:
	return (
		low.begins_with("attack")
		or low.begins_with("spell")
		or low.begins_with("death")
		or low.begins_with("decay")
		or low.begins_with("dissipate")
		or low.begins_with("birth")
		or low.begins_with("morph")
	)


func _is_skeletal_motion(anim: Animation) -> bool:
	if anim == null or anim.length < 0.05:
		return false
	var move_tracks := 0
	for ti in range(anim.get_track_count()):
		var tt := anim.track_get_type(ti)
		if tt == Animation.TYPE_POSITION_3D or tt == Animation.TYPE_ROTATION_3D:
			move_tracks += 1
			if move_tracks >= _MIN_SKELETAL_TRACKS:
				return true
	return false


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null


func _reveal_hidden_geosets(n: Node) -> void:
	if n is Node3D:
		var n3 := n as Node3D
		if n3.scale.length_squared() < 1e-8:
			n3.scale = Vector3.ONE
	for c in n.get_children():
		_reveal_hidden_geosets(c)


## 供 MapDoodadLayer.ensure_promoted 等：GeosetAnim rest 全隐时强制可见。
func reveal_hidden_geosets_public(root: Node) -> void:
	if root == null:
		return
	_reveal_hidden_geosets(root)
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		mi.visible = true
		if mi.scale.length_squared() < 1e-8:
			mi.scale = Vector3.ONE


## 按 Stand 的 :visible 轨定格（树=藏树桩 Geoset；主城=默认档）。
## 树/可破坏物 promote 必须走这里，禁止 reveal_all（否则桩与活树同亮）。
func snap_stand_geoset_visibility(root: Node) -> void:
	if root == null:
		return
	var ap := _find_animation_player(root)
	var leaf := "Stand"
	if ap != null:
		var picked := _pick_stand_name(ap)
		if not picked.is_empty():
			leaf = _anim_leaf_name(picked)
	_snap_geoset_visibility_pose(root, leaf)


## 按任意 Sequence（如 Stand_Work / Decay_Flesh）指定时刻的 :visible 定格 geoset。
func snap_geoset_visibility_for(
	root: Node, anim_name: String, at_time: float = 0.0, hide_zero_scale: bool = true
) -> void:
	if root == null or anim_name.is_empty():
		return
	_snap_geoset_visibility_pose(root, anim_name, at_time, hide_zero_scale)


func _collect_mesh_parts(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		# 跳过 Stand 下应隐藏的 Geoset（树桩）；否则 MultiMesh 会把桩和活树一起画
		if mi.mesh != null and mi.visible:
			out.append({
				"mesh": mi.mesh,
				"material": mi.get_active_material(0),
			})
	for c in n.get_children():
		_collect_mesh_parts(c, out)


## 无共同祖先时 `Node.get_path_to` 会引擎 ERROR。
func _nodes_share_tree(a: Node, b: Node) -> bool:
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
