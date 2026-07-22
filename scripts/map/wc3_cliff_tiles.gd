class_name Wc3CliffTiles
extends RefCounted
## 悬崖 / 斜坡判定与模型 TAG。
## 悬崖 TAG 对齐 mdx-m3-viewer（BL,TL,TR,BR → A/B/C）。
## 斜坡选型对齐 HiveWE（CliffTrans 竖/横两格条带 + A/H/L/B 编码）。


const FLAG_RAMP := Wc3Coords.FLAG_RAMP

const CLIFF_VAR_MAX := {
	"AAAB": 1, "AAAC": 1, "AABA": 1, "AABB": 2, "AABC": 0, "AACA": 1, "AACB": 0, "AACC": 1,
	"ABAA": 1, "ABAB": 1, "ABAC": 0, "ABBA": 2, "ABBB": 1, "ABBC": 0, "ABCA": 0, "ABCB": 0,
	"ABCC": 0, "ACAA": 1, "ACAB": 0, "ACAC": 1, "ACBA": 0, "ACBB": 0, "ACBC": 0, "ACCA": 1,
	"ACCB": 0, "ACCC": 1, "BAAA": 1, "BAAB": 1, "BAAC": 0, "BABA": 1, "BABB": 1, "BABC": 0,
	"BACA": 0, "BACB": 0, "BACC": 0, "BBAA": 1, "BBAB": 1, "BBAC": 0, "BBBA": 1, "BBCA": 0,
	"BCAA": 0, "BCAB": 0, "BCAC": 0, "BCBA": 0, "BCCA": 0, "CAAA": 1, "CAAB": 0, "CAAC": 1,
	"CABA": 0, "CABB": 0, "CABC": 0, "CACA": 1, "CACB": 0, "CACC": 1, "CBAA": 0, "CBAB": 0,
	"CBAC": 0, "CBBA": 0, "CBCA": 0, "CCAA": 1, "CCAB": 0, "CCAC": 1, "CCBA": 0, "CCCA": 1,
}

const CITY_CLIFF_VAR_MAX := {
	"AAAB": 2, "AAAC": 1, "AABA": 1, "AABB": 3, "AABC": 0, "AACA": 1, "AACB": 0, "AACC": 3,
	"ABAA": 1, "ABAB": 2, "ABAC": 0, "ABBA": 3, "ABBB": 0, "ABBC": 0, "ABCA": 0, "ABCB": 0,
	"ABCC": 0, "ACAA": 1, "ACAB": 0, "ACAC": 2, "ACBA": 0, "ACBB": 0, "ACBC": 0, "ACCA": 3,
	"ACCB": 0, "ACCC": 1, "BAAA": 1, "BAAB": 3, "BAAC": 0, "BABA": 2, "BABB": 0, "BABC": 0,
	"BACA": 0, "BACB": 0, "BACC": 0, "BBAA": 3, "BBAB": 1, "BBAC": 0, "BBBA": 1, "BBCA": 0,
	"BCAA": 0, "BCAB": 0, "BCAC": 0, "BCBA": 0, "BCCA": 0, "CAAA": 1, "CAAB": 0, "CAAC": 3,
	"CABA": 0, "CABB": 0, "CABC": 0, "CACA": 2, "CACB": 0, "CACC": 1, "CBAA": 0, "CBAB": 0,
	"CBAC": 0, "CBBA": 0, "CBCA": 0, "CCAA": 3, "CCAB": 0, "CCAC": 1, "CCBA": 0, "CCCA": 1,
}


static func is_cliff_tile(layer_heights: Array, width: int, ix: int, iy: int) -> bool:
	if layer_heights.is_empty():
		return false
	var i00 := iy * width + ix
	var i10 := i00 + 1
	var i01 := i00 + width
	var i11 := i01 + 1
	if i11 >= layer_heights.size():
		return false
	var a := int(layer_heights[i00])
	return a != int(layer_heights[i10]) or a != int(layer_heights[i01]) or a != int(layer_heights[i11])


static func is_ramp_flag(flags: Array, i: int) -> bool:
	if i < 0 or i >= flags.size():
		return false
	return (int(flags[i]) & FLAG_RAMP) != 0


