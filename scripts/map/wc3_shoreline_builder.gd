class_name Wc3ShorelineBuilder
extends RefCounted
## 官方自动岸浪放置点：直边 (S) / 外角 (OC) / 内角 (IC)
## + WavesDepth 等深线（深→浅），水道中间对向泡沫 ≈ 激流感。
##
## 偏移分流（同一套 Shoreline，不是两套特效）：
##   cliff  — 悬崖岸：统一中等 inset（略偏水面，躲开崖 mesh）
##   ramp   — 斜坡岸：可向岸拉近
##   shore  — 平缓岸：可向岸拉近
##   contour— 等深线：固定 inset，与崖岸无关（水道中间那层）


const FLAG_WATER := Wc3Coords.FLAG_WATER
const WAVES_DEPTH_WC3 := 25.0

## 内缩（格）：越大越远离岸边、越靠水面中央
const INSET_WATER := 0.42
const INSET_RAMP := 0.22
## 悬崖统一：略偏水面，躲开崖 mesh
const INSET_CLIFF := 0.55
const INSET_CORNER := 0.36
const INSET_CORNER_RAMP := 0.18
const INSET_CORNER_CLIFF := 0.50
const INSET_CONTOUR := 0.35
const INSET_MIN := 0.12
## 斜坡可更贴岸（低于普通 INSET_MIN）
const INSET_MIN_RAMP := 0.02
const INSET_MAX_CLIFF := 0.78
const INSET_MAX_OTHER := 0.92

const KIND_S := "S"
const KIND_OC := "OC"
const KIND_IC := "IC"

const _DIRS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0),
]
const _CONTOUR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(0, 1),
]


## shore_pull / ramp_pull：向岸拉近。cliff_out_extra：悬崖额外退入水面（全悬崖共用）。
static func collect_foam_placements(
	hf: Dictionary,
	params: Wc3WaterParams,
	height_bias_wc3: float = 0.0,
	enable_cliff_waves: bool = true,
	enable_rolling_waves: bool = true,
	meta: Dictionary = {},
	shore_pull_tiles: float = 0.0,
	ramp_pull_tiles: float = 0.0,
	cliff_out_extra: float = 0.0,
) -> Dictionary:
	var out := {
		"placements": [],
		"skipped_shallow": 0,
		"edge_candidates": 0,
		"count_s": 0,
		"count_oc": 0,
		"count_ic": 0,
		"count_contour": 0,
		"count_cliff_l1": 0,
		"count_cliff_l2": 0,
	}
	if not enable_cliff_waves and not enable_rolling_waves:
		return out

	if meta.is_empty():
		meta = Wc3Heightfield.build_meta_from_dict(hf)
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
	var n_l1 := 0
	var n_l2 := 0

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

			var cliff_lv := _max_cliff_levels(layers, tp_w, tp_h, ix, iy, land)
			var is_cliff := cliff_lv >= 1
			var near_ramp := (not is_cliff) and _any_ramp_neighbor(flags, tp_w, tp_h, ix, iy, land)
			if is_cliff and not enable_cliff_waves:
				continue
			if not is_cliff and not enable_rolling_waves:
				continue

			var water_z := _avg_surface(water_h, tp_w, ix, iy) + offset
			var inset := _pick_inset(is_cliff, near_ramp, false)
			var pull := 0.0
			if near_ramp:
				pull = ramp_pull_tiles
			elif not is_cliff:
				pull = shore_pull_tiles
			# 悬崖：只允许额外退入水面；斜坡/平岸：可向岸拉
			if is_cliff:
				inset = clampf(inset + cliff_out_extra, INSET_MIN, INSET_MAX_CLIFF)
			elif near_ramp:
				inset = clampf(inset - pull, INSET_MIN_RAMP, INSET_MAX_OTHER)
			else:
				inset = clampf(inset - pull, INSET_MIN, INSET_MAX_OTHER)

			if land.size() == 1:
				var rec := _place_edge(
					ix, iy, land[0], water_z, center, tile_size, inset, ground, tp_w,
					is_cliff, near_ramp, cliff_lv
				)
				if not rec.is_empty():
					list.append(rec)
					n_s += 1
					if is_cliff:
						if cliff_lv <= 1:
							n_l1 += 1
						else:
							n_l2 += 1
			else:
				var added := false
				for i in range(land.size()):
					for j in range(i + 1, land.size()):
						var a: Vector2i = land[i]
						var b: Vector2i = land[j]
						if a.x * b.x + a.y * b.y != 0:
							continue
						var kind := _corner_kind(flags, tp_w, tp_h, ix, iy, a, b)
						var inset_c := _pick_inset(is_cliff, near_ramp, true)
						if is_cliff:
							inset_c = clampf(inset_c + cliff_out_extra, INSET_MIN, INSET_MAX_CLIFF)
						elif near_ramp:
							inset_c = clampf(inset_c - pull, INSET_MIN_RAMP, INSET_MAX_OTHER)
						else:
							inset_c = clampf(inset_c - pull, INSET_MIN, INSET_MAX_OTHER)
						var rec2 := _place_corner(
							ix, iy, a, b, water_z, center, tile_size, inset_c, ground, tp_w,
							is_cliff, near_ramp, cliff_lv, kind
						)
						if rec2.is_empty():
							continue
						list.append(rec2)
						if kind == KIND_OC:
							n_oc += 1
						else:
							n_ic += 1
						if is_cliff:
							if cliff_lv <= 1:
								n_l1 += 1
							else:
								n_l2 += 1
						added = true
				if not added:
					for d2 in land:
						var rec3 := _place_edge(
							ix, iy, d2, water_z, center, tile_size, inset, ground, tp_w,
							is_cliff, near_ramp, cliff_lv
						)
						if not rec3.is_empty():
							list.append(rec3)
							n_s += 1
							if is_cliff:
								if cliff_lv <= 1:
									n_l1 += 1
								else:
									n_l2 += 1

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
					if (d0 >= WAVES_DEPTH_WC3) == (d1 >= WAVES_DEPTH_WC3):
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
						INSET_CONTOUR, ground, tp_w, false, false, 0
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
	out["count_cliff_l1"] = n_l1
	out["count_cliff_l2"] = n_l2
	return out


