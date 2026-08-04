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
## path → PackedByteArray（空闲预读；点选可跳过磁盘 IO）
var _bytes_cache: Dictionary = {}
## GLB 解析后待懒烘焙为 .scn 的队列
var _lazy_bake_queue: PackedStringArray = PackedStringArray()
## 后台预载：path → { kind, scn_path|holder|task_id }
var _preload: Dictionary = {}


func instance_glb(path: String) -> Node3D:
	var packed: PackedScene = _ensure_packed(path)
	if packed != null:
		var inst := packed.instantiate()
		if inst is Node3D:
			# .scn 可能在材质修正前烘焙；每次实例化都再修一次
			_fix_wc3_blend_materials(inst as Node3D)
			return inst as Node3D
		if inst != null:
			inst.free()
	var proto := _ensure_scene(path)
	if proto == null:
		return null
	var dup := proto.duplicate() as Node3D
	if dup != null:
		_fix_wc3_blend_materials(dup)
	return dup


## 是否已有可实例化的缓存（点选热路径可跳过磁盘/解析）。
func has_cached(path: String) -> bool:
	return not path.is_empty() and (_packed_cache.has(path) or _scene_cache.has(path))


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
func register_external_packed(glb_path: String, packed: PackedScene) -> void:
	if glb_path.is_empty() or packed == null:
		return
	_packed_cache[glb_path] = packed
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
	var bytes: PackedByteArray = PackedByteArray()
	if _bytes_cache.has(path):
		bytes = _bytes_cache[path] as PackedByteArray
	_preload.erase(path)
	if bytes.is_empty():
		return false
	# GLTFDocument 必须在主线程
	var proto := _ensure_scene_from_bytes(path, bytes)
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
func instance_glb_preview(path: String, prefer_visuals: bool = true) -> Node3D:
	if path.is_empty():
		return null
	if prefer_visuals and _packed_cache.has(path):
		var packed: PackedScene = _packed_cache[path] as PackedScene
		var inst := packed.instantiate()
		if inst is Node3D:
			_fix_wc3_blend_materials(inst as Node3D)
			return inst as Node3D
		if inst != null:
			inst.free()
	var proto := _ensure_scene(path, prefer_visuals)
	if proto == null:
		return null
	var dup := proto.duplicate() as Node3D
	if dup != null:
		_fix_wc3_blend_materials(dup)
	return dup


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
			_fix_wc3_blend_materials(inst as Node3D)
			return inst as Node3D
		if inst != null:
			inst.free()
	var dup := proto.duplicate() as Node3D
	if dup != null:
		_fix_wc3_blend_materials(dup)
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
	# 优先可提交的 visuals 封装（继承 .scn + Pe2Root + ModelVisualSync）
	if prefer_visuals:
		var vis_path := RuntimeAssets.resolve_visual_scene(glb_path)
		if not vis_path.is_empty():
			var vis_packed := RuntimeAssets.load_packed_scene(vis_path)
			if vis_packed != null:
				return vis_packed
			# .gdignore 导致 ExtResource 基座失败时，按 visuals 配方运行时拼装
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
	_fix_wc3_blend_materials(root)
	var ap := _find_animation_player(root)
	if ap != null:
		ap.autoplay = ""
		ap.stop()
	_inject_geoset_vis_tracks(glb_path, root)
	const _Pe2 := preload("res://scripts/map/presentation/effects/wc3_pe2_particles.gd")
	const _Sync := preload("res://scripts/map/presentation/model_visual_sync.gd")
	if _Pe2.has_emitters(glb_path):
		_Pe2.attach_to(root, glb_path)
	root.set_script(_Sync)
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
	# 优先旁路 .scn（免 GLTFDocument）；导出基座时 prefer_visuals=false 跳过 visuals
	var from_scn := _try_load_scn_packed(path, prefer_visuals)
	if from_scn != null:
		var inst := from_scn.instantiate()
		if inst is Node3D:
			# 即使 prefer_visuals=false 也写入缓存，供随后 bake_model_scene 打包
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
	var loaded := RuntimeAssets.load_gltf_scene_from_bytes(bytes, path)
	return _register_loaded_scene(path, loaded, true)


