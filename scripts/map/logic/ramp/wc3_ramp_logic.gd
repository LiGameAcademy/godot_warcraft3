class_name Wc3RampLogic
extends RefCounted

## 斜坡逻辑层（对齐 HiveWE / docs/ramp/RAMP_WE.md）：
##   paint → 只写 FLAG_RAMP（直坡 3 点 / 外角对角 3×3 / L 仅补中心）
##   collect_placements → CliffTrans 滑窗匹配 + romp
## 对外：bind / paint_at / try_paint_at / peek_spine_at / collect_placements / clear_flags_around
##
## 目录约定（与 cliff/terrain 对齐，禁止再拆薄工具文件）：
##   wc3_ramp_logic.gd   — 门面 + 常量 + 落旗 + plan/result 字典
##   wc3_ramp_paint.gd   — 笔刷规划（只算标记）
##   wc3_ramp_collect.gd — 拓扑匹配 / dig / entrance

# --- 常量（Data 权威；此处转发便于 Logic 调用点）---
const AXIS_H := Wc3RampPlacement.AXIS_H
const AXIS_V := Wc3RampPlacement.AXIS_V
const AXIS_D := Wc3RampPlacement.AXIS_D

const VARIANT_STRAIGHT := Wc3RampPlacement.VARIANT_STRAIGHT
const VARIANT_DIAGONAL := Wc3RampPlacement.VARIANT_DIAGONAL
const VARIANT_L := Wc3RampPlacement.VARIANT_L

const ROMP_NONE := Wc3RampCollectResult.ROMP_NONE
const ROMP_TRANS := Wc3RampCollectResult.ROMP_TRANS

var heightfield: Wc3Heightfield = null
var cliff: Wc3CliffLogic = null
var last_message: String = ""


func bind(hf: Wc3Heightfield, cliff_logic: Wc3CliffLogic = null) -> Wc3RampLogic:
	heightfield = hf
	cliff = cliff_logic
	return self


func paint_at(
	ix: int, iy: int, horizontal: int = 0, vertical: int = 0, cliff_tex_index: int = -1
) -> bool:
	var r: Dictionary = try_paint_at(ix, iy, horizontal, vertical, cliff_tex_index)
	last_message = str(r.get("message", ""))
	return bool(r.get("changed", false))


func try_paint_at(
	ix: int, iy: int, horizontal: int = 0, vertical: int = 0, cliff_tex_index: int = -1
) -> Dictionary:
	if heightfield == null or not heightfield.is_valid():
		return result_fail("地图为空")
	var tp_w: int = heightfield.width
	var tp_h: int = heightfield.height
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return result_fail("顶点越界")
	var layers: Array = heightfield.layer_heights
	var flags: Array = heightfield.flags_packed
	var cliff_tex: Array = heightfield.cliff_textures
	if layers.is_empty() or flags.is_empty():
		return result_fail("缺少层高/旗数据")

	var plan: Dictionary = Wc3RampPaint.plan_from_pointer(
		ix, iy, layers, flags, tp_w, tp_h, horizontal, vertical
	)
	if not plan.get("ok", false):
		return result_fail(str(plan.get("message", "")))

	# HiveWE：落旗角用原点崖贴图；调用方可覆盖（编辑器 brush）
	var tex_idx: int = cliff_tex_index
	var ox: int = int(plan.get("sx", ix))
	var oy: int = int(plan.get("sy", iy))
	var origin_i: int = oy * tp_w + ox
	if tex_idx < 0 and origin_i < cliff_tex.size():
		tex_idx = int(cliff_tex[origin_i])
		if tex_idx == 15:
			tex_idx = 1

	var marked: Array[Vector2i] = []
	for v in plan.get("marked", []):
		marked.append(v as Vector2i)

	var did_change := apply_marks(plan, flags, cliff_tex, tp_w, tex_idx)
	var n_mark: int = marked.size()
	var msg := (
		"已刷斜坡 %s×%d @(%d,%d)"
		% [str(plan.get("variant", "")), n_mark, ox, oy]
		if did_change
		else "斜坡已存在 %s×%d" % [str(plan.get("variant", "")), n_mark]
	)
	return result_ok(
		did_change,
		msg,
		str(plan.get("variant", "")),
		str(plan.get("axis", "")),
		ox,
		oy,
		marked
	)