static func _pick_inset(is_cliff: bool, near_ramp: bool, corner: bool) -> float:
	if is_cliff:
		return INSET_CORNER_CLIFF if corner else INSET_CLIFF
	if near_ramp:
		return INSET_CORNER_RAMP if corner else INSET_RAMP
	return INSET_CORNER if corner else INSET_WATER


static func _place_edge(
	ix: int, iy: int, d: Vector2i, water_z: float, center: Vector2, tile_size: float,
	inset: float, ground: Array, tp_w: int, cliff: bool, ramp: bool, cliff_levels: int
) -> Dictionary:
	var mx := float(ix) + 0.5 + float(d.x) * (0.5 - inset)
	var my := float(iy) + 0.5 + float(d.y) * (0.5 - inset)
	if not _over_water(mx, my, water_z, ground, tp_w):
		# 失败时略偏水面，避免贴死岸边
		var fallback := -0.05 if cliff else 0.12
		mx = float(ix) + 0.5 + float(d.x) * fallback
		my = float(iy) + 0.5 + float(d.y) * fallback
	return {
		"origin": Wc3Coords.wc3_xy_to_godot(mx * tile_size + center.x, my * tile_size + center.y, water_z + 6.0),
		"emit_dir": _landward(d),
		"cliff": cliff,
		"ramp": ramp and not cliff,
		"cliff_levels": cliff_levels,
		"kind": KIND_S,
	}


