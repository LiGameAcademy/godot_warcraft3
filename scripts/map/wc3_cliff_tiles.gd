class_name Wc3CliffTiles
extends RefCounted
## 悬崖判定与模型 TAG（直崖）。
## 斜坡（Ramp / CliffTrans / romp）已在 feature/ramp-rebuild 清空；API 保留空壳供逐步重做。
## 悬崖 TAG 对齐 mdx-m3-viewer（BL,TL,TR,BR → A/B/C）。


const FLAG_RAMP := Wc3Coords.FLAG_RAMP

## 斜坡甲板开关（重建前恒 false）。
const RAMP_SURFACE_DECK_ENABLED := false

## romp 字节（重建前仅占位）：0 无。
const ROMP_NONE := 0
const ROMP_SINGLE := 1
const ROMP_WIDE := 2
const ROMP_SIDE := 3

const CLIFF_VAR_MAX := {
	"AAAB": 1, "AAAC": 1, "AABA": 1, "AABB": 2, "AABC": 0, "AACA": 1, "AACB": 0, "AACC": 1,
	"ABAA": 1, "ABAB": 1, "ABAC": 0, "ABBA": 2, "ABBB": 1, "ABBC": 0, "ABCA": 0, "ABCB": 0,
	"ABCC": 0, "ACAA": 1, "ACAB": 0, "ACAC": 1, "ACBA": 0, "ACBB": 0, "ACBC": 0, "ACCA": 1,
	"ACCB": 0, "ACCC": 1, "BAAA": 1, "BAAB": 1, "BAAC": 0, "BABA": 1, "BABB": 1, "BABC": 0,
	"BACA": 0, "BACB": 0, "BACC": 0, "BBAA": 1, "BBAB": 1, "BBAC": 0, "BBBA": 1, "BBCA": 0,
	"BCAA": 0, "BCAB": 0, "BCAC": 0, "BCBA": 0, "BCCA": 0, "CAAA": 1, "CAAB": 0, "CAAC": 1,
	"CABA": 0, "CABB": 0, "CABC": 0, "CACA": 1, "CACB": 0, "CACC": 1, "CBAA": 0, "CBAB": 0,
	"CBAC": 0, "CBBA": 0, "CBCA": 0, "CCAA": 1, "CCAB": 0, "CCAC": 1, "CCBA": 0, "CCCA": 1,
}

const CITY_CLIFF_VAR_MAX := {
	"AAAB": 2, "AAAC": 1, "AABA": 1, "AABB": 3, "AABC": 0, "AACA": 1, "AACB": 0, "AACC": 3,
	"ABAA": 1, "ABAB": 2, "ABAC": 0, "ABBA": 3, "ABBB": 0, "ABBC": 0, "ABCA": 0, "ABCB": 0,
	"ABCC": 0, "ACAA": 1, "ACAB": 0, "ACAC": 2, "ACBA": 0, "ACBB": 0, "ACBC": 0, "ACCA": 3,
	"ACCB": 0, "ACCC": 1, "BAAA": 1, "BAAB": 3, "BAAC": 0, "BABA": 2, "BABB": 0, "BABC": 0,
	"BACA": 0, "BACB": 0, "BACC": 0, "BBAA": 3, "BBAB": 1, "BBAC": 0, "BBBA": 1, "BBCA": 0,
	"BCAA": 0, "BCAB": 0, "BCAC": 0, "BCBA": 0, "BCCA": 0, "CAAA": 1, "CAAB": 0, "CAAC": 3,
	"CABA": 0, "CABB": 0, "CABC": 0, "CACA": 2, "CACB": 0, "CACC": 1, "CBAA": 0, "CBAB": 0,
	"CBAC": 0, "CBBA": 0, "CBCA": 0, "CCAA": 3, "CCAB": 0, "CCAC": 1, "CCBA": 0, "CCCA": 1,
}


static func is_cliff_tile(layer_heights: Array, width: int, ix: int, iy: int) -> bool:
	if layer_heights.is_empty():
		return false
	var i00 := iy * width + ix
	var i10 := i00 + 1
	var i01 := i00 + width
	var i11 := i01 + 1
	if i11 >= layer_heights.size():
		return false
	var a := int(layer_heights[i00])
	return a != int(layer_heights[i10]) or a != int(layer_heights[i01]) or a != int(layer_heights[i11])


