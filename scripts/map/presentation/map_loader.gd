class_name MapLoader
extends Node3D

## 地图装配入口：构建 MapBuildContext，按序驱动各 Layer。

signal map_loaded

@export var map_dir: String = "res://assets/map-parsed/losttemple"
@export var build_water: bool = true
@export var build_cliffs: bool = true
@export var place_doodads: bool = true
@export var place_units: bool = false
## 游戏内应关闭：开始点（sloc）仅编辑器可见
@export var show_start_locations: bool = true
## 游戏内应关闭：单位死亡掉落提示环仅编辑器可见
@export var show_drop_rings: bool = true
@export var try_load_glb: bool = true
@export var multimesh_threshold: int = 8
@export var status_path: NodePath = ^"../UI/Status"
## false：由外部（如地图编辑器）调用 reload_from_hf，不在 _ready 读盘
@export var auto_load_on_ready: bool = true
## 重建地面后生成 trimesh 碰撞（编辑器笔刷拾取用）
@export var build_terrain_collision: bool = false

@export_group("寻路调试")
## GPU 三级栅格：小灰(32) / 中白(128) / 大黄(512)（地图场景自动开；编辑器改用 set_view_grid_level）
@export var show_pathing_debug_grid: bool = true
## FLAG_RAMP 蓝菱形（逻辑验收；不依赖 Present 坡模）
@export var show_ramp_debug: bool = true
## View→路径-地面：不可走 / 不可建造色块
@export var show_pathing_ground: bool = false

## 查看→栅格：0无 / 1大黄 / 2大+中白 / 3大+中+小灰
enum ViewGridLevel { NONE = 0, LARGE = 1, MEDIUM = 2, SMALL = 3 }
var _view_grid_level: int = ViewGridLevel.NONE

@export_group("岸浪微调")
## 悬崖泡沫额外退入水面（格）。全悬崖共用。
@export_range(0.0, 0.40, 0.01) var foam_cliff_out_extra: float = 0.08
## 斜坡泡沫向岸拉近（格）。
@export_range(0.0, 0.55, 0.01) var foam_ramp_pull_tiles: float = 0.38
## 普通平缓岸向岸拉近（格）
@export_range(0.0, 0.40, 0.01) var foam_shore_pull_tiles: float = 0.10

@onready var _terrain: MapTerrainLayer = $Terrain
@onready var _water: MapWaterLayer = $Water
@onready var _cliffs: MapCliffLayer = $Cliffs
@onready var _ramps: MapRampLayer = $Ramps
@onready var _doodads: MapDoodadLayer = $Doodads
@onready var _units: MapUnitLayer = $Units
@onready var _debug_grid: Node = $DebugGrid
@onready var _ramp_debug: Node = $RampDebug
@onready var _boundary: MapBoundaryLayer = get_node_or_null("Boundary") as MapBoundaryLayer
@onready var _pathing_layer: MapPathingLayer = get_node_or_null("Pathing") as MapPathingLayer

var _catalog := Wc3IdCatalog.new()
var _tiles := Wc3TerrainTileCatalog.new()
var _cliff_catalog := Wc3CliffCatalog.new()
var _cache := MapModelCache.new()
var _status: Label
## 非空时优先于磁盘 JSON（编辑器内存文档）
var _external_hf: Dictionary = {}
var _external_info: Dictionary = {}
var _tiles_ready: bool = false
var _pathing_map: Wc3PathingMap = null
## 动态 pathTex blit 用的实例列表（单位/建筑；树木等装饰需一并 blit — Echo Isles 的 WPM 未含树脚印）
var _pathing_unit_entries: Array = []
var _pathing_doodad_entries: Array = []
## 最近一次加载的 heightfield JSON（供运行时加单位插值高度）
var _last_hf_dict: Dictionary = {}
var _map_ready: bool = false


func get_tiles() -> Wc3TerrainTileCatalog:
	return _tiles


func get_cliff_catalog() -> Wc3CliffCatalog:
	return _cliff_catalog


func get_id_catalog() -> Wc3IdCatalog:
	# 编辑器默认 place_doodads=false，_ready 可能跳过 load
	if _catalog.doodad_count() == 0 and _catalog.destructable_count() == 0:
		_catalog.load_default()
	return _catalog


func get_model_cache() -> MapModelCache:
	return _cache


func get_doodad_layer() -> MapDoodadLayer:
	return _doodads


func get_terrain_layer() -> MapTerrainLayer:
	return _terrain