static func _place_corner(
	ix: int, iy: int, a: Vector2i, b: Vector2i, water_z: float, center: Vector2, tile_size: float,
	inset: float, ground: Array, tp_w: int, cliff: bool, ramp: bool, cliff_levels: int, kind: String
) -> Dictionary:
	var mx := float(ix) + 0.5 + float(a.x + b.x) * (0.5 - inset)
	var my := float(iy) + 0.5 + float(a.y + b.y) * (0.5 - inset)
	if not _over_water(mx, my, water_z, ground, tp_w):
		var fallback := -0.04 if cliff else 0.10
		mx = float(ix) + 0.5 + float(a.x + b.x) * fallback
		my = float(iy) + 0.5 + float(a.y + b.y) * fallback
	return {
		"origin": Wc3Coords.wc3_xy_to_godot(mx * tile_size + center.x, my * tile_size + center.y, water_z + 6.0),
		"emit_dir": _landward(Vector2i(a.x + b.x, a.y + b.y)),
		"cliff": cliff,
		"ramp": ramp and not cliff,
		"cliff_levels": cliff_levels,
		"kind": kind,
	}


static func _corner_kind(
	flags: Array, tp_w: int, tp_h: int, ix: int, iy: int, a: Vector2i, b: Vector2i
) -> String:
	var diag := Vector2i(ix + a.x + b.x, iy + a.y + b.y)
	if (
		diag.x >= 0 and diag.y >= 0 and diag.x < tp_w - 1 and diag.y < tp_h - 1
		and Wc3WaterMesh.is_surface_water_tile(flags, tp_w, diag.x, diag.y)
	):
		return KIND_IC
	return KIND_OC


static func _landward(d: Vector2i) -> Vector3:
	var flat := Vector3(float(d.x), 0.0, -float(d.y))
	if flat.length_squared() < 1e-6:
		return Vector3(0, 0, -1)
	return flat.normalized()


static func _over_water(mx: float, my: float, water_z: float, ground: Array, tp_w: int) -> bool:
	var ix := clampi(int(floor(mx)), 0, tp_w - 1)
	var iy := clampi(
		int(floor(my)),
		0,
		floori(float(ground.size()) / float(tp_w)) - 1 if tp_w > 0 else 0
	)
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
	return sum / float(maxi(n, 1))


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


## 水格相对邻接「岸」方向的最大层差（取整）。≥1 视为悬崖岸。
static func _max_cliff_levels(
	layers: Array, tp_w: int, tp_h: int, ix: int, iy: int, land: Array[Vector2i]
) -> int:
	if layers.is_empty():
		return 0
	var best := 0
	for d in land:
		var delta := _edge_layer_delta(layers, tp_w, tp_h, ix, iy, d)
		best = maxi(best, delta)
		var nx := clampi(ix + d.x, 0, tp_w - 2)
		var ny := clampi(iy + d.y, 0, tp_h - 2)
		if Wc3CliffLogic.is_cliff_tile(layers, tp_w, nx, ny):
			var info := Wc3CliffLogic.cliff_tag_at(layers, tp_w, nx, ny)
			var tag := str(info.get("tag", "AAAA"))
			var tag_lv := 0
			for ci in range(mini(4, tag.length())):
				tag_lv = maxi(tag_lv, clampi(tag.unicode_at(ci) - 65, 0, 8))
			best = maxi(best, maxi(1, tag_lv))
	return best


static func _edge_layer_delta(
	layers: Array, tp_w: int, tp_h: int, ix: int, iy: int, d: Vector2i
) -> int:
	var a := _avg_layer(layers, tp_w, ix, iy)
	var b := _avg_layer(
		layers, tp_w, clampi(ix + d.x, 0, tp_w - 2), clampi(iy + d.y, 0, tp_h - 2)
	)
	var delta := int(round(absf(a - b)))
	return delta if delta >= 1 else 0


static func _any_ramp_neighbor(
	_flags: Array, _tp_w: int, _tp_h: int, _ix: int, _iy: int, _land: Array[Vector2i]
) -> bool:
	# feature/ramp-rebuild：忽略 FLAG_RAMP
	return false


static func _avg_layer(layers: Array, tp_w: int, ix: int, iy: int) -> float:
	var i00 := iy * tp_w + ix
	var i11 := i00 + tp_w + 1
	if i11 >= layers.size():
		return 0.0
	return (float(layers[i00]) + float(layers[i00 + 1]) + float(layers[i00 + tp_w]) + float(layers[i11])) * 0.25
