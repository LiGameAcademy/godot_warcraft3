class_name MapLoader
extends Node3D

## 地图装配入口：构建 MapBuildContext，按序驱动各 Layer。

@export var map_dir: String = "res://assets/map-parsed/losttemple"
@export var build_water: bool = true
@export var build_cliffs: bool = true
@export var place_doodads: bool = true
@export var place_units: bool = false
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

var _catalog := Wc3IdCatalog.new()
var _tiles := Wc3TerrainTileCatalog.new()
var _cliff_catalog := Wc3CliffCatalog.new()
var _cache := MapModelCache.new()
var _status: Label
## 非空时优先于磁盘 JSON（编辑器内存文档）
var _external_hf: Dictionary = {}
var _external_info: Dictionary = {}
var _tiles_ready: bool = false


func get_tiles() -> Wc3TerrainTileCatalog:
	return _tiles


func get_cliff_catalog() -> Wc3CliffCatalog:
	return _cliff_catalog


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


func _build_ramps(ctx: MapBuildContext) -> void:
	if _ramps == null:
		return
	_ramps.build(ctx)


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
	_build_ramps(ctx)
	_apply_view_grid()
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
	ctx.ensure_cliff_topology()
	_terrain.build(ctx)
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

func _load_all() -> void:
	var t0 := Time.get_ticks_msec()
	var hf: Dictionary = _external_hf
	if hf.is_empty():
		hf = _read_json(map_dir.path_join("terrain-heightfield.json"))
	if hf.is_empty():
		_set_status("地图加载失败：缺少 terrain-heightfield.json")
		return

	var info: Dictionary = _external_info
	if info.is_empty() and _external_hf.is_empty():
		info = _read_json(map_dir.path_join("info.json"))
	var ctx = MapBuildContext.create(map_dir, hf, info, _tiles, _catalog, _cache, _cliff_catalog)
	ctx.ensure_cliff_topology()

	_set_status("生成贴图地形高度图（悬崖留缝）…")
	_terrain.build(ctx)
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
	if place_units:
		_units.build(_read_json(map_dir.path_join("units.json")))
		await get_tree().process_frame
	if place_doodads:
		_doodads.build(_read_json(map_dir.path_join("doodads.json")))
		await get_tree().process_frame
	if show_pathing_debug_grid and _debug_grid:
		_set_status("开启调试栅格（GPU）…")
		_debug_grid.build(ctx)
		await get_tree().process_frame

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


func _ensure_terrain_collision() -> void:
	var ground := _terrain.get_node_or_null("Ground") as MeshInstance3D
	if ground == null or ground.mesh == null:
		return
	for c in ground.get_children():
		if c is StaticBody3D:
			c.free()
	ground.create_trimesh_collision()


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
