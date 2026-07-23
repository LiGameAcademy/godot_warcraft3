class_name Wc3CliffTiles
extends RefCounted
## 悬崖 / 斜坡判定与模型 TAG。
## 悬崖 TAG 对齐 mdx-m3-viewer（BL,TL,TR,BR → A/B/C）。
## 斜坡选型对齐 HiveWE（CliffTrans 竖/横两格条带 + A/H/L/B 编码）。


const FLAG_RAMP := Wc3Coords.FLAG_RAMP

## M3 调试开关：false = 单脊主条挖洞 + CliffTrans（两侧收口）。
## 双脊 wide 格仍铺甲板（宽度≥2 连续坡，对照 WE）。
const RAMP_SURFACE_DECK_ENABLED := false

## romp 字节：0 无；1 单脊主条（挖洞+CliffTrans）；2 宽坡甲板；3 宽坡外侧侧脊（挖洞+CliffTrans）。
const ROMP_NONE := 0
const ROMP_SINGLE := 1
const ROMP_WIDE := 2
const ROMP_SIDE := 3

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
					var base_v := _vertical_ramp_base(layers, tp_w, ix, iy)
					var ramp_left := is_ramp_flag(flags, iy * tp_w + ix)
					# M1/M2：甲板与 romp 只依赖合法 TAG；CliffTrans GLB 缺模不阻塞（M3 再强制）
					placements.append({
						"ix": ix, "iy": iy, "tag": tag_v, "base_layer": base_v,
						"tex_idx": _tex_idx_at(cliff_tex, cliff_tilesets, iy * tp_w + ix, tp_w),
						"ramp_dir": ramp_dir,
						"axis": "v",
						"ramp_left": ramp_left,
						"has_glb": resolve_glb(ramp_dir, tag_v, 0) != "",
					})
					placed = true
			# 横向斜坡（占 2x1 格）
			if not placed and ix < tp_w - 2:
				var tag_h := _horizontal_ramp_tag(layers, flags, tp_w, ix, iy)
				if not tag_h.is_empty():
					var ramp_dir_h := _ramp_dir_at(cliff_tilesets, cliff_tex, tp_w, ix, iy, tiles)
					var base_h := _horizontal_ramp_base(layers, tp_w, ix, iy)
					var ramp_bottom := is_ramp_flag(flags, iy * tp_w + ix)
					placements.append({
						"ix": ix, "iy": iy, "tag": tag_h, "base_layer": base_h,
						"tex_idx": _tex_idx_at(cliff_tex, cliff_tilesets, iy * tp_w + ix, tp_w),
						"ramp_dir": ramp_dir_h,
						"axis": "h",
						"ramp_bottom": ramp_bottom,
						"has_glb": resolve_glb(ramp_dir_h, tag_h, 0) != "",
					})

	# 单条脊 XOR 会同时命中主条与邻格幻影 TAG；甲板只保留主条
	_mark_horizontal_phantom_twins(placements, layers, tp_w)
	_mark_vertical_phantom_twins(placements, layers, tp_w)
	_apply_romp_from_placements(romp, placements, tp_w, tp_h)
	# 双脊线及以上：相邻 placement 或连续旗列 → 宽坡甲板
	_expand_romp_for_wide_ramps(romp, placements, tp_w, tp_h)
	_expand_romp_for_adjacent_flag_cols(romp, placements, flags, tp_w, tp_h)
	_propagate_wide_to_phantoms(placements)

	return {"placements": placements, "romp": romp}


## 宽坡主条的幻影对也标 wide，避免再放 CliffTrans 在中间顶出 U 隔墙。
static func _propagate_wide_to_phantoms(placements: Array) -> void:
	var wide_v: Dictionary = {} # "ramp_col,iy"
	var wide_h: Dictionary = {} # "ix,ramp_row"
	for p in placements:
		if bool(p.get("phantom", false)) or not bool(p.get("wide", false)):
			continue
		var ix: int = int(p.get("ix", 0))
		var iy: int = int(p.get("iy", 0))
		if str(p.get("axis", "")) == "v":
			var rl: bool = bool(p.get("ramp_left", true))
			var rc := ix if rl else ix + 1
			wide_v["%d,%d" % [rc, iy]] = true
		else:
			var rb: bool = bool(p.get("ramp_bottom", true))
			var rr := iy if rb else iy + 1
			wide_h["%d,%d" % [ix, rr]] = true
	for i in range(placements.size()):
		var p: Dictionary = placements[i]
		if not bool(p.get("phantom", false)):
			continue
		var ix2: int = int(p.get("ix", 0))
		var iy2: int = int(p.get("iy", 0))
		if str(p.get("axis", "")) == "v":
			var rl2: bool = bool(p.get("ramp_left", true))
			var rc2 := ix2 if rl2 else ix2 + 1
			if wide_v.has("%d,%d" % [rc2, iy2]):
				p["wide"] = true
				placements[i] = p
		else:
			var rb2: bool = bool(p.get("ramp_bottom", true))
			var rr2 := iy2 if rb2 else iy2 + 1
			if wide_h.has("%d,%d" % [ix2, rr2]):
				p["wide"] = true
				placements[i] = p


