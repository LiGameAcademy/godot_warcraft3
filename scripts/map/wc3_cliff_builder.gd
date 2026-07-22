class_name Wc3CliffBuilder
extends RefCounted
## 扫描 heightfield，生成悬崖 (Cliffs) 实例。
##
## 斜坡策略（数据推演，不再放 CliffTrans GLB）：
##   - romp 占用格由地面层铺 A→B 平面甲板（贴图走地表 autotile）
##   - 直崖仍放 Cliffs 模型
## CliffTrans 模型轴向与 GLB 转换纠缠已多次失败；可走面用高度场两端插值更稳。


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
	var ramp_n: int = (ramp_data.get("placements", []) as Array).size()

	var buckets: Dictionary = {}
	var placed_cliffs := 0
	var placed_ramps := 0
	var missing := 0
	var missing_logged: Dictionary = {}

	# 不放置 CliffTrans：斜坡可走面改由地面 A→B 甲板承担
	print("Cliffs: CliffTrans skipped — ramp decks from heightfield (n=%d)" % ramp_n)

	# 直崖（跳过 romp / 斜坡入口）
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