func peek_spine_at(ix: int, iy: int, horizontal: int = 0, vertical: int = 0) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if heightfield == null or not heightfield.is_valid():
		return empty
	var tp_w: int = heightfield.width
	var tp_h: int = heightfield.height
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return empty
	var plan: Dictionary = Wc3RampPaint.plan_from_pointer(
		ix, iy, heightfield.layer_heights, heightfield.flags_packed, tp_w, tp_h,
		horizontal, vertical
	)
	if not plan.get("ok", false):
		return empty
	var marked: Array[Vector2i] = []
	for v in plan.get("marked", []):
		marked.append(v as Vector2i)
	return marked


## 拓扑：旗 → CliffTrans placements + romp（≈ update_cliff_meshes 数据侧）。
static func collect_placements(
	hf: Variant, meta: Dictionary = {}, cliff_catalog: Wc3CliffCatalog = null
) -> Wc3RampCollectResult:
	var hf_out: Wc3Heightfield = null
	if hf is Wc3Heightfield:
		hf_out = hf as Wc3Heightfield
	elif typeof(hf) == TYPE_DICTIONARY:
		var d: Dictionary = hf as Dictionary
		if d.is_empty():
			return Wc3RampCollectResult.empty_for_size(
				int(meta.get("width", 0)), int(meta.get("height", 0))
			)
		hf_out = Wc3Heightfield.from_dict(d, false)
	if hf_out == null or not hf_out.is_valid():
		if not meta.is_empty():
			return Wc3RampCollectResult.empty_for_size(
				int(meta.get("width", 0)), int(meta.get("height", 0))
			)
		return Wc3RampCollectResult.empty_for_size(0, 0)
	return Wc3RampCollect.collect(hf_out, cliff_catalog)


## Present 用：挖洞计划 / 入口格列表（不写 cliff gap）。
static func plan_dig_mask(
	hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult
) -> PackedByteArray:
	return Wc3RampCollect.plan_dig_mask(hf, ramp_data)


## 对角斜坡的地面挖洞（独立于 placement；用于 placement 为空但仍有 diagonal ramp flag 的情况）。
static func plan_diagonal_dig_mask(hf: Wc3Heightfield) -> PackedByteArray:
	return Wc3RampCollect.plan_diagonal_dig_mask(hf)


static func plan_entrance_tiles(
	hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult = null
) -> Array[Vector2i]:
	return Wc3RampCollect.plan_entrance_tiles(hf, ramp_data)


## Present：入口低角半层抬高 mask（tilepoint；不写 HF）。与 undig 入口列表一致。
static func plan_entrance_height_boost(
	hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult = null
) -> PackedByteArray:
	return Wc3RampCollect.plan_entrance_height_boost(hf, ramp_data)


## Present / Loader：单块直崖模型是否应跳过（叠段粒度）。
static func should_hide_cliff_piece(
	ix: int,
	iy: int,
	piece_base: int,
	hf: Wc3Heightfield,
	ramp_data: Wc3RampCollectResult
) -> bool:
	return Wc3RampCollect.should_hide_cliff_piece(ix, iy, piece_base, hf, ramp_data)


## Loader：挂直崖前过滤 placements（新数组；对齐 WE continue）。
static func filter_cliff_placements(
	placements: Array[Wc3CliffPlacement],
	hf: Wc3Heightfield,
	ramp_data: Wc3RampCollectResult
) -> Array[Wc3CliffPlacement]:
	return Wc3RampCollect.filter_cliff_placements(placements, hf, ramp_data)


# --- 改崖联动（Document 一般不再调用；保留 API 供显式清区）---

