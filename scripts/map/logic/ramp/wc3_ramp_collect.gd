class_name Wc3RampCollect
extends RefCounted

## HiveWE `Terrain::update_cliff_meshes` 斜坡匹配部分（只产出 placements + romp）。
## 权威：docs/ramp/RAMP_WE.md §5


static func collect(
	hf: Wc3Heightfield, cliff_catalog: Wc3CliffCatalog = null
) -> Wc3RampCollectResult:
	if hf == null or not hf.is_valid():
		return Wc3RampCollectResult.empty_for_size(0, 0)
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var out := Wc3RampCollectResult.empty_for_size(tp_w, tp_h)
	var layers: Array = hf.layer_heights
	var flags: Array = hf.flags_packed
	var cliff_tex: Array = hf.cliff_textures
	var cliff_sets: Array = hf.cliff_tilesets
	if layers.is_empty() or flags.is_empty():
		return out

	var cat := cliff_catalog
	if cat == null:
		cat = Wc3CliffCatalog.new()
		cat.load_default()

	# 预计算 ramp 布尔便于匹配
	var ramp: PackedByteArray = PackedByteArray()
	ramp.resize(tp_w * tp_h)
	for i in range(mini(flags.size(), ramp.size())):
		ramp[i] = 1 if (int(flags[i]) & Wc3Coords.FLAG_RAMP) != 0 else 0

	for j in range(tp_h - 1):
		for i in range(tp_w - 1):
			# 竖直 2×3
			if j < tp_h - 2:
				var hit_v: Dictionary = _try_vertical(
					i, j, layers, ramp, cliff_tex, cliff_sets, cat, tp_w
				)
				if bool(hit_v.get("ok", false)):
					var pv: Wc3RampPlacement = hit_v["placement"]
					out.placements.append(pv)
					out.romp[_ci(i, j, tp_w)] = Wc3RampLogic.ROMP_TRANS
					out.romp[_ci(i, j + 1, tp_w)] = Wc3RampLogic.ROMP_TRANS
					continue
			# 水平 2×3
			if i < tp_w - 2:
				var hit_h: Dictionary = _try_horizontal(
					i, j, layers, ramp, cliff_tex, cliff_sets, cat, tp_w
				)
				if bool(hit_h.get("ok", false)):
					var ph: Wc3RampPlacement = hit_h["placement"]
					out.placements.append(ph)
					out.romp[_ci(i, j, tp_w)] = Wc3RampLogic.ROMP_TRANS
					out.romp[_ci(i + 1, j, tp_w)] = Wc3RampLogic.ROMP_TRANS
	return out