## from_gltf=true 时排队懒烘焙 .scn，供下次点选走 ResourceLoader。
func _register_loaded_scene(path: String, loaded: Node3D, from_gltf: bool = true) -> Node3D:
	if loaded == null:
		return null
	_fix_wc3_blend_materials(loaded)
	# 原型上清掉 autoplay，避免实例化瞬间播 Attack
	var ap := _find_animation_player(loaded)
	if ap != null:
		ap.autoplay = ""
		ap.stop()
	_inject_geoset_vis_tracks(path, loaded)
	var has_anim := _scene_has_skeletal_stand(loaded)
	_anim_flags[path] = has_anim
	# 静物：GeosetAnim 在 rest 可能 scale=0，强制可见
	# 动画物：按 Stand / Stand - 1 等轨落到默认显隐（藏尸体、地精商店内嵌地精/Shadow 盘等）
	if has_anim:
		var stand_leaf := "Stand"
		var ap_snap := _find_animation_player(loaded)
		if ap_snap != null:
			var picked := _pick_stand_name(ap_snap)
			if not picked.is_empty():
				stand_leaf = _anim_leaf_name(picked)
		_snap_geoset_visibility_pose(loaded, stand_leaf)
	else:
		_reveal_hidden_geosets(loaded)
	_scene_cache[path] = loaded
	var packed := PackedScene.new()
	if packed.pack(loaded) == OK:
		_packed_cache[path] = packed
	if from_gltf and RuntimeAssets.resolve_model_scene(path).is_empty():
		_enqueue_lazy_bake(path)
	return loaded


## 按指定动画 t=0 的 :visible 轨立刻设 Geoset 显隐（不依赖正在播放）。
func _snap_geoset_visibility_pose(root: Node, anim_name: String) -> void:
	var ap := _find_animation_player(root)
	if ap == null:
		return
	var resolved := anim_name
	if not ap.has_animation(resolved):
		resolved = ""
		for n in ap.get_animation_list():
			var leaf := str(n)
			var slash := leaf.rfind("/")
			if slash >= 0:
				leaf = leaf.substr(slash + 1)
			if leaf == anim_name or leaf.to_lower() == anim_name.to_lower():
				resolved = str(n)
				break
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
	for i in anim.get_track_count():
		var tpath := anim.track_get_path(i)
		var ps := str(tpath)
		if not ps.contains("Geoset_") or not ps.ends_with(":visible"):
			continue
		if anim.track_get_key_count(i) <= 0:
			continue
		var vis: bool = bool(anim.track_get_key_value(i, 0))
		var node_path := NodePath(ps.get_basename())
		var target := anim_root.get_node_or_null(node_path)
		if target is Node3D:
			(target as Node3D).visible = vis


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
	var res_p := RuntimeAssets.model_scene_path(glb_path)
	var err := RuntimeAssets.save_packed_scene(proto, res_p)
	if err != OK:
		err = RuntimeAssets.save_packed_scene(proto, RuntimeAssets.model_scene_user_path(glb_path))
	if err == OK:
		var packed := RuntimeAssets.load_packed_scene(
			res_p if RuntimeAssets.file_exists(res_p) else RuntimeAssets.model_scene_user_path(glb_path)
		)
		if packed != null:
			_packed_cache[glb_path] = packed
		return true
	return false


## Godot 导入丢弃蒙皮 Geoset / 空父节点上的 scale 轨；用旁路 *.geosetvis.json 补 `:visible`。
func _inject_geoset_vis_tracks(glb_path: String, root: Node) -> bool:
	if root == null or glb_path.is_empty():
		return false
	var json_res := _geoset_vis_json_path(glb_path)
	if json_res.is_empty() or not RuntimeAssets.file_exists(json_res):
		return false
	var disk := RuntimeAssets.project_abs(json_res)
	var f := FileAccess.open(disk, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	if text.is_empty():
		return false
	var data: Variant = JSON.parse_string(text)
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
		if anim_name.is_empty() or not ap.has_animation(anim_name):
			continue
		var anim := ap.get_animation(anim_name)
		if anim == null:
			continue
		_remove_geoset_visible_tracks(anim)
		var geosets: Variant = seq.get("geosets", {})
		if typeof(geosets) != TYPE_DICTIONARY:
			continue
		for gi_key in (geosets as Dictionary).keys():
			var mesh_n: Node = geoset_nodes.get(str(gi_key)) as Node
			if mesh_n == null:
				continue
			var keys_v: Variant = (geosets as Dictionary)[gi_key]
			if typeof(keys_v) != TYPE_ARRAY or (keys_v as Array).is_empty():
				continue
			# 轨路径相对 AnimationPlayer.root_node（默认 ..），不是相对 AP 自身
			var rel := anim_root.get_path_to(mesh_n)
			if str(rel).is_empty() or str(rel) == ".":
				continue
			var track_path := NodePath("%s:visible" % str(rel))
			var ti := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(ti, track_path)
			anim.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)
			anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_NEAREST)
			for key_v in keys_v as Array:
				if typeof(key_v) != TYPE_DICTIONARY:
					continue
				var kd: Dictionary = key_v
				var t := float(kd.get("t", 0.0))
				var vis := int(kd.get("v", 1)) != 0
				anim.track_insert_key(ti, t, vis)
			injected = true
	return injected