static func is_ramp_tile(flags: Array, width: int, ix: int, iy: int) -> bool:
	if flags.is_empty():
		return false
	var i00 := iy * width + ix
	var i10 := i00 + 1
	var i01 := i00 + width
	var i11 := i01 + 1
	if i11 >= flags.size():
		return false
	return (
		is_ramp_flag(flags, i00)
		or is_ramp_flag(flags, i10)
		or is_ramp_flag(flags, i01)
		or is_ramp_flag(flags, i11)
	)


## 四角均有 ramp、且层高呈对角落差 → 斜坡入口（保留地面，高度 +0.5 层）。
static func is_ramp_entrance(layer_heights: Array, flags: Array, width: int, ix: int, iy: int) -> bool:
	var i00 := iy * width + ix
	var i10 := i00 + 1
	var i01 := i00 + width
	var i11 := i01 + 1
	if i11 >= flags.size() or i11 >= layer_heights.size():
		return false
	if not (
		is_ramp_flag(flags, i00)
		and is_ramp_flag(flags, i10)
		and is_ramp_flag(flags, i01)
		and is_ramp_flag(flags, i11)
	):
		return false
	var bl := int(layer_heights[i00])
	var br := int(layer_heights[i10])
	var tl := int(layer_heights[i01])
	var tr := int(layer_heights[i11])
	return not (bl == tr and tl == br)


## 扫描整张地图，返回斜坡模型实例与 romp 占位（对齐 HiveWE update_cliff_meshes）。
## 每项: { ix, iy, tag, base_layer, tex_idx, ramp_dir }
## meta / tiles 可选：meta 空则 read；tiles 空则用 cliffID 硬编码回退。
static func collect_ramp_placements(
	hf: Dictionary,
	meta: Dictionary = {},
	tiles: Wc3TerrainTiles = null
) -> Dictionary:
	if meta.is_empty():
		meta = HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var tp_w: int = meta["width"]
	var tp_h: int = meta["height"]
	var layers: Array = meta["layer_heights"]
	var flags: Array = meta["flags"]
	var cliff_tex: Array = meta["cliff_textures"]
	var cliff_tilesets: Array = meta["cliff_tilesets"]

	var placements: Array = []
	var romp := PackedByteArray()
	romp.resize(tp_w * tp_h)
	romp.fill(0)

	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			var placed := false
			# 竖向斜坡（占 1x2 格）
			if iy < tp_h - 2:
				var tag_v := _vertical_ramp_tag(layers, flags, tp_w, ix, iy)
				if not tag_v.is_empty():
					var ramp_dir := _ramp_dir_at(cliff_tilesets, cliff_tex, tp_w, ix, iy, tiles)
					if resolve_glb(ramp_dir, tag_v, 0) != "":
						var base_v := _vertical_ramp_base(layers, tp_w, ix, iy)
						placements.append({
							"ix": ix, "iy": iy, "tag": tag_v, "base_layer": base_v,
							"tex_idx": _tex_idx_at(cliff_tex, cliff_tilesets, iy * tp_w + ix),
							"ramp_dir": ramp_dir,
							"axis": "v",
						})
						romp[iy * tp_w + ix] = 1
						romp[(iy + 1) * tp_w + ix] = 1
						placed = true
			# 横向斜坡（占 2x1 格）
			if not placed and ix < tp_w - 2:
				var tag_h := _horizontal_ramp_tag(layers, flags, tp_w, ix, iy)
				if not tag_h.is_empty():
					var ramp_dir_h := _ramp_dir_at(cliff_tilesets, cliff_tex, tp_w, ix, iy, tiles)
					if resolve_glb(ramp_dir_h, tag_h, 0) != "":
						var base_h := _horizontal_ramp_base(layers, tp_w, ix, iy)
						placements.append({
							"ix": ix, "iy": iy, "tag": tag_h, "base_layer": base_h,
							"tex_idx": _tex_idx_at(cliff_tex, cliff_tilesets, iy * tp_w + ix),
							"ramp_dir": ramp_dir_h,
							"axis": "h",
						})
						romp[iy * tp_w + ix] = 1
						romp[iy * tp_w + ix + 1] = 1

	return {"placements": placements, "romp": romp}


