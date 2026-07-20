class_name Wc3ShorelineBuilder
extends RefCounted
## 官方自动岸浪：Water.slk → Shoreline / OC / IC（PE2）。
## 放置点必须在**水面一侧**（斜坡/悬崖底），发射方向从深水指向岸/浅水。


const FLAG_WATER := 1
const WAVES_DEPTH_WC3 := 25.0
## 相对岸边向水面内缩（格）。太小会贴在悬崖顶缘/斜坡高侧。
const INSET_WATER := 0.58
const INSET_CLIFF := 0.72
const INSET_CORNER := 0.48

const _DIRS: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(-1, 0),
]
const _CONTOUR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(0, 1),
]

enum Kind { STRAIGHT, OUTSIDE_CORNER, INSIDE_CORNER }


## 每条: { origin: Vector3, emit_dir: Vector3, kind }
static func collect_foam_placements(
	hf: Dictionary,
	params: Wc3WaterParams,
	height_bias_wc3: float = 0.0,
	enable_cliff_waves: bool = true,
	enable_rolling_waves: bool = true
) -> Dictionary:
	var empty := {
		"straight": [],
		"outside": [],
		"inside": [],
		"skipped_shallow": 0,
		"edge_candidates": 0,
	}
	if not enable_cliff_waves and not enable_rolling_waves:
		return empty

	var meta := HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var tp_w: int = meta["width"]
	var tp_h: int = meta["height"]
	var ground: Array = meta["heights"]
	var water_h: Array = meta["water_heights"]
	var flags: Array = meta["flags"]
	var center: Vector2 = meta["center"]
	var tile_size: float = meta["tile_size"]
	if tp_w < 2 or tp_h < 2 or flags.is_empty():
		return empty
	if water_h.is_empty():
		water_h = ground

	var offset := params.height_offset_wc3() + height_bias_wc3
	var straight: Array = []
	var outside: Array = []
	var inside: Array = []
	var skipped := 0
	var candidates := 0

	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if not Wc3WaterMesh.is_surface_water_tile(flags, tp_w, ix, iy):
				continue

			var land_dirs: Array[Vector2i] = []
			for d in _DIRS:
				var nix := ix + d.x
				var niy := iy + d.y
				var nb_water := (
					nix >= 0 and niy >= 0 and nix < tp_w - 1 and niy < tp_h - 1
					and Wc3WaterMesh.is_surface_water_tile(flags, tp_w, nix, niy)
				)
				if not nb_water:
					land_dirs.append(d)

			if land_dirs.is_empty():
				continue

			candidates += 1
			var depth := _cell_max_water_depth(water_h, ground, flags, tp_w, ix, iy, offset)
			if depth < WAVES_DEPTH_WC3:
				skipped += 1
				continue

			var is_cliff := false
			for d in land_dirs:
				if _edge_is_cliff(hf, ix, iy, d):
					is_cliff = true
					break
			if is_cliff and not enable_cliff_waves:
				continue
			if not is_cliff and not enable_rolling_waves:
				continue

			var water_z := _cell_avg_water_surface(water_h, tp_w, ix, iy) + offset
			var inset := INSET_CLIFF if is_cliff else INSET_WATER

			if land_dirs.size() == 1:
				var d: Vector2i = land_dirs[0]
				var rec := _edge_placement(
					ix, iy, d, water_z, center, tile_size, inset, ground, tp_w
				)
				if not rec.is_empty():
					straight.append(rec)
			else:
				var placed_corner := false
				for i in range(land_dirs.size()):
					for j in range(i + 1, land_dirs.size()):
						var a: Vector2i = land_dirs[i]
						var b: Vector2i = land_dirs[j]
						if a.x * b.x + a.y * b.y != 0:
							continue
						var kind := _corner_kind(flags, tp_w, tp_h, ix, iy, a, b)
						var rec2 := _corner_placement(
							ix, iy, a, b, water_z, center, tile_size, kind, ground, tp_w
						)
						if rec2.is_empty():
							continue
						if kind == Kind.OUTSIDE_CORNER:
							outside.append(rec2)
						else:
							inside.append(rec2)
						placed_corner = true
				if not placed_corner:
					for d2 in land_dirs:
						var rec3 := _edge_placement(
							ix, iy, d2, water_z, center, tile_size, inset, ground, tp_w
						)
						if not rec3.is_empty():
							straight.append(rec3)

	# WavesDepth 等深线：放在深水格内，朝向浅水喷
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if not Wc3WaterMesh.is_surface_water_tile(flags, tp_w, ix, iy):
				continue
			var d0 := _cell_avg_water_depth(water_h, ground, flags, tp_w, ix, iy, offset)
			for cd in _CONTOUR_DIRS:
				var nx: int = ix + cd.x
				var ny: int = iy + cd.y
				if nx < 0 or ny < 0 or nx >= tp_w - 1 or ny >= tp_h - 1:
					continue
				if not Wc3WaterMesh.is_surface_water_tile(flags, tp_w, nx, ny):
					continue
				var d1 := _cell_avg_water_depth(water_h, ground, flags, tp_w, nx, ny, offset)
				var a_deep := d0 >= WAVES_DEPTH_WC3
				var b_deep := d1 >= WAVES_DEPTH_WC3
				if a_deep == b_deep:
					continue
				# 深水格 + 朝浅方向
				var deep_ix := ix
				var deep_iy := iy
				var toward_shallow: Vector2i = cd
				if d1 > d0:
					deep_ix = nx
					deep_iy = ny
					toward_shallow = Vector2i(-cd.x, -cd.y)
				var water_z2 := _cell_avg_water_surface(water_h, tp_w, deep_ix, deep_iy) + offset
				var rec4 := _edge_placement(
					deep_ix,
					deep_iy,
					toward_shallow,
					water_z2,
					center,
					tile_size,
					0.35,
					ground,
					tp_w
				)
				if not rec4.is_empty():
					rec4["contour"] = true
					straight.append(rec4)

	return {
		"straight": straight,
		"outside": outside,
		"inside": inside,
		"skipped_shallow": skipped,
		"edge_candidates": candidates,
	}


