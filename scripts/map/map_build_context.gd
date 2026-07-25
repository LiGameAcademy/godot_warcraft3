class_name MapBuildContext
extends RefCounted

## 单次地图构建会话（Presentation 装配缓存），不是数据权威，也不含领域判断。
##
## 权威地形态：`Wc3Heightfield`（Data）与 `MapDocument`（Editor）。
## 本类职责：
## - 持有本次 rebuild 要用的 Catalog / Cache
## - 缓存 Logic 已算好的 placements / gap_mask（只赋值，不重算拓扑）
## - 过渡期保留 `hf` / `meta` 字典视图，供尚未改完的水体层
##
## 禁止：在本类写 Heightfield；禁止在本类做 TAG / 挖洞判断（一律 Logic）。

var map_dir: String = ""
var heightfield: Wc3Heightfield = null
var hf: Dictionary = {}
var meta: Dictionary = {}
var info: Dictionary = {}
var map_flags: Dictionary = {}
var main_tileset: String = "I"

var tiles: Wc3TerrainTileCatalog = null
var cliff_catalog: Wc3CliffCatalog = null
var catalog: Wc3IdCatalog = null
var cache: MapModelCache = null

var cliff_romp: PackedByteArray = PackedByteArray()
var cliff_ramp_placements: Array = []
var cliff_placements: Array[Wc3CliffPlacement] = []
var cliff_gap_mask: PackedByteArray = PackedByteArray()
var cliff_gap_stats: Dictionary = {}
var _cliff_ready: bool = false


static func create(
	p_map_dir: String, p_hf: Dictionary, p_info: Dictionary,
	p_tiles: Wc3TerrainTileCatalog, p_catalog: Wc3IdCatalog = null, p_cache: MapModelCache = null,
	p_cliff_catalog: Wc3CliffCatalog = null
) -> MapBuildContext:
	var ctx := MapBuildContext.new()
	ctx.map_dir = p_map_dir
	ctx.heightfield = Wc3Heightfield.from_dict(p_hf, false)
	ctx.hf = ctx.heightfield.as_dict_view()
	ctx.meta = ctx.heightfield.to_build_meta()
	ctx.info = p_info
	ctx.tiles = p_tiles
	ctx.cliff_catalog = p_cliff_catalog
	if ctx.cliff_catalog == null:
		ctx.cliff_catalog = Wc3CliffCatalog.new()
		ctx.cliff_catalog.load_default()
	ctx.catalog = p_catalog
	ctx.cache = p_cache if p_cache else MapModelCache.new()

	var flags_wrap: Variant = p_info.get("flags", {})
	if typeof(flags_wrap) == TYPE_DICTIONARY:
		ctx.map_flags = flags_wrap

	var ts: String = ""
	if ctx.heightfield != null:
		ts = str(ctx.heightfield.main_tileset)
	ctx.main_tileset = ts if not ts.is_empty() else "I"
	return ctx


## 向 Logic 要拓扑结果并缓存；本函数不含判断。
func ensure_cliff_topology() -> void:
	if _cliff_ready:
		return
	var topo: Wc3CliffTopologyResult = Wc3CliffLogic.build_topology(
		heightfield, cliff_catalog
	)
	cliff_romp = topo.romp
	cliff_ramp_placements = topo.ramp_placements
	cliff_placements = topo.placements
	cliff_gap_mask = topo.gap_mask
	cliff_gap_stats = topo.gap_stats
	_cliff_ready = true


func width() -> int:
	return heightfield.width if heightfield else 0


func height() -> int:
	return heightfield.height if heightfield else 0
