class_name MapUnitLayer
extends Node3D
## 单位 / 建筑层：单 Node3D 实例（骨骼动画，不用 MultiMesh）。
## 大批量重建走分帧队列，避免开图卡死主线程。


signal batch_progress(done: int, total: int)
signal batch_finished(placed: int, placeholders: int)

## 产品注入：编辑器默认使用纯展示节点，游戏提供实体及运行态初始化。
var unit_factory: Callable
var unit_initializer: Callable

@export var try_load_glb: bool = true
## 每帧放置预算（毫秒）；模型已缓存时 instantiate 很快。
@export var batch_budget_ms: int = 28
@export var batch_max_per_frame: int = 64
## 每帧最多在主线程解析几个尚无 .scn 的 GLB（GLTFDocument 非线程安全）。
@export var gltf_parse_per_frame: int = 6
## false：不放置 sloc（游戏内隐藏开始点；编辑器保持 true）
@export var show_start_locations: bool = true
## false：不显示死亡掉落提示环（游戏内隐藏；编辑器对齐 WE 可开）
@export var show_drop_rings: bool = true

var _catalog: Wc3IdCatalog
var _cache: MapModelCache
var _effects: MapUnitEffects = MapUnitEffects.new()
var last_placed: int = 0
var last_placeholder: int = 0

var _batch_active: bool = false
var _batch_pending: Array[Dictionary] = [] ## 待放置 Dictionary
var _batch_done_count: int = 0
var _batch_total: int = 0
var _batch_hf: Wc3Heightfield = null
var _batch_gen: int = 0


func setup(catalog: Wc3IdCatalog, cache: MapModelCache) -> void:
	_catalog = catalog
	_cache = cache
	_effects.configure(cache)


func build(ctx: MapBuildContext) -> void:
	## 预览场景同步路径（单位少 / 非编辑器）。
	cancel_batch()
	_clear_children()
	last_placed = 0
	last_placeholder = 0
	if ctx == null:
		return
	if _cache != null and _cache.has_method("reset_load_stats"):
		_cache.reset_load_stats()
	var t0: int = Time.get_ticks_msec()
	var units: Array = ctx.units.get("units", [])
	var unique: int = 0
	var seen: Dictionary = {}
	var scn_ready: int = 0
	var missing_scn: PackedStringArray = PackedStringArray()
	for u: Variant in units:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = u as Dictionary
		var tid: String = str(entry.get("typeId", ""))
		var variation: int = int(entry.get("variation", 0))
		var glb: String = _unit_glb_path(entry)
		if glb.is_empty() or seen.has(glb):
			continue
		seen[glb] = true
		unique += 1
		if RuntimeAssets.resolve_model_scene(glb) != "":
			scn_ready += 1
		else:
			missing_scn.append("%s v%d → %s" % [tid, variation, glb.get_file()])
	for u: Variant in units:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		_place_one_internal(u as Dictionary, ctx.heightfield, true)
	var ms: float = Time.get_ticks_msec() - t0
	var scn_h: int = int(_cache.last_scn_hits) if _cache != null else 0
	var gltf_n: int = int(_cache.last_gltf_loads) if _cache != null else 0
	var cache_h: int = int(_cache.last_cache_hits) if _cache != null else 0
	AppLog.info(
		AppLog.Layer.LOAD,
		"Units",
		"glb=%d placeholder=%d unique=%d scnDisk=%d/%d loadMs=%d cacheHit=%d scnLoad=%d gltfParse=%d"
		% [last_placed, last_placeholder, unique, scn_ready, unique, ms, cache_h, scn_h, gltf_n]
	)
	if not missing_scn.is_empty():
		AppLog.warn(
			AppLog.Layer.LOAD,
			"Units",
			"缺旁路 .scn（%d/%d，同步将 GLTF 解析）: %s"
			% [missing_scn.size(), unique, ", ".join(missing_scn)]
		)
		# 方便复制进 bake --include
		var stems: PackedStringArray = PackedStringArray()
		for line: String in missing_scn:
			var arrow: int = line.find("→")
			if arrow >= 0:
				stems.append(line.substr(arrow + 1).strip_edges())
			else:
				stems.append(line)
		AppLog.info(
			AppLog.Layer.LOAD,
			"Units",
			"missing .scn stems: %s | hint: npm run bake:scn -- --force --include <path-fragment>"
			% ", ".join(stems)
		)


## 用 Document 的 AoS 条目全量重建（同步，仅小列表或测试用）。
func rebuild_from_list(hf: Wc3Heightfield, units: Array) -> void:
	var ctx: MapBuildContext = MapBuildContext.new()
	ctx.heightfield = hf
	ctx.units = {"units": units}
	build(ctx)