## 默认 expand=0：只清矩形内顶点。需要清臂时由 CliffLogic 走「变更点穿臂」。
const CLEAR_AROUND_CLIFF_EXPAND := 0


## 清除单角点邻域内 FLAG_RAMP。返回清除点数。
func clear_flags_around(
	ix: int, iy: int, expand: int = CLEAR_AROUND_CLIFF_EXPAND
) -> int:
	return clear_flags_in_rect(Vector2i(ix, iy), Vector2i(ix, iy), expand)


## 清除矩形（含 expand）内所有 FLAG_RAMP。返回清除点数。
func clear_flags_in_rect(
	rmin: Vector2i, rmax: Vector2i, expand: int = CLEAR_AROUND_CLIFF_EXPAND
) -> int:
	if heightfield == null or not heightfield.is_valid():
		return 0
	var flags: Array = heightfield.flags_packed
	var tw: int = heightfield.width
	var th: int = heightfield.height
	if flags.is_empty() or tw <= 0 or th <= 0:
		return 0
	var x0: int = maxi(0, rmin.x - expand)
	var y0: int = maxi(0, rmin.y - expand)
	var x1: int = mini(tw - 1, rmax.x + expand)
	var y1: int = mini(th - 1, rmax.y + expand)
	if x1 < x0 or y1 < y0:
		return 0
	var n := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if set_ramp_flag(flags, y * tw + x, false):
				n += 1
	return n


# --- 落旗 ---

## 只写 FLAG_RAMP（清水位）；可选同步 cliff_textures。不改层高。
static func apply_marks(
	plan: Dictionary,
	flags: Array,
	cliff_textures: Array,
	tp_w: int,
	cliff_tex_index: int = -1
) -> bool:
	var changed := false
	for v in plan.get("marked", []):
		var p: Vector2i = v as Vector2i
		if set_ramp_flag(flags, p.y * tp_w + p.x, true):
			changed = true
		if cliff_tex_index >= 0 and not cliff_textures.is_empty():
			var i: int = p.y * tp_w + p.x
			if i >= 0 and i < cliff_textures.size() and int(cliff_textures[i]) != cliff_tex_index:
				cliff_textures[i] = cliff_tex_index
				changed = true
	return changed


static func set_ramp_flag(flags: Array, i: int, want_ramp: bool) -> bool:
	if i < 0 or i >= flags.size():
		return false
	var fl: int = int(flags[i])
	var nf: int = (fl | Wc3Coords.FLAG_RAMP) if want_ramp else (fl & ~Wc3Coords.FLAG_RAMP)
	if want_ramp:
		nf = nf & ~Wc3Coords.FLAG_WATER
	if nf == fl:
		return false
	flags[i] = nf
	return true


# --- plan / result 字典 ---

static func plan_fail(message: String) -> Dictionary:
	return {
		"ok": false,
		"message": message,
		"variant": "",
		"axis": "",
		"sx": 0,
		"sy": 0,
		"marked": [],
		"horizontal": 0,
		"vertical": 0,
	}


static func plan_ok(
	variant: String, axis: String, sx: int, sy: int, marked: Array, hx: int, hy: int
) -> Dictionary:
	return {
		"ok": true,
		"message": "",
		"variant": variant,
		"axis": axis,
		"sx": sx,
		"sy": sy,
		"marked": marked,
		"horizontal": hx,
		"vertical": hy,
	}


static func result_fail(message: String) -> Dictionary:
	return {
		"ok": false,
		"changed": false,
		"message": message,
		"variant": "",
		"axis": "",
		"sx": 0,
		"sy": 0,
		"marked": [],
	}


static func result_ok(
	changed: bool,
	message: String,
	variant: String,
	axis: String,
	sx: int,
	sy: int,
	marked: Array
) -> Dictionary:
	return {
		"ok": true,
		"changed": changed,
		"message": message,
		"variant": variant,
		"axis": axis,
		"sx": sx,
		"sy": sy,
		"marked": marked,
	}