## d = 朝向陆地/浅水（发射朝向）；点放在水面格内。
static func _edge_placement(
	ix: int,
	iy: int,
	d: Vector2i,
	water_z: float,
	center: Vector2,
	tile_size: float,
	inset: float,
	ground: Array,
	tp_w: int
) -> Dictionary:
	# 从格心向岸边走 (0.5 - inset)，保证落在水面格内、斜坡底侧
	var mx := float(ix) + 0.5 + float(d.x) * (0.5 - inset)
	var my := float(iy) + 0.5 + float(d.y) * (0.5 - inset)
	if not _is_over_water(mx, my, water_z, ground, tp_w):
		# 再往格心收一点
		mx = float(ix) + 0.5 + float(d.x) * 0.15
		my = float(iy) + 0.5 + float(d.y) * 0.15
	var origin := Wc3Coords.wc3_xy_to_godot(
		mx * tile_size + center.x,
		my * tile_size + center.y,
		water_z + 3.0
	)
	# 发射：从深水/水面 → 岸（陆地方向），略抬升
	var emit := _landward_godot(d)
	return {"origin": origin, "emit_dir": emit, "kind": Kind.STRAIGHT}


static func _corner_placement(
	ix: int,
	iy: int,
	a: Vector2i,
	b: Vector2i,
	water_z: float,
	center: Vector2,
	tile_size: float,
	kind: int,
	ground: Array,
	tp_w: int
) -> Dictionary:
	# 角在陆地方向，再收进水面
	var mx := float(ix) + 0.5 + float(a.x + b.x) * (0.5 - INSET_CORNER)
	var my := float(iy) + 0.5 + float(a.y + b.y) * (0.5 - INSET_CORNER)
	if not _is_over_water(mx, my, water_z, ground, tp_w):
		mx = float(ix) + 0.5 + float(a.x + b.x) * 0.12
		my = float(iy) + 0.5 + float(a.y + b.y) * 0.12
	var origin := Wc3Coords.wc3_xy_to_godot(
		mx * tile_size + center.x,
		my * tile_size + center.y,
		water_z + 3.0
	)
	var bisect := Vector2i(a.x + b.x, a.y + b.y)
	var emit := _landward_godot(bisect)
	return {"origin": origin, "emit_dir": emit, "kind": kind}


