class_name Wc3TerrainLogic
extends RefCounted

## 高度图 / 地表逻辑层：只改 Wc3Heightfield，不建 Mesh、不查资产路径。
## 脏矩形供表现层局部重建（现阶段可先全量，接口已预留）。

const LAYER_MIN := 0						## 最小层数
const LAYER_MAX := 14						## 最大层数
const FLAT_LAYER := 2						## 平坦层数

## 经典 WE / HiveWE 地表 variation 加权表（总和 570）。
const VARIATION_CHANCE_SUM := 570
const VARIATION_CHANCES := [
	[0, 85], [16, 85], [17, 85],
	[1, 10], [2, 4], [3, 1],
	[4, 85], [5, 10], [6, 4], [7, 1],
	[8, 85], [9, 10], [10, 4], [11, 1],
	[12, 85], [13, 10], [14, 4], [15, 1],
]

var heightfield: Wc3Heightfield = null		## 高度场
var dirty_min: Vector2i = Vector2i.ZERO		## 脏区最小坐标
var dirty_max: Vector2i = Vector2i.ZERO		## 脏区最大坐标
var _dirty_valid: bool = false				## 是否有效


## 新建地图 / 笔刷铺地时的 groundVariation（5 bit）。对齐 HiveWE。
static func random_ground_variation(rng: RandomNumberGenerator = null) -> int:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var nr: int = r.randi_range(0, VARIATION_CHANCE_SUM) - 1
	for pair in VARIATION_CHANCES:
		var chance: int = int(pair[1])
		if nr < chance:
			return int(pair[0])
		nr -= chance
	return 0

## 绑定高度场
## [param hf: Wc3Heightfield] 高度场
## [return Wc3TerrainLogic] 自身
func bind(hf: Wc3Heightfield) -> Wc3TerrainLogic:
	heightfield = hf
	clear_dirty()
	return self

## 是否绑定
## [return bool] 是否绑定
func is_bound() -> bool:
	return heightfield != null and heightfield.width >= 2

## 清空脏区
func clear_dirty() -> void:
	_dirty_valid = false
	dirty_min = Vector2i.ZERO
	dirty_max = Vector2i.ZERO

## 是否有脏区
## [return bool] 是否有脏区
func has_dirty() -> bool:
	return _dirty_valid


## 取出并清空脏矩形（tilepoint 坐标，闭区间 → Rect2i position/size）。
## [return Rect2i] 脏矩形
func take_dirty_rect() -> Rect2i:
	if not _dirty_valid:
		return Rect2i()
	var r := Rect2i(dirty_min, dirty_max - dirty_min + Vector2i.ONE)
	clear_dirty()
	return r

## 获取顶点
## [param ix: int] 坐标 x
## [param iy: int] 坐标 y
## [return Wc3TileVertex] 顶点
func vertex_at(ix: int, iy: int) -> Wc3TileVertex:
	if not is_bound():
		return null
	return heightfield.vertex_at(ix, iy)

## 获取层数
## [param ix: int] 坐标 x
## [param iy: int] 坐标 y
## [return int] 层数
func layer_at(ix: int, iy: int) -> int:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		return FLAT_LAYER
	var i: int = heightfield.index_at(ix, iy)
	return clampi(int(heightfield.layer_heights[i]), LAYER_MIN, LAYER_MAX)

## 获取高度
## [param ix: int] 坐标 x
## [param iy: int] 坐标 y
## [return float] 高度
func height_at(ix: int, iy: int) -> float:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		return 0.0
	return float(heightfield.heights[heightfield.index_at(ix, iy)])


