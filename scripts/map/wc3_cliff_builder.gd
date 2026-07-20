class_name Wc3CliffBuilder
extends RefCounted
## 扫描 heightfield，生成悬崖 (Cliffs) 与斜坡过渡 (CliffTrans) 模型实例。


static func collect_instances(hf: Dictionary, tiles: Wc3TerrainTiles) -> Dictionary:
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(hf)
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

	var ramp_data := Wc3CliffTiles.collect_ramp_placements(hf)
	var romp: PackedByteArray = ramp_data["romp"]
	var ramp_placements: Array = ramp_data["placements"]

	var buckets: Dictionary = {}
	var placed_cliffs := 0
	var placed_ramps := 0
	var missing := 0
	var missing_logged: Dictionary = {}

	# 斜坡过渡模型（HiveWE 选型；实例带 90° 补偿以匹配 CliffTrans 枢轴）
	for p in ramp_placements:
		var ix: int = int(p["ix"])
		var iy: int = int(p["iy"])
		var tag: String = str(p["tag"])
		var base_layer: int = int(p["base_layer"])
		var tex_idx: int = int(p["tex_idx"])
		var ramp_dir: String = str(p["ramp_dir"])
		var glb := Wc3CliffTiles.resolve_glb(ramp_dir, tag, 0)
		if glb.is_empty():
			missing += 1
			continue
		var xf := _ramp_instance_transform(ix, iy, base_layer, center, tile_size)
		_bucket_add(buckets, glb, tex_idx, xf)
		placed_ramps += 1

	# 直崖模型（跳过已由斜坡占用 / 斜坡入口格）
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			var i00 := iy * tp_w + ix
			if i00 < romp.size() and romp[i00] != 0:
				continue
			if not Wc3CliffTiles.is_cliff_tile(layers, tp_w, ix, iy):
				continue
			if Wc3CliffTiles.is_ramp_entrance(layers, flags, tp_w, ix, iy):
				continue

			var info := Wc3CliffTiles.cliff_tag_at(layers, tp_w, ix, iy)
			var tag: String = str(info.get("tag", ""))
			if tag.is_empty() or tag == "AAAA":
				continue
			var base_layer: int = int(info.get("base_layer", 2))
			var tex_idx := _cliff_tex_index(cliff_tex, cliff_tilesets, i00)
			var cliff_id := str(cliff_tilesets[tex_idx])
			var variation := int(cliff_var[i00]) if i00 < cliff_var.size() else 0
			var model_dir := tiles.cliff_model_dir(cliff_id)
			variation = Wc3CliffTiles.clamp_variation(model_dir, tag, variation)
			var glb := Wc3CliffTiles.resolve_glb(model_dir, tag, variation)
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


static func _cliff_tex_index(cliff_tex: Array, cliff_tilesets: Array, i00: int) -> int:
	var tex_idx := int(cliff_tex[i00]) if i00 < cliff_tex.size() else 0
	if tex_idx == 15:
		tex_idx = 1
	if tex_idx < 0 or tex_idx >= cliff_tilesets.size():
		tex_idx = clampi(tex_idx, 0, maxi(cliff_tilesets.size() - 1, 0))
	return tex_idx


static func _bucket_add(buckets: Dictionary, glb: String, tex_idx: int, xf: Transform3D) -> void:
	var key := "%s|%d" % [glb, tex_idx]
	if not buckets.has(key):
		buckets[key] = {
			"glb": glb,
			"cliff_tex_index": tex_idx,
			"transforms": [],
		}
	(buckets[key]["transforms"] as Array).append(xf)


## mdx-m3-viewer：锚点 (x+1)*128, y*128；Z = (base-2)*128（地面起伏由顶点着色器叠加）。
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


## HiveWE CliffTrans：网格在 WC3 XY 上旋转 (x,y,z)→(y,-x,z)，锚点为格点 (ix, iy)。
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
	# GLB 已是 (wc3_x, wc3_z, -wc3_y)；再施加 HiveWE 的 90° 使 CliffTrans TAG 朝向正确
	var rot := Basis(
		Vector3(0, 0, 1),
		Vector3(0, 1, 0),
		Vector3(-1, 0, 0)
	)
	var basis := rot.scaled(Vector3.ONE * Wc3Coords.WORLD_SCALE)
	return Transform3D(basis, origin)