func get_view_grid_level() -> int:
	return _view_grid_level


## 察看→栅格：无 / 大 / 中 / 小（嵌套显示：小 ⊂ 中 ⊂ 大）。
func set_view_grid_level(level: int) -> void:
	_view_grid_level = clampi(level, ViewGridLevel.NONE, ViewGridLevel.SMALL)
	_apply_view_grid()


func _apply_view_grid() -> void:
	if _debug_grid == null or not _debug_grid.has_method("set_grid_flags"):
		return
	var show_large := _view_grid_level >= ViewGridLevel.LARGE
	var show_medium := _view_grid_level >= ViewGridLevel.MEDIUM
	var show_small := _view_grid_level >= ViewGridLevel.SMALL
	_debug_grid.set_grid_flags(show_large, show_medium, show_small)


func _ready() -> void:
	if not status_path.is_empty():
		_status = get_node_or_null(status_path) as Label
	_doodads.try_load_glb = try_load_glb
	_doodads.multimesh_threshold = multimesh_threshold
	_units.try_load_glb = try_load_glb
	_units.show_start_locations = show_start_locations
	_units.show_drop_rings = show_drop_rings
	_doodads.setup(_catalog, _cache)
	_units.setup(_catalog, _cache)

	_set_status("加载地形贴图索引…")
	_tiles.load_default()
	_cliff_catalog.load_default()
	_tiles_ready = true
	if place_units or place_doodads or show_pathing_debug_grid:
		_catalog.load_default()
	await get_tree().process_frame
	if auto_load_on_ready:
		await _load_all()


## 用内存 heightfield 重建地图（编辑器主路径）。
func reload_from_hf(hf: Dictionary, info: Dictionary = {}, p_map_dir: String = "") -> void:
	if hf.is_empty():
		_set_status("reload_from_hf：heightfield 为空")
		return
	_external_hf = hf
	_external_info = info
	if not p_map_dir.is_empty():
		map_dir = p_map_dir
	elif map_dir.is_empty():
		map_dir = "res://"
	if not _tiles_ready:
		_tiles.load_default()
		_cliff_catalog.load_default()
		_tiles_ready = true
	await _load_all()


func _build_boundary(ctx: MapBuildContext) -> void:
	if _boundary == null:
		return
	_boundary.build(ctx)


func _build_ramps(ctx: MapBuildContext) -> void:
	if _ramps == null:
		return
	_ramps.build(ctx)


## 挂直崖前：ensure 坡拓扑并按单块模型过滤 cliff_placements（不污染 Logic 缓存语义：ctx 每次新建）。
func _apply_ramp_cliff_filter(ctx: MapBuildContext) -> int:
	if ctx == null:
		return 0
	ctx.ensure_cliff_topology()
	ctx.ensure_ramp_topology()
	var before: int = ctx.cliff_placements.size()
	ctx.cliff_placements = Wc3RampLogic.filter_cliff_placements(
		ctx.cliff_placements, ctx.heightfield, ctx.ramp
	)
	var removed: int = before - ctx.cliff_placements.size()
	if removed > 0:
		MapLog.info(
			MapLog.Layer.PRESENT,
			"MapLoader",
			"ramp filtered cliffs=%d (kept=%d)" % [removed, ctx.cliff_placements.size()]
		)
	return removed


func _build_ramp_debug(ctx) -> void:
	if _ramp_debug == null or not _ramp_debug.has_method("build"):
		return
	_ramp_debug.enabled = show_ramp_debug
	_ramp_debug.build(ctx)


func get_show_ramp_debug() -> bool:
	return show_ramp_debug


func set_show_ramp_debug(on: bool) -> void:
	show_ramp_debug = on
	if _external_hf.is_empty() and map_dir.is_empty():
		if _ramp_debug != null and _ramp_debug.has_method("build"):
			_ramp_debug.enabled = false
			_ramp_debug.build(null)
		return
	var hf: Dictionary = _external_hf
	if hf.is_empty():
		return
	var ctx = MapBuildContext.create(
		map_dir if not map_dir.is_empty() else "res://",
		hf,
		_external_info,
		_tiles,
		_catalog,
		_cache,
		_cliff_catalog
	)
	_build_ramp_debug(ctx)


func get_pathing_map() -> Wc3PathingMap:
	return _pathing_map


func is_map_ready() -> bool:
	return _map_ready


