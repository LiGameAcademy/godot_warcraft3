class_name Wc3ShorelineBuilder
extends RefCounted
## 收集自动岸浪放置点（水面侧、朝岸发射）。角与直边统一为同一列表。


const FLAG_WATER := 1
const WAVES_DEPTH := 25.0
const INSET := 0.62
const INSET_CLIFF := 0.88

const _DIRS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0),
]


## 返回 { placements, skipped_shallow, edge_candidates }
## meta 可选：传入则不再 read_heightfield_meta。
static func collect_foam_placements(
	hf: Dictionary,
	params: Wc3WaterParams,
	height_bias_wc3: float = 0.0,
	enable_cliff_waves: bool = true,
	enable_rolling_waves: bool = true,
	meta: Dictionary = {}
) -> Dictionary:
	var out := {"placements": [], "skipped_shallow": 0, "edge_candidates": 0}
	if not enable_cliff_waves and not enable_rolling_waves:
		return out

	if meta.is_empty():
		meta = HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var tp_w: int = meta["width"]
	var tp_h: int = meta["height"]
	var ground: Array = meta["heights"]
	var water_h: Array = meta["water_heights"]
	var flags: Array = meta["flags"]
	var center: Vector2 = meta["center"]
	var tile_size: float = meta["tile_size"]
	if tp_w < 2 or tp_h < 2 or flags.is_empty():
		return out
	if water_h.is_empty():
		water_h = ground

	var offset := params.height_offset_wc3() + height_bias_wc3
	var list: Array = []
	var skipped := 0
	var candidates := 0

	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if not Wc3WaterMesh.is_surface_water_tile(flags, tp_w, ix, iy):
				continue

			var land: Array[Vector2i] = []
			for d in _DIRS:
				var nx := ix + d.x
				var ny := iy + d.y
				var nb := (
					nx >= 0 and ny >= 0 and nx < tp_w - 1 and ny < tp_h - 1
					and Wc3WaterMesh.is_surface_water_tile(flags, tp_w, nx, ny)
				)
				if not nb:
					land.append(d)
			if land.is_empty():
				continue

			candidates += 1
			if _max_depth(water_h, ground, flags, tp_w, ix, iy, offset) < WAVES_DEPTH:
				skipped += 1
				continue

			var cliff := _any_cliff(hf, ix, iy, land)
			if cliff and not enable_cliff_waves:
				continue
			if not cliff and not enable_rolling_waves:
				continue

			var water_z := _avg_surface(water_h, tp_w, ix, iy) + offset
			var inset := INSET_CLIFF if cliff else INSET

			if land.size() == 1:
				var rec := _place(ix, iy, land[0], water_z, center, tile_size, inset, ground, tp_w, cliff)
				if not rec.is_empty():
					list.append(rec)
			else:
				# 正交邻接对 → 角平分；否则按各边各放一点
				var added := false
				for i in range(land.size()):
					for j in range(i + 1, land.size()):
						var a: Vector2i = land[i]
						var b: Vector2i = land[j]
						if a.x * b.x + a.y * b.y != 0:
							continue
						var bisect := Vector2i(a.x + b.x, a.y + b.y)
						var rec2 := _place(ix, iy, bisect, water_z, center, tile_size, inset, ground, tp_w, cliff)
						if not rec2.is_empty():
							list.append(rec2)
							added = true
				if not added:
					for d2 in land:
						var rec3 := _place(ix, iy, d2, water_z, center, tile_size, inset, ground, tp_w, cliff)
						if not rec3.is_empty():
							list.append(rec3)

	out["placements"] = list
	out["skipped_shallow"] = skipped
	out["edge_candidates"] = candidates
	return out


static func _place(
	ix: int, iy: int, d: Vector2i, water_z: float, center: Vector2, tile_size: float,
	inset: float, ground: Array, tp_w: int, cliff: bool
) -> Dictionary:
	# d 可为角平分（分量 ±1/±2）；归一化到格内偏移
	var dx := float(d.x)
	var dy := float(d.y)
	var len := sqrt(dx * dx + dy * dy)
	if len < 0.001:
		return {}
	dx /= len
	dy /= len
	var mx := float(ix) + 0.5 + dx * (0.5 - inset)
	var my := float(iy) + 0.5 + dy * (0.5 - inset)
	if not _over_water(mx, my, water_z, ground, tp_w):
		mx = float(ix) + 0.5 + dx * 0.1
		my = float(iy) + 0.5 + dy * 0.1
	return {
		"origin": Wc3Coords.wc3_xy_to_godot(mx * tile_size + center.x, my * tile_size + center.y, water_z + 3.0),
		"emit_dir": Vector3(dx, 0.0, -dy).normalized(),
		"cliff": cliff,
	}


static func _over_water(mx: float, my: float, water_z: float, ground: Array, tp_w: int) -> bool:
	var ix := clampi(int(floor(mx)), 0, tp_w - 1)
	var iy := clampi(int(floor(my)), 0, int(ground.size() / tp_w) - 1 if tp_w > 0 else 0)
	var i := iy * tp_w + ix
	return i >= 0 and i < ground.size() and float(ground[i]) <= water_z + 8.0


static func _max_depth(water_h: Array, ground: Array, flags: Array, tp_w: int, ix: int, iy: int, offset: float) -> float:
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


static func _avg_surface(water_h: Array, tp_w: int, ix: int, iy: int) -> float:
	var sum := 0.0
	var n := 0
	for dy in range(2):
		for dx in range(2):
			var i := (iy + dy) * tp_w + (ix + dx)
			if i >= 0 and i < water_h.size():
				sum += float(water_h[i])
				n += 1
	return sum / float(maxi(n, 1))


static func _any_cliff(hf: Dictionary, ix: int, iy: int, land: Array[Vector2i]) -> bool:
	for d in land:
		if _edge_cliff(hf, ix, iy, d):
			return true
	return false


static func _edge_cliff(hf: Dictionary, ix: int, iy: int, d: Vector2i) -> bool:
	var layers: Array = hf.get("layerHeights", []) as Array
	var tp_w: int = int(hf.get("tilepointWidth", 0))
	var tp_h: int = int(hf.get("tilepointHeight", 0))
	if layers.is_empty() or tp_w < 2:
		return false
	var a := _avg_layer(layers, tp_w, ix, iy)
	var b := _avg_layer(layers, tp_w, clampi(ix + d.x, 0, tp_w - 2), clampi(iy + d.y, 0, tp_h - 2))
	return absf(a - b) >= 0.75


static func _avg_layer(layers: Array, tp_w: int, ix: int, iy: int) -> float:
	var i00 := iy * tp_w + ix
	var i11 := i00 + tp_w + 1
	if i11 >= layers.size():
		return 0.0
	return (float(layers[i00]) + float(layers[i00 + 1]) + float(layers[i00 + tp_w]) + float(layers[i11])) * 0.25
