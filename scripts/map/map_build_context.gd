class_name MapBuildContext
extends RefCounted
## 单次地图加载的共享上下文。权威地形为 Wc3Heightfield；meta/hf 为其视图。


var map_dir: String = ""
## 权威 SoA（与 Document / 磁盘共用或自持平行数组）
var heightfield: Wc3Heightfield
## 与 heightfield 共享数组的 JSON 形视图（兼容尚未改完的 Domain）
var hf: Dictionary = {}
## 构建器用 meta（heightfield.to_build_meta，数组共享）
var meta: Dictionary = {}
## info.json（可空）
var info: Dictionary = {}
## info.flags（waterWavesCliff 等）
var map_flags: Dictionary = {}
var main_tileset: String = "I"

var tiles: Wc3TerrainTiles
var catalog: Wc3IdCatalog
var cache: MapModelCache

## 悬崖拓扑（ensure_cliff_topology 后有效）
var cliff_romp: PackedByteArray = PackedByteArray()
var cliff_ramp_placements: Array = []
var cliff_gap_stats: Dictionary = {}
var _cliff_ready: bool = false


static func create(
	p_map_dir: String,
	p_hf: Dictionary,
	p_info: Dictionary,
	p_tiles: Wc3TerrainTiles,
	p_catalog: Wc3IdCatalog = null,
	p_cache: MapModelCache = null
):
	# 不用 MapBuildContext.new()：headless 下 class_name 缓存可能尚未生成
	var ctx = (load("res://scripts/map/map_build_context.gd") as GDScript).new()
	ctx.map_dir = p_map_dir
	# 共享调用方 SoA（编辑器 Document 视图 / 刚读入的 JSON），避免每刷复制 2.6 万点
	ctx.heightfield = Wc3Heightfield.from_dict(p_hf, false)
	ctx.hf = ctx.heightfield.as_dict_view()
	ctx.meta = ctx.heightfield.to_build_meta()
	ctx.info = p_info
	ctx.tiles = p_tiles
	ctx.catalog = p_catalog
	ctx.cache = p_cache if p_cache else MapModelCache.new()

	var flags_wrap: Variant = p_info.get("flags", {})
	if typeof(flags_wrap) == TYPE_DICTIONARY:
		ctx.map_flags = flags_wrap

	var ts := ctx.heightfield.main_tileset
	ctx.main_tileset = ts if not ts.is_empty() else "I"
	return ctx


func ensure_cliff_topology() -> void:
	if _cliff_ready:
		return
	var ramp_data := Wc3CliffTiles.collect_ramp_placements(hf, meta, tiles)
	cliff_romp = ramp_data.get("romp", PackedByteArray()) as PackedByteArray
	cliff_ramp_placements = ramp_data.get("placements", []) as Array
	cliff_gap_stats = Wc3CliffTiles.count_gaps(hf, meta, ramp_data)
	_cliff_ready = true


func width() -> int:
	return heightfield.width if heightfield else 0


func height() -> int:
	return heightfield.height if heightfield else 0