func get_heightfield_dict() -> Dictionary:
	if not _last_hf_dict.is_empty():
		return _last_hf_dict
	if not _external_hf.is_empty():
		return _external_hf
	if map_dir.is_empty():
		return {}
	return _read_json(map_dir.path_join("terrain-heightfield.json"))


func get_show_pathing_ground() -> bool:
	return show_pathing_ground


func get_pathing_overlay_cell_count() -> int:
	if _pathing_layer == null:
		_pathing_layer = get_node_or_null("Pathing") as MapPathingLayer
	if _pathing_layer == null:
		return 0
	return int(_pathing_layer.last_cell_count)


func set_show_pathing_ground(on: bool) -> void:
	show_pathing_ground = on
	_rebuild_pathing_overlay()


## 编辑器注入 Document 的寻路面（优先于磁盘 / 合成）。
func set_pathing_map(pathing: Wc3PathingMap) -> void:
	_pathing_map = pathing
	_rebuild_pathing_overlay()


func _ensure_pathing_map(hf: Wc3Heightfield) -> void:
	if _pathing_map != null and _pathing_map.is_valid():
		_pathing_map.sync_origin_from_heightfield(hf)
		return
	var path_json := map_dir.path_join("pathing.json") if not map_dir.is_empty() else ""
	if not path_json.is_empty():
		var loaded := Wc3PathingMap.load_json_path(path_json)
		if loaded != null and loaded.is_valid():
			loaded.sync_origin_from_heightfield(hf)
			_pathing_map = loaded
			return
	_pathing_map = Wc3PathingMap.synthesize_from_heightfield(hf, _tiles)


## 按 Catalog.path_tex 把单位/建筑/装饰（含树木）脚印 OR 进动态寻路面。
## 注：部分地图 pathing.json（WPM）未烘焙树木脚印，必须以 doodads 动态 blit。
func _apply_dynamic_pathing() -> void:
	if _pathing_map == null or not _pathing_map.is_valid():
		return
	if _pathing_unit_entries.is_empty() and place_units and not map_dir.is_empty():
		var unit_path := map_dir.path_join("units.json")
		if FileAccess.file_exists(unit_path):
			var unit_list: Wc3UnitList = Wc3UnitList.load_json_path(unit_path)
			if unit_list != null:
				_pathing_unit_entries = unit_list.to_entries_array()
	if _pathing_doodad_entries.is_empty() and place_doodads and not map_dir.is_empty():
		var dood_path := map_dir.path_join("doodads.json")
		if FileAccess.file_exists(dood_path):
			var dood_list: Wc3DoodadList = Wc3DoodadList.load_json_path(dood_path)
			if dood_list != null:
				_pathing_doodad_entries = dood_list.to_entries_array()
	var merged: Array = []
	merged.append_array(_pathing_unit_entries)
	merged.append_array(_pathing_doodad_entries)
	var n: int = _pathing_map.apply_entity_pathing(merged, get_id_catalog())
	if n > 0:
		print("Pathing: blit pathTex ×%d (units=%d doodads=%d)" % [n, _pathing_unit_entries.size(), _pathing_doodad_entries.size()])
		MapLog.info(
			MapLog.Layer.PRESENT,
			"Pathing",
			"blit pathTex ×%d (units=%d doodads=%d)" % [n, _pathing_unit_entries.size(), _pathing_doodad_entries.size()]
		)


func _rebuild_pathing_overlay() -> void:
	if _pathing_layer == null:
		_pathing_layer = get_node_or_null("Pathing") as MapPathingLayer
	var hf: Wc3Heightfield = null
	if not _external_hf.is_empty():
		hf = Wc3Heightfield.from_dict(_external_hf, true)
	_ensure_pathing_map(hf)
	# 无论是否显示 overlay，都要 blit 动态脚印（树木不可走依赖此步）
	_apply_dynamic_pathing()
	if _pathing_layer == null:
		push_warning("MapLoader: 缺少 Pathing 层，无法显示路径-地面")
		return
	_pathing_layer.set_visible_overlay(show_pathing_ground)
	if not show_pathing_ground:
		_pathing_layer.clear()
		return
	_pathing_layer.rebuild(_pathing_map, hf)


