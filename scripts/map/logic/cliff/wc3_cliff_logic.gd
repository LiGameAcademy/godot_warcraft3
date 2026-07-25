class_name Wc3CliffLogic
extends RefCounted

## 悬崖逻辑层：改 layerHeights / cliffTextures / groundTile（策略 B）；
## 以及直崖拓扑（is_cliff / TAG 叠段 / 挖洞统计）。不建 Mesh；GLB 路径归 Catalog。
## 斜坡（Ramp / CliffTrans / romp）重建前 API 为空壳。

const LAYER_MIN := 0
const LAYER_MAX := 14
const MAX_CLIFF_ADJ_DELTA := 2
const LAYER_HEIGHT_STEP := 128.0
const WATER_SHALLOW_EXTRA := 48.0
const WATER_DEEP_EXTRA := 128.0
const FLAG_WATER := Wc3Coords.FLAG_WATER
const FLAG_RAMP := Wc3Coords.FLAG_RAMP

## 斜坡甲板开关（重建前恒 false）。
const RAMP_SURFACE_DECK_ENABLED := false
## romp 字节（重建前仅占位）：0 无。
const ROMP_NONE := 0
const ROMP_SINGLE := 1
const ROMP_WIDE := 2
const ROMP_SIDE := 3

enum Propagate {
	RAISE_LOWER = 0, ## 升：抬低邻
	LOWER_HIGHER = 1, ## 降：压高邻
	BOTH = 2,
}

var heightfield: Wc3Heightfield = null
var cliff_catalog: Wc3CliffCatalog = null
## cliffTilesets 下标 → groundTilesets 下标；-2=未缓存，-1=无对应
var _cliff_ground_cache: PackedInt32Array = PackedInt32Array()
var dirty_min: Vector2i = Vector2i.ZERO
var dirty_max: Vector2i = Vector2i.ZERO
var _dirty_valid: bool = false


func bind(hf: Wc3Heightfield) -> Wc3CliffLogic:
	heightfield = hf
	clear_dirty()
	return self


func ensure_catalog() -> void:
	if cliff_catalog == null:
		cliff_catalog = Wc3CliffCatalog.new()
		cliff_catalog.load_default()


func clear_ground_tile_cache() -> void:
	_cliff_ground_cache = PackedInt32Array()


func is_bound() -> bool:
	return heightfield != null and heightfield.width >= 2


func clear_dirty() -> void:
	_dirty_valid = false
	dirty_min = Vector2i.ZERO
	dirty_max = Vector2i.ZERO


func has_dirty() -> bool:
	return _dirty_valid


func take_dirty_rect() -> Rect2i:
	if not _dirty_valid:
		return Rect2i()
	var r := Rect2i(dirty_min, dirty_max - dirty_min + Vector2i.ONE)
	clear_dirty()
	return r


## 悬崖笔刷核心。不含 Ramp（由 Document 另处理）。
## tool_id: "0".."4" | "ShallowWater" | "DeepWater"
func paint_corner(
	ix: int,
	iy: int,
	tool_id: String,
	cliff_type_idx: int = 0,
	level_layer: int = -1
) -> bool:
	if not is_bound():
		return false
	var tp_w: int = heightfield.width
	var tp_h: int = heightfield.height
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return false
	var i: int = iy * tp_w + ix
	var layers: Array = heightfield.layer_heights
	var heights: Array = heightfield.heights
	var water_h: Array = heightfield.water_heights
	var flags: Array = heightfield.flags_packed
	var cliff_tex: Array = heightfield.cliff_textures
	var cliff_var: Array = heightfield.cliff_variations
	if i < 0 or i >= layers.size() or i >= heights.size() or i >= flags.size():
		return false

	var cts: Array = heightfield.cliff_tilesets
	var ctype: int = cliff_type_idx
	if not cts.is_empty():
		ctype = clampi(ctype, 0, cts.size() - 1)

	var changed_any := false
	var propagate := -1
	var touched: Array = []
	match tool_id:
		"0":
			if apply_layer_delta(i, layers, heights, water_h, -2):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = Propagate.LOWER_HIGHER
		"1":
			if apply_layer_delta(i, layers, heights, water_h, -1):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = Propagate.LOWER_HIGHER
		"2":
			var target: int = level_layer if level_layer >= 0 else int(layers[i])
			if set_layer(i, layers, heights, water_h, target):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = Propagate.BOTH
		"3":
			if apply_layer_delta(i, layers, heights, water_h, 1):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = Propagate.RAISE_LOWER
		"4":
			if apply_layer_delta(i, layers, heights, water_h, 2):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = Propagate.RAISE_LOWER
		"ShallowWater":
			changed_any = paint_water(i, heights, water_h, flags, WATER_SHALLOW_EXTRA) or changed_any
		"DeepWater":
			changed_any = paint_water(i, heights, water_h, flags, WATER_DEEP_EXTRA) or changed_any
		_:
			return false

	if changed_any and propagate >= 0:
		var raised: Array = _propagate_adjacency(
			ix, iy, tp_w, tp_h, layers, heights, water_h, propagate
		)
		if not raised.is_empty():
			changed_any = true
			touched.append_array(raised)

	var ground_tex: Array = heightfield.ground_textures
	var ground_var: Array = heightfield.ground_variations
	var gti: int = ground_index_for_cliff_type(ctype)
	if changed_any and (not cts.is_empty() or gti >= 0) and (
		propagate >= 0 or tool_id in ["0", "1", "2", "3", "4"]
	):
		if _sync_corner_textures(
			ix, iy, tp_w, tp_h, layers, cliff_tex, cliff_var, ground_tex, ground_var, ctype, gti, touched
		):
			changed_any = true
			MapLog.debug(
				MapLog.Layer.LOGIC,
				"CliffLogic",
				"sync ground @(%d,%d) gti=%d ctype=%d" % [ix, iy, gti, ctype]
			)

	if changed_any:
		_mark_dirty_point(ix, iy)
		for p in touched:
			_mark_dirty_point(int(p.x), int(p.y))
	return changed_any


