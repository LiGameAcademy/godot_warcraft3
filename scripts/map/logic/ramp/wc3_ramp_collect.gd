class_name Wc3RampCollect
extends RefCounted

## HiveWE `Terrain::update_cliff_meshes` 斜坡匹配部分（只产出 placements + romp）。
## 权威：docs/RAMP_WE.md §5


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


## HiveWE is_corner_ramp_entrance
static func is_entrance(flags: Array, layers: Array, tp_w: int, tp_h: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= tp_w - 1 or y >= tp_h - 1:
		return false
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


## 斜坡 Present 用的挖洞计划（≈ HiveWE `update_ground_exists` 坡相关部分）。
## 返回与直崖 gap 同尺寸的 mask：1=应挖；入口强制 0。
## 禁止写入 cliff gap_mask；由 Ramp Present 调 `MapTerrainLayer.apply_dig_mask` 施加。
static func plan_dig_mask(
	hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult
) -> PackedByteArray:
	var out := PackedByteArray()
	if hf == null or not hf.is_valid():
		return out
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var layers: Array = hf.layer_heights
	var flags: Array = hf.flags_packed
	var romp: PackedByteArray = (
		ramp_data.romp if ramp_data != null else PackedByteArray()
	)
	out.resize(maxi((tp_w - 1) * (tp_h - 1), 0))
	out.fill(0)
	var i := 0
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if is_entrance(flags, layers, tp_w, tp_h, ix, iy):
				out[i] = 0
			else:
				var bl: int = iy * tp_w + ix
				var has_romp: bool = bl < romp.size() and romp[bl] != Wc3RampLogic.ROMP_NONE
				var is_cliff: bool = Wc3CliffLogic.is_cliff_tile(layers, tp_w, ix, iy)
				if is_cliff or has_romp:
					out[i] = 1
			i += 1
	return out


## 入口格：相对直崖 gap 需要「保留地面」的坐标（斜坡 Present 调 undig / 隐藏直崖）。
static func plan_entrance_tiles(hf: Wc3Heightfield) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if hf == null or not hf.is_valid():
		return tiles
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var layers: Array = hf.layer_heights
	var flags: Array = hf.flags_packed
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if is_entrance(flags, layers, tp_w, tp_h, ix, iy):
				tiles.append(Vector2i(ix, iy))
	return tiles


## 入口低角抬高半层（对齐 WE update_ground_heights）：tilepoint 上 1=该角 heights 再 +0.5*128。
## 仅 Present bake 使用，不写回 Heightfield。
static func plan_entrance_height_boost(hf: Wc3Heightfield) -> PackedByteArray:
	var out := PackedByteArray()
	if hf == null or not hf.is_valid():
		return out
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	var layers: Array = hf.layer_heights
	var flags: Array = hf.flags_packed
	out.resize(maxi(tp_w * tp_h, 0))
	out.fill(0)
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if not is_entrance(flags, layers, tp_w, tp_h, ix, iy):
				continue
			var i00: int = iy * tp_w + ix
			var i10: int = i00 + 1
			var i01: int = i00 + tp_w
			var i11: int = i01 + 1
			var bl: int = int(layers[i00])
			var br: int = int(layers[i10])
			var tl: int = int(layers[i01])
			var tr: int = int(layers[i11])
			var lo: int = mini(mini(bl, br), mini(tl, tr))
			# 幂等：多入口格共享角可重复标 1
			if bl == lo:
				out[i00] = 1
			if br == lo:
				out[i10] = 1
			if tl == lo:
				out[i01] = 1
			if tr == lo:
				out[i11] = 1
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


## 直崖叠段模型是否应被斜坡跳过（按「单块模型」判断，非整格一刀切）。
##
## 规则：
## 1) 入口格：该格全部直崖模型都跳过（要留地面通道）。
## 2) 被某 CliffTrans footprint 盖住，且叠段高度带与坡 base 相交 → 跳过该块。
##    高度带：崖块 [piece_base, piece_base+2)，坡 [ramp_base, ramp_base+2)。
## 3) 否则保留（高台上层叠段可留）。
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
	var layers: Array = hf.layer_heights
	var flags: Array = hf.flags_packed
	if is_entrance(flags, layers, tp_w, tp_h, ix, iy):
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
	# 左列三格 ramp 同，右列三格 ramp 同，且左右相反
	if not (
		ramp[bl] == ramp[tl]
		and ramp[bl] == ramp[ttl]
		and ramp[br] == ramp[top_r]
		and ramp[br] == ramp[ttr]
		and ramp[bl] != ramp[br]
	):
		return {"ok": false}
	# TAG 角序：ttl, ttr, br, bl（HiveWE 竖窗）
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
	if not (
		ramp[bl] == ramp[br]
		and ramp[bl] == ramp[brr]
		and ramp[tl] == ramp[top_r]
		and ramp[tl] == ramp[trr]
		and ramp[bl] != ramp[tl]
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