## 分帧 + 后台预载重建：.scn/GLB 字节在线程加载，主线程只实例化入树。
func rebuild_from_list_batched(hf: Wc3Heightfield, units: Array) -> void:
	cancel_batch()
	_clear_children()
	last_placed = 0
	last_placeholder = 0
	_batch_pending.clear()
	# 上一局若把 .gltf 误当 GLB 解析，会进 fail 黑名单；开图清掉
	RuntimeAssets.clear_gltf_fail_cache()
	var unique_paths: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var missing_scn: PackedStringArray = PackedStringArray()
	if _cache != null and _cache.has_method("reset_load_stats"):
		_cache.reset_load_stats()
	for u: Variant in units:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = (u as Dictionary).duplicate(true)
		_batch_pending.append(entry)
		if not try_load_glb or _catalog == null:
			continue
		var tid: String = str(entry.get("typeId", ""))
		var variation: int = int(entry.get("variation", 0))
		var glb: String = _catalog.converted_glb_path(tid, variation)
		if not glb.is_empty() and not seen.has(glb):
			seen[glb] = true
			unique_paths.append(glb)
			if RuntimeAssets.resolve_model_scene(glb) == "":
				missing_scn.append("%s v%d → %s" % [tid, variation, glb.get_file()])
		# HUD 肖像与战场体不同路径，一并预载以免点选卡顿
		var portrait: String = _catalog.portrait_glb_path(tid)
		if not portrait.is_empty() and not seen.has(portrait):
			seen[portrait] = true
			unique_paths.append(portrait)
			if RuntimeAssets.resolve_model_scene(portrait) == "":
				missing_scn.append("%s portrait → %s" % [tid, portrait.get_file()])
	if not missing_scn.is_empty():
		AppLog.warn(
			AppLog.Layer.LOAD,
			"Units",
			"缺可用旁路 .scn（%d/%d，将分帧 GLTF）：%s"
			% [missing_scn.size(), unique_paths.size(), ", ".join(missing_scn)]
		)
		AppLog.info(
			AppLog.Layer.LOAD,
			"Units",
			"missing .scn: %s" % ", ".join(missing_scn)
		)
	_batch_hf = hf
	_batch_done_count = 0
	_batch_total = _batch_pending.size()
	_batch_gen += 1
	_batch_active = _batch_total > 0
	if _cache != null and not unique_paths.is_empty():
		_cache.request_preload_many(unique_paths)
	set_process(_batch_active)
	if not _batch_active:
		batch_finished.emit(0, 0)
		return
	batch_progress.emit(0, _batch_total)


func cancel_batch() -> void:
	_batch_active = false
	_batch_pending.clear()
	_batch_done_count = 0
	_batch_total = 0
	_batch_hf = null
	_batch_gen += 1
	if _cache != null and _cache.has_method("cancel_preloads"):
		_cache.cancel_preloads()
	set_process(false)


func is_batch_loading() -> bool:
	return _batch_active


func batch_total() -> int:
	return _batch_total


func batch_done() -> int:
	return _batch_done_count


## 增量追加一条（笔刷放置）。返回根节点；失败 null。
func add_one(u: Dictionary, hf: Wc3Heightfield) -> Node3D:
	if u.is_empty() or _catalog == null:
		return null
	return _place_one_internal(u, hf, true)


func remove_by_creation_number(creation_number: int) -> bool:
	var node: Node3D = find_by_creation_number(creation_number)
	if node == null:
		return false
	# 须 queue_free：尸体过期常从 Unit.corpse_expired 信号栈进入；
	# 信号锁定期间 free() 会报 “Attempted to free a locked object”。
	remove_child(node)
	node.queue_free()
	return true


func find_by_creation_number(creation_number: int) -> Node3D:
	if creation_number < 0:
		return null
	for c: Node in get_children():
		if not (c is Node3D):
			continue
		var d: Dictionary = c.get_meta("unit_data", {})
		if d.is_empty():
			continue
		if int(d.get("creationNumber", -1)) != creation_number:
			continue
		return c as Node3D
	return null


## 地形改高后重算单位 Y。
func refresh_heights(hf: Wc3Heightfield) -> void:
	if hf == null or not hf.is_valid():
		return
	for c: Node in get_children():
		_effects._refresh_one_height(c, hf)