static func should_leave_gap(
	layer_heights: Array,
	flags: Array,
	tp_w: int,
	_tp_h: int,
	ix: int,
	iy: int,
	romp: PackedByteArray = PackedByteArray()
) -> bool:
	# 数据推演方案：romp 不挖洞（铺 A→B 地面甲板）；仅直崖挖洞。
	# 斜坡入口始终保留地面。
	if is_ramp_entrance(layer_heights, flags, tp_w, ix, iy):
		return false
	var i00 := iy * tp_w + ix
	if i00 < romp.size() and romp[i00] != 0:
		return false
	return is_cliff_tile(layer_heights, tp_w, ix, iy)


## 落在 2 格 ramp 条带内时，用两端 tilepoint 线性插值（侧视 A→B 斜线）。
## 中间层在 W3E 里常为低台；直接用 heights 会出「平台+陡坎」。
static func sample_ramp_plane_height(
	heights: Array, placements: Array, tp_w: int, tp_h: int, tx: float, ty: float
) -> float:
	for p in placements:
		var ix: int = int(p.get("ix", 0))
		var iy: int = int(p.get("iy", 0))
		var axis := str(p.get("axis", "v"))
		if axis == "v":
			if tx < float(ix) or tx > float(ix + 1) or ty < float(iy) or ty > float(iy + 2):
				continue
			var t := (ty - float(iy)) / 2.0
			var fx := tx - float(ix)
			var h_sw := _tp_height(heights, tp_w, tp_h, ix, iy)
			var h_se := _tp_height(heights, tp_w, tp_h, ix + 1, iy)
			var h_nw := _tp_height(heights, tp_w, tp_h, ix, iy + 2)
			var h_ne := _tp_height(heights, tp_w, tp_h, ix + 1, iy + 2)
			return lerpf(lerpf(h_sw, h_se, fx), lerpf(h_nw, h_ne, fx), t)
		else:
			if ty < float(iy) or ty > float(iy + 1) or tx < float(ix) or tx > float(ix + 2):
				continue
			var t2 := (tx - float(ix)) / 2.0
			var fy := ty - float(iy)
			var h_sw2 := _tp_height(heights, tp_w, tp_h, ix, iy)
			var h_nw2 := _tp_height(heights, tp_w, tp_h, ix, iy + 1)
			var h_se2 := _tp_height(heights, tp_w, tp_h, ix + 2, iy)
			var h_ne2 := _tp_height(heights, tp_w, tp_h, ix + 2, iy + 1)
			return lerpf(lerpf(h_sw2, h_nw2, fy), lerpf(h_se2, h_ne2, fy), t2)
	return NAN


static func _tp_height(heights: Array, tp_w: int, tp_h: int, ix: int, iy: int) -> float:
	ix = clampi(ix, 0, tp_w - 1)
	iy = clampi(iy, 0, tp_h - 1)
	var i := iy * tp_w + ix
	if i < 0 or i >= heights.size():
		return 0.0
	return float(heights[i])


static func cliff_tag_at(layer_heights: Array, width: int, ix: int, iy: int) -> Dictionary:
	if not is_cliff_tile(layer_heights, width, ix, iy):
		return {}
	var i00 := iy * width + ix
	var i10 := i00 + 1
	var i01 := i00 + width
	var i11 := i01 + 1
	var bl := int(layer_heights[i00])
	var br := int(layer_heights[i10])
	var tl := int(layer_heights[i01])
	var tr := int(layer_heights[i11])
	var base_layer := mini(mini(bl, br), mini(tl, tr))
	var tag := (
		String.chr(65 + bl - base_layer)
		+ String.chr(65 + tl - base_layer)
		+ String.chr(65 + tr - base_layer)
		+ String.chr(65 + br - base_layer)
	)
	return {"tag": tag, "base_layer": base_layer}


static func _vertical_ramp_base(layers: Array, tp_w: int, ix: int, iy: int) -> int:
	var ae := mini(_layer(layers, tp_w, ix, iy), _layer(layers, tp_w, ix, iy + 2))
	var cf := mini(_layer(layers, tp_w, ix + 1, iy), _layer(layers, tp_w, ix + 1, iy + 2))
	return mini(ae, cf)