## 正交四邻层高（越界为 FLAT_LAYER）。顺序：左、右、下、上。
## [param ix: int] 坐标 x
## [param iy: int] 坐标 y
## [return PackedInt32Array] 四邻层高
func neighbor_layers(ix: int, iy: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(4)
	out[0] = layer_at(ix - 1, iy)
	out[1] = layer_at(ix + 1, iy)
	out[2] = layer_at(ix, iy - 1)
	out[3] = layer_at(ix, iy + 1)
	return out


## 写地表索引；可选随机 groundVariation（对齐笔刷）。
## [param ix: int] 坐标 x
## [param iy: int] 坐标 y
## [param tex_index: int] 地表索引
## [param randomize_var: bool] 是否随机地表变体
## [return bool] 是否成功
func set_ground_tex(ix: int, iy: int, tex_index: int, randomize_var: bool = true) -> bool:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		AppLog.debug(
			AppLog.Layer.LOGIC,
			"TerrainLogic",
			"set_ground_tex OOB/unbound (%d,%d)" % [ix, iy]
		)
		return false
	var gs: Array = heightfield.ground_tilesets
	if tex_index < 0 or tex_index >= gs.size():
		AppLog.warn(
			AppLog.Layer.LOGIC,
			"TerrainLogic",
			"tex_index=%d 越界 tilesets=%d" % [tex_index, gs.size()]
		)
		return false
	var i: int = heightfield.index_at(ix, iy)
	var old_tex: int = int(heightfield.ground_textures[i])
	var changed := false
	if old_tex != tex_index:
		heightfield.ground_textures[i] = tex_index
		changed = true
	if randomize_var and i < heightfield.ground_variations.size():
		heightfield.ground_variations[i] = Wc3TerrainLogic.random_ground_variation()
		changed = true
	if changed:
		_mark_dirty(ix, iy)
		AppLog.debug(
			AppLog.Layer.LOGIC,
			"TerrainLogic",
			"paint (%d,%d) %d→%d var_rand=%s"
			% [ix, iy, old_tex, tex_index, randomize_var]
		)
	return changed


## 写污染（Blight）标志。
## 保护规则：写入 v=true 时若 3×3 邻域内有 cliff，返回 false（HivEWE TextureOperator 经典）。
## force=true 跳过保护（仅供内部用，如加载离线资产时强制 set）。
## 当前无 Blight 笔刷实现（ToolPaletteWindow 有 SpecialBlight 按钮但 setter 未接），
## 此方法为未来 ROADMAP §⑪ 装饰物 / Blight 笔刷铺路。
## [param ix: int] 坐标 x
## [param iy: int] 坐标 y
## [param v: bool] 是否设污染
## [param force: bool] 跳过 cliff 邻接保护
## [return bool] 是否成功写入
func set_blight(ix: int, iy: int, v: bool, force: bool = false) -> bool:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		return false
	if v and not force:
		var tp_w: int = heightfield.width
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var tx: int = ix + dx
				var ty: int = iy + dy
				if not heightfield.in_bounds(tx, ty):
					continue
				if Wc3CliffLogic.is_cliff_tile(heightfield.layer_heights, tp_w, tx, ty):
					AppLog.debug(
						AppLog.Layer.LOGIC,
						"TerrainLogic",
						"set_blight(%d,%d) 邻接 cliff @(%d,%d)，跳过" % [ix, iy, tx, ty]
					)
					return false
	var i: int = heightfield.index_at(ix, iy)
	if i < 0 or i >= heightfield.flags_packed.size():
		return false
	var cur: int = int(heightfield.flags_packed[i])
	var nf: int = (cur | Wc3Coords.FLAG_BLIGHT) if v else (cur & ~Wc3Coords.FLAG_BLIGHT)
	if cur == nf:
		return false
	heightfield.flags_packed[i] = nf
	_mark_dirty(ix, iy)
	return true


## Nothing 笔刷边界（FLAG_BOUNDARY）。HiveWE：cell 模式写 BL corner。
func set_boundary(ix: int, iy: int, v: bool) -> bool:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		return false
	var i: int = heightfield.index_at(ix, iy)
	if i < 0 or i >= heightfield.flags_packed.size():
		return false
	var cur: int = int(heightfield.flags_packed[i])
	var nf: int = (cur | Wc3Coords.FLAG_BOUNDARY) if v else (cur & ~Wc3Coords.FLAG_BOUNDARY)
	if cur == nf:
		return false
	heightfield.flags_packed[i] = nf
	_mark_dirty(ix, iy)
	return true


## 实用区外缘（FLAG_MAP_EDGE）。由 cameraBoundsComplements 批量写入。
func set_map_edge(ix: int, iy: int, v: bool) -> bool:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		return false
	var i: int = heightfield.index_at(ix, iy)
	if i < 0 or i >= heightfield.flags_packed.size():
		return false
	var cur: int = int(heightfield.flags_packed[i])
	var nf: int = (cur | Wc3Coords.FLAG_MAP_EDGE) if v else (cur & ~Wc3Coords.FLAG_MAP_EDGE)
	if cur == nf:
		return false
	heightfield.flags_packed[i] = nf
	_mark_dirty(ix, iy)
	return true


## 按补边重写整图 FLAG_MAP_EDGE（对齐 HiveWE set_unplayable_boundaries）。
## complements 以「格」为单位（playable = map − L/R/B/T）；写在 cell BL 角点上。
## complements: {left,right,bottom,top}；缺省用 Blizzard 默认 L6R6B4T8。
func apply_unplayable_boundaries(complements: Dictionary = {}) -> int:
	if not is_bound():
		return 0
	var left: int = int(complements.get("left", Wc3Coords.DEFAULT_BOUNDS_LEFT))
	var right: int = int(complements.get("right", Wc3Coords.DEFAULT_BOUNDS_RIGHT))
	var bottom: int = int(complements.get("bottom", Wc3Coords.DEFAULT_BOUNDS_BOTTOM))
	var top: int = int(complements.get("top", Wc3Coords.DEFAULT_BOUNDS_TOP))
	var tp_w: int = heightfield.width
	var tp_h: int = heightfield.height
	# map_* = 格数；tilepoint 多一圈。不可玩判定只看 cell BL。
	var mw: int = heightfield.map_width if heightfield.map_width > 0 else maxi(tp_w - 1, 0)
	var mh: int = heightfield.map_height if heightfield.map_height > 0 else maxi(tp_h - 1, 0)
	var changed := 0
	for iy in range(tp_h):
		for ix in range(tp_w):
			var edge := false
			if ix < mw and iy < mh:
				edge = (
					ix < left
					or ix >= mw - right
					or iy < bottom
					or iy >= mh - top
				)
			if set_map_edge(ix, iy, edge):
				changed += 1
	return changed


## 写高度
## [param ix: int] 坐标 x
## [param iy: int] 坐标 y
## [param h: float] 高度
## [return bool] 是否成功
func set_height(ix: int, iy: int, h: float) -> bool:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		return false
	var i: int = heightfield.index_at(ix, iy)
	if is_equal_approx(float(heightfield.heights[i]), h):
		return false
	heightfield.heights[i] = h
	_mark_dirty(ix, iy)
	return true


## 单 tilepoint 地表（与 MapDocument.paint_corner 同语义）。
## [param ix: int] 坐标 x
## [param iy: int] 坐标 y
## [param tex_index: int] 地表索引
## [return bool] 是否成功
func paint_corner(ix: int, iy: int, tex_index: int) -> bool:
	return set_ground_tex(ix, iy, tex_index, true)


## 地表格四角地表。
## [param tx: int] 坐标 x
## [param ty: int] 坐标 y
## [param tex_index: int] 地表索引
## [return bool] 是否成功
func paint_tile(tx: int, ty: int, tex_index: int) -> bool:
	if not is_bound():
		return false
	var map_w: int = heightfield.map_width
	var map_h: int = heightfield.map_height
	if tx < 0 or ty < 0 or tx >= map_w or ty >= map_h:
		return false
	var changed_any := false
	for c in [
		Vector2i(tx, ty),
		Vector2i(tx + 1, ty),
		Vector2i(tx, ty + 1),
		Vector2i(tx + 1, ty + 1),
	]:
		if paint_corner(c.x, c.y, tex_index):
			changed_any = true
	return changed_any


## 采样地表高度；若至少一个顶点越界，返回 0。
## [param tx: int] 坐标 x
## [param ty: int] 坐标 y
## [return float] 高度, 0 表示越界
func sample_height_at_tile(tx: int, ty: int) -> float:
	if not is_bound():
		return 0.0
	var sum := 0.0
	var n := 0
	for c in [
		Vector2i(tx, ty),
		Vector2i(tx + 1, ty),
		Vector2i(tx, ty + 1),
		Vector2i(tx + 1, ty + 1),
	]:
		if heightfield.in_bounds(c.x, c.y):
			sum += height_at(c.x, c.y)
			n += 1
	return sum / float(n) if n > 0 else 0.0

## 标记脏区
## [param ix: int] 坐标 x
## [param iy: int] 坐标 y
func _mark_dirty(ix: int, iy: int) -> void:
	if not _dirty_valid:
		dirty_min = Vector2i(ix, iy)
		dirty_max = Vector2i(ix, iy)
		_dirty_valid = true
		return
	dirty_min.x = mini(dirty_min.x, ix)
	dirty_min.y = mini(dirty_min.y, iy)
	dirty_max.x = maxi(dirty_max.x, ix)
	dirty_max.y = maxi(dirty_max.y, iy)


## 角点「实际」地表纹理下标（对齐 HiveWE `real_tile_texture` / MapTerrainLayer.corner_texture）。
## 优先级：附近 romp 或 (附近 cliff 且自身非 ramp) → cliff_to_ground；否则 ground_tex。
## blight 路径留后置。
static func real_tile_texture(
	ground_tex: Array,
	layer_heights: Array,
	cliff_tex: Array,
	cliff_to_ground: PackedInt32Array,
	flags_packed: Array,
	romp: PackedByteArray,
	tp_w: int,
	tp_h: int,
	col: int,
	row: int,
) -> int:
	var self_idx := row * tp_w + col
	var self_is_ramp: bool = (
		self_idx >= 0
		and self_idx < flags_packed.size()
		and (int(flags_packed[self_idx]) & Wc3Coords.FLAG_RAMP) != 0
	)
	if not cliff_to_ground.is_empty():
		for dy in range(-1, 1):
			for dx in range(-1, 1):
				var tx := col + dx
				var ty := row + dy
				if tx < 0 or ty < 0 or tx >= tp_w - 1 or ty >= tp_h - 1:
					continue
				if not Wc3CliffLogic.is_cliff_tile(layer_heights, tp_w, tx, ty):
					continue
				if self_is_ramp and tx == col and ty == row:
					continue
				var i00 := ty * tp_w + tx
				var ci := int(cliff_tex[i00]) if i00 < cliff_tex.size() else 0
				if ci == 15:
					ci = 1
				if ci >= 0 and ci < cliff_to_ground.size() and cliff_to_ground[ci] >= 0:
					return cliff_to_ground[ci]
		if not romp.is_empty():
			for dy in range(-1, 1):
				for dx in range(-1, 1):
					var tx2 := col + dx
					var ty2 := row + dy
					if tx2 < 0 or ty2 < 0 or tx2 >= tp_w - 1 or ty2 >= tp_h - 1:
						continue
					var i_romp: int = ty2 * tp_w + tx2
					if i_romp < romp.size() and romp[i_romp] != 0:
						var ci2 := int(cliff_tex[self_idx]) if self_idx < cliff_tex.size() else 0
						if ci2 == 15:
							ci2 = 1
						if ci2 >= 0 and ci2 < cliff_to_ground.size() and cliff_to_ground[ci2] >= 0:
							return cliff_to_ground[ci2]
	if self_idx < 0 or self_idx >= ground_tex.size():
		return 0
	return int(ground_tex[self_idx])
