class_name Wc3CliffLogic
extends RefCounted

## 悬崖逻辑层：改 layerHeights / cliffTextures / groundTile（策略 B），不建 Mesh、不查 GLB。
## 绑定 Wc3Heightfield；Catalog 仅用于 groundTile → groundTilesets 下标。

const LAYER_MIN := 0
const LAYER_MAX := 14
const MAX_CLIFF_ADJ_DELTA := 2
const LAYER_HEIGHT_STEP := 128.0
const WATER_SHALLOW_EXTRA := 48.0
const WATER_DEEP_EXTRA := 128.0
const FLAG_WATER := Wc3Coords.FLAG_WATER
const FLAG_RAMP := Wc3Coords.FLAG_RAMP

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
				if not Wc3CliffTiles.is_cliff_tile(layers, tp_w, tx, ty):
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