func apply_layer_delta(
	i: int, layers: Array, heights: Array, water_h: Array, delta: int
) -> bool:
	return set_layer(i, layers, heights, water_h, int(layers[i]) + delta)


func set_layer(
	i: int, layers: Array, heights: Array, water_h: Array, new_layer: int
) -> bool:
	var clamped: int = clampi(new_layer, LAYER_MIN, LAYER_MAX)
	var old_layer: int = int(layers[i])
	if clamped == old_layer:
		return false
	var dh: float = float(clamped - old_layer) * LAYER_HEIGHT_STEP
	layers[i] = clamped
	heights[i] = float(heights[i]) + dh
	if i < water_h.size():
		water_h[i] = float(water_h[i]) + dh
	return true


func paint_water(
	i: int, heights: Array, water_h: Array, flags: Array, water_extra: float
) -> bool:
	var did := false
	var fl: int = int(flags[i])
	var nf: int = (fl | FLAG_WATER) & ~FLAG_RAMP
	if nf != fl:
		flags[i] = nf
		did = true
	var target_w: float = float(heights[i]) + water_extra
	if i < water_h.size() and not is_equal_approx(float(water_h[i]), target_w):
		water_h[i] = target_w
		did = true
	return did


func ground_index_for_cliff_type(ctype: int) -> int:
	if not is_bound():
		return -1
	var cts: Array = heightfield.cliff_tilesets
	var gs: Array = heightfield.ground_tilesets
	if ctype < 0 or ctype >= cts.size() or gs.is_empty():
		return -1
	if _cliff_ground_cache.size() != cts.size():
		_cliff_ground_cache = PackedInt32Array()
		_cliff_ground_cache.resize(cts.size())
		_cliff_ground_cache.fill(-2)
	if _cliff_ground_cache[ctype] != -2:
		return _cliff_ground_cache[ctype]
	ensure_catalog()
	var ground_id := cliff_catalog.ground_tile_for_cliff_id(str(cts[ctype]))
	var found := -1
	if not ground_id.is_empty():
		for gi in range(gs.size()):
			if str(gs[gi]) == ground_id:
				found = gi
				break
	_cliff_ground_cache[ctype] = found
	return found


func _mark_dirty_point(ix: int, iy: int) -> void:
	if not _dirty_valid:
		dirty_min = Vector2i(ix, iy)
		dirty_max = Vector2i(ix, iy)
		_dirty_valid = true
		return
	dirty_min = Vector2i(mini(dirty_min.x, ix), mini(dirty_min.y, iy))
	dirty_max = Vector2i(maxi(dirty_max.x, ix), maxi(dirty_max.y, iy))