## 编辑器：用 Document 的 doodads 重建装饰物层（不读盘）。
## doodads_src 可为 AoS Array，或 Wc3DoodadList。
func rebuild_doodads_from_list(hf: Dictionary, doodads_src: Variant) -> void:
	if _doodads == null:
		return
	_doodads.setup(get_id_catalog(), _cache)
	_doodads.try_load_glb = try_load_glb
	_doodads.multimesh_threshold = multimesh_threshold
	var entries: Array = _coerce_doodad_entries(doodads_src)
	_pathing_doodad_entries = entries
	var heightfield: Wc3Heightfield = null
	if not hf.is_empty():
		heightfield = Wc3Heightfield.from_dict(hf, true)
	_doodads.rebuild_from_list(heightfield, entries)
	if show_pathing_ground or (_pathing_map != null and _pathing_map.is_valid()):
		_rebuild_pathing_overlay()


## 编辑器：用 Document 的 units 重建单位层（不读盘）。
## batched=true 时分帧放置，避免大图卡死。
func rebuild_units_from_list(hf: Dictionary, units_src: Variant, batched: bool = false) -> void:
	if _units == null:
		return
	_units.setup(get_id_catalog(), _cache)
	_units.try_load_glb = try_load_glb
	_units.show_start_locations = show_start_locations
	_units.show_drop_rings = show_drop_rings
	var entries: Array = _coerce_unit_entries(units_src)
	_pathing_unit_entries = entries
	var heightfield: Wc3Heightfield = null
	if not hf.is_empty():
		heightfield = Wc3Heightfield.from_dict(hf, true)
	if batched and _units.has_method("rebuild_from_list_batched"):
		_units.rebuild_from_list_batched(heightfield, entries)
	else:
		_units.rebuild_from_list(heightfield, entries)
	if show_pathing_ground:
		_rebuild_pathing_overlay()


func get_unit_layer() -> MapUnitLayer:
	return _units


func is_units_batch_loading() -> bool:
	return _units != null and _units.has_method("is_batch_loading") and _units.is_batch_loading()


## 编辑器增量放置一条单位。
func add_unit_instance(entry: Dictionary, hf: Dictionary) -> bool:
	if _units == null:
		return false
	_units.setup(get_id_catalog(), _cache)
	var heightfield: Wc3Heightfield = null
	if not hf.is_empty():
		heightfield = Wc3Heightfield.from_dict(hf, true)
	var ok: bool = _units.add_one(entry, heightfield)
	if ok:
		_pathing_unit_entries.append(entry)
		if show_pathing_ground:
			_rebuild_pathing_overlay()
	return ok


func remove_unit_instance(creation_number: int) -> bool:
	if _units == null:
		return false
	return _units.remove_by_creation_number(creation_number)


func find_unit_node(creation_number: int) -> Node3D:
	if _units == null:
		return null
	return _units.find_by_creation_number(creation_number)


func update_unit_instance(entry: Dictionary, hf: Dictionary) -> bool:
	if _units == null or entry.is_empty():
		return false
	var cn: int = int(entry.get("creationNumber", -1))
	if cn < 0:
		return false
	if not _units.remove_by_creation_number(cn):
		return false
	return add_unit_instance(entry, hf)


## 编辑器增量放置一条。
func add_doodad_instance(entry: Dictionary, hf: Dictionary) -> bool:
	if _doodads == null:
		return false
	_doodads.setup(get_id_catalog(), _cache)
	var heightfield: Wc3Heightfield = null
	if not hf.is_empty():
		heightfield = Wc3Heightfield.from_dict(hf, true)
	var ok: bool = _doodads.add_one(entry, heightfield)
	if ok:
		_pathing_doodad_entries.append(entry)
		_rebuild_pathing_overlay()
	return ok


## 按 creationNumber 移除 Present；MultiMesh 组内失败时返回 false。
func remove_doodad_instance(creation_number: int) -> bool:
	if _doodads == null:
		return false
	var ok: bool = _doodads.remove_by_creation_number(creation_number)
	if ok:
		var cn: int = creation_number
		for i in range(_pathing_doodad_entries.size() - 1, -1, -1):
			var e: Variant = _pathing_doodad_entries[i]
			if typeof(e) == TYPE_DICTIONARY and int((e as Dictionary).get("creationNumber", -1)) == cn:
				_pathing_doodad_entries.remove_at(i)
				break
		_rebuild_pathing_overlay()
	return ok


## 查找装饰物 Present 节点（编辑器选中环等）。
func find_doodad_node(creation_number: int) -> Node3D:
	if _doodads == null:
		return null
	return _doodads.find_by_creation_number(creation_number)