func _process(_delta: float) -> void:
	if not _batch_active:
		set_process(false)
		return
	var gen: int = _batch_gen
	if _cache != null:
		_cache.poll_preloads(gltf_parse_per_frame)
	if gen != _batch_gen:
		return

	var t0: int = Time.get_ticks_msec()
	var placed_this_frame: int = 0
	var i: int = 0
	while i < _batch_pending.size():
		if gen != _batch_gen:
			return
		var u: Dictionary = _batch_pending[i]
		var glb_path: String = _unit_glb_path(u)
		# 模型仍在后台加载：跳过，本帧先放其它已就绪的
		if (
			try_load_glb
			and not glb_path.is_empty()
			and _cache != null
			and not _cache.has_cached(glb_path)
			and _cache.is_preload_pending(glb_path)
		):
			i += 1
			continue
		_batch_pending.remove_at(i)
		# 已缓存：只实例化；未缓存且预载已结束：允许同步解析一次，避免永久粉胶囊
		var allow_sync: bool = (
			_cache == null
			or glb_path.is_empty()
			or not _cache.has_cached(glb_path)
		)
		_place_one_internal(u, _batch_hf, allow_sync)
		_batch_done_count += 1
		placed_this_frame += 1
		var elapsed: int = Time.get_ticks_msec() - t0
		if placed_this_frame >= batch_max_per_frame:
			break
		if elapsed >= batch_budget_ms and placed_this_frame >= 1:
			break

	if gen != _batch_gen:
		return
	batch_progress.emit(_batch_done_count, _batch_total)

	var preload_left: int = _cache.preload_pending_count() if _cache != null else 0
	if _batch_pending.is_empty():
		_batch_active = false
		_batch_hf = null
		set_process(false)
		AppLog.info(
			AppLog.Layer.LOAD,
			"Units",
			"threaded glb=%d placeholder=%d" % [last_placed, last_placeholder]
		)
		if _cache != null:
			AppLog.info(
				AppLog.Layer.LOAD,
				"Units",
				"threaded placed=%d ph=%d cache=%d scn=%d gltf=%d"
				% [
					last_placed,
					last_placeholder,
					int(_cache.last_cache_hits),
					int(_cache.last_scn_hits),
					int(_cache.last_gltf_loads),
				]
			)
		batch_finished.emit(last_placed, last_placeholder)
		return
	# 全部卡在 pending 且预载已结束 → 同步解析收尾（禁止再冻成占位粉胶囊）
	if preload_left == 0 and placed_this_frame == 0:
		while not _batch_pending.is_empty():
			var left: Dictionary = _batch_pending.pop_front()
			_place_one_internal(left, _batch_hf, true)
			_batch_done_count += 1
		batch_progress.emit(_batch_done_count, _batch_total)
		_batch_active = false
		_batch_hf = null
		set_process(false)
		AppLog.info(
			AppLog.Layer.LOAD,
			"Units",
			"threaded(flush) glb=%d placeholder=%d" % [last_placed, last_placeholder]
		)
		batch_finished.emit(last_placed, last_placeholder)


func _unit_glb_path(u: Dictionary) -> String:
	if _catalog == null:
		return ""
	return _catalog.converted_glb_path(str(u.get("typeId", "")), int(u.get("variation", 0)))


