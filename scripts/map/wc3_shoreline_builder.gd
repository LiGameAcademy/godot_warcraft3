class_name Wc3ShorelineBuilder
extends RefCounted
## 官方自动岸浪放置点：直边 (S) / 外角 (OC) / 内角 (IC)
## + WavesDepth 等深线（深→浅），水道中间对向泡沫 ≈ 激流感。
## 点在水面侧，发射方向朝岸或朝浅水。


const FLAG_WATER := Wc3Coords.FLAG_WATER
## UI/MiscData.txt [Water] WavesDepth=25（与 heightfield 高度差同单位）
const WAVES_DEPTH_WC3 := 25.0

## 相对岸边向水面内缩（格）。悬崖略大，保证点在水面、不被崖 mesh 吞掉。
const INSET_WATER := 0.58
const INSET_CLIFF := 0.78
const INSET_CORNER := 0.50
const INSET_CORNER_CLIFF := 0.72
## 深浅交界：落在深水格内、略靠浅侧
const INSET_CONTOUR := 0.35

const KIND_S := "S"
const KIND_OC := "OC"
const KIND_IC := "IC"

const _DIRS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0),
]
## 等深线只扫右/上，避免双边重复
const _CONTOUR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(0, 1),
]


## 返回 { placements, skipped_shallow, edge_candidates, count_s, count_oc, count_ic, count_contour }
## 每条: { origin, emit_dir, cliff, kind, contour? }
static func collect_foam_placements(
	hf: Dictionary,
	params: Wc3WaterParams,
	height_bias_wc3: float = 0.0,
	enable_cliff_waves: bool = true,
	enable_rolling_waves: bool = true,
	meta: Dictionary = {}
) -> Dictionary:
	var out := {
		"placements": [],
		"skipped_shallow": 0,
		"edge_candidates": 0,
		"count_s": 0,
		"count_oc": 0,
		"count_ic": 0,
		"count_contour": 0,
	}
	if not enable_cliff_waves and not enable_rolling_waves:
		return out

	if meta.is_empty():
		meta = HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var tp_w: int = meta["width"]
	var tp_h: int = meta["height"]
	var ground: Array = meta["heights"]
	var water_h: Array = meta["water_heights"]
	var flags: Array = meta["flags"]
	var layers: Array = meta["layer_heights"]
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
	var n_s := 0
	var n_oc := 0
	var n_ic := 0
	var n_contour := 0

	# --- 岸线：陆地邻接 ---
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
			if _max_depth(water_h, ground, flags, tp_w, ix, iy, offset) < WAVES_DEPTH_WC3:
				skipped += 1
				continue

			var cliff := _any_cliff(hf, layers, tp_w, tp_h, ix, iy, land)
			if cliff and not enable_cliff_waves:
				continue
			if not cliff and not enable_rolling_waves:
				continue

			var water_z := _avg_surface(water_h, tp_w, ix, iy) + offset

			if land.size() == 1:
				var inset := INSET_CLIFF if cliff else INSET_WATER
				var rec := _place_edge(ix, iy, land[0], water_z, center, tile_size, inset, ground, tp_w, cliff)
				if not rec.is_empty():
					list.append(rec)
					n_s += 1
			else:
				var added := false
				for i in range(land.size()):
					for j in range(i + 1, land.size()):
						var a: Vector2i = land[i]
						var b: Vector2i = land[j]
						if a.x * b.x + a.y * b.y != 0:
							continue
						var kind := _corner_kind(flags, tp_w, tp_h, ix, iy, a, b)
						var inset_c := INSET_CORNER_CLIFF if cliff else INSET_CORNER
						var rec2 := _place_corner(
							ix, iy, a, b, water_z, center, tile_size, inset_c, ground, tp_w, cliff, kind
						)
						if rec2.is_empty():
							continue
						list.append(rec2)
						if kind == KIND_OC:
							n_oc += 1
						else:
							n_ic += 1
						added = true
				if not added:
					var inset2 := INSET_CLIFF if cliff else INSET_WATER
					for d2 in land:
						var rec3 := _place_edge(
							ix, iy, d2, water_z, center, tile_size, inset2, ground, tp_w, cliff
						)
						if not rec3.is_empty():
							list.append(rec3)
							n_s += 1

	# --- WavesDepth 等深线：深水格 → 朝浅水，形成水道对向「激流」 ---
	if enable_rolling_waves:
		for iy in range(tp_h - 1):
			for ix in range(tp_w - 1):
				if not Wc3WaterMesh.is_surface_water_tile(flags, tp_w, ix, iy):
					continue
				var d0 := _avg_depth(water_h, ground, flags, tp_w, ix, iy, offset)
				for cd in _CONTOUR_DIRS:
					var nx: int = ix + cd.x
					var ny: int = iy + cd.y
					if nx < 0 or ny < 0 or nx >= tp_w - 1 or ny >= tp_h - 1:
						continue
					if not Wc3WaterMesh.is_surface_water_tile(flags, tp_w, nx, ny):
						continue
					var d1 := _avg_depth(water_h, ground, flags, tp_w, nx, ny, offset)
					var a_deep := d0 >= WAVES_DEPTH_WC3
					var b_deep := d1 >= WAVES_DEPTH_WC3
					if a_deep == b_deep:
						continue
					var deep_ix := ix
					var deep_iy := iy
					var toward_shallow: Vector2i = cd
					if d1 > d0:
						deep_ix = nx
						deep_iy = ny
						toward_shallow = Vector2i(-cd.x, -cd.y)
					var water_z2 := _avg_surface(water_h, tp_w, deep_ix, deep_iy) + offset
					var rec4 := _place_edge(
						deep_ix, deep_iy, toward_shallow, water_z2, center, tile_size,
						INSET_CONTOUR, ground, tp_w, false
					)
					if rec4.is_empty():
						continue
					rec4["contour"] = true
					list.append(rec4)
					n_s += 1
					n_contour += 1

	out["placements"] = list
	out["skipped_shallow"] = skipped
	out["edge_candidates"] = candidates
	out["count_s"] = n_s
	out["count_oc"] = n_oc
	out["count_ic"] = n_ic
	out["count_contour"] = n_contour
	return out


