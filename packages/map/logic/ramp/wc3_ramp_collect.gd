class_name Wc3RampCollect
extends RefCounted

## HiveWE b70f9b8 terrain.ixx: one entrance predicate controls ground, boosts and cliffs.


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




static func is_entrance(flags: Array, layers: Array, tp_w: int, tp_h: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= tp_w - 1 or y >= tp_h - 1:
		return false
	return _is_classic_entrance(flags, layers, tp_w, x, y)


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




static func plan_dig_mask(
	hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult
) -> PackedByteArray:
	return _ramp_body_mask(hf, ramp_data)





static func plan_entrance_tiles(
	hf: Wc3Heightfield, _ramp_data: Wc3RampCollectResult = null
) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if hf == null or not hf.is_valid():
		return tiles
	for y in range(hf.height - 1):
		for x in range(hf.width - 1):
			if is_entrance(hf.flags_packed, hf.layer_heights, hf.width, hf.height, x, y):
				tiles.append(Vector2i(x, y))
	return tiles





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




static func plan_entrance_height_boost(
	hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult = null
) -> PackedByteArray:
	var out := PackedByteArray()
	if hf == null or not hf.is_valid():
		return out
	out.resize(hf.width * hf.height)
	for t in plan_entrance_tiles(hf, ramp_data):
		var indices := [t.y * hf.width + t.x, t.y * hf.width + t.x + 1,
			(t.y + 1) * hf.width + t.x, (t.y + 1) * hf.width + t.x + 1]
		var low: int = int(hf.layer_heights[indices[0]])
		for i in indices:
			low = mini(low, int(hf.layer_heights[i]))
		for i in indices:
			if int(hf.layer_heights[i]) == low:
				out[i] = 1
	return out





static func plan_diagonal_dig_mask(hf: Wc3Heightfield) -> PackedByteArray:
	# HiveWE keeps entrance ground, including diagonal entrances.
	var out := PackedByteArray()
	if hf != null and hf.is_valid():
		out.resize((hf.width - 1) * (hf.height - 1))
	return out





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




static func should_hide_cliff_piece(
	ix: int,
	iy: int,
	_piece_base: int,
	hf: Wc3Heightfield,
	ramp_data: Wc3RampCollectResult
) -> bool:
	if hf == null or not hf.is_valid() or ramp_data == null:
		return false
	if ix < 0 or iy < 0 or ix >= hf.width - 1 or iy >= hf.height - 1:
		return false
	var index := iy * hf.width + ix
	return is_entrance(hf.flags_packed, hf.layer_heights, hf.width, hf.height, ix, iy) or (index < ramp_data.romp.size() and ramp_data.romp[index] != 0)





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
	# 左列 / 右列 ramp 相反；列内必须一致（HiveWE 原始匹配条件）
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
	# 下行 / 上行 ramp 相反；列内必须一致
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




static func _ramp_cols_opposite(a0: int, a1: int, a2: int, b0: int, b1: int, b2: int) -> bool:
	return a0 == a1 and a1 == a2 and b0 == b1 and b1 == b2 and a0 != b0


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