## 更新一条 Present：先删后加；失败（MultiMesh）返回 false，调用方应全量 rebuild。
func update_doodad_instance(entry: Dictionary, hf: Dictionary) -> bool:
	if _doodads == null or entry.is_empty():
		return false
	var cn: int = int(entry.get("creationNumber", -1))
	if cn < 0:
		return false
	if not _doodads.remove_by_creation_number(cn):
		return false
	return add_doodad_instance(entry, hf)


## 仅重建地面（笔刷脏更新）；不重载装饰/单位。
func rebuild_terrain_only(hf: Dictionary, info: Dictionary = {}) -> void:
	if hf.is_empty():
		MapLog.warn(MapLog.Layer.PRESENT, "MapLoader", "rebuild_terrain_only: hf 空")
		return
	_external_hf = hf
	if not info.is_empty():
		_external_info = info
	var ctx = MapBuildContext.create(
		map_dir if not map_dir.is_empty() else "res://",
		hf,
		_external_info,
		_tiles,
		_catalog,
		_cache,
		_cliff_catalog
	)
	MapLog.info(
		MapLog.Layer.PRESENT,
		"MapLoader",
		"rebuild_terrain_only %dx%d" % [ctx.width(), ctx.height()]
	)
	ctx.ensure_cliff_topology()
	_terrain.build(ctx)
	_build_boundary(ctx)
	_build_ramps(ctx)
	_build_ramp_debug(ctx)
	_apply_view_grid()
	# 改地形后刷 doodad Y（change_doodad_heights 等价；HF 走 undo 自动同步 doodad 状态）
	if _doodads != null:
		_doodads.refresh_heights(ctx.heightfield)
	if _units != null:
		_units.refresh_heights(ctx.heightfield)
	if build_terrain_collision:
		_ensure_terrain_collision()


## 地表 + 悬崖 + 水面（悬崖笔刷脏更新）。
func rebuild_terrain_cliffs_water(hf: Dictionary, info: Dictionary = {}) -> void:
	if hf.is_empty():
		MapLog.warn(MapLog.Layer.PRESENT, "MapLoader", "rebuild_cliffs_water: hf 空")
		return
	_external_hf = hf
	if not info.is_empty():
		_external_info = info
	var ctx = MapBuildContext.create(
		map_dir if not map_dir.is_empty() else "res://",
		hf,
		_external_info,
		_tiles,
		_catalog,
		_cache,
		_cliff_catalog
	)
	MapLog.info(
		MapLog.Layer.PRESENT,
		"MapLoader",
		"rebuild_cliffs_water %dx%d" % [ctx.width(), ctx.height()]
	)
	_apply_ramp_cliff_filter(ctx)
	_terrain.build(ctx)
	_build_boundary(ctx)
	if build_terrain_collision:
		_ensure_terrain_collision()
	if build_cliffs:
		_cliffs.build(ctx)
	_build_ramps(ctx)
	if build_water:
		_water.foam_cliff_out_extra = foam_cliff_out_extra
		_water.foam_ramp_pull_tiles = foam_ramp_pull_tiles
		_water.foam_shore_pull_tiles = foam_shore_pull_tiles
		_water.build(ctx)
	_build_ramp_debug(ctx)
	_apply_view_grid()
	# 改地形后刷 doodad / unit Y（同 rebuild_terrain_only）
	if _doodads != null:
		_doodads.refresh_heights(ctx.heightfield)
	if _units != null:
		_units.refresh_heights(ctx.heightfield)

