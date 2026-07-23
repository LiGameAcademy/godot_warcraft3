class_name Wc3CliffBuilder
extends RefCounted
## 扫描 heightfield，生成悬崖 (Cliffs) 与斜坡过渡 (CliffTrans) 实例。
##
## M3：单脊侧缝靠 CliffTrans；romp 格跳过直崖。
## 斜坡可走甲板由 RAMP_SURFACE_DECK_ENABLED 控制（当前关闭，先看模型收口）。


static func collect_instances(
	hf: Dictionary,
	tiles: Wc3TerrainTiles,
	meta: Dictionary = {},
	ramp_data: Dictionary = {}
) -> Dictionary:
	if meta.is_empty():
		meta = HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var tp_w: int = meta["width"]
	var tp_h: int = meta["height"]
	var layers: Array = meta["layer_heights"]
	var flags: Array = meta["flags"]
	var cliff_tex: Array = meta["cliff_textures"]
	var cliff_var: Array = meta["cliff_variations"]
	var cliff_tilesets: Array = meta["cliff_tilesets"]
	var center: Vector2 = meta["center"]
	var tile_size: float = meta["tile_size"]

	if layers.is_empty() or cliff_tilesets.is_empty():
		return {}

	if ramp_data.is_empty():
		ramp_data = Wc3CliffTiles.collect_ramp_placements(hf, meta, tiles)
	var romp: PackedByteArray = ramp_data["romp"]
	var ramp_placements: Array = ramp_data.get("placements", []) as Array

	var buckets: Dictionary = {}
	var placed_cliffs := 0
	var placed_ramps := 0
	var missing := 0
	var missing_logged: Dictionary = {}

	# CliffTrans：
	# - 单脊：主条 + 幻影（左右两侧各一块，缺一不可）
	# - 宽坡：仅外侧侧脊（幻影 / side_ridge）；跳过宽坡内部主条
	for p in ramp_placements:
		var is_wide: bool = bool(p.get("wide", false))
		var is_phantom: bool = bool(p.get("phantom", false))
		var is_side: bool = bool(p.get("side_ridge", false))
		if is_wide and not is_phantom and not is_side:
			continue
		if bool(p.get("wide_core", false)):
			continue
		var ix: int = int(p.get("ix", 0))
		var iy: int = int(p.get("iy", 0))
		var tag: String = str(p.get("tag", ""))
		var base_layer: int = int(p.get("base_layer", 2))
		var tex_idx: int = int(p.get("tex_idx", 0))
		var ramp_dir: String = str(p.get("ramp_dir", "CliffTrans"))
		if tag.is_empty():
			continue
		var glb := Wc3CliffTiles.resolve_glb(ramp_dir, tag, 0)
		if glb.is_empty():
			if not missing_logged.has("R:" + tag):
				missing_logged["R:" + tag] = true
				push_warning("斜坡模型缺失: %s/%s" % [ramp_dir, tag])
			missing += 1
			continue
		var xf := _ramp_instance_transform(ix, iy, base_layer, center, tile_size)
		_bucket_add(buckets, glb, tex_idx, xf)
		placed_ramps += 1

	print(
		"Cliffs: CliffTrans placed=%d missing=%d deck=%s"
		% [placed_ramps, missing, str(Wc3CliffTiles.RAMP_SURFACE_DECK_ENABLED)]
	)

	# 直崖（跳过 romp / 斜坡入口 / 斜坡脚底——脚底铺地面，不放崖模）
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			var i00 := iy * tp_w + ix
			if i00 < romp.size() and romp[i00] != 0:
				continue
			if Wc3CliffTiles.is_ramp_foot_cell(romp, tp_w, ix, iy):
				continue
			if not Wc3CliffTiles.is_cliff_tile(layers, tp_w, ix, iy):
				continue
			if Wc3CliffTiles.is_ramp_entrance(layers, flags, tp_w, ix, iy):
				continue

			var slices: Array = Wc3CliffTiles.cliff_slices_at(layers, tp_w, ix, iy)
			if slices.is_empty():
				continue
			var tex_idx := _cliff_tex_index(cliff_tex, cliff_tilesets, tp_w, tp_h, ix, iy)
			var cliff_id := str(cliff_tilesets[tex_idx]) if tex_idx < cliff_tilesets.size() else ""
			var model_dir := tiles.cliff_model_dir(cliff_id)
			var variation := int(cliff_var[i00]) if i00 < cliff_var.size() else 0
			for slice in slices:
				var tag: String = str(slice.get("tag", ""))
				if tag.is_empty() or tag == "AAAA":
					continue
				var base_layer: int = int(slice.get("base_layer", 2))
				var var_clamped := Wc3CliffTiles.pick_cliff_variation(
					model_dir, tag, variation, ix, iy
				)
				var glb := Wc3CliffTiles.resolve_glb(model_dir, tag, var_clamped)
				if glb.is_empty():
					if not missing_logged.has("C:" + tag):
						missing_logged["C:" + tag] = true
						push_warning("悬崖模型缺失: %s/%s" % [model_dir, tag])
					missing += 1
					continue
				var xf := _instance_transform(ix, iy, base_layer, center, tile_size)
				_bucket_add(buckets, glb, tex_idx, xf)
				placed_cliffs += 1

	var groups: Array = []
	for k in buckets.keys():
		groups.append(buckets[k])

	return {
		"groups": groups,
		"placed_cliffs": placed_cliffs,
		"placed_ramps": placed_ramps,
		"missing": missing,
		"cliff_tilesets": cliff_tilesets,
		"romp": romp,
	}


## 从格子四角选悬崖类型：优先非 0 索引（草地等），避免只读 i00 时落成默认泥土。
static func _cliff_tex_index(
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


static func _bucket_add(buckets: Dictionary, glb: String, tex_idx: int, xf: Transform3D) -> void:
	var key := "%s|%d" % [glb, tex_idx]
	if not buckets.has(key):
		buckets[key] = {
			"glb": glb,
			"cliff_tex_index": tex_idx,
			"transforms": [],
		}
	(buckets[key]["transforms"] as Array).append(xf)


## Cliffs：局部 X∈[-128,0]，锚 (ix+1, iy)；Z=(base-2)*128。
static func _instance_transform(
	ix: int,
	iy: int,
	base_layer: int,
	center: Vector2,
	tile_size: float
) -> Transform3D:
	var wc3_x := float(ix + 1) * tile_size + center.x
	var wc3_y := float(iy) * tile_size + center.y
	var wc3_z := float(base_layer - 2) * 128.0
	var origin := Wc3Coords.wc3_xy_to_godot(wc3_x, wc3_y, wc3_z)
	return Transform3D(Basis.from_scale(Vector3.ONE * Wc3Coords.WORLD_SCALE), origin)


## HiveWE CliffTrans：锚 (ix, iy)；GLB 空间再旋 90° 对齐 TAG 朝向。
static func _ramp_instance_transform(
	ix: int,
	iy: int,
	base_layer: int,
	center: Vector2,
	tile_size: float
) -> Transform3D:
	var wc3_x := float(ix) * tile_size + center.x
	var wc3_y := float(iy) * tile_size + center.y
	var wc3_z := float(base_layer - 2) * 128.0
	var origin := Wc3Coords.wc3_xy_to_godot(wc3_x, wc3_y, wc3_z)
	var rot := Basis(
		Vector3(0, 0, 1),
		Vector3(0, 1, 0),
		Vector3(-1, 0, 0)
	)
	var basis := rot.scaled(Vector3.ONE * Wc3Coords.WORLD_SCALE)
	return Transform3D(basis, origin)
