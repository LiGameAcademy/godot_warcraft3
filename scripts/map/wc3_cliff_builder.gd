class_name Wc3CliffBuilder
extends RefCounted
## 扫描 heightfield，生成直崖 (Cliffs) 实例。
## 斜坡 CliffTrans 已在 feature/ramp-rebuild 移除；待逐步重做。


static func collect_instances(
	hf: Dictionary,
	cliff_catalog: Wc3CliffCatalog,
	meta: Dictionary = {},
	ramp_data: Dictionary = {}
) -> Dictionary:
	if meta.is_empty():
		meta = Wc3Heightfield.build_meta_from_dict(hf)
	var tp_w: int = meta["width"]
	var tp_h: int = meta["height"]
	var layers: Array = meta["layer_heights"]
	var cliff_tex: Array = meta["cliff_textures"]
	var cliff_var: Array = meta["cliff_variations"]
	var cliff_tilesets: Array = meta["cliff_tilesets"]
	var center: Vector2 = meta["center"]
	var tile_size: float = meta["tile_size"]

	if layers.is_empty() or cliff_tilesets.is_empty():
		return {}

	if ramp_data.is_empty():
		ramp_data = Wc3CliffLogic.collect_ramp_placements(hf, meta, cliff_catalog)
	var romp: PackedByteArray = ramp_data["romp"]

	var buckets: Dictionary = {}
	var placed_cliffs := 0
	var missing := 0
	var missing_logged: Dictionary = {}

	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			var i00 := iy * tp_w + ix
			if not Wc3CliffLogic.is_cliff_tile(layers, tp_w, ix, iy):
				continue

			var slices: Array = Wc3CliffLogic.cliff_slices_at(layers, tp_w, ix, iy)
			if slices.is_empty():
				continue
			var tex_idx := _cliff_tex_index(cliff_tex, cliff_tilesets, tp_w, tp_h, ix, iy)
			var cliff_id := str(cliff_tilesets[tex_idx]) if tex_idx < cliff_tilesets.size() else ""
			var model_dir := "Cliffs"
			if cliff_catalog != null:
				model_dir = cliff_catalog.cliff_model_dir(cliff_id)
			var variation := int(cliff_var[i00]) if i00 < cliff_var.size() else 0
			for slice in slices:
				var tag: String = str(slice.get("tag", ""))
				if tag.is_empty() or tag == "AAAA":
					continue
				var base_layer: int = int(slice.get("base_layer", 2))
				var var_clamped := cliff_catalog.pick_cliff_variation(
					model_dir, tag, variation, ix, iy
				)
				var glb := cliff_catalog.resolve_glb(model_dir, tag, var_clamped)
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
		"placed_ramps": 0,
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