## 同一条 3 旗竖脊会得到 (ix=R) ramp_left 与 (ix=R-1) !ramp_left 两个 TAG。
## 按旗列分组去幻影；若存在间隔一列的兄弟旗列（111|000|111），主条朝向中缝。
static func _mark_vertical_phantom_twins(
	placements: Array, layers: Array, tp_w: int
) -> void:
	# ramp_col → [placement indices]
	var by_col: Dictionary = {}
	for i in range(placements.size()):
		var p: Dictionary = placements[i]
		if str(p.get("axis", "")) != "v":
			continue
		var ix: int = int(p.get("ix", 0))
		var rl: bool = bool(p.get("ramp_left", true))
		var ramp_col := ix if rl else ix + 1
		var key := "%d,%d" % [ramp_col, int(p.get("iy", 0))]
		if not by_col.has(key):
			by_col[key] = []
		(by_col[key] as Array).append(i)
	for key in by_col.keys():
		var idxs: Array = by_col[key]
		if idxs.size() < 2:
			continue
		var parts: PackedStringArray = str(key).split(",")
		var ramp_col: int = int(parts[0])
		var iy: int = int(parts[1])
		var keep_i := _pick_vertical_primary_idx(placements, idxs, layers, tp_w, ramp_col, iy)
		for i in idxs:
			var p: Dictionary = placements[i]
			p["phantom"] = int(i) != keep_i
			placements[i] = p


static func _pick_vertical_primary_idx(
	placements: Array, idxs: Array, layers: Array, _tp_w: int, ramp_col: int, iy: int
) -> int:
	# 邻列是否也有竖脊（相邻旗列 111|111）→ 宽坡外侧朝向
	var has_left_sibling := false
	var has_right_sibling := false
	for j in range(placements.size()):
		var q: Dictionary = placements[j]
		if str(q.get("axis", "")) != "v":
			continue
		if int(q.get("iy", 0)) != iy:
			continue
		var qix: int = int(q.get("ix", 0))
		var qrl: bool = bool(q.get("ramp_left", true))
		var qc := qix if qrl else qix + 1
		if qc == ramp_col - 1:
			has_left_sibling = true
		if qc == ramp_col + 1:
			has_right_sibling = true
	var prefer_left_facing := has_left_sibling and not has_right_sibling
	var prefer_right_facing := has_right_sibling and not has_left_sibling
	var best_i: int = int(idxs[0])
	var best_score := -999999
	for i in idxs:
		var p: Dictionary = placements[i]
		var ix: int = int(p.get("ix", 0))
		var rl: bool = bool(p.get("ramp_left", true))
		var score := _v_ramp_lowside_score(p, layers, _tp_w) * 10
		# 宽坡：左脊朝右（ramp_left）；右脊朝左（!ramp_left）
		if prefer_right_facing and rl and ix == ramp_col:
			score += 1000
		if prefer_left_facing and (not rl) and ix == ramp_col - 1:
			score += 1000
		# 单脊：略偏向 ramp_left 主条（ix==ramp_col）
		if not prefer_left_facing and not prefer_right_facing and rl and ix == ramp_col:
			score += 50
		if score > best_score:
			best_score = score
			best_i = int(i)
	return best_i


static func _v_ramp_lowside_score(p: Dictionary, layers: Array, tp_w: int) -> int:
	var ix: int = int(p.get("ix", 0))
	var iy: int = int(p.get("iy", 0))
	var ramp_left: bool = bool(p.get("ramp_left", true))
	var x_ramp := ix if ramp_left else ix + 1
	var x_flat := ix + 1 if ramp_left else ix
	var h_ramp := (
		_layer(layers, tp_w, x_ramp, iy)
		+ _layer(layers, tp_w, x_ramp, iy + 1)
		+ _layer(layers, tp_w, x_ramp, iy + 2)
	)
	var h_flat := (
		_layer(layers, tp_w, x_flat, iy)
		+ _layer(layers, tp_w, x_flat, iy + 1)
		+ _layer(layers, tp_w, x_flat, iy + 2)
	)
	return h_flat - h_ramp


