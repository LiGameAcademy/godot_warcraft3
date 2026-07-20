extends Node3D
## 通用地图加载器。当前专注：贴图正确的地形高度网格。


@export var map_dir: String = "res://assets/map-parsed/losttemple"
@export var build_water: bool = true
@export var build_cliffs: bool = true
@export var place_doodads: bool = false
@export var place_units: bool = false
@export var try_load_glb: bool = true
@export var multimesh_threshold: int = 8
@export var status_path: NodePath = ^"../UI/Status"

@onready var _terrain: MapTerrainLayer = $Terrain
@onready var _water: MapWaterLayer = $Water
@onready var _cliffs: MapCliffLayer = $Cliffs
@onready var _doodads: MapDoodadLayer = $Doodads
@onready var _units: MapUnitLayer = $Units

var _catalog := Wc3IdCatalog.new()
var _tiles := Wc3TerrainTiles.new()
var _cache := MapModelCache.new()
var _status: Label


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
	if place_units or place_doodads:
		_catalog.load_default()
	await get_tree().process_frame
	await _load_all()


func _load_all() -> void:
	var t0 := Time.get_ticks_msec()
	var hf := _read_json(map_dir.path_join("terrain-heightfield.json"))
	if hf.is_empty():
		_set_status("地图加载失败：缺少 terrain-heightfield.json")
		return

	_set_status("生成贴图地形高度图（悬崖/斜坡留缝）…")
	_terrain.build(hf, _tiles)
	await get_tree().process_frame

	if build_cliffs:
		_set_status("放置悬崖模型…")
		_cliffs.build(hf, _tiles)
		await get_tree().process_frame
	if build_water:
		_set_status("生成水体…")
		var main_ts := str(hf.get("mainTileset", "I"))
		if main_ts.is_empty():
			main_ts = "I"
		_water.build(hf, main_ts)
		await get_tree().process_frame
	if place_units:
		_units.build(_read_json(map_dir.path_join("units.json")))
		await get_tree().process_frame
	if place_doodads:
		_doodads.build(_read_json(map_dir.path_join("doodads.json")))
		await get_tree().process_frame

	var ms := Time.get_ticks_msec() - t0
	var cliff_n := _cliffs.last_placed if build_cliffs else 0
	var water_n := _water.last_cell_count if build_water else 0
	_set_status(
		"地形就绪（%d ms，留缝 %d，悬崖 %d，水面 %d）— WASD 移动，右键转向，滚轮缩放"
		% [ms, _terrain.last_gap_count, cliff_n, water_n]
	)
	print(
		"Terrain load in %d ms from %s (gaps=%d cliffs=%d water=%d)"
		% [ms, map_dir, _terrain.last_gap_count, cliff_n, water_n]
	)


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
