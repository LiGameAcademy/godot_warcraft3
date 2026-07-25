class_name MapBuildContext
extends RefCounted

## 单次地图构建会话（Presentation 装配状态），不是数据权威。
##
## 权威地形态：`Wc3Heightfield`（Data）与 `MapDocument`（Editor）。
## 本类职责：
## - 持有本次 rebuild 要用的 Catalog / Cache / tiles
## - 缓存悬崖拓扑（romp / placements），避免各 Layer 重复算
## - 过渡期保留 `hf` / `meta` 字典视图，供尚未改完的水体层
##
## 与 Data 不重叠：Heightfield 描述「地图是什么」；Context 描述「这一次怎么建」。
## 长期方向：Layer 优先读 `heightfield` 字段；`meta`/`hf` 随水重构删掉。

var map_dir: String = ""
var heightfield: Wc3Heightfield = null					## 权威 SoA（与 Document / 磁盘共用或自持平行数组）
var hf: Dictionary = {}									## 与 heightfield 共享数组的 JSON 形视图（兼容尚未改完的 Domain）
var meta: Dictionary = {}								## 构建器用 meta（heightfield.to_build_meta，数组共享）——过渡期
var info: Dictionary = {}								## info.json（可空）
var map_flags: Dictionary = {}							## info.flags（waterWavesCliff 等）
var main_tileset: String = "I"							## 主 tileset（I=1，D=2，C=3）

var tiles: Wc3TerrainTileCatalog = null					## 地表瓷砖 Catalog
var cliff_catalog: Wc3CliffCatalog = null				## 直崖 Catalog
var catalog: Wc3IdCatalog = null						## 瓷砖 ID 目录
var cache: MapModelCache = null							## 模型缓存

# 悬崖拓扑（ensure_cliff_topology 后有效）
var cliff_romp: PackedByteArray = PackedByteArray()		## 斜坡 romp（重建前全 0）
var cliff_ramp_placements: Array = []					## 斜坡放置（重建前空）
var cliff_placements: Array[Wc3CliffPlacement] = []		## 直崖 Logic 输出
var cliff_gap_mask: PackedByteArray = PackedByteArray()	## 地表格挖洞：1=留缝（Logic 预计算）
var cliff_gap_stats: Dictionary = {}					## 悬崖 gap 统计
var _cliff_ready: bool = false							## 悬崖拓扑是否已准备好


## 创建上下文
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


## Logic 算 placements / gaps；Present Layer 只读缓存（不回调 Logic）。
func ensure_cliff_topology() -> void:
	if _cliff_ready:
		return
	var ramp_data := Wc3CliffLogic.collect_ramp_placements(hf, meta, cliff_catalog)
	cliff_romp = ramp_data.get("romp", PackedByteArray()) as PackedByteArray
	cliff_ramp_placements = ramp_data.get("placements", []) as Array
	cliff_placements = Wc3CliffLogic.collect_placements(heightfield, cliff_catalog)
	cliff_gap_stats = Wc3CliffLogic.count_gaps(hf, meta, ramp_data)
	cliff_gap_mask = _build_gap_mask()
	_cliff_ready = true


func _build_gap_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	if heightfield == null or not heightfield.is_valid():
		return mask
	var tp_w: int = heightfield.width
	var tp_h: int = heightfield.height
	var layers: Array = heightfield.layer_heights
	var flags: Array = heightfield.flags_packed
	mask.resize(maxi((tp_w - 1) * (tp_h - 1), 0))
	mask.fill(0)
	var i := 0
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if Wc3CliffLogic.should_leave_gap(
				layers, flags, tp_w, tp_h, ix, iy, cliff_romp
			):
				mask[i] = 1
			i += 1
	return mask


func width() -> int:
	return heightfield.width if heightfield else 0


func height() -> int:
	return heightfield.height if heightfield else 0