func _load_all() -> void:
	_map_ready = false
	var t0 := Time.get_ticks_msec()
	var hf: Dictionary = _external_hf
	if hf.is_empty():
		hf = _read_json(map_dir.path_join("terrain-heightfield.json"))
	if hf.is_empty():
		_set_status("地图加载失败：缺少 terrain-heightfield.json")
		return
	_last_hf_dict = hf

	var info: Dictionary = _external_info
	if info.is_empty() and _external_hf.is_empty():
		info = _read_json(map_dir.path_join("info.json"))
	var ctx = MapBuildContext.create(map_dir, hf, info, _tiles, _catalog, _cache, _cliff_catalog)
	_apply_ramp_cliff_filter(ctx)

	_set_status("生成贴图地形高度图（悬崖留缝）…")
	_terrain.build(ctx)
	_build_boundary(ctx)
	if build_terrain_collision:
		_ensure_terrain_collision()
	await get_tree().process_frame

	if build_cliffs:
		_set_status("放置悬崖模型…")
		_cliffs.build(ctx)
		await get_tree().process_frame
	_set_status("放置斜坡模型…")
	_build_ramps(ctx)
	await get_tree().process_frame
	_build_ramp_debug(ctx)
	_apply_view_grid()
	if build_water:
		_set_status("生成水体…")
		_water.foam_cliff_out_extra = foam_cliff_out_extra
		_water.foam_ramp_pull_tiles = foam_ramp_pull_tiles
		_water.foam_shore_pull_tiles = foam_shore_pull_tiles
		_water.build(ctx)
		await get_tree().process_frame
	# Doodad/Unit：SoA 加载后再 to_dict 填 ctx（Layer 仍吃 AoS）
	if place_units:
		var unit_path: String = map_dir.path_join("units.json")
		if FileAccess.file_exists(unit_path):
			var unit_list: Wc3UnitList = Wc3UnitList.load_json_path(unit_path)
			ctx.units = unit_list.to_dict() if unit_list != null else {}
		_pathing_unit_entries = ctx.units.get("units", []) as Array if typeof(ctx.units) == TYPE_DICTIONARY else []
		_units.build(ctx)
		await get_tree().process_frame
	else:
		_pathing_unit_entries = []
	if place_doodads:
		var dood_path: String = map_dir.path_join("doodads.json")
		if FileAccess.file_exists(dood_path):
			var dood_list: Wc3DoodadList = Wc3DoodadList.load_json_path(dood_path)
			ctx.doodads = dood_list.to_dict() if dood_list != null else {}
		_pathing_doodad_entries = (
			ctx.doodads.get("doodads", []) as Array if typeof(ctx.doodads) == TYPE_DICTIONARY else []
		)
		_doodads.build(ctx)
		await get_tree().process_frame
	else:
		_pathing_doodad_entries = []
	if show_pathing_debug_grid and _debug_grid:
		_set_status("开启调试栅格（GPU）…")
		_debug_grid.build(ctx)
		await get_tree().process_frame
	_ensure_pathing_map(ctx.heightfield as Wc3Heightfield)
	_apply_dynamic_pathing()
	if show_pathing_ground:
		_rebuild_pathing_overlay()

	var ms := Time.get_ticks_msec() - t0
	var cliff_n := _cliffs.last_placed if build_cliffs else 0
	var ramp_n := _ramps.last_placement_count if _ramps else 0
	var water_n := _water.last_cell_count if build_water else 0
	var shore_n := _water.last_shore_count if build_water else 0
	var doodad_n := _doodads.last_placed if place_doodads else 0
	_set_status(
		"地形就绪（%d ms，留缝 %d，悬崖 %d，斜坡 %d，水面 %d，岸浪 %d，装饰 %d）— WASD 移动，右键转向，滚轮缩放"
		% [ms, _terrain.last_gap_count, cliff_n, ramp_n, water_n, shore_n, doodad_n]
	)
	print(
		"Terrain load in %d ms from %s (gaps=%d cliffs=%d ramps=%d water=%d shore=%d doodads=%d)"
		% [ms, map_dir, _terrain.last_gap_count, cliff_n, ramp_n, water_n, shore_n, doodad_n]
	)
	_map_ready = true
	map_loaded.emit()


func _ensure_terrain_collision() -> void:
	var ground := _terrain.get_node_or_null("Ground") as MeshInstance3D
	if ground == null or ground.mesh == null:
		return
	for c in ground.get_children():
		if c is StaticBody3D:
			c.free()
	ground.create_trimesh_collision()


func _coerce_doodad_entries(src: Variant) -> Array:
	if src is Wc3DoodadList:
		return (src as Wc3DoodadList).to_entries_array()
	if typeof(src) == TYPE_ARRAY:
		return src as Array
	if typeof(src) == TYPE_DICTIONARY:
		var arr: Variant = (src as Dictionary).get("doodads", [])
		return arr as Array if typeof(arr) == TYPE_ARRAY else []
	return []


func _coerce_unit_entries(src: Variant) -> Array:
	if src is Wc3UnitList:
		return (src as Wc3UnitList).to_entries_array()
	if typeof(src) == TYPE_ARRAY:
		return src as Array
	if typeof(src) == TYPE_DICTIONARY:
		var arr: Variant = (src as Dictionary).get("units", [])
		return arr as Array if typeof(arr) == TYPE_ARRAY else []
	return []


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("缺少 %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _set_status(text: String) -> void:
	if _status:
		_status.text = text
	print(text)