func _place_one_internal(u: Dictionary, hf: Wc3Heightfield, allow_sync_load: bool = true) -> Node3D:
	var type_id: String = str(u.get("typeId", ""))
	if not show_start_locations and type_id == "sloc":
		return null
	var variation: int = int(u.get("variation", 0))
	var pos: Dictionary = u.get("position", {})
	var owner_id: int = int(u.get("owner", 12))
	var angle: float = float(u.get("angle", 0.0))
	var scale_data: Dictionary = u.get("scale", {})
	var wx: float = float(pos.get("x", 0.0))
	var wy: float = float(pos.get("y", 0.0))
	var wz: float = float(pos.get("z", 0.0))
	if hf != null and hf.is_valid():
		wz = hf.interpolated_height(wx, wy)
		pos = pos.duplicate()
		pos["z"] = wz
		u = u.duplicate(true)
		u["position"] = pos
	var gpos: Vector3 = Wc3Coords.wc3_xy_to_godot(wx, wy, wz)
	var node: Node3D = _make_unit_node(type_id, variation, owner_id, allow_sync_load)
	if node.get_meta("is_placeholder", false):
		last_placeholder += 1
	else:
		last_placed += 1
		var sx: float = float(scale_data.get("x", 1.0))
		var sy: float = float(scale_data.get("y", 1.0))
		var sz: float = float(scale_data.get("z", 1.0))
		if _catalog != null and not BuildingVisual.is_building(type_id):
			var ms: float = float(_catalog.lookup(type_id).get("model_scale", 1.0))
			if ms > 0.0:
				sx *= ms
				sy *= ms
				sz *= ms
		var scale_node: Node3D = _scale_target_for(node)
		var b: Vector3 = scale_node.scale
		scale_node.scale = Vector3(b.x * sx, b.y * sz, b.z * sy)
	node.name = "%s_%s" % [type_id, str(u.get("creationNumber", 0))]
	node.position = gpos
	# 模型和地图使用相同换轴，单位与装饰物均保留原始朝向角。
	node.rotation.y = Wc3Coords.yaw_wc3_unit_to_godot(angle)
	node.set_meta("unit_data", u.duplicate(true))
	add_child(node)
	if not node.get_meta("is_placeholder", false) and _cache != null:
		var glb: String = _unit_glb_path(u)
		if not CompiledModelPresentation.is_compiled(node.get_node_or_null("Model")) and not glb.is_empty() and Wc3Pe2Particles.has_emitters(glb):
			Wc3Pe2Particles.attach_to(node, glb)
		# 建筑（含主城升本档）按 typeId 选 Stand / Stand Upgrade*；单位仍走普通 Stand
		if BuildingVisual.is_building(type_id):
			# 仅明确半成品播 Birth。地图 hitPoints=-1 表示「用默认满血」，切勿当成残血开工。
			# 金矿等中立建筑始终 Stand（Birth 很长且带尘效，会整图错乱）。
			var under: bool = bool(u.get("under_construction", false))
			if under and type_id != "ngol":
				BuildingVisual.apply_phase(_cache, node, type_id, BuildingVisual.Phase.BIRTH)
			else:
				BuildingVisual.apply_idle(_cache, node, type_id)
			_effects._apply_building_ground(node, type_id, hf)
		else:
			var spawn_anim: String = str(u.get("spawn_anim", ""))
			if spawn_anim == "Birth":
				_effects._play_unit_birth_then_stand(node, type_id, glb)
			else:
				# Stand + geosetvis 定格：藏尸体/无关 Geoset（羊、野猪、野怪等同建筑/树）
				_cache.autoplay_stand(node)
				if _cache.has_method("snap_stand_geoset_visibility"):
					_cache.call("snap_stand_geoset_visibility", node)
				if not CompiledModelPresentation.is_compiled(node.get_node_or_null("Model")) and not glb.is_empty():
					Wc3Pe2Particles.apply_sequence(node, "Stand")
	_effects._sync_drop_ring(node, u, show_drop_rings)
	if unit_initializer.is_valid():
		unit_initializer.call(node)
	_effects._apply_unit_render_layers(node)
	return node


## 单位/建筑走 RENDER_LAYER_UNITS，使 UberSplat Decal 只印地形、不印墙体。
func _make_unit_node(
	type_id: String, variation: int, owner_id: int, allow_sync_load: bool = true
) -> Node3D:
	var model: Node3D = null
	if try_load_glb and _catalog != null and _cache != null:
		var glb: String = _catalog.converted_glb_path(type_id, variation)
		if not glb.is_empty():
			if _cache.has_cached(glb) or allow_sync_load:
				var unit_soft: bool = not BuildingVisual.is_building(type_id)
				var inst: Node3D = CompiledModelPresentation.instantiate(glb, _cache, unit_soft)
				if inst:
					inst.set_meta("is_placeholder", false)
					# 开始点本体即队伍色环；英雄 Team Glow 也需染色显示
					var color_i: int = resolve_team_color_index(type_id, owner_id)
					CompiledModelPresentation.apply_team(inst, color_i, _cache)
					model = inst
	if model == null:
		model = MapPlaceholders.make_entity(type_id, owner_id, true)
		model.set_meta("is_placeholder", true)
	return _wrap_unit_entity(model)


## 实体根 Unit + 子节点 Model（表现）；unit_data / 变换挂在 Unit 上。
func _wrap_unit_entity(model: Node3D) -> Node3D:
	var unit: Node3D = unit_factory.call() if unit_factory.is_valid() else Node3D.new()
	var is_ph: bool = bool(model.get_meta("is_placeholder", false))
	unit.set_meta("is_placeholder", is_ph)
	model.name = "Model"
	unit.add_child(model)
	return unit


func _scale_target_for(node: Node3D) -> Node3D:
	var model: Node3D = node.get_node_or_null("Model") as Node3D
	if model != null:
		return model
	return node


## 有死亡掉落时在头顶挂白色提示环（对齐 WE；游戏内可关）。
func _clear_children() -> void:
	# 立即释放，避免分帧重建时与旧节点并存
	for c: Node in get_children():
		remove_child(c)
		c.free()

static func resolve_team_color_index(type_id: String, owner_id: int) -> int:
	return MapUnitEffects.resolve_team_color_index(type_id, owner_id)
