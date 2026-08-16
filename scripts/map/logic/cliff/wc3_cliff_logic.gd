class_name Wc3CliffLogic
extends RefCounted

## 悬崖逻辑层：改 layerHeights / cliffTextures / groundTile（策略 A 清坡）；
## 拓扑选型 / placements / gap_mask。不建 Mesh、不 resolve GLB。
## Present 只消费 build_topology 输出；若 Present 写 Heightfield 即为 BUG。
## 斜坡笔刷 / Collect 在 Wc3RampLogic；此处嵌 Collect 供拓扑与挖洞。
## 策略 A：层高变更自动清除 ramp flag（不对斜坡模块产生导入依赖）。

const LAYER_MIN := 0
const LAYER_MAX := 14
const MAX_CLIFF_ADJ_DELTA := 2
const LAYER_HEIGHT_STEP := 128.0
const WATER_SHALLOW_EXTRA := 48.0
const WATER_DEEP_EXTRA := 128.0
const FLAG_WATER := Wc3Coords.FLAG_WATER
const FLAG_RAMP := Wc3Coords.FLAG_RAMP
## _RAMP_BIT 仅在层高变更清除 ramp 时内联使用；不引用斜坡模块以保持解耦。
const _RAMP_BIT: int = 4

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

	## 策略 A：按层高变更点清除其所在连续坡臂（非 ±2 方阵）
	if changed_any and propagate >= 0:
		_clear_ramp_flags_near(flags, ix, iy, touched)

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
			AppLog.debug(
				AppLog.Layer.LOGIC,
				"CliffLogic",
				"sync ground @(%d,%d) gti=%d ctype=%d" % [ix, iy, gti, ctype]
			)

	if changed_any:
		# 放 cliff 后清 4 角 FLAG_BLIGHT（HivEWE 经典规则：腐地不该跨到 cliff）。
		# 仅 cliff 升降路径（propagate>=0）触发；水操作不调。
		if propagate >= 0:
			for tx in range(ix, ix + 2):
				for ty in range(iy, iy + 2):
					if tx < 0 or ty < 0 or tx >= tp_w or ty >= tp_h:
						continue
					var j: int = ty * tp_w + tx
					if j < flags.size():
						flags[j] = int(flags[j]) & ~Wc3Coords.FLAG_BLIGHT
		_mark_dirty_point(ix, iy)
		for p in touched:
			_mark_dirty_point(int(p.x), int(p.y))
	return changed_any


## 策略 A（收紧）：只清「层高变更顶点」所穿过的连续坡臂，不扫刷点 ±2 方阵。
## 方阵会误删平行邻列仍合法的斜坡；蛋糕/传播 touched 很多时尤其过量。
## 臂长最多 3（原点±2 步），遇无旗即停，不跨空洞扫到无关坡。
func _clear_ramp_flags_near(flags: Array, brush_x: int, brush_y: int, touched: Array) -> void:
	var tw: int = heightfield.width
	var th: int = heightfield.height
	var seeds: Dictionary = {}
	seeds[Vector2i(brush_x, brush_y)] = true
	for p in touched:
		seeds[Vector2i(int(p.x), int(p.y))] = true
	for key in seeds.keys():
		var s: Vector2i = key as Vector2i
		_clear_ramp_arms_through(flags, tw, th, s.x, s.y)


## 清除经过 (x,y) 的连续 FLAG_RAMP（自身 + 四向各最多 2 步，遇空停）。
func _clear_ramp_arms_through(flags: Array, tw: int, th: int, x: int, y: int) -> void:
	_clear_ramp_bit_at(flags, tw, th, x, y)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for step in range(1, 3):
			var nx: int = x + d.x * step
			var ny: int = y + d.y * step
			if not _has_ramp_bit(flags, tw, th, nx, ny):
				break
			_clear_ramp_bit_at(flags, tw, th, nx, ny)