func _geoset_vis_json_path(glb_path: String) -> String:
	var logical := RuntimeAssets.relative_or_res_to_logical(glb_path)
	var lower := logical.to_lower()
	if lower.ends_with(".glb"):
		logical = logical.substr(0, logical.length() - 4) + ".geosetvis.json"
	elif lower.ends_with(".scn"):
		logical = logical.substr(0, logical.length() - 4) + ".geosetvis.json"
	else:
		logical = logical + ".geosetvis.json"
	return RuntimeAssets.converted_path(logical)


func _index_geoset_meshes(root: Node) -> Dictionary:
	var out: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var nm := str(n.name)
		if not nm.begins_with("Geoset_"):
			continue
		var id_str := nm.substr("Geoset_".length())
		if id_str.is_valid_int():
			out[id_str] = n
	return out


func _remove_geoset_visible_tracks(anim: Animation) -> void:
	for i in range(anim.get_track_count() - 1, -1, -1):
		var p := str(anim.track_get_path(i))
		if p.contains("Geoset_") and p.ends_with(":visible"):
			anim.remove_track(i)


## 把 replaceable 队伍色占位贴图换成 TeamColorXX（对齐 WE / HiveWE 预览染色）。
## color_index: 0..15（TeamColor 序号）。中立建筑常由 unitUI.teamColor 固定为 0（红），
## 与地图 owner（如 15 Neutral Passive）无关。
## hide_team_glow：隐藏 Team Glow（ReplaceableId=2）大面片——转换后常被画成实心色块。
## 同时隐藏预览不该出现的 UberSplat / Death 烟雾 / Portrait BackGround geoset。
##
## 两类 _rep1：
## - 纯队色占位：整面换成 TeamColorXX（步兵肩甲等）
## - 队色垫底（建筑旗帜等）：漫反射 alpha 下透队伍色 → ShaderMaterial
func apply_team_color(root: Node, color_index: int = 0, hide_team_glow: bool = true) -> void:
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
		# Team Glow：整 mesh 只有 team_color 占位，且比身体 geoset 大得多 → 隐藏
		# （圣骑士 Geoset_2 = ReplaceableId=2 Additive，被当成实心红面片）
		if hide_team_glow and _is_exclusive_team_color_mesh(mi) and _looks_like_team_glow(mi, body_aabb):
			mi.visible = false
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(si)
			if mat == null or not (mat is StandardMaterial3D):
				continue
			var sm := mat as StandardMaterial3D
			if not _is_team_color_material(sm):
				continue
			# Additive glow 材质：即使未隐藏也不要铺成实心 TeamColor
			var mat_key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
			if mat_key.contains("_fm3") or mat_key.contains("_fm4") or sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
				mi.visible = false
				break
			if _is_team_color_underlay_material(sm):
				mi.set_surface_override_material(si, _make_team_color_underlay(sm, tex, fallback))
			elif tex != null:
				var out := sm.duplicate() as StandardMaterial3D
				out.albedo_texture = tex
				out.albedo_color = Color.WHITE
				mi.set_surface_override_material(si, out)


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


func _make_team_color_underlay(
	src: StandardMaterial3D, team_tex: Texture2D, fallback: Color
) -> ShaderMaterial:
	var sh: Shader = load("res://assets/shaders/wc3_team_color_underlay.gdshader") as Shader
	var out := ShaderMaterial.new()
	out.shader = sh
	out.set_shader_parameter("diffuse_tex", src.albedo_texture)
	if team_tex != null:
		out.set_shader_parameter("team_color_tex", team_tex)
		out.set_shader_parameter("use_team_texture", true)
	else:
		out.set_shader_parameter("use_team_texture", false)
	out.set_shader_parameter("team_color_fallback", fallback)
	return out