## 同一条 3 旗横脊会得到 (ix,iy) ramp_bottom 与 (ix,iy-1) !ramp_bottom 两个 TAG。
## 只保留「斜坡旗在低侧」的那条作为甲板主条；另一条标 phantom（M3 仍可选用）。
static func _mark_horizontal_phantom_twins(
	placements: Array, layers: Array, tp_w: int
) -> void:
	var h_at: Dictionary = {} # "ix,iy" → idx
	for i in range(placements.size()):
		var p: Dictionary = placements[i]
		if str(p.get("axis", "")) != "h":
			continue
		h_at["%d,%d" % [int(p.get("ix", 0)), int(p.get("iy", 0))]] = i
	var seen: Dictionary = {}
	for i in range(placements.size()):
		var p: Dictionary = placements[i]
		if str(p.get("axis", "")) != "h":
			continue
		var ix: int = int(p.get("ix", 0))
		var iy: int = int(p.get("iy", 0))
		var key := "%d,%d" % [ix, iy]
		if seen.get(key, false):
			continue
		var twin_key := "%d,%d" % [ix, iy - 1]
		if not h_at.has(twin_key):
			continue
		var j: int = int(h_at[twin_key])
		var q: Dictionary = placements[j]
		# 幻影对：相邻 iy、ramp_bottom 相反，且共用同一 FLAG 行
		if bool(p.get("ramp_bottom", true)) == bool(q.get("ramp_bottom", true)):
			continue
		var rb_p: bool = bool(p.get("ramp_bottom", true))
		var rb_q: bool = bool(q.get("ramp_bottom", true))
		var ramp_row_p := iy if rb_p else iy + 1
		var qiy: int = int(q.get("iy", 0))
		var ramp_row_q := qiy if rb_q else qiy + 1
		if ramp_row_p != ramp_row_q:
			continue
		var keep_i := i
		var drop_i := j
		if _h_ramp_lowside_score(p, layers, tp_w) < _h_ramp_lowside_score(q, layers, tp_w):
			keep_i = j
			drop_i = i
		var keep_p: Dictionary = placements[keep_i]
		var drop_p: Dictionary = placements[drop_i]
		keep_p["phantom"] = false
		drop_p["phantom"] = true
		placements[keep_i] = keep_p
		placements[drop_i] = drop_p
		seen[key] = true
		seen["%d,%d" % [int(drop_p.get("ix", 0)), int(drop_p.get("iy", 0))]] = true


static func _h_ramp_lowside_score(p: Dictionary, layers: Array, tp_w: int) -> int:
	var ix: int = int(p.get("ix", 0))
	var iy: int = int(p.get("iy", 0))
	var ramp_bottom: bool = bool(p.get("ramp_bottom", true))
	var y_ramp := iy if ramp_bottom else iy + 1
	var y_flat := iy + 1 if ramp_bottom else iy
	var h_ramp := (
		_layer(layers, tp_w, ix, y_ramp)
		+ _layer(layers, tp_w, ix + 1, y_ramp)
		+ _layer(layers, tp_w, ix + 2, y_ramp)
	)
	var h_flat := (
		_layer(layers, tp_w, ix, y_flat)
		+ _layer(layers, tp_w, ix + 1, y_flat)
		+ _layer(layers, tp_w, ix + 2, y_flat)
	)
	return h_flat - h_ramp


static func _apply_romp_from_placements(
	romp: PackedByteArray, placements: Array, tp_w: int, tp_h: int
) -> void:
	for p in placements:
		var ix: int = int(p.get("ix", 0))
		var iy: int = int(p.get("iy", 0))
		# 主条 → SINGLE（铺高度图）；幻影侧脊 → SIDE（挖洞给 CliffTrans）
		var kind: int = ROMP_SIDE if bool(p.get("phantom", false)) else ROMP_SINGLE
		if str(p.get("axis", "")) == "v":
			_romp_set(romp, tp_w, tp_h, ix, iy, kind)
			_romp_set(romp, tp_w, tp_h, ix, iy + 1, kind)
		else:
			_romp_set(romp, tp_w, tp_h, ix, iy, kind)
			_romp_set(romp, tp_w, tp_h, ix + 1, iy, kind)