func _sync_corner_textures(
	ix: int,
	iy: int,
	tp_w: int,
	tp_h: int,
	layers: Array,
	cliff_tex: Array,
	cliff_var: Array,
	ground_tex: Array,
	ground_var: Array,
	ctype: int,
	gti: int,
	touched: Array
) -> bool:
	var seed_corners: Dictionary = {}
	for p in touched:
		seed_corners[Vector2i(int(p.x), int(p.y))] = true
	for oy in range(-1, 1):
		for ox in range(-1, 1):
			seed_corners[Vector2i(ix + ox, iy + oy)] = true

	var corner_pts: Dictionary = {}
	for key in seed_corners.keys():
		var p: Vector2i = key
		corner_pts[p] = true
		for oy in range(-1, 1):
			for ox in range(-1, 1):
				var tx: int = p.x + ox
				var ty: int = p.y + oy
				if tx < 0 or ty < 0 or tx >= tp_w - 1 or ty >= tp_h - 1:
					continue
				if not is_cliff_tile(layers, tp_w, tx, ty):
					continue
				for cy in range(0, 2):
					for cx in range(0, 2):
						corner_pts[Vector2i(tx + cx, ty + cy)] = true

	var any := false
	for key2 in corner_pts.keys():
		var q: Vector2i = key2
		if q.x < 0 or q.y < 0 or q.x >= tp_w or q.y >= tp_h:
			continue
		var ci: int = q.y * tp_w + q.x
		if ctype >= 0 and ci < cliff_tex.size():
			var prev_tex: int = int(cliff_tex[ci])
			if prev_tex != ctype:
				cliff_tex[ci] = ctype
				any = true
			if ci < cliff_var.size():
				if prev_tex != ctype:
					cliff_var[ci] = (randi() % 3) + 1
					any = true
				elif int(cliff_var[ci]) == 0:
					cliff_var[ci] = (absi(ci * 2654435761) % 3) + 1
					any = true
		if gti >= 0 and ci < ground_tex.size() and int(ground_tex[ci]) != gti:
			ground_tex[ci] = gti
			any = true
			if ci < ground_var.size():
				ground_var[ci] = Wc3TerrainLogic.random_ground_variation()
	return any


func _propagate_adjacency(
	ix: int,
	iy: int,
	tp_w: int,
	tp_h: int,
	layers: Array,
	heights: Array,
	water_h: Array,
	mode: int
) -> Array:
	var queue: Array = [Vector2i(ix, iy)]
	var changed_pts: Array = []
	var guard := 0
	var guard_max: int = tp_w * tp_h * 16
	var dirs: Array = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	while not queue.is_empty() and guard < guard_max:
		guard += 1
		var p: Vector2i = queue.pop_front()
		var i: int = p.y * tp_w + p.x
		if i < 0 or i >= layers.size():
			continue
		var lv: int = int(layers[i])
		for d in dirs:
			var nx: int = p.x + int(d.x)
			var ny: int = p.y + int(d.y)
			if nx < 0 or ny < 0 or nx >= tp_w or ny >= tp_h:
				continue
			var ni: int = ny * tp_w + nx
			if ni < 0 or ni >= layers.size():
				continue
			var ln: int = int(layers[ni])
			var did := false
			if mode != Propagate.LOWER_HIGHER and lv > ln + MAX_CLIFF_ADJ_DELTA:
				did = set_layer(ni, layers, heights, water_h, lv - MAX_CLIFF_ADJ_DELTA)
			elif mode != Propagate.RAISE_LOWER and ln > lv + MAX_CLIFF_ADJ_DELTA:
				did = set_layer(ni, layers, heights, water_h, lv + MAX_CLIFF_ADJ_DELTA)
			if did:
				var np := Vector2i(nx, ny)
				changed_pts.append(np)
				queue.append(np)
		_enforce_tile_spans_at(
			p.x, p.y, tp_w, tp_h, layers, heights, water_h, mode, queue, changed_pts
		)
	return changed_pts


func _enforce_tile_spans_at(
	vx: int,
	vy: int,
	tp_w: int,
	tp_h: int,
	layers: Array,
	heights: Array,
	water_h: Array,
	mode: int,
	queue: Array,
	changed_pts: Array
) -> void:
	for oy in range(-1, 1):
		for ox in range(-1, 1):
			var tx: int = vx + ox
			var ty: int = vy + oy
			if tx < 0 or ty < 0 or tx >= tp_w - 1 or ty >= tp_h - 1:
				continue
			var i00: int = ty * tp_w + tx
			var i10: int = i00 + 1
			var i01: int = i00 + tp_w
			var i11: int = i01 + 1
			var c0: int = int(layers[i00])
			var c1: int = int(layers[i10])
			var c2: int = int(layers[i01])
			var c3: int = int(layers[i11])
			var lo: int = mini(mini(c0, c1), mini(c2, c3))
			var hi: int = maxi(maxi(c0, c1), maxi(c2, c3))
			if hi - lo <= MAX_CLIFF_ADJ_DELTA:
				continue
			var corners: Array = [
				Vector2i(tx, ty),
				Vector2i(tx + 1, ty),
				Vector2i(tx, ty + 1),
				Vector2i(tx + 1, ty + 1),
			]
			var floor_l: int = hi - MAX_CLIFF_ADJ_DELTA
			var ceil_l: int = lo + MAX_CLIFF_ADJ_DELTA
			for c in corners:
				var ci: int = int(c.y) * tp_w + int(c.x)
				var lv: int = int(layers[ci])
				var did := false
				if mode != Propagate.LOWER_HIGHER and lv < floor_l:
					did = set_layer(ci, layers, heights, water_h, floor_l)
				elif mode != Propagate.RAISE_LOWER and lv > ceil_l:
					did = set_layer(ci, layers, heights, water_h, ceil_l)
				if did:
					changed_pts.append(c)
					queue.append(c)