static func _horizontal_ramp_base(layers: Array, tp_w: int, ix: int, iy: int) -> int:
	var ae := mini(_layer(layers, tp_w, ix, iy), _layer(layers, tp_w, ix + 2, iy))
	var bf := mini(_layer(layers, tp_w, ix, iy + 1), _layer(layers, tp_w, ix + 2, iy + 1))
	return mini(ae, bf)


static func _vertical_ramp_tag(layers: Array, flags: Array, tp_w: int, ix: int, iy: int) -> String:
	var bl := _layer(layers, tp_w, ix, iy)
	var br := _layer(layers, tp_w, ix + 1, iy)
	var tl := _layer(layers, tp_w, ix, iy + 1)
	var tr := _layer(layers, tp_w, ix + 1, iy + 1)
	var ttl := _layer(layers, tp_w, ix, iy + 2)
	var ttr := _layer(layers, tp_w, ix + 1, iy + 2)
	var ae := mini(bl, ttl)
	var cf := mini(br, ttr)
	if tl != ae or tr != cf:
		return ""
	var r_bl := is_ramp_flag(flags, iy * tp_w + ix)
	var r_br := is_ramp_flag(flags, iy * tp_w + ix + 1)
	var r_tl := is_ramp_flag(flags, (iy + 1) * tp_w + ix)
	var r_tr := is_ramp_flag(flags, (iy + 1) * tp_w + ix + 1)
	var r_ttl := is_ramp_flag(flags, (iy + 2) * tp_w + ix)
	var r_ttr := is_ramp_flag(flags, (iy + 2) * tp_w + ix + 1)
	if not (r_bl == r_tl and r_bl == r_ttl and r_br == r_tr and r_br == r_ttr and r_bl != r_br):
		return ""
	var base := mini(ae, cf)
	return (
		_ramp_char(r_ttl, ttl, base)
		+ _ramp_char(r_ttr, ttr, base)
		+ _ramp_char(r_br, br, base)
		+ _ramp_char(r_bl, bl, base)
	)


static func _horizontal_ramp_tag(layers: Array, flags: Array, tp_w: int, ix: int, iy: int) -> String:
	var bl := _layer(layers, tp_w, ix, iy)
	var br := _layer(layers, tp_w, ix + 1, iy)
	var brr := _layer(layers, tp_w, ix + 2, iy)
	var tl := _layer(layers, tp_w, ix, iy + 1)
	var tr := _layer(layers, tp_w, ix + 1, iy + 1)
	var trr := _layer(layers, tp_w, ix + 2, iy + 1)
	var ae := mini(bl, brr)
	var bf := mini(tl, trr)
	if br != ae or tr != bf:
		return ""
	var r_bl := is_ramp_flag(flags, iy * tp_w + ix)
	var r_br := is_ramp_flag(flags, iy * tp_w + ix + 1)
	var r_brr := is_ramp_flag(flags, iy * tp_w + ix + 2)
	var r_tl := is_ramp_flag(flags, (iy + 1) * tp_w + ix)
	var r_tr := is_ramp_flag(flags, (iy + 1) * tp_w + ix + 1)
	var r_trr := is_ramp_flag(flags, (iy + 1) * tp_w + ix + 2)
	if not (r_bl == r_br and r_bl == r_brr and r_tl == r_tr and r_tl == r_trr and r_bl != r_tl):
		return ""
	var base := mini(ae, bf)
	return (
		_ramp_char(r_tl, tl, base)
		+ _ramp_char(r_trr, trr, base)
		+ _ramp_char(r_brr, brr, base)
		+ _ramp_char(r_bl, bl, base)
	)


## HiveWE: (ramp ? 'L' : 'A') + (layer - base) * (ramp ? -4 : 1)
static func _ramp_char(is_ramp: bool, layer: int, base: int) -> String:
	var code := (76 if is_ramp else 65) + (layer - base) * (-4 if is_ramp else 1)
	return String.chr(code)


static func _layer(layers: Array, tp_w: int, ix: int, iy: int) -> int:
	return int(layers[iy * tp_w + ix])