## 仅当存在相邻同向真条带、或连续两列/行都有脊旗时：条带内升为宽坡甲板。
## 外侧不扩甲板——侧脊用 CliffTrans，对照 WE。
## WE 宽2 = 相邻列菱形(111|111)，不是隔列(111|000|111)。
static func _expand_romp_for_wide_ramps(
	romp: PackedByteArray, placements: Array, tp_w: int, tp_h: int
) -> void:
	var v_keys: Dictionary = {} # "ix,iy" → idx
	var h_keys: Dictionary = {}
	for i in range(placements.size()):
		var p: Dictionary = placements[i]
		if bool(p.get("phantom", false)):
			continue
		var key := "%d,%d" % [int(p.get("ix", 0)), int(p.get("iy", 0))]
		if str(p.get("axis", "")) == "v":
			v_keys[key] = i
		else:
			h_keys[key] = i
	for i in range(placements.size()):
		var p: Dictionary = placements[i]
		if bool(p.get("phantom", false)):
			continue
		var ix: int = int(p.get("ix", 0))
		var iy: int = int(p.get("iy", 0))
		if str(p.get("axis", "")) == "v":
			var has_nbr: bool = (
				v_keys.has("%d,%d" % [ix - 1, iy]) or v_keys.has("%d,%d" % [ix + 1, iy])
			)
			if not has_nbr:
				continue
			_romp_set(romp, tp_w, tp_h, ix, iy, ROMP_WIDE)
			_romp_set(romp, tp_w, tp_h, ix, iy + 1, ROMP_WIDE)
			p["wide"] = true
			placements[i] = p
		else:
			var ramp_bottom: bool = bool(p.get("ramp_bottom", true))
			var has_nbr_h := false
			for dy in [-1, 1]:
				var nk := "%d,%d" % [ix, iy + dy]
				if not h_keys.has(nk):
					continue
				var np: Dictionary = placements[int(h_keys[nk])]
				if bool(np.get("ramp_bottom", true)) == ramp_bottom:
					has_nbr_h = true
					break
			if not has_nbr_h:
				continue
			_romp_set(romp, tp_w, tp_h, ix, iy, ROMP_WIDE)
			_romp_set(romp, tp_w, tp_h, ix + 1, iy, ROMP_WIDE)
			p["wide"] = true
			placements[i] = p


## 连续脊旗列/行 → 宽坡：
## - 仅「脊列之间」的格标 WIDE（铺甲板）
## - 外侧侧脊格强制 SINGLE（挖洞给 CliffTrans）；宽坡 expand 可能已把外侧升成 WIDE，此处降回
## - 顶/底接缝格不标 WIDE：背部应显示直崖模型，禁止铺地形甲板（否则天窗/多余网格）
## - 追加 wide_core 供坡面采样（覆盖整段宽度，避免内部点采不到平面而凹进 R5 min）
static func _expand_romp_for_adjacent_flag_cols(
	romp: PackedByteArray,
	placements: Array,
	flags: Array,
	tp_w: int,
	tp_h: int
) -> void:
	var bands: Dictionary = {}
	for p in placements:
		if str(p.get("axis", "")) != "v":
			continue
		bands[int(p.get("iy", 0))] = true
	for iy in bands.keys():
		var sy: int = int(iy)
		var col := 0
		while col < tp_w:
			if not _flag_col_all_ramp(flags, tp_w, col, sy):
				col += 1
				continue
			var c_lo := col
			while col + 1 < tp_w and _flag_col_all_ramp(flags, tp_w, col + 1, sy):
				col += 1
			var c_hi := col
			if c_hi > c_lo:
				# 内部格：脊列之间（仅条带 2 格深，不含顶/底）
				for ix in range(c_lo, c_hi):
					_romp_set(romp, tp_w, tp_h, ix, sy, ROMP_WIDE)
					_romp_set(romp, tp_w, tp_h, ix, sy + 1, ROMP_WIDE)
				# 外侧侧脊：强制 SIDE 挖洞（覆盖 wide_ramps 误升的 WIDE；勿改成地形）
				for side_x in [c_lo - 1, c_hi]:
					_romp_force(romp, tp_w, tp_h, side_x, sy, ROMP_SIDE)
					_romp_force(romp, tp_w, tp_h, side_x, sy + 1, ROMP_SIDE)
				placements.append({
					"ix": c_lo,
					"iy": sy,
					"axis": "v",
					"wide": true,
					"wide_core": true,
					"span_x": c_hi - c_lo,
					"tag": "",
					"base_layer": 2,
					"tex_idx": 0,
					"ramp_dir": "CliffTrans",
					"has_glb": false,
				})
				for i in range(placements.size()):
					var p2: Dictionary = placements[i]
					if bool(p2.get("wide_core", false)):
						continue
					if str(p2.get("axis", "")) != "v":
						continue
					if int(p2.get("iy", 0)) != sy:
						continue
					var pix: int = int(p2.get("ix", 0))
					# 外侧 TAG 条（侧脊）
					if pix == c_lo - 1 or pix == c_hi:
						p2["wide"] = true
						p2["side_ridge"] = true
						placements[i] = p2
			col += 1
	var h_bands: Dictionary = {}
	for p3 in placements:
		if str(p3.get("axis", "")) != "h":
			continue
		if bool(p3.get("wide_core", false)):
			continue
		h_bands[int(p3.get("ix", 0))] = true
	for ix0 in h_bands.keys():
		var sx0: int = int(ix0)
		var row := 0
		while row < tp_h:
			if not _flag_row_all_ramp(flags, tp_w, sx0, row):
				row += 1
				continue
			var r_lo := row
			while row + 1 < tp_h and _flag_row_all_ramp(flags, tp_w, sx0, row + 1):
				row += 1
			var r_hi := row
			if r_hi > r_lo:
				for iy2 in range(r_lo, r_hi):
					_romp_set(romp, tp_w, tp_h, sx0, iy2, ROMP_WIDE)
					_romp_set(romp, tp_w, tp_h, sx0 + 1, iy2, ROMP_WIDE)
				for side_y in [r_lo - 1, r_hi]:
					_romp_force(romp, tp_w, tp_h, sx0, side_y, ROMP_SIDE)
					_romp_force(romp, tp_w, tp_h, sx0 + 1, side_y, ROMP_SIDE)
				placements.append({
					"ix": sx0,
					"iy": r_lo,
					"axis": "h",
					"wide": true,
					"wide_core": true,
					"span_y": r_hi - r_lo,
					"tag": "",
					"base_layer": 2,
					"tex_idx": 0,
					"ramp_dir": "CliffTrans",
					"has_glb": false,
				})
				for j in range(placements.size()):
					var p4: Dictionary = placements[j]
					if bool(p4.get("wide_core", false)):
						continue
					if str(p4.get("axis", "")) != "h":
						continue
					if int(p4.get("ix", 0)) != sx0:
						continue
					var piy: int = int(p4.get("iy", 0))
					if piy == r_lo - 1 or piy == r_hi:
						p4["wide"] = true
						p4["side_ridge"] = true
						placements[j] = p4
			row += 1