static func _place_edge(
	ix: int, iy: int, d: Vector2i, water_z: float, center: Vector2, tile_size: float,
	inset: float, ground: Array, tp_w: int, cliff: bool
) -> Dictionary:
	var mx := float(ix) + 0.5 + float(d.x) * (0.5 - inset)
	var my := float(iy) + 0.5 + float(d.y) * (0.5 - inset)
	if not _over_water(mx, my, water_z, ground, tp_w):
		mx = float(ix) + 0.5 + float(d.x) * 0.15
		my = float(iy) + 0.5 + float(d.y) * 0.15
	return {
		"origin": Wc3Coords.wc3_xy_to_godot(mx * tile_size + center.x, my * tile_size + center.y, water_z + 6.0),
		"emit_dir": _landward(d),
		"cliff": cliff,
		"kind": KIND_S,
	}


static func _place_corner(
	ix: int, iy: int, a: Vector2i, b: Vector2i, water_z: float, center: Vector2, tile_size: float,
	inset: float, ground: Array, tp_w: int, cliff: bool, kind: String
) -> Dictionary:
	var mx := float(ix) + 0.5 + float(a.x + b.x) * (0.5 - inset)
	var my := float(iy) + 0.5 + float(a.y + b.y) * (0.5 - inset)
	if not _over_water(mx, my, water_z, ground, tp_w):
		mx = float(ix) + 0.5 + float(a.x + b.x) * 0.12
		my = float(iy) + 0.5 + float(a.y + b.y) * 0.12
	return {
		"origin": Wc3Coords.wc3_xy_to_godot(mx * tile_size + center.x, my * tile_size + center.y, water_z + 6.0),
		"emit_dir": _landward(Vector2i(a.x + b.x, a.y + b.y)),
		"cliff": cliff,
		"kind": kind,
	}


static func _corner_kind(
	flags: Array, tp_w: int, tp_h: int, ix: int, iy: int, a: Vector2i, b: Vector2i
) -> String:
	var dx := ix + a.x + b.x
	var dy := iy + a.y + b.y
	if dx < 0 or dy < 0 or dx >= tp_w - 1 or dy >= tp_h - 1:
		return KIND_OC
	if Wc3WaterMesh.is_surface_water_tile(flags, tp_w, dx, dy):
		return KIND_IC
	return KIND_OC


static func _landward(d: Vector2i) -> Vector3:
	var flat := Vector3(float(d.x), 0.0, -float(d.y))
	if flat.length_squared() < 1e-6:
		return Vector3(0, 0, -1)
	return flat.normalized()


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


static func _avg_depth(water_h: Array, ground: Array, flags: Array, tp_w: int, ix: int, iy: int, offset: float) -> float:
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


static func _any_cliff(
	hf: Dictionary, layers: Array, tp_w: int, tp_h: int, ix: int, iy: int, land: Array[Vector2i]
) -> bool:
	for d in land:
		if _edge_cliff(layers, tp_w, tp_h, ix, iy, d):
			return true
		# 邻格本身是悬崖格也算崖岸（层差阈值漏检时补上）
		var nx := clampi(ix + d.x, 0, tp_w - 2)
		var ny := clampi(iy + d.y, 0, tp_h - 2)
		if not layers.is_empty() and Wc3CliffTiles.is_cliff_tile(layers, tp_w, nx, ny):
			return true
	return false


static func _edge_cliff(layers: Array, tp_w: int, tp_h: int, ix: int, iy: int, d: Vector2i) -> bool:
	if layers.is_empty() or tp_w < 2:
		return false
	var a := _avg_layer(layers, tp_w, ix, iy)
	var b := _avg_layer(layers, tp_w, clampi(ix + d.x, 0, tp_w - 2), clampi(iy + d.y, 0, tp_h - 2))
	return absf(a - b) >= 0.55


static func _avg_layer(layers: Array, tp_w: int, ix: int, iy: int) -> float:
	var i00 := iy * tp_w + ix
	var i11 := i00 + tp_w + 1
	if i11 >= layers.size():
		return 0.0
	return (float(layers[i00]) + float(layers[i00 + 1]) + float(layers[i00 + tp_w]) + float(layers[i11])) * 0.25