## WC3 水平方向 (dx,dy) → Godot 朝岸水平方向（泡沫四边形法线 / 漂移轴）
static func _landward_godot(d: Vector2i) -> Vector3:
	var flat := Vector3(float(d.x), 0.0, -float(d.y))
	if flat.length_squared() < 0.001:
		return Vector3(0, 0, -1)
	return flat.normalized()


## 采样点地面应低于水面，避免落在斜坡高侧/悬崖顶
static func _is_over_water(mx: float, my: float, water_z: float, ground: Array, tp_w: int) -> bool:
	var ix := clampi(int(floor(mx)), 0, tp_w - 1)
	var iy := clampi(int(floor(my)), 0, int(ground.size() / tp_w) - 1 if tp_w > 0 else 0)
	var i := iy * tp_w + ix
	if i < 0 or i >= ground.size():
		return false
	# 允许少量误差；地面明显高于水面 → 高侧
	return float(ground[i]) <= water_z + 8.0


static func _corner_kind(
	flags: Array,
	tp_w: int,
	tp_h: int,
	ix: int,
	iy: int,
	a: Vector2i,
	b: Vector2i
) -> int:
	var dx := ix + a.x + b.x
	var dy := iy + a.y + b.y
	if dx < 0 or dy < 0 or dx >= tp_w - 1 or dy >= tp_h - 1:
		return Kind.OUTSIDE_CORNER
	if Wc3WaterMesh.is_surface_water_tile(flags, tp_w, dx, dy):
		return Kind.INSIDE_CORNER
	return Kind.OUTSIDE_CORNER


static func _cell_max_water_depth(
	water_h: Array, ground: Array, flags: Array, tp_w: int, ix: int, iy: int, offset: float
) -> float:
	var best := -1.0e9
	for dy in range(2):
		for dx in range(2):
			var i := (iy + dy) * tp_w + (ix + dx)
			if i < 0 or i >= water_h.size() or i >= ground.size():
				continue
			if (int(flags[i]) & FLAG_WATER) == 0:
				continue
			best = maxf(best, float(water_h[i]) + offset - float(ground[i]))
	return best


static func _cell_avg_water_depth(
	water_h: Array, ground: Array, flags: Array, tp_w: int, ix: int, iy: int, offset: float
) -> float:
	var sum := 0.0
	var n := 0
	for dy in range(2):
		for dx in range(2):
			var i := (iy + dy) * tp_w + (ix + dx)
			if i < 0 or i >= water_h.size() or i >= ground.size():
				continue
			if (int(flags[i]) & FLAG_WATER) == 0:
				continue
			sum += float(water_h[i]) + offset - float(ground[i])
			n += 1
	return sum / float(maxi(n, 1)) if n > 0 else -1.0e9


static func _cell_avg_water_surface(water_h: Array, tp_w: int, ix: int, iy: int) -> float:
	var sum := 0.0
	var n := 0
	for dy in range(2):
		for dx in range(2):
			var i := (iy + dy) * tp_w + (ix + dx)
			if i >= 0 and i < water_h.size():
				sum += float(water_h[i])
				n += 1
	return sum / float(maxi(n, 1))


static func _edge_is_cliff(hf: Dictionary, ix: int, iy: int, d: Vector2i) -> bool:
	var layers: Array = hf.get("layerHeights", []) as Array
	var tp_w: int = int(hf.get("tilepointWidth", 0))
	var tp_h: int = int(hf.get("tilepointHeight", 0))
	if layers.is_empty() or tp_w < 2:
		return false
	var nix := clampi(ix + d.x, 0, tp_w - 2)
	var niy := clampi(iy + d.y, 0, tp_h - 2)
	var a := _avg_layer(layers, tp_w, ix, iy)
	var b := _avg_layer(layers, tp_w, nix, niy)
	return absf(a - b) >= 0.75


static func _avg_layer(layers: Array, tp_w: int, ix: int, iy: int) -> float:
	var i00 := iy * tp_w + ix
	var i11 := i00 + tp_w + 1
	if i11 >= layers.size():
		return 0.0
	return (
		float(layers[i00]) + float(layers[i00 + 1]) + float(layers[i00 + tp_w]) + float(layers[i11])
	) * 0.25