static func _flag_col_all_ramp(flags: Array, tp_w: int, ix: int, sy: int) -> bool:
	for yy in range(sy, sy + 3):
		var i: int = yy * tp_w + ix
		if i < 0 or i >= flags.size():
			return false
		if not is_ramp_flag(flags, i):
			return false
	return true


static func _flag_row_all_ramp(flags: Array, tp_w: int, sx: int, iy: int) -> bool:
	for xx in range(sx, sx + 3):
		var i: int = iy * tp_w + xx
		if i < 0 or i >= flags.size():
			return false
		if not is_ramp_flag(flags, i):
			return false
	return true


static func _romp_set(
	romp: PackedByteArray, tp_w: int, tp_h: int, ix: int, iy: int, kind: int = ROMP_SINGLE
) -> void:
	if ix < 0 or iy < 0 or ix >= tp_w - 1 or iy >= tp_h - 1:
		return
	var i := iy * tp_w + ix
	if i >= 0 and i < romp.size():
		var cur := int(romp[i])
		# SIDE 不被主条 SINGLE 覆盖；WIDE 仍可盖过 SINGLE；不可盖 SIDE（侧脊优先）
		if cur == ROMP_SIDE and kind != ROMP_SIDE:
			return
		if kind == ROMP_SIDE:
			romp[i] = ROMP_SIDE
			return
		romp[i] = maxi(cur, kind)


## 强制写入 romp（可降级），用于侧脊挖洞。
static func _romp_force(
	romp: PackedByteArray, tp_w: int, tp_h: int, ix: int, iy: int, kind: int
) -> void:
	if ix < 0 or iy < 0 or ix >= tp_w - 1 or iy >= tp_h - 1:
		return
	var i := iy * tp_w + ix
	if i >= 0 and i < romp.size():
		romp[i] = kind


static func romp_kind_at(romp: PackedByteArray, tp_w: int, ix: int, iy: int) -> int:
	var i00 := iy * tp_w + ix
	if i00 < 0 or i00 >= romp.size():
		return ROMP_NONE
	return int(romp[i00])


static func should_leave_gap(
	layer_heights: Array,
	flags: Array,
	tp_w: int,
	_tp_h: int,
	ix: int,
	iy: int,
	romp: PackedByteArray = PackedByteArray()
) -> bool:
	var kind := romp_kind_at(romp, tp_w, ix, iy)
	if kind == ROMP_WIDE:
		# 宽坡内部：铺高度图甲板
		return false
	if kind == ROMP_SINGLE or kind == ROMP_SIDE:
		# 条带「最底下一格」铺泥土/草地；上格仍挖洞给 CliffTrans
		# 竖坡底格：北有 romp、南无 romp；横坡左格：东有 romp、西无 romp
		if _is_romp_strip_floor_cell(romp, tp_w, ix, iy):
			return false
		return not RAMP_SURFACE_DECK_ENABLED
	# 斜坡脚底外侧一格：也不挖洞
	if is_ramp_foot_cell(romp, tp_w, ix, iy):
		return false
	if is_ramp_entrance(layer_heights, flags, tp_w, ix, iy):
		return not RAMP_SURFACE_DECK_ENABLED
	# 直崖格挖洞 → 背后用 Cliffs 收口
	return is_cliff_tile(layer_heights, tp_w, ix, iy)