## 入口格：保留地面 + 低角 +0.5（对齐 HiveWE is_corner_ramp_entrance，并扩展 L 内角凹陷）。
## 1) 经典：四角皆 ramp 且非「对角层高两两相等」。
## 2) L 凹陷：恰一角最低，且该角与其边上两邻角有 ramp（L 补心常见：高角无旗）。
##    → undig 三高一低地面，形成朝补心下凹的坡，而不是只挖洞靠 BBAB。
static func is_entrance(flags: Array, layers: Array, tp_w: int, tp_h: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= tp_w - 1 or y >= tp_h - 1:
		return false
	if _is_classic_entrance(flags, layers, tp_w, x, y):
		return true
	return _is_l_recess_entrance(flags, layers, tp_w, x, y)


static func _is_classic_entrance(
	flags: Array, layers: Array, tp_w: int, x: int, y: int
) -> bool:
	if not (
		_flag_ramp(flags, tp_w, x, y)
		and _flag_ramp(flags, tp_w, x + 1, y)
		and _flag_ramp(flags, tp_w, x, y + 1)
		and _flag_ramp(flags, tp_w, x + 1, y + 1)
	):
		return false
	var bl: int = int(layers[y * tp_w + x])
	var br: int = int(layers[y * tp_w + x + 1])
	var tl: int = int(layers[(y + 1) * tp_w + x])
	var top_r: int = int(layers[(y + 1) * tp_w + x + 1])
	return not (bl == top_r and tl == br)


## L 补心内角：唯一低角 + 两边邻角有旗（高角可无旗）。
static func _is_l_recess_entrance(
	flags: Array, layers: Array, tp_w: int, x: int, y: int
) -> bool:
	if not Wc3CliffLogic.is_cliff_tile(layers, tp_w, x, y):
		return false
	var i00: int = y * tp_w + x
	var i10: int = i00 + 1
	var i01: int = i00 + tp_w
	var i11: int = i01 + 1
	var lv00: int = int(layers[i00])
	var lv10: int = int(layers[i10])
	var lv01: int = int(layers[i01])
	var lv11: int = int(layers[i11])
	var lo: int = mini(mini(lv00, lv10), mini(lv01, lv11))
	var low_bits: int = 0
	if lv00 == lo:
		low_bits |= 1
	if lv10 == lo:
		low_bits |= 2
	if lv01 == lo:
		low_bits |= 4
	if lv11 == lo:
		low_bits |= 8
	# 恰一角最低（三高一低）
	if low_bits != 1 and low_bits != 2 and low_bits != 4 and low_bits != 8:
		return false
	# 低角必须有 ramp；与低角共边的两角也必须有 ramp
	match low_bits:
		1: # BL 低 → 邻 BR、TL
			return (
				_flag_ramp(flags, tp_w, x, y)
				and _flag_ramp(flags, tp_w, x + 1, y)
				and _flag_ramp(flags, tp_w, x, y + 1)
			)
		2: # BR 低 → 邻 BL、TR
			return (
				_flag_ramp(flags, tp_w, x + 1, y)
				and _flag_ramp(flags, tp_w, x, y)
				and _flag_ramp(flags, tp_w, x + 1, y + 1)
			)
		4: # TL 低 → 邻 BL、TR
			return (
				_flag_ramp(flags, tp_w, x, y + 1)
				and _flag_ramp(flags, tp_w, x, y)
				and _flag_ramp(flags, tp_w, x + 1, y + 1)
			)
		8: # TR 低 → 邻 BR、TL（L 补心典型）
			return (
				_flag_ramp(flags, tp_w, x + 1, y + 1)
				and _flag_ramp(flags, tp_w, x + 1, y)
				and _flag_ramp(flags, tp_w, x, y + 1)
			)
	return false


## 斜坡 Present 用的挖洞计划（≈ HiveWE `update_ground_exists` 坡相关部分）。
## 只挖有模 CliffTrans footprint。
## **仅 L 凹槽 2×2 强制清 dig**；外角未齐四旗只 undig 非 footprint（保留 WE 坡身洞）。
static func plan_dig_mask(
	hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult
) -> PackedByteArray:
	var out := PackedByteArray()
	if hf == null or not hf.is_valid():
		return out
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	out.resize(maxi(map_w * map_h, 0))
	out.fill(0)
	var body := _ramp_body_mask(hf, ramp_data)
	for i in range(mini(out.size(), body.size())):
		out[i] = body[i]
	var layers: Array = hf.layer_heights
	var flags: Array = hf.flags_packed
	for t in _all_l_bowl_tiles(flags, layers, tp_w, tp_h):
		if t.x < 0 or t.y < 0 or t.x >= map_w or t.y >= map_h:
			continue
		out[t.y * map_w + t.x] = 0
	return out


## 入口 undig。L 凹槽 / 未齐四旗外角碗 undig；外角与 CT footprint 重叠时保留 dig；经典两低照旧。
static func plan_entrance_tiles(
	hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult = null
) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if hf == null or not hf.is_valid():
		return tiles
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	var body := _ramp_body_mask(hf, ramp_data)
	var flags: Array = hf.flags_packed
	var layers: Array = hf.layer_heights
	var seen: Dictionary = {}
	for t in _all_l_bowl_tiles(flags, layers, tp_w, tp_h):
		if t.x < 0 or t.y < 0 or t.x >= map_w or t.y >= map_h:
			continue
		var key: int = t.y * map_w + t.x
		if seen.has(key):
			continue
		seen[key] = true
		tiles.append(t)
	for t2 in _all_forced_ground_tiles(flags, layers, tp_w, tp_h):
		if t2.x < 0 or t2.y < 0 or t2.x >= map_w or t2.y >= map_h:
			continue
		var key2: int = t2.y * map_w + t2.x
		if seen.has(key2):
			continue
		# 外角碗与 CT footprint 重叠时保留 dig（WE footprint 优先）
		if key2 < body.size() and body[key2] != 0:
			continue
		seen[key2] = true
		tiles.append(t2)
	for iy in range(map_h):
		for ix in range(map_w):
			var key3: int = iy * map_w + ix
			if seen.has(key3):
				continue
			## 统一经 is_entrance() 过滤后分支；避免与 _is_classic_entrance 重复检测
			if not is_entrance(flags, layers, tp_w, tp_h, ix, iy):
				continue
			if _is_l_recess_entrance(flags, layers, tp_w, ix, iy):
				continue  ## L 碗已在第一循环处理
			if _count_corners_at_min(layers, tp_w, ix, iy) != 2:
				continue
			if key3 < body.size() and body[key3] != 0:
				continue
			tiles.append(Vector2i(ix, iy))
	return tiles


## 该格用地面代替直崖（undig + hide 必须同时成立）。
static func _keeps_ground_over_cliff(
	flags: Array, layers: Array, tp_w: int, tp_h: int, ix: int, iy: int
) -> bool:
	if _is_l_recess_entrance(flags, layers, tp_w, ix, iy):
		return true
	if _is_l_recess_2x2_sibling(flags, layers, tp_w, tp_h, ix, iy):
		return true
	if _is_outer_corner_ramp_tile(flags, layers, tp_w, tp_h, ix, iy):
		return true
	if _is_outer_corner_2x2_sibling(flags, layers, tp_w, tp_h, ix, iy):
		return true
	if not _is_classic_entrance(flags, layers, tp_w, ix, iy):
		return false
	return _count_corners_at_min(layers, tp_w, ix, iy) == 2


## L 碗 + 外角未齐四旗的坡口（笔刷 L/外角常见；齐四旗的走经典入口+footprint 优先）。
static func _all_forced_ground_tiles(
	flags: Array, layers: Array, tp_w: int, tp_h: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	for t in _all_l_bowl_tiles(flags, layers, tp_w, tp_h):
		var key: int = t.y * 65536 + t.x
		if seen.has(key):
			continue
		seen[key] = true
		out.append(t)
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	for iy in range(map_h):
		for ix in range(map_w):
			if not _is_outer_corner_ramp_tile(flags, layers, tp_w, tp_h, ix, iy):
				continue
			# 四旗已齐 → 交给经典入口 / CT footprint，不强制挖掉 dig
			if _count_ramp_corners(flags, tp_w, ix, iy) >= 4:
				continue
			for t2 in _outer_corner_bowl_tiles(layers, tp_w, ix, iy):
				if t2.x < 0 or t2.y < 0 or t2.x >= map_w or t2.y >= map_h:
					continue
				var key2: int = t2.y * 65536 + t2.x
				if seen.has(key2):
					continue
				seen[key2] = true
				out.append(t2)
	return out


## 高台外角坡口：三低一高崖格 + 高台支撑 + 坡旗（本格或邻格）。
## 笔刷 L 常把旗落在邻边而非外角格本身，故允许邻格 nr≥2。
## 靠近真正 L 凹槽时禁用（防把凹槽扩成伪对角）。
static func _is_outer_corner_ramp_tile(
	flags: Array, layers: Array, tp_w: int, tp_h: int, ix: int, iy: int
) -> bool:
	if not Wc3CliffLogic.is_cliff_tile(layers, tp_w, ix, iy):
		return false
	if _count_corners_at_min(layers, tp_w, ix, iy) != 3:
		return false
	if _near_l_recess(flags, layers, tp_w, tp_h, ix, iy, 2):
		return false
	var hi: Vector2i = _unique_high_corner_delta(layers, tp_w, ix, iy)
	if hi.x < 0:
		return false
	var vx: int = ix + hi.x
	var vy: int = iy + hi.y
	var hi_layer: int = int(layers[vy * tp_w + vx])
	if not _vertex_has_plateau_support(layers, tp_w, tp_h, vx, vy, hi_layer):
		return false
	var nr: int = _count_ramp_corners(flags, tp_w, ix, iy)
	if nr >= 2:
		return true
	if nr >= 1 and _flag_ramp(flags, tp_w, vx, vy):
		return true
	# 旗在邻边（外角格自身 nr=0）：邻接崖格有 ≥2 坡旗即可
	return _adjacent_tile_has_ramp_arm(flags, tp_w, tp_h, ix, iy)


## 四邻崖格是否有 ≥2 角带 ramp（L 臂落在邻边）。
static func _adjacent_tile_has_ramp_arm(
	flags: Array, tp_w: int, tp_h: int, ix: int, iy: int
) -> bool:
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = ix + d.x
		var ny: int = iy + d.y
		if nx < 0 or ny < 0 or nx >= map_w or ny >= map_h:
			continue
		if _count_ramp_corners(flags, tp_w, nx, ny) >= 2:
			return true
	return false


## 是否落在某个未齐四旗外角碗的 2×2 内（非外角崖格本身）。
static func _is_outer_corner_2x2_sibling(
	flags: Array, layers: Array, tp_w: int, tp_h: int, ix: int, iy: int
) -> bool:
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var ox: int = ix + dx
			var oy: int = iy + dy
			if ox < 0 or oy < 0 or ox >= map_w or oy >= map_h:
				continue
			if not _is_outer_corner_ramp_tile(flags, layers, tp_w, tp_h, ox, oy):
				continue
			if _count_ramp_corners(flags, tp_w, ox, oy) >= 4:
				continue
			for t in _outer_corner_bowl_tiles(layers, tp_w, ox, oy):
				if t.x == ix and t.y == iy:
					return true
	return false


## 高台外角顶点周围 2×2 顶点中，至少 3 个同为高层（真外角；单点抬高泄漏则只有 1 个）。
static func _vertex_has_plateau_support(
	layers: Array, tp_w: int, tp_h: int, vx: int, vy: int, hi_layer: int
) -> bool:
	var n := 0
	for y in [vy - 1, vy]:
		for x in [vx - 1, vx]:
			if x < 0 or y < 0 or x >= tp_w or y >= tp_h:
				continue
			if int(layers[y * tp_w + x]) == hi_layer:
				n += 1
	return n >= 3


## 外角坡口的 2×2 地面：崖格 + 朝低侧三格（四格地形 Mesh）。
static func _outer_corner_bowl_tiles(
	layers: Array, tp_w: int, ix: int, iy: int
) -> Array[Vector2i]:
	var hi: Vector2i = _unique_high_corner_delta(layers, tp_w, ix, iy)
	if hi.x < 0:
		return [Vector2i(ix, iy)]
	var dx: int = 1 if hi.x == 0 else -1
	var dy: int = 1 if hi.y == 0 else -1
	return [
		Vector2i(ix, iy),
		Vector2i(ix + dx, iy),
		Vector2i(ix, iy + dy),
		Vector2i(ix + dx, iy + dy),
	]


## 三低一高时唯一高角相对 BL 的 (dx,dy)；否则 (-1,-1)。
static func _unique_high_corner_delta(
	layers: Array, tp_w: int, ix: int, iy: int
) -> Vector2i:
	if _count_corners_at_min(layers, tp_w, ix, iy) != 3:
		return Vector2i(-1, -1)
	var i00: int = iy * tp_w + ix
	var i10: int = i00 + 1
	var i01: int = i00 + tp_w
	var i11: int = i01 + 1
	if i11 >= layers.size():
		return Vector2i(-1, -1)
	var lo: int = mini(
		mini(int(layers[i00]), int(layers[i10])),
		mini(int(layers[i01]), int(layers[i11]))
	)
	if int(layers[i00]) != lo:
		return Vector2i(0, 0)
	if int(layers[i10]) != lo:
		return Vector2i(1, 0)
	if int(layers[i01]) != lo:
		return Vector2i(0, 1)
	if int(layers[i11]) != lo:
		return Vector2i(1, 1)
	return Vector2i(-1, -1)


static func _count_ramp_corners(flags: Array, tp_w: int, ix: int, iy: int) -> int:
	var n := 0
	if _flag_ramp(flags, tp_w, ix, iy):
		n += 1
	if _flag_ramp(flags, tp_w, ix + 1, iy):
		n += 1
	if _flag_ramp(flags, tp_w, ix, iy + 1):
		n += 1
	if _flag_ramp(flags, tp_w, ix + 1, iy + 1):
		n += 1
	return n


## 是否在某个 L 凹陷格的 Chebyshev 邻域内。
static func _near_l_recess(
	flags: Array, layers: Array, tp_w: int, tp_h: int, ix: int, iy: int, radius: int
) -> bool:
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx: int = ix + dx
			var ny: int = iy + dy
			if nx < 0 or ny < 0 or nx >= map_w or ny >= map_h:
				continue
			if _is_l_recess_entrance(flags, layers, tp_w, nx, ny):
				return true
	return false


## 所有 L 凹槽的 2×2 四格（凹陷格 + 三兄弟）。
static func _all_l_bowl_tiles(
	flags: Array, layers: Array, tp_w: int, tp_h: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	var seen: Dictionary = {}
	for iy in range(map_h):
		for ix in range(map_w):
			if not _is_l_recess_entrance(flags, layers, tp_w, ix, iy):
				continue
			for t in _l_bowl_tiles(layers, tp_w, ix, iy):
				var key: int = t.y * 65536 + t.x
				if seen.has(key):
					continue
				seen[key] = true
				out.append(t)
	return out


## 单个 L 凹陷的 2×2：凹陷格 + 朝低角方向的三格。
static func _l_bowl_tiles(layers: Array, tp_w: int, ix: int, iy: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i(ix, iy)]
	for t in _l_recess_sibling_tiles(layers, tp_w, ix, iy):
		out.append(t)
	return out


## 是否为某个 L 凹陷格低角所在 2×2 地块中的「非凹陷」格。
static func _is_l_recess_2x2_sibling(
	flags: Array, layers: Array, tp_w: int, tp_h: int, ix: int, iy: int
) -> bool:
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var rx: int = ix + dx
			var ry: int = iy + dy
			if rx < 0 or ry < 0 or rx >= map_w or ry >= map_h:
				continue
			if not _is_l_recess_entrance(flags, layers, tp_w, rx, ry):
				continue
			for t in _l_recess_sibling_tiles(layers, tp_w, rx, ry):
				if t.x == ix and t.y == iy:
					return true
	return false


## L 凹陷格低角所在 2×2 地块中、除凹陷格外的另外三格。
static func _l_recess_sibling_tiles(
	layers: Array, tp_w: int, ix: int, iy: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var low: Vector2i = _l_recess_low_corner_delta(layers, tp_w, ix, iy)
	if low.x < 0:
		return out
	for t in [
		Vector2i(ix + low.x, iy),
		Vector2i(ix, iy + low.y),
		Vector2i(ix + low.x, iy + low.y),
	]:
		if t.x == ix and t.y == iy:
			continue
		out.append(t)
	return out


## 低角相对凹陷格 BL 的 (dx,dy)；非 L 凹陷返回 (-1,-1)。
static func _l_recess_low_corner_delta(
	layers: Array, tp_w: int, ix: int, iy: int
) -> Vector2i:
	var i00: int = iy * tp_w + ix
	var i10: int = i00 + 1
	var i01: int = i00 + tp_w
	var i11: int = i01 + 1
	if i11 >= layers.size():
		return Vector2i(-1, -1)
	var lv00: int = int(layers[i00])
	var lv10: int = int(layers[i10])
	var lv01: int = int(layers[i01])
	var lv11: int = int(layers[i11])
	var lo: int = mini(mini(lv00, lv10), mini(lv01, lv11))
	var bits := 0
	if lv00 == lo:
		bits |= 1
	if lv10 == lo:
		bits |= 2
	if lv01 == lo:
		bits |= 4
	if lv11 == lo:
		bits |= 8
	match bits:
		1:
			return Vector2i(0, 0)
		2:
			return Vector2i(1, 0)
		4:
			return Vector2i(0, 1)
		8:
			return Vector2i(1, 1)
		_:
			return Vector2i(-1, -1)


## 地表格四角中层高 == min 的角数。
static func _count_corners_at_min(layers: Array, tp_w: int, ix: int, iy: int) -> int:
	var i00: int = iy * tp_w + ix
	var i10: int = i00 + 1
	var i01: int = i00 + tp_w
	var i11: int = i01 + 1
	if i11 >= layers.size():
		return 0
	var lv00: int = int(layers[i00])
	var lv10: int = int(layers[i10])
	var lv01: int = int(layers[i01])
	var lv11: int = int(layers[i11])
	var lo: int = mini(mini(lv00, lv10), mini(lv01, lv11))
	var n := 0
	if lv00 == lo:
		n += 1
	if lv10 == lo:
		n += 1
	if lv01 == lo:
		n += 1
	if lv11 == lo:
		n += 1
	return n


## 坡身格 mask（仅有模 CliffTrans footprint）。
## 不用裸 romp：有匹配无 GLB 时 dig 会留下灰缝（藏不了崖也盖不住洞）。
static func _ramp_body_mask(
	hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult
) -> PackedByteArray:
	var out := PackedByteArray()
	if hf == null or not hf.is_valid():
		return out
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	out.resize(maxi(map_w * map_h, 0))
	out.fill(0)
	if ramp_data == null:
		return out
	for p in ramp_data.placements:
		if p == null or not p.has_glb:
			continue
		for t in placement_footprint_tiles(p):
			if t.x < 0 or t.y < 0 or t.x >= map_w or t.y >= map_h:
				continue
			out[t.y * map_w + t.x] = 1
	return out


## 入口低角抬高半层（对齐 WE update_ground_heights）：tilepoint 上 1=该角 heights 再 +0.5*128。
## 抬高：L 凹陷、外角坡口、非碗内两低经典入口。碗内三兄弟只 undig 不 boost。
## 仅 Present bake 使用，不写回 Heightfield。
static func plan_entrance_height_boost(
	hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult = null
) -> PackedByteArray:
	var out := PackedByteArray()
	if hf == null or not hf.is_valid():
		return out
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var layers: Array = hf.layer_heights
	var flags: Array = hf.flags_packed
	out.resize(maxi(tp_w * hf.height, 0))
	out.fill(0)
	var ents: Array[Vector2i] = plan_entrance_tiles(hf, ramp_data)
	for t in ents:
		var l_rec: bool = _is_l_recess_entrance(flags, layers, tp_w, t.x, t.y)
		var outer: bool = _is_outer_corner_ramp_tile(flags, layers, tp_w, tp_h, t.x, t.y)
		var clas: bool = (
			_is_classic_entrance(flags, layers, tp_w, t.x, t.y)
			and _count_corners_at_min(layers, tp_w, t.x, t.y) == 2
			and not _is_l_recess_2x2_sibling(flags, layers, tp_w, tp_h, t.x, t.y)
		)
		if not l_rec and not outer and not clas:
			continue
		var i00: int = t.y * tp_w + t.x
		var i10: int = i00 + 1
		var i01: int = i00 + tp_w
		var i11: int = i01 + 1
		if i11 >= layers.size() or i11 >= out.size():
			continue
		var bl: int = int(layers[i00])
		var br: int = int(layers[i10])
		var tl: int = int(layers[i01])
		var top_r: int = int(layers[i11])
		var lo: int = mini(mini(bl, br), mini(tl, top_r))
		if bl == lo:
			out[i00] = 1
		if br == lo:
			out[i10] = 1
		if tl == lo:
			out[i01] = 1
		if top_r == lo:
			out[i11] = 1
	return out


## 对角斜坡的地面挖洞计划（独立于 placement 匹配）。
## 原理：对角 ramp 的 2×2 tile 满足「四角有 ramp 旗且 BL==TR（对角等高）但 TL!=BR（另一对角不等）」，
## 这正是 HiveWE is_corner_ramp_entrance 中 diagonal 分支的判断条件。
## 与 L-bowl（low_bits 恰一位）的条件互斥，不会重叠。
static func plan_diagonal_dig_mask(hf: Wc3Heightfield) -> PackedByteArray:
	var out := PackedByteArray()
	if hf == null or not hf.is_valid():
		return out
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	out.resize(maxi(map_w * map_h, 0))
	out.fill(0)
	var flags: Array = hf.flags_packed
	var layers: Array = hf.layer_heights
	for ty in range(map_h):
		for tx in range(map_w):
			var i_bl := ty * tp_w + tx
			var i_br := i_bl + 1
			var i_tl := i_bl + tp_w
			var i_tr := i_tl + 1
			if i_tr >= layers.size():
				continue
			## 四角都有 ramp 旗？
			if not (_flag_ramp(flags, tp_w, tx, ty)
				and _flag_ramp(flags, tp_w, tx + 1, ty)
				and _flag_ramp(flags, tp_w, tx, ty + 1)
				and _flag_ramp(flags, tp_w, tx + 1, ty + 1)):
				continue
			var bl := int(layers[i_bl])
			var br := int(layers[i_br])
			var tl := int(layers[i_tl])
			var _tr := int(layers[i_tr])
			## BL == TR（对角等高）但 TL != BR（另一对角不等）→ 对角 ramp
			if bl == _tr and tl != br:
				out[ty * map_w + tx] = 1
	return out


## CliffTrans 覆盖的地表格（竖窗占 (i,j)+(i,j+1)；横窗占 (i,j)+(i+1,j)）。
static func placement_footprint_tiles(p: Wc3RampPlacement) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if p == null:
		return out
	out.append(Vector2i(p.ix, p.iy))
	if p.axis == Wc3RampLogic.AXIS_V:
		out.append(Vector2i(p.ix, p.iy + 1))
	elif p.axis == Wc3RampLogic.AXIS_H:
		out.append(Vector2i(p.ix + 1, p.iy))
	return out


## 直崖叠段是否跳过。hide 与 undig 必须同源（`_keeps_ground_over_cliff`），禁止藏崖留灰缝。
static func should_hide_cliff_piece(
	ix: int,
	iy: int,
	piece_base: int,
	hf: Wc3Heightfield,
	ramp_data: Wc3RampCollectResult
) -> bool:
	if hf == null or not hf.is_valid() or ramp_data == null:
		return false
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	if ix < 0 or iy < 0 or ix >= tp_w - 1 or iy >= tp_h - 1:
		return false
	if _keeps_ground_over_cliff(hf.flags_packed, hf.layer_heights, tp_w, tp_h, ix, iy):
		return true
	for p in ramp_data.placements:
		if p == null or not p.has_glb:
			continue
		if not _footprint_contains(p, ix, iy):
			continue
		if piece_base < p.base_layer + 2 and piece_base + 2 > p.base_layer:
			return true
	return false


## 挂直崖 MultiMesh 前过滤：去掉应被斜坡跳过的单块 placement（对齐 WE continue）。
## 返回新数组，不改入参；无坡数据时原样复制。
static func filter_cliff_placements(
	placements: Array[Wc3CliffPlacement],
	hf: Wc3Heightfield,
	ramp_data: Wc3RampCollectResult
) -> Array[Wc3CliffPlacement]:
	var out: Array[Wc3CliffPlacement] = []
	if placements.is_empty():
		return out
	if hf == null or not hf.is_valid() or ramp_data == null:
		for p in placements:
			if p != null:
				out.append(p)
		return out
	for p in placements:
		if p == null:
			continue
		if should_hide_cliff_piece(p.ix, p.iy, p.base_layer, hf, ramp_data):
			continue
		out.append(p)
	return out


static func _footprint_contains(p: Wc3RampPlacement, ix: int, iy: int) -> bool:
	for t in placement_footprint_tiles(p):
		if t.x == ix and t.y == iy:
			return true
	return false


static func _try_vertical(
	i: int,
	j: int,
	layers: Array,
	ramp: PackedByteArray,
	cliff_tex: Array,
	cliff_sets: Array,
	cat: Wc3CliffCatalog,
	tp_w: int
) -> Dictionary:
	var bl := _ci(i, j, tp_w)
	var br := _ci(i + 1, j, tp_w)
	var tl := _ci(i, j + 1, tp_w)
	var top_r := _ci(i + 1, j + 1, tp_w)
	var ttl := _ci(i, j + 2, tp_w)
	var ttr := _ci(i + 1, j + 2, tp_w)
	var ae: int = mini(int(layers[bl]), int(layers[ttl]))
	var cf: int = mini(int(layers[br]), int(layers[ttr]))
	if int(layers[tl]) != ae or int(layers[top_r]) != cf:
		return {"ok": false}
	var base: int = mini(ae, cf)
	# 左列 / 右列 ramp 相反；允许 L 转角「中格被另一臂污染」的放宽（见 _ramp_cols_opposite）
	if not _ramp_cols_opposite(
		ramp[bl], ramp[tl], ramp[ttl], ramp[br], ramp[top_r], ramp[ttr]
	):
		return {"ok": false}
	# TAG 角序：ttl, ttr, br, bl（HiveWE 竖窗）；字符仍按实际旗位
	var tag := (
		_tag_char(ramp[ttl] != 0, int(layers[ttl]), base)
		+ _tag_char(ramp[ttr] != 0, int(layers[ttr]), base)
		+ _tag_char(ramp[br] != 0, int(layers[br]), base)
		+ _tag_char(ramp[bl] != 0, int(layers[bl]), base)
	)
	return _placement_from_tag(i, j, tag, base, bl, cliff_tex, cliff_sets, cat, Wc3RampLogic.AXIS_V)


static func _try_horizontal(
	i: int,
	j: int,
	layers: Array,
	ramp: PackedByteArray,
	cliff_tex: Array,
	cliff_sets: Array,
	cat: Wc3CliffCatalog,
	tp_w: int
) -> Dictionary:
	var bl := _ci(i, j, tp_w)
	var br := _ci(i + 1, j, tp_w)
	var tl := _ci(i, j + 1, tp_w)
	var top_r := _ci(i + 1, j + 1, tp_w)
	var brr := _ci(i + 2, j, tp_w)
	var trr := _ci(i + 2, j + 1, tp_w)
	var ae: int = mini(int(layers[bl]), int(layers[brr]))
	var bf: int = mini(int(layers[tl]), int(layers[trr]))
	if int(layers[br]) != ae or int(layers[top_r]) != bf:
		return {"ok": false}
	var base: int = mini(ae, bf)
	# 下行 / 上行 ramp 相反；同样允许 L 转角中格污染放宽
	if not _ramp_cols_opposite(
		ramp[bl], ramp[br], ramp[brr], ramp[tl], ramp[top_r], ramp[trr]
	):
		return {"ok": false}
	# TAG：tl, trr, brr, bl
	var tag := (
		_tag_char(ramp[tl] != 0, int(layers[tl]), base)
		+ _tag_char(ramp[trr] != 0, int(layers[trr]), base)
		+ _tag_char(ramp[brr] != 0, int(layers[brr]), base)
		+ _tag_char(ramp[bl] != 0, int(layers[bl]), base)
	)
	return _placement_from_tag(i, j, tag, base, bl, cliff_tex, cliff_sets, cat, Wc3RampLogic.AXIS_H)


## 两列 ramp 是否构成合法坡列组合：
##   1. 严格：列内全同，列间相反（经典 HiveWE）
##   2. A 污染：A 列完整，B 列仅中格被污染（两端仍与 A 相反）
##   3. B 污染：B 列完整，A 列仅中格被污染（两端仍与 B 相反）
## 注意：两端有旗中格无旗的「双向各污染」不属于合法组合（无法判断 base 层）。
static func _ramp_cols_opposite(a0: int, a1: int, a2: int, b0: int, b1: int, b2: int) -> bool:
	if a0 == a1 and a1 == a2 and b0 == b1 and b1 == b2 and a0 != b0:
		return true
	# A 为完整坡列，B 仅中格被污染
	if a0 == a1 and a1 == a2 and b0 == b2 and b0 != a0 and b1 == a0:
		return true
	# B 为完整坡列，A 仅中格被污染
	if b0 == b1 and b1 == b2 and a0 == a2 and a0 != b0 and a1 == b0:
		return true
	return false


static func _placement_from_tag(
	ix: int,
	iy: int,
	tag: String,
	base: int,
	bl_idx: int,
	cliff_tex: Array,
	cliff_sets: Array,
	cat: Wc3CliffCatalog,
	axis: String
) -> Dictionary:
	if tag.length() != 4:
		return {"ok": false}
	var tex_idx: int = int(cliff_tex[bl_idx]) if bl_idx < cliff_tex.size() else 0
	if tex_idx == 15:
		tex_idx = 1
	var cliff_id := ""
	if tex_idx >= 0 and tex_idx < cliff_sets.size():
		cliff_id = str(cliff_sets[tex_idx])
	var model_dir: String = cat.ramp_model_dir(cliff_id) if not cliff_id.is_empty() else "CliffTrans"
	var path: String = Wc3CliffCatalog.glb_path(model_dir, tag, 0)
	var has_glb: bool = RuntimeAssets.file_exists(path)
	if not has_glb:
		# 无模则不算命中（与 HiveWE load_cliff 失败则不写 romp 一致）
		return {"ok": false}
	var p := Wc3RampPlacement.make(
		ix, iy, tag, base, tex_idx, model_dir, axis, 0, true
	)
	return {"ok": true, "placement": p}


## HiveWE：ramp → 'L'+(layer-base)*(-4)；否则 'A'+(layer-base)
static func _tag_char(is_ramp: bool, layer: int, base: int) -> String:
	var diff: int = layer - base
	if is_ramp:
		return char(76 + diff * -4) # 'L'
	return char(65 + diff) # 'A'


static func _ci(x: int, y: int, tp_w: int) -> int:
	return y * tp_w + x


static func _flag_ramp(flags: Array, tp_w: int, x: int, y: int) -> bool:
	var i: int = y * tp_w + x
	if i < 0 or i >= flags.size():
		return false
	return (int(flags[i]) & Wc3Coords.FLAG_RAMP) != 0