## —— 拓扑 / TAG（纯函数）——
## Catalog 仅用于变体上限 / modelDir（配置）；不解析 GLB。

## 从 Heightfield 算出直崖 placements（Present 只消费此列表 + Catalog.resolve）。
static func collect_placements(
	hf: Wc3Heightfield, cliff_catalog: Wc3CliffCatalog
) -> Array[Wc3CliffPlacement]:
	var out: Array[Wc3CliffPlacement] = []
	if hf == null or not hf.is_valid():
		return out
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var layers: Array = hf.layer_heights
	var cliff_tex: Array = hf.cliff_textures
	var cliff_var: Array = hf.cliff_variations
	var cliff_tilesets: Array = hf.cliff_tilesets
	if layers.is_empty() or cliff_tilesets.is_empty():
		return out

	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if not is_cliff_tile(layers, tp_w, ix, iy):
				continue
			var slices: Array = cliff_slices_at(layers, tp_w, ix, iy)
			if slices.is_empty():
				continue
			var tex_idx: int = cliff_tex_index(cliff_tex, cliff_tilesets, tp_w, tp_h, ix, iy)
			var cliff_id := str(cliff_tilesets[tex_idx]) if tex_idx < cliff_tilesets.size() else ""
			var model_dir := "Cliffs"
			if cliff_catalog != null:
				model_dir = cliff_catalog.cliff_model_dir(cliff_id)
			var i00: int = iy * tp_w + ix
			var stored: int = int(cliff_var[i00]) if i00 < cliff_var.size() else 0
			for slice in slices:
				var tag: String = str(slice.get("tag", ""))
				if tag.is_empty() or tag == "AAAA":
					continue
				var base_layer: int = int(slice.get("base_layer", 2))
				var variation: int = 0
				if cliff_catalog != null:
					variation = cliff_catalog.pick_cliff_variation(
						model_dir, tag, stored, ix, iy
					)
				out.append(
					Wc3CliffPlacement.make(ix, iy, tag, base_layer, tex_idx, variation)
				)
	return out


## 从格子四角选悬崖类型：优先非 0 索引（草地等），避免只读 i00 时落成默认泥土。
static func cliff_tex_index(
	cliff_tex: Array, cliff_tilesets: Array, tp_w: int, tp_h: int, ix: int, iy: int
) -> int:
	var best := 0
	var found_nonzero := false
	for oy in range(0, 2):
		for ox in range(0, 2):
			var cx: int = ix + ox
			var cy: int = iy + oy
			if cx < 0 or cy < 0 or cx >= tp_w or cy >= tp_h:
				continue
			var i: int = cy * tp_w + cx
			if i < 0 or i >= cliff_tex.size():
				continue
			var tex_idx := int(cliff_tex[i])
			if tex_idx == 15:
				tex_idx = 1
			if tex_idx < 0 or tex_idx >= cliff_tilesets.size():
				continue
			if not found_nonzero:
				best = tex_idx
			if tex_idx != 0:
				best = tex_idx
				found_nonzero = true
	if best < 0 or best >= cliff_tilesets.size():
		best = clampi(best, 0, maxi(cliff_tilesets.size() - 1, 0))
	return best


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


static func is_ramp_flag(flags: Array, i: int) -> bool:
	if i < 0 or i >= flags.size():
		return false
	return (int(flags[i]) & FLAG_RAMP) != 0


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
	hf: Dictionary, meta: Dictionary = {}, _cliff_catalog: Wc3CliffCatalog = null
) -> Dictionary:
	if meta.is_empty():
		meta = Wc3Heightfield.build_meta_from_dict(hf)
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
	var tr_c := int(layer_heights[i11])
	var lo := mini(mini(bl, br), mini(tl, tr_c))
	var hi := maxi(maxi(bl, br), maxi(tl, tr_c))
	var out: Array = []
	var base := lo
	while base < hi:
		var raw_bl := bl - base
		var raw_tl := tl - base
		var raw_tr := tr_c - base
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
		meta = Wc3Heightfield.build_meta_from_dict(hf)
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