## W3E 只读：顶点是否带 FLAG_RAMP（不驱动渲染）。
static func is_ramp_flag(flags: Array, i: int) -> bool:
	if i < 0 or i >= flags.size():
		return false
	return (int(flags[i]) & FLAG_RAMP) != 0


## W3E 只读：地表格四角是否任一有 RAMP 旗（不驱动渲染）。
static func is_ramp_tile(flags: Array, width: int, ix: int, iy: int) -> bool:
	if flags.is_empty():
		return false
	var i00 := iy * width + ix
	var i10 := i00 + 1
	var i01 := i00 + width
	var i11 := i01 + 1
	if i11 >= flags.size():
		return false
	return (
		is_ramp_flag(flags, i00)
		or is_ramp_flag(flags, i10)
		or is_ramp_flag(flags, i01)
		or is_ramp_flag(flags, i11)
	)


## 斜坡入口判定（重建前恒 false）。
static func is_ramp_entrance(
	_layer_heights: Array, _flags: Array, _width: int, _ix: int, _iy: int
) -> bool:
	return false


## 斜坡选型入口（重建前返回空 placements + 全 0 romp）。
static func collect_ramp_placements(
	hf: Dictionary, meta: Dictionary = {}, _tiles: Wc3TerrainTiles = null
) -> Dictionary:
	if meta.is_empty():
		meta = HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var tp_w: int = int(meta.get("width", 0))
	var tp_h: int = int(meta.get("height", 0))
	var romp := PackedByteArray()
	romp.resize(maxi(tp_w * tp_h, 0))
	romp.fill(0)
	return {"placements": [], "romp": romp}


static func romp_kind_at(_romp: PackedByteArray, _tp_w: int, _ix: int, _iy: int) -> int:
	return ROMP_NONE


## 仅直崖挖洞；斜坡相关逻辑已移除。
static func should_leave_gap(
	layer_heights: Array,
	_flags: Array,
	tp_w: int,
	_tp_h: int,
	ix: int,
	iy: int,
	_romp: PackedByteArray = PackedByteArray()
) -> bool:
	return is_cliff_tile(layer_heights, tp_w, ix, iy)


static func is_ramp_foot_cell(_romp: PackedByteArray, _tp_w: int, _ix: int, _iy: int) -> bool:
	return false


static func sample_ramp_plane_height(
	_heights: Array, _placements: Array, _tp_w: int, _tp_h: int, _tx: float, _ty: float
) -> float:
	return NAN


static func cliff_tag_at(layer_heights: Array, width: int, ix: int, iy: int) -> Dictionary:
	var slices: Array = cliff_slices_at(layer_heights, width, ix, iy)
	if slices.is_empty():
		return {}
	return slices[0]


## 直崖 TAG 选型（BL,TL,TR,BR → 相对 base 的 A/B/C）。
## 对齐 HiveWE / WE：跨度 ≤2 时只放一条完整变体；跨度 >2 时分段剥满 C。
static func cliff_slices_at(layer_heights: Array, width: int, ix: int, iy: int) -> Array:
	if not is_cliff_tile(layer_heights, width, ix, iy):
		return []
	var i00 := iy * width + ix
	var i10 := i00 + 1
	var i01 := i00 + width
	var i11 := i01 + 1
	var bl := int(layer_heights[i00])
	var br := int(layer_heights[i10])
	var tl := int(layer_heights[i01])
	var tr := int(layer_heights[i11])
	var lo := mini(mini(bl, br), mini(tl, tr))
	var hi := maxi(maxi(bl, br), maxi(tl, tr))
	var out: Array = []
	var base := lo
	while base < hi:
		var raw_bl := bl - base
		var raw_tl := tl - base
		var raw_tr := tr - base
		var raw_br := br - base
		var raw_hi := maxi(maxi(raw_bl, raw_br), maxi(raw_tl, raw_tr))
		if raw_hi <= 2:
			var tag_exact := _cliff_tag_from_rels(raw_bl, raw_tl, raw_tr, raw_br)
			if tag_exact != "AAAA":
				out.append({"tag": tag_exact, "base_layer": base})
			break
		var rbl := clampi(raw_bl, 0, 2)
		var rtl := clampi(raw_tl, 0, 2)
		var rtr := clampi(raw_tr, 0, 2)
		var rbr := clampi(raw_br, 0, 2)
		var tag := _cliff_tag_from_rels(rbl, rtl, rtr, rbr)
		if tag != "AAAA":
			out.append({"tag": tag, "base_layer": base})
		base += 2
	return out