static func _tex_idx_at(cliff_tex: Array, cliff_tilesets: Array, i00: int) -> int:
	var tex_idx := int(cliff_tex[i00]) if i00 < cliff_tex.size() else 0
	if tex_idx == 15:
		tex_idx = 1
	if tex_idx < 0 or tex_idx >= cliff_tilesets.size():
		tex_idx = clampi(tex_idx, 0, maxi(cliff_tilesets.size() - 1, 0))
	return tex_idx


static func _ramp_dir_at(
	cliff_tilesets: Array,
	cliff_tex: Array,
	tp_w: int,
	ix: int,
	iy: int,
	tiles: Wc3TerrainTiles = null
) -> String:
	var tex_idx := _tex_idx_at(cliff_tex, cliff_tilesets, iy * tp_w + ix)
	var cliff_id := str(cliff_tilesets[tex_idx]) if tex_idx < cliff_tilesets.size() else ""
	if tiles != null and not cliff_id.is_empty():
		return tiles.cliff_ramp_dir(cliff_id)
	# 无 SLK 时的最小回退（城市冰崖）
	if cliff_id == "CIrb":
		return "CityCliffTrans"
	return "CliffTrans"


static func clamp_variation(model_dir: String, tag: String, variation: int) -> int:
	if model_dir == "CliffTrans" or model_dir == "CityCliffTrans":
		return 0
	var table: Dictionary = CITY_CLIFF_VAR_MAX if model_dir == "CityCliffs" else CLIFF_VAR_MAX
	if not table.has(tag):
		return 0
	return mini(variation, int(table[tag]))


static func glb_path(model_dir: String, tag: String, variation: int) -> String:
	return RuntimeAssets.converted_path(
		"Doodads/Terrain/%s/%s%s%d.glb" % [model_dir, model_dir, tag, variation]
	)


static func resolve_glb(model_dir: String, tag: String, variation: int) -> String:
	if tag.is_empty():
		return ""
	variation = clamp_variation(model_dir, tag, variation)
	var path := glb_path(model_dir, tag, variation)
	if RuntimeAssets.file_exists(path):
		return path
	path = glb_path(model_dir, tag, 0)
	if RuntimeAssets.file_exists(path):
		return path
	if model_dir == "CityCliffTrans":
		return resolve_glb("CliffTrans", tag, variation)
	return ""


## 斜坡入口：底层角点最终高度 +64（0.5 层），让地面形成缓坡。
static func apply_ramp_entrance_heights(heights: Array, layers: Array, flags: Array, tp_w: int, tp_h: int) -> Array:
	if heights.is_empty() or layers.is_empty() or flags.is_empty():
		return heights
	var out := heights.duplicate()
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if not is_ramp_entrance(layers, flags, tp_w, ix, iy):
				continue
			var i00 := iy * tp_w + ix
			var i10 := i00 + 1
			var i01 := i00 + tp_w
			var i11 := i01 + 1
			var base := mini(
				mini(int(layers[i00]), int(layers[i10])),
				mini(int(layers[i01]), int(layers[i11]))
			)
			for i in [i00, i10, i01, i11]:
				if int(layers[i]) == base:
					out[i] = float(out[i]) + 64.0
	return out


## gap/cliff/ramp 统计。可传入已算好的 meta 与 ramp_data，避免重复全图扫描。
static func count_gaps(
	hf: Dictionary, meta: Dictionary = {}, ramp_data: Dictionary = {}
) -> Dictionary:
	if meta.is_empty():
		meta = HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var width: int = meta["width"]
	var height: int = meta["height"]
	var layers: Array = meta["layer_heights"]
	var flags: Array = meta["flags"]
	if ramp_data.is_empty():
		ramp_data = collect_ramp_placements(hf, meta)
	var romp: PackedByteArray = ramp_data["romp"]
	var cliffs := 0
	var ramps := 0
	var gaps := 0
	var tiles := (width - 1) * (height - 1)
	for iy in range(height - 1):
		for ix in range(width - 1):
			if should_leave_gap(layers, flags, width, height, ix, iy, romp):
				gaps += 1
			if is_cliff_tile(layers, width, ix, iy):
				cliffs += 1
			if is_ramp_tile(flags, width, ix, iy):
				ramps += 1
	return {
		"gaps": gaps,
		"cliffs": cliffs,
		"ramps": ramps,
		"tiles": tiles,
		"ramp_models": (ramp_data["placements"] as Array).size(),
	}