## 斜坡脚底外侧：紧贴竖条带正南（或横条带正西）且自身不在 romp。
static func is_ramp_foot_cell(romp: PackedByteArray, tp_w: int, ix: int, iy: int) -> bool:
	if romp_kind_at(romp, tp_w, ix, iy) != ROMP_NONE:
		return false
	var n1 := romp_kind_at(romp, tp_w, ix, iy + 1)
	var n2 := romp_kind_at(romp, tp_w, ix, iy + 2)
	if n1 != ROMP_NONE and n2 != ROMP_NONE:
		return true
	var e1 := romp_kind_at(romp, tp_w, ix + 1, iy)
	var e2 := romp_kind_at(romp, tp_w, ix + 2, iy)
	if e1 != ROMP_NONE and e2 != ROMP_NONE:
		return true
	return false


## romp 条带朝向低地的那一格（竖=南侧格，横=西侧格）→ 脚底地板。
static func _is_romp_strip_floor_cell(romp: PackedByteArray, tp_w: int, ix: int, iy: int) -> bool:
	var north := romp_kind_at(romp, tp_w, ix, iy + 1)
	var south := ROMP_NONE if iy <= 0 else romp_kind_at(romp, tp_w, ix, iy - 1)
	# 竖坡底格：北有 romp、南无
	if north != ROMP_NONE and south == ROMP_NONE:
		return true
	var east := romp_kind_at(romp, tp_w, ix + 1, iy)
	var west := ROMP_NONE if ix <= 0 else romp_kind_at(romp, tp_w, ix - 1, iy)
	# 横坡左格：东有 romp、西无，且上下都不是竖条带（避免误伤竖坡上格）
	if east != ROMP_NONE and west == ROMP_NONE and north == ROMP_NONE and south == ROMP_NONE:
		return true
	return false


static func _cell_touches_romp(romp: PackedByteArray, tp_w: int, ix: int, iy: int) -> bool:
	return _cell_touches_romp_kind(romp, tp_w, ix, iy, -1)


## want_kind < 0 时：任意非 NONE；否则须匹配指定 kind（如 ROMP_WIDE）。
static func _cell_touches_romp_kind(
	romp: PackedByteArray, tp_w: int, ix: int, iy: int, want_kind: int
) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var k := romp_kind_at(romp, tp_w, ix + dx, iy + dy)
			if k == ROMP_NONE:
				continue
			if want_kind < 0 or k == want_kind:
				return true
	return false


## 落在 ramp 条带内时，用两端 tilepoint 线性插值（侧视 A→B 斜线）。
## 单脊线：仅条带内 1×2/2×1；宽坡外扩格按扩展域四角真实高度插值（填缝）。
## 多 placement 重叠时优先条带内核（score 更低），避免邻条外扩抢采样。
static func sample_ramp_plane_height(
	heights: Array, placements: Array, tp_w: int, tp_h: int, tx: float, ty: float
) -> float:
	var best_h := NAN
	var best_score := INF
	var best_dist := INF
	for p in placements:
		if bool(p.get("phantom", false)):
			continue
		# wide_core 优先（负分），覆盖整段宽坡内部
		var score := _ramp_hit_score(p, tp_w, tp_h, tx, ty)
		if score >= INF:
			continue
		var h := _sample_one_ramp_plane(heights, p, tp_w, tp_h, tx, ty)
		if is_nan(h):
			continue
		var dist := _ramp_center_dist2(p, tx, ty)
		if (
			score < best_score - 0.0001
			or (absf(score - best_score) <= 0.0001 and dist < best_dist - 0.0001)
		):
			best_score = score
			best_dist = dist
			best_h = h
	return best_h


static func _ramp_center_dist2(p: Dictionary, tx: float, ty: float) -> float:
	var ix: int = int(p.get("ix", 0))
	var iy: int = int(p.get("iy", 0))
	var cx: float
	var cy: float
	if str(p.get("axis", "v")) == "v":
		var span_x: float = float(p.get("span_x", 1))
		cx = float(ix) + span_x * 0.5
		cy = float(iy) + 1.0
	else:
		var span_y: float = float(p.get("span_y", 1))
		cx = float(ix) + 1.0
		cy = float(iy) + span_y * 0.5
	var dx := tx - cx
	var dy := ty - cy
	return dx * dx + dy * dy