static func _cliff_tag_from_rels(rbl: int, rtl: int, rtr: int, rbr: int) -> String:
	return (
		String.chr(65 + clampi(rbl, 0, 2))
		+ String.chr(65 + clampi(rtl, 0, 2))
		+ String.chr(65 + clampi(rtr, 0, 2))
		+ String.chr(65 + clampi(rbr, 0, 2))
	)


static func clamp_variation(model_dir: String, tag: String, variation: int) -> int:
	if model_dir == "CliffTrans" or model_dir == "CityCliffTrans":
		return 0
	var table: Dictionary = CITY_CLIFF_VAR_MAX if model_dir == "CityCliffs" else CLIFF_VAR_MAX
	if not table.has(tag):
		return 0
	return mini(maxi(variation, 0), int(table[tag]))


## 直崖变体：优先用存盘值；存盘为 0 时用格点哈希打散。
static func pick_cliff_variation(
	model_dir: String, tag: String, stored: int, ix: int, iy: int
) -> int:
	var table: Dictionary = CITY_CLIFF_VAR_MAX if model_dir == "CityCliffs" else CLIFF_VAR_MAX
	var max_v: int = int(table.get(tag, 0))
	if max_v <= 0:
		return 0
	if stored > 0:
		return mini(stored, max_v)
	var h: int = absi((ix * 73856093) ^ (iy * 19349663) ^ tag.hash())
	return h % (max_v + 1)


static func glb_path(model_dir: String, tag: String, variation: int) -> String:
	return RuntimeAssets.converted_path(
		"Doodads/Terrain/%s/%s%s%d.glb" % [model_dir, model_dir, tag, variation]
	)


static func resolve_glb(model_dir: String, tag: String, variation: int) -> String:
	if tag.is_empty():
		return ""
	variation = clamp_variation(model_dir, tag, variation)
	var path := glb_path(model_dir, tag, variation)
	if RuntimeAssets.file_exists(path):
		return path
	path = glb_path(model_dir, tag, 0)
	if RuntimeAssets.file_exists(path):
		return path
	if model_dir == "CityCliffTrans":
		return resolve_glb("CliffTrans", tag, variation)
	return ""


## 斜坡入口抬高（重建前 no-op）。
static func apply_ramp_entrance_heights(
	heights: Array, _layers: Array, _flags: Array, _tp_w: int, _tp_h: int
) -> Array:
	return heights


## gap / cliff / ramp-flag 统计（ramp_models 恒 0）。
static func count_gaps(
	hf: Dictionary, meta: Dictionary = {}, ramp_data: Dictionary = {}
) -> Dictionary:
	if meta.is_empty():
		meta = HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var width: int = meta["width"]
	var height: int = meta["height"]
	var layers: Array = meta["layer_heights"]
	var flags: Array = meta["flags"]
	if ramp_data.is_empty():
		ramp_data = collect_ramp_placements(hf, meta)
	var romp: PackedByteArray = ramp_data["romp"]
	var cliffs := 0
	var ramps := 0
	var gaps := 0
	var tiles := (width - 1) * (height - 1)
	for iy in range(height - 1):
		for ix in range(width - 1):
			if should_leave_gap(layers, flags, width, height, ix, iy, romp):
				gaps += 1
			if is_cliff_tile(layers, width, ix, iy):
				cliffs += 1
			if is_ramp_tile(flags, width, ix, iy):
				ramps += 1
	return {
		"gaps": gaps,
		"cliffs": cliffs,
		"ramps": ramps,
		"tiles": tiles,
		"ramp_models": 0,
	}