func _is_exclusive_team_color_mesh(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.mesh.get_surface_count() <= 0:
		return false
	for si in range(mi.mesh.get_surface_count()):
		var mat: Material = mi.get_active_material(si)
		if mat == null or not (mat is StandardMaterial3D):
			return false
		if not _is_team_color_material(mat as StandardMaterial3D):
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


func _should_hide_preview_mesh(mi: MeshInstance3D) -> bool:
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
		if (
			blob.contains("ubersplat")
			or blob.contains("/splats/")
			or blob.contains("deathsmug")
			or blob.contains("death_smug")
			or blob.contains("background")
			or blob.contains("back_ground")
			or blob.contains("_portrait")
		):
			return true
		# 模型内嵌 Textures\Shadow.blp（地精商店脚底实心黑盘等）；真正建筑阴影走 unitUI.buildingShadow
		if _is_embedded_blob_shadow_tex(tex, blob):
			return true
		# Team Glow（_rep2 / team_glow 占位）：英雄光环/武器光晕，Stand 下应隐藏
		if blob.contains("team_glow") or blob.contains("_rep2"):
			return true
	return false


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
	_ensure_scene(path)
	return bool(_anim_flags.get(path, false))


## 优先播 Stand（及 Stand -1 等变体），否则空闲回退；循环。
## random_phase：多实例错开相位，避免蝙蝠/鸟群齐刷刷扑翅。
func autoplay_stand(root: Node, random_phase: bool = true) -> bool:
	if root == null:
		return false
	var ap := _find_animation_player(root)
	if ap == null:
		return false
	# 关掉 GLTF/烘焙场景自带的 autoplay（常为列表首条 Attack）
	ap.autoplay = ""
	ap.stop()
	var chosen := _pick_stand_name(ap)
	if chosen.is_empty():
		chosen = _pick_idle_fallback(ap)
	if chosen.is_empty():
		return false
	if not play_animation(root, chosen, true):
		return false
	if random_phase:
		var len: float = ap.current_animation_length
		if len > 0.05:
			ap.seek(randf() * len, true)
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
	if anim != null and loop:
		anim.loop_mode = Animation.LOOP_LINEAR
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
## - FilterMode Blend：Godot Alpha Blend / 甚至 DEPTH_PRE_PASS 仍可能透视 → 改 ALPHA_SCISSOR
## - 默认双面（旧 convert）→ 非 TwoSided/非 Additive 强制 cull_back，避免屋顶背面发黑
func _fix_wc3_blend_materials(root: Node) -> void:
	if root == null:
		return
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
			var fixed := _as_wc3_material_fix(mat)
			if fixed != null and fixed != mat:
				mi.set_surface_override_material(si, fixed)


func _as_wc3_material_fix(mat: Material) -> Material:
	var add := _as_wc3_additive_material(mat)
	if add != mat:
		return add
	var scissor := _as_wc3_blend_scissor_fix(mat)
	return _as_wc3_cull_back_fix(scissor)


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


## 旧 GLB 一律 doubleSided；非 Additive 改回 cull_back（屋顶背面不再透出发黑）。
func _as_wc3_cull_back_fix(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm := mat as StandardMaterial3D
	if sm.cull_mode != BaseMaterial3D.CULL_DISABLED:
		return mat
	if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return mat
	var key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	if key.contains("_fm3") or key.contains("_fm4") or key.contains("_rep2"):
		return mat
	var out := sm.duplicate() as StandardMaterial3D
	out.cull_mode = BaseMaterial3D.CULL_BACK
	return out


func _as_wc3_additive_material(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm := mat as StandardMaterial3D
	var key := str(sm.resource_name) + " " + str(sm.get_name())
	var tex: Texture2D = sm.albedo_texture
	var tex_path := ""
	if tex != null:
		tex_path = str(tex.resource_path) + " " + str(tex.resource_name)
	var want_add := (
		key.contains("_fm3")
		or key.contains("_fm4")
		or key.contains("_rep2")
		or tex_path.to_lower().contains("glow")
		or tex_path.to_lower().contains("team_glow")
	)
	if not want_add:
		return mat
	# 不改共享原型：duplicate 后写入 override
	var out := sm.duplicate() as StandardMaterial3D
	out.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	out.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	out.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	out.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
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


func _collect_mesh_parts(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			out.append({
				"mesh": mi.mesh,
				"material": mi.get_active_material(0),
			})
	for c in n.get_children():
		_collect_mesh_parts(c, out)