## 0=条带内核；-1=wide_core（优先）；INF=未命中。
static func _ramp_hit_score(
	p: Dictionary, _tp_w: int, _tp_h: int, tx: float, ty: float
) -> float:
	var ix: int = int(p.get("ix", 0))
	var iy: int = int(p.get("iy", 0))
	if bool(p.get("wide_core", false)):
		if str(p.get("axis", "v")) == "v":
			var span_x: int = int(p.get("span_x", 1))
			if ty < float(iy) or ty > float(iy + 2):
				return INF
			if tx >= float(ix) and tx <= float(ix + span_x):
				return -1.0
			return INF
		var span_y: int = int(p.get("span_y", 1))
		if tx < float(ix) or tx > float(ix + 2):
			return INF
		if ty >= float(iy) and ty <= float(iy + span_y):
			return -1.0
		return INF
	if str(p.get("axis", "v")) == "v":
		if ty < float(iy) or ty > float(iy + 2):
			return INF
		if tx >= float(ix) and tx <= float(ix + 1):
			return 0.0
		return INF
	if tx < float(ix) or tx > float(ix + 2):
		return INF
	if ty >= float(iy) and ty <= float(iy + 1):
		return 0.0
	return INF


static func _sample_one_ramp_plane(
	heights: Array, p: Dictionary, tp_w: int, tp_h: int, tx: float, ty: float
) -> float:
	var ix: int = int(p.get("ix", 0))
	var iy: int = int(p.get("iy", 0))
	var axis := str(p.get("axis", "v"))
	if bool(p.get("wide_core", false)):
		if axis == "v":
			var span_x: int = int(p.get("span_x", 1))
			if tx < float(ix) or tx > float(ix + span_x) or ty < float(iy) or ty > float(iy + 2):
				return NAN
			var t := clampf((ty - float(iy)) / 2.0, 0.0, 1.0)
			var fx := 0.0 if span_x <= 0 else clampf((tx - float(ix)) / float(span_x), 0.0, 1.0)
			var h_sw := _tp_height(heights, tp_w, tp_h, ix, iy)
			var h_se := _tp_height(heights, tp_w, tp_h, ix + span_x, iy)
			var h_nw := _tp_height(heights, tp_w, tp_h, ix, iy + 2)
			var h_ne := _tp_height(heights, tp_w, tp_h, ix + span_x, iy + 2)
			return lerpf(lerpf(h_sw, h_se, fx), lerpf(h_nw, h_ne, fx), t)
		var span_y: int = int(p.get("span_y", 1))
		if ty < float(iy) or ty > float(iy + span_y) or tx < float(ix) or tx > float(ix + 2):
			return NAN
		var th := clampf((tx - float(ix)) / 2.0, 0.0, 1.0)
		var fy := 0.0 if span_y <= 0 else clampf((ty - float(iy)) / float(span_y), 0.0, 1.0)
		var h_sw2 := _tp_height(heights, tp_w, tp_h, ix, iy)
		var h_nw2 := _tp_height(heights, tp_w, tp_h, ix, iy + span_y)
		var h_se2 := _tp_height(heights, tp_w, tp_h, ix + 2, iy)
		var h_ne2 := _tp_height(heights, tp_w, tp_h, ix + 2, iy + span_y)
		return lerpf(lerpf(h_sw2, h_se2, th), lerpf(h_nw2, h_ne2, th), fy)
	if axis == "v":
		if tx < float(ix) or tx > float(ix + 1) or ty < float(iy) or ty > float(iy + 2):
			return NAN
		var tv := (ty - float(iy)) / 2.0
		var fxv := clampf(tx - float(ix), 0.0, 1.0)
		var h_swv := _tp_height(heights, tp_w, tp_h, ix, iy)
		var h_sev := _tp_height(heights, tp_w, tp_h, ix + 1, iy)
		var h_nwv := _tp_height(heights, tp_w, tp_h, ix, iy + 2)
		var h_nev := _tp_height(heights, tp_w, tp_h, ix + 1, iy + 2)
		return lerpf(lerpf(h_swv, h_sev, fxv), lerpf(h_nwv, h_nev, fxv), tv)
	if ty < float(iy) or ty > float(iy + 1) or tx < float(ix) or tx > float(ix + 2):
		return NAN
	var th := (tx - float(ix)) / 2.0
	var fyh := clampf(ty - float(iy), 0.0, 1.0)
	var h_swh := _tp_height(heights, tp_w, tp_h, ix, iy)
	var h_nwh := _tp_height(heights, tp_w, tp_h, ix, iy + 1)
	var h_seh := _tp_height(heights, tp_w, tp_h, ix + 2, iy)
	var h_neh := _tp_height(heights, tp_w, tp_h, ix + 2, iy + 1)
	return lerpf(lerpf(h_swh, h_nwh, fyh), lerpf(h_seh, h_neh, fyh), th)


static func _tp_height(heights: Array, tp_w: int, tp_h: int, ix: int, iy: int) -> float:
	ix = clampi(ix, 0, tp_w - 1)
	iy = clampi(iy, 0, tp_h - 1)
	var i := iy * tp_w + ix
	if i < 0 or i >= heights.size():
		return 0.0
	return float(heights[i])