func _has_ramp_bit(flags: Array, tw: int, th: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= tw or y >= th:
		return false
	var i: int = y * tw + x
	if i < 0 or i >= flags.size():
		return false
	return (int(flags[i]) & _RAMP_BIT) != 0


func _clear_ramp_bit_at(flags: Array, tw: int, th: int, x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= tw or y >= th:
		return
	var i: int = y * tw + x
	if i < 0 or i >= flags.size():
		return
	if (int(flags[i]) & _RAMP_BIT) != 0:
		flags[i] = int(flags[i]) & ~_RAMP_BIT


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


## 角点是否落在某直崖格的四角上（用于 groundTile 崖缘过渡圈）。
## 台顶内侧不贴直崖的角点不会命中 → 保持原地表。
static func is_cliff_tile_corner(
	layers: Array, tp_w: int, tp_h: int, col: int, row: int
) -> bool:
	if layers.is_empty() or col < 0 or row < 0 or col >= tp_w or row >= tp_h:
		return false
	for dy in range(-1, 1):
		for dx in range(-1, 1):
			var tx: int = col + dx
			var ty: int = row + dy
			if tx < 0 or ty < 0 or tx >= tp_w - 1 or ty >= tp_h - 1:
				continue
			if is_cliff_tile(layers, tp_w, tx, ty):
				return true
	return false


## 角点是否落在某直崖格的「低侧」（层高 < 该格四角 max）。
static func is_low_side_cliff_corner(
	layers: Array, tp_w: int, tp_h: int, col: int, row: int
) -> bool:
	if layers.is_empty() or col < 0 or row < 0 or col >= tp_w or row >= tp_h:
		return false
	var lv: int = int(layers[row * tp_w + col])
	for dy in range(-1, 1):
		for dx in range(-1, 1):
			var tx: int = col + dx
			var ty: int = row + dy
			if tx < 0 or ty < 0 or tx >= tp_w - 1 or ty >= tp_h - 1:
				continue
			if not is_cliff_tile(layers, tp_w, tx, ty):
				continue
			var mx: int = -1
			for cy in range(0, 2):
				for cx in range(0, 2):
					var i: int = (ty + cy) * tp_w + (tx + cx)
					if i < 0 or i >= layers.size():
						continue
					mx = maxi(mx, int(layers[i]))
			if mx >= 0 and lv < mx:
				return true
	return false


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
			# 真随机写入角点变体（0–7）；挂模按 BL 夹紧到 TAG 可用变体，避免空间哈希 010101
			if ci < cliff_var.size():
				var rv: int = Wc3CliffCatalog.random_variation_byte()
				if int(cliff_var[ci]) != rv:
					cliff_var[ci] = rv
					any = true
		# 直崖格四角写 groundTile → 台顶缘/崖脚与泥土形成 bitmask 过渡（对齐 WE / viewer）
		if gti >= 0 and ci < ground_tex.size() and int(ground_tex[ci]) != gti:
			ground_tex[ci] = gti
			any = true
			if ci < ground_var.size():
				ground_var[ci] = Wc3TerrainLogic.random_ground_variation()

	# 抬台过程中曾落在崖缘的角点，填平后不再贴直崖 → 清回默认地表，避免台心整片残留草
	if gti >= 0 and not ground_tex.is_empty():
		var min_x: int = ix
		var max_x: int = ix
		var min_y: int = iy
		var max_y: int = iy
		for p4 in touched:
			min_x = mini(min_x, int(p4.x))
			max_x = maxi(max_x, int(p4.x))
			min_y = mini(min_y, int(p4.y))
			max_y = maxi(max_y, int(p4.y))
		for key3 in corner_pts.keys():
			var q3: Vector2i = key3
			min_x = mini(min_x, q3.x)
			max_x = maxi(max_x, q3.x)
			min_y = mini(min_y, q3.y)
			max_y = maxi(max_y, q3.y)
		min_x = clampi(min_x - 2, 0, tp_w - 1)
		max_x = clampi(max_x + 2, 0, tp_w - 1)
		min_y = clampi(min_y - 2, 0, tp_h - 1)
		max_y = clampi(max_y + 2, 0, tp_h - 1)
		for cy3 in range(min_y, max_y + 1):
			for cx3 in range(min_x, max_x + 1):
				if is_cliff_tile_corner(layers, tp_w, tp_h, cx3, cy3):
					continue
				var ci3: int = cy3 * tp_w + cx3
				if ci3 < ground_tex.size() and int(ground_tex[ci3]) == gti:
					ground_tex[ci3] = 0
					any = true
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


## —— 拓扑 / TAG ——
## Catalog 仅用于 modelDir / 变体上限（配置）；不解析 GLB、不建 Mesh。

## 一次扫完：直崖 placements + 直崖 gap_mask。
## 斜坡 Collect / 入口挖洞例外不在此合并——由 Ramp Present 调地形/悬崖 API（见 RAMP_WE §8）。
static func build_topology(
	hf: Wc3Heightfield, catalog: Wc3CliffCatalog
) -> Wc3CliffTopologyResult:
	var result := Wc3CliffTopologyResult.new()
	if hf == null or not hf.is_valid():
		return result
	result.placements = collect_placements(hf, catalog)
	result.gap_mask = build_gap_mask(hf)
	result.gap_stats = count_gaps(hf.as_dict_view(), hf.to_build_meta())
	return result


## 地表格挖洞 mask：1=Present 跳过地面四边形（仅直崖；不含斜坡 romp/入口）。
static func build_gap_mask(hf: Wc3Heightfield) -> PackedByteArray:
	var mask := PackedByteArray()
	if hf == null or not hf.is_valid():
		return mask
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var layers: Array = hf.layer_heights
	mask.resize(maxi((tp_w - 1) * (tp_h - 1), 0))
	mask.fill(0)
	var i := 0
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if is_cliff_tile(layers, tp_w, ix, iy):
				mask[i] = 1
			i += 1
	return mask


## 从 Heightfield 算出直崖 placements（已过滤无效 TAG；含 model_dir / variation）。
## 变体按格（对齐 HiveWE：用 BL 角 cliff_variation；同墙允许不同变体）。
static func collect_placements(
	hf: Wc3Heightfield, catalog: Wc3CliffCatalog
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

	var raw: Array[Dictionary] = []
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
			if catalog != null:
				model_dir = catalog.cliff_model_dir(cliff_id)
			# HiveWE：file_name 变体取 bottom_left.cliff_variation
			var stored: int = _tile_bl_variation(cliff_var, tp_w, tp_h, ix, iy)
			for slice in slices:
				var tag: String = str(slice.get("tag", ""))
				if tag.is_empty() or tag == "AAAA":
					continue
				var base_layer: int = int(slice.get("base_layer", 2))
				var variation := 0
				if catalog != null:
					variation = catalog.pick_cliff_variation(
						model_dir, tag, stored, ix, iy
					)
				else:
					variation = maxi(stored, 0)
				raw.append({
					"ix": ix,
					"iy": iy,
					"tag": tag,
					"base_layer": base_layer,
					"tex_idx": tex_idx,
					"model_dir": model_dir,
					"variation": variation,
				})

	for item in raw:
		out.append(
			Wc3CliffPlacement.make(
				int(item["ix"]),
				int(item["iy"]),
				str(item["tag"]),
				int(item["base_layer"]),
				int(item["tex_idx"]),
				str(item["model_dir"]),
				int(item["variation"])
			)
		)
	return out


## 地表格 BL 角 cliffVariations（对齐 HiveWE bottom_left.cliff_variation）。
static func _tile_bl_variation(
	cliff_var: Array, tp_w: int, tp_h: int, ix: int, iy: int
) -> int:
	if cliff_var.is_empty() or ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return 0
	var i: int = iy * tp_w + ix
	if i < 0 or i >= cliff_var.size():
		return 0
	return maxi(int(cliff_var[i]), 0)


## 四角 cliffVariations：取非 0 众数；并列取较大值；全 0 返回 0。
##（笔刷/调试用；挂模选型改走 _tile_bl_variation。）
static func _tile_stored_variation(
	cliff_var: Array, tp_w: int, tp_h: int, ix: int, iy: int
) -> int:
	if cliff_var.is_empty():
		return 0
	var counts: Dictionary = {}
	for oy in range(0, 2):
		for ox in range(0, 2):
			var cx: int = ix + ox
			var cy: int = iy + oy
			if cx < 0 or cy < 0 or cx >= tp_w or cy >= tp_h:
				continue
			var i: int = cy * tp_w + cx
			if i < 0 or i >= cliff_var.size():
				continue
			var v: int = int(cliff_var[i])
			if v <= 0:
				continue
			counts[v] = int(counts.get(v, 0)) + 1
	if counts.is_empty():
		return 0
	var best_v := 0
	var best_n := -1
	for k in counts.keys():
		var n: int = int(counts[k])
		var kv: int = int(k)
		if n > best_n or (n == best_n and kv > best_v):
			best_n = n
			best_v = kv
	return best_v


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


## 四角任一顶点带 FLAG_RAMP。
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
		(int(flags[i00]) & FLAG_RAMP) != 0
		or (int(flags[i10]) & FLAG_RAMP) != 0
		or (int(flags[i01]) & FLAG_RAMP) != 0
		or (int(flags[i11]) & FLAG_RAMP) != 0
	)


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


## gap / cliff / FLAG_RAMP / romp 统计。
static func count_gaps(
	hf: Dictionary, meta: Dictionary = {}, ramp_data: Wc3RampCollectResult = null
) -> Dictionary:
	if meta.is_empty():
		meta = Wc3Heightfield.build_meta_from_dict(hf)
	var width: int = meta["width"]
	var height: int = meta["height"]
	var layers: Array = meta["layer_heights"]
	var flags: Array = meta["flags"]
	if ramp_data == null:
		ramp_data = Wc3RampCollectResult.empty_for_size(width, height)
	var cliffs := 0
	var ramps := 0
	var gaps := 0
	var tiles := (width - 1) * (height - 1)
	for iy in range(height - 1):
		for ix in range(width - 1):
			if is_cliff_tile(layers, width, ix, iy):
				gaps += 1
				cliffs += 1
			if is_ramp_tile(flags, width, ix, iy):
				ramps += 1
	return {
		"gaps": gaps,
		"cliffs": cliffs,
		"ramps": ramps,
		"tiles": tiles,
		"ramp_models": ramp_data.non_phantom_count(),
	}