static func cliff_tag_at(layer_heights: Array, width: int, ix: int, iy: int) -> Dictionary:
	var slices: Array = cliff_slices_at(layer_heights, width, ix, iy)
	if slices.is_empty():
		return {}
	return slices[0]


## 直崖 TAG 选型（BL,TL,TR,BR → 相对 base 的 A/B/C）。
## 对齐 HiveWE / WE：跨度 ≤2 时只放一条完整变体（含 AABC「底两边、顶一边」等）。
## 跨度 >2（旧图/异常）：每次剥一段满 C 高（+2），再收尾剩余 ≤2 的一段。
## 切勿对跨度≤2 再按 min_up 叠段——AABC 会错误再叠 AAAB，导致碎裂重影。
## 返回 [{ tag, base_layer }, ...]，tag 字母仅 A–C。
static func cliff_slices_at(layer_heights: Array, width: int, ix: int, iy: int) -> Array:
	if not is_cliff_tile(layer_heights, width, ix, iy):
		return []
	var i00 := iy * width + ix
	var i10 := i00 + 1
	var i01 := i00 + width
	var i11 := i01 + 1
	var bl := int(layer_heights[i00])
	var br := int(layer_heights[i10])
	var tl := int(layer_heights[i01])
	var tr := int(layer_heights[i11])
	var lo := mini(mini(bl, br), mini(tl, tr))
	var hi := maxi(maxi(bl, br), maxi(tl, tr))
	var out: Array = []
	var base := lo
	while base < hi:
		var raw_bl := bl - base
		var raw_tl := tl - base
		var raw_tr := tr - base
		var raw_br := br - base
		var raw_hi := maxi(maxi(raw_bl, raw_br), maxi(raw_tl, raw_tr))
		# 本段已能被单个 A/B/C 模型表达 → 收尾，禁止再叠
		if raw_hi <= 2:
			var tag_exact := _cliff_tag_from_rels(raw_bl, raw_tl, raw_tr, raw_br)
			if tag_exact != "AAAA":
				out.append({"tag": tag_exact, "base_layer": base})
			break
		var rbl := clampi(raw_bl, 0, 2)
		var rtl := clampi(raw_tl, 0, 2)
		var rtr := clampi(raw_tr, 0, 2)
		var rbr := clampi(raw_br, 0, 2)
		var tag := _cliff_tag_from_rels(rbl, rtl, rtr, rbr)
		if tag != "AAAA":
			out.append({"tag": tag, "base_layer": base})
		# 剥掉一段满 C（相对 +2）；剩余高度下一轮再表达
		base += 2
	return out


static func _cliff_tag_from_rels(rbl: int, rtl: int, rtr: int, rbr: int) -> String:
	return (
		String.chr(65 + clampi(rbl, 0, 2))
		+ String.chr(65 + clampi(rtl, 0, 2))
		+ String.chr(65 + clampi(rtr, 0, 2))
		+ String.chr(65 + clampi(rbr, 0, 2))
	)


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


static func _tex_idx_at(cliff_tex: Array, cliff_tilesets: Array, i00: int, tp_w: int = 0) -> int:
	var best := 0
	var found_nonzero := false
	var offsets: Array = [0]
	if tp_w > 0:
		offsets = [0, 1, tp_w, tp_w + 1]
	for off in offsets:
		var i: int = i00 + int(off)
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


static func _ramp_dir_at(
	cliff_tilesets: Array,
	cliff_tex: Array,
	tp_w: int,
	ix: int,
	iy: int,
	tiles: Wc3TerrainTiles = null
) -> String:
	var tex_idx := _tex_idx_at(cliff_tex, cliff_tilesets, iy * tp_w + ix, tp_w)
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
	return mini(maxi(variation, 0), int(table[tag]))


## 直崖变体：优先用存盘值；存盘为 0 时用格点哈希打散（避免新建图整墙同一模）。
static func pick_cliff_variation(
	model_dir: String, tag: String, stored: int, ix: int, iy: int
) -> int:
	var table: Dictionary = CITY_CLIFF_VAR_MAX if model_dir == "CityCliffs" else CLIFF_VAR_MAX
	var max_v: int = int(table.get(tag, 0))
	if max_v <= 0:
		return 0
	if stored > 0:
		return mini(stored, max_v)
	# stored==0：可能是「未刷变体」；用稳定哈希在 0..max_v 间打散
	var h: int = absi((ix * 73856093) ^ (iy * 19349663) ^ tag.hash())
	return h % (max_v + 1)


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
## 甲板关闭时不改高度（避免邻面被抬高；视觉交给 CliffTrans）。
static func apply_ramp_entrance_heights(heights: Array, layers: Array, flags: Array, tp_w: int, tp_h: int) -> Array:
	if not RAMP_SURFACE_DECK_ENABLED:
		return heights
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
