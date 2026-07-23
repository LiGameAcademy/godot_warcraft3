extends RefCounted
## 可编辑地图文档：内存中的 terrain-heightfield（与 map-parsed JSON 同形）。
## （不用 class_name；编辑器通过 preload 引用）

signal changed
signal dirty_changed(is_dirty: bool)

const DEFAULT_MAP_DIR := "res://assets/map-parsed/losttemple"
const BLANK_TILEPOINTS := 33 ## → 32×32 格
const DEFAULT_TILESET := "I"
const DEFAULT_TILESET_NAME := "Icecrown"
const DEFAULT_GROUND := ["Idrt", "Idtr", "Idki", "Ibkb", "Irbk", "Itbk", "Iice", "Ibsq", "Isnw"]
const DEFAULT_CLIFF := ["CIsn", "CIrb"]
## layerHeight=2 时 groundHeightRaw=0x2000 → 高度 0
const FLAT_HEIGHT := 0.0
const FLAT_LAYER := 2
const LAYER_MIN := 0
const LAYER_MAX := 14
## 悬崖层差上限（WE / 官方模型仅 A/B/C）：
## 1) 正交相邻顶点最多差 2；2) 同一地表格四角 max−min 也不得超过 2
## （仅约束正交时，对角可差 3 → 出现 D 级相对高、叠片碎柱）。
## 再升高则把较低点抬到 high-2（叠蛋糕外扩）；再降低则把较高点压到 low+2。
const MAX_CLIFF_ADJ_DELTA := 2
## 悬崖层差 1 → WC3 高度 128（与 W3E / create_from_options 一致）
const LAYER_HEIGHT_STEP := 128.0

enum CliffPropagate {
	RAISE_LOWER = 0, ## 升：抬低邻
	LOWER_HIGHER = 1, ## 降：压高邻
	BOTH = 2,
}
const WATER_SHALLOW_EXTRA := 48.0
const WATER_DEEP_EXTRA := 128.0
const FLAG_WATER := Wc3Coords.FLAG_WATER
const FLAG_RAMP := Wc3Coords.FLAG_RAMP

var hf: Dictionary = {}
var info: Dictionary = {}
var map_dir: String = ""
var source_name: String = ""
var brush_tile_index: int = 0
var brush_cliff_type: int = 0
var _dirty: bool = false
## cliffTilesets 下标 → groundTilesets 下标（CliffTypes.groundTile）；-1=未解析
var _cliff_ground_cache: PackedInt32Array = PackedInt32Array()
## 最近一次斜坡笔刷结果（供状态栏 / 自测）
var last_ramp_message: String = ""


func is_dirty() -> bool:
	return _dirty


func mark_dirty() -> void:
	if _dirty:
		changed.emit()
		return
	_dirty = true
	dirty_changed.emit(true)
	changed.emit()


func clear_dirty() -> void:
	if not _dirty:
		return
	_dirty = false
	dirty_changed.emit(false)


func is_empty() -> bool:
	return hf.is_empty() or int(hf.get("tilepointWidth", 0)) < 2


func tilepoint_size() -> Vector2i:
	return Vector2i(int(hf.get("tilepointWidth", 0)), int(hf.get("tilepointHeight", 0)))


func map_size() -> Vector2i:
	var tp: Vector2i = tilepoint_size()
	return Vector2i(maxi(tp.x - 1, 0), maxi(tp.y - 1, 0))


func center_offset() -> Vector2:
	var co: Dictionary = hf.get("centerOffset", {})
	return Vector2(float(co.get("x", 0.0)), float(co.get("y", 0.0)))


func tile_size() -> float:
	return float(hf.get("tileSize", Wc3Coords.TILE_SIZE))


func ground_tilesets() -> Array:
	return hf.get("groundTilesets", []) as Array


func cliff_tilesets() -> Array:
	return hf.get("cliffTilesets", []) as Array


func ensure_brush_index_valid() -> void:
	var n: int = ground_tilesets().size()
	if n <= 0:
		brush_tile_index = 0
		return
	brush_tile_index = clampi(brush_tile_index, 0, n - 1)


func ensure_cliff_type_valid() -> void:
	var n: int = cliff_tilesets().size()
	if n <= 0:
		brush_cliff_type = 0
		return
	brush_cliff_type = clampi(brush_cliff_type, 0, n - 1)


func layer_at(ix: int, iy: int) -> int:
	if is_empty():
		return FLAT_LAYER
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return FLAT_LAYER
	var layers: Array = hf.get("layerHeights", []) as Array
	var i: int = iy * tp_w + ix
	if i < 0 or i >= layers.size():
		return FLAT_LAYER
	return clampi(int(layers[i]), LAYER_MIN, LAYER_MAX)


func brush_tile_id() -> String:
	ensure_brush_index_valid()
	var gs: Array = ground_tilesets()
	if brush_tile_index < 0 or brush_tile_index >= gs.size():
		return ""
	return str(gs[brush_tile_index])


func load_from_map_dir(path: String = DEFAULT_MAP_DIR) -> Error:
	var hf_path: String = path.path_join("terrain-heightfield.json")
	if not FileAccess.file_exists(hf_path):
		push_error("MapDocument: 缺少 %s" % hf_path)
		return ERR_FILE_NOT_FOUND
	var f: FileAccess = FileAccess.open(hf_path, FileAccess.READ)
	if f == null:
		return ERR_CANT_OPEN
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	hf = parsed
	info = {}
	var info_path: String = path.path_join("info.json")
	if FileAccess.file_exists(info_path):
		var fi: FileAccess = FileAccess.open(info_path, FileAccess.READ)
		if fi:
			var ip: Variant = JSON.parse_string(fi.get_as_text())
			if typeof(ip) == TYPE_DICTIONARY:
				info = ip
	map_dir = path
	source_name = path.get_file()
	_dirty = false
	_cliff_ground_cache = PackedInt32Array()
	ensure_brush_index_valid()
	dirty_changed.emit(false)
	changed.emit()
	return OK


func create_blank(
	tilepoints: int = BLANK_TILEPOINTS,
	main_tileset: String = DEFAULT_TILESET
) -> void:
	create_from_options({
		"width": tilepoints - 1,
		"height": tilepoints - 1,
		"main_tileset": main_tileset,
		"main_tileset_name": DEFAULT_TILESET_NAME if main_tileset == "I" else main_tileset,
		"ground_tilesets": DEFAULT_GROUND.duplicate(),
		"cliff_tilesets": DEFAULT_CLIFF.duplicate(),
		"default_tile_index": 0,
		"cliff_level": FLAT_LAYER,
		"water_mode": 0,
		"random_height": false,
	})


## options: width/height(格), main_tileset, ground_tilesets, cliff_tilesets,
## default_tile_index, cliff_level, water_mode(0无/1浅/2深), random_height
func create_from_options(options: Dictionary) -> void:
	var map_w: int = maxi(int(options.get("width", 64)), 2)
	var map_h: int = maxi(int(options.get("height", 64)), 2)
	var tp_w: int = map_w + 1
	var tp_h: int = map_h + 1
	var n: int = tp_w * tp_h
	var half_x: float = float(map_w) * Wc3Coords.TILE_SIZE * 0.5
	var half_y: float = float(map_h) * Wc3Coords.TILE_SIZE * 0.5
	var main_ts: String = str(options.get("main_tileset", DEFAULT_TILESET))
	var ts_name: String = str(options.get("main_tileset_name", main_ts))
	var ground: Array = options.get("ground_tilesets", DEFAULT_GROUND.duplicate()) as Array
	var cliffs: Array = options.get("cliff_tilesets", DEFAULT_CLIFF.duplicate()) as Array
	if ground.is_empty():
		ground = DEFAULT_GROUND.duplicate()
	if cliffs.is_empty():
		cliffs = DEFAULT_CLIFF.duplicate()
	_cliff_ground_cache = PackedInt32Array()
	var tile_index: int = clampi(int(options.get("default_tile_index", 0)), 0, ground.size() - 1)
	var cliff_level: int = clampi(int(options.get("cliff_level", FLAT_LAYER)), 0, 14)
	var water_mode: int = clampi(int(options.get("water_mode", 0)), 0, 2)
	var random_h: bool = bool(options.get("random_height", false))
	var base_h: float = float(cliff_level - 2) * 128.0
	var water_extra: float = 0.0
	if water_mode == 1:
		water_extra = 48.0
	elif water_mode == 2:
		water_extra = 128.0

	var heights: Array = []
	var water_h: Array = []
	var ground_tex: Array = []
	var ground_var: Array = []
	var cliff_var: Array = []
	var cliff_tex: Array = []
	var layers: Array = []
	var flags: Array = []
	heights.resize(n)
	water_h.resize(n)
	ground_tex.resize(n)
	ground_var.resize(n)
	cliff_var.resize(n)
	cliff_tex.resize(n)
	layers.resize(n)
	flags.resize(n)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(n):
		var h: float = base_h
		if random_h:
			h += rng.randf_range(-40.0, 40.0)
		heights[i] = h
		water_h[i] = h + water_extra if water_mode > 0 else h
		ground_tex[i] = tile_index
		ground_var[i] = Wc3TerrainAutotile.random_ground_variation(rng)
		cliff_var[i] = 0
		cliff_tex[i] = 0
		layers[i] = cliff_level
		flags[i] = FLAG_WATER if water_mode > 0 else 0

	hf = {
		"tilepointWidth": tp_w,
		"tilepointHeight": tp_h,
		"mapWidth": map_w,
		"mapHeight": map_h,
		"centerOffset": {"x": -half_x, "y": -half_y},
		"mainTileset": main_ts,
		"mainTilesetName": ts_name,
		"groundTilesets": ground,
		"cliffTilesets": cliffs,
		"tileSize": int(Wc3Coords.TILE_SIZE),
		"heights": heights,
		"groundTextures": ground_tex,
		"groundVariations": ground_var,
		"cliffVariations": cliff_var,
		"cliffTextures": cliff_tex,
		"layerHeights": layers,
		"waterHeights": water_h,
		"flagsPacked": flags,
	}
	info = {"name": "Untitled", "flags": {}}
	map_dir = ""
	source_name = "untitled"
	brush_tile_index = tile_index
	_dirty = true
	dirty_changed.emit(true)
	changed.emit()


## 将整格四角写成当前笔刷地表索引。tx/ty 为地形格（非 tilepoint）。
func paint_tile(tx: int, ty: int, tex_index: int = -1) -> bool:
	if is_empty():
		return false
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	if tx < 0 or ty < 0 or tx >= map_w or ty >= map_h:
		return false
	var changed_any: bool = false
	for c in [
		Vector2i(tx, ty),
		Vector2i(tx + 1, ty),
		Vector2i(tx, ty + 1),
		Vector2i(tx + 1, ty + 1),
	]:
		if paint_corner(c.x, c.y, tex_index):
			changed_any = true
	return changed_any


## 写单个中级栅格顶点（tilepoint）的地表索引。对齐 WE / HiveWE 角点笔刷。
func paint_corner(ix: int, iy: int, tex_index: int = -1) -> bool:
	if is_empty():
		return false
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return false
	var idx: int = tex_index if tex_index >= 0 else brush_tile_index
	var gs: Array = hf["groundTilesets"]
	if idx < 0 or idx >= gs.size():
		return false
	var ground: Array = hf["groundTextures"]
	var ground_var: Array = hf["groundVariations"]
	var i: int = iy * tp_w + ix
	if i < 0 or i >= ground.size():
		return false
	var changed_any: bool = false
	if int(ground[i]) != idx:
		ground[i] = idx
		changed_any = true
	if i < ground_var.size():
		ground_var[i] = Wc3TerrainAutotile.random_ground_variation()
		changed_any = true
	if changed_any:
		mark_dirty()
	return changed_any


## 悬崖笔刷：按 WorldEditData 工具 id 改 layerHeights / heights / 水 / 斜坡 / 悬崖类型。
## tool_id: "0".."4"（降两/降一/整平/升一/升两）| "ShallowWater" | "DeepWater" | "Ramp"
## level_layer: 整平目标层；<0 时用当前顶点层（无效果）。
func paint_cliff_corner(
	ix: int,
	iy: int,
	tool_id: String,
	cliff_type_idx: int = -1,
	level_layer: int = -1
) -> bool:
	if is_empty():
		return false
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return false
	var i: int = iy * tp_w + ix
	var layers: Array = hf.get("layerHeights", []) as Array
	var heights: Array = hf.get("heights", []) as Array
	var water_h: Array = hf.get("waterHeights", []) as Array
	var flags: Array = hf.get("flagsPacked", []) as Array
	var cliff_tex: Array = hf.get("cliffTextures", []) as Array
	var cliff_var: Array = hf.get("cliffVariations", []) as Array
	if i < 0 or i >= layers.size() or i >= heights.size() or i >= flags.size():
		return false

	var ctype: int = cliff_type_idx if cliff_type_idx >= 0 else brush_cliff_type
	var cts: Array = cliff_tilesets()
	if not cts.is_empty():
		ctype = clampi(ctype, 0, cts.size() - 1)

	var changed_any := false
	var propagate := -1
	var touched: Array = [] ## Vector2i：层高被改动的顶点，用于同步 cliff/ground 贴图
	match tool_id:
		"0":
			if _apply_layer_delta(i, layers, heights, water_h, -2):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = CliffPropagate.LOWER_HIGHER
		"1":
			if _apply_layer_delta(i, layers, heights, water_h, -1):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = CliffPropagate.LOWER_HIGHER
		"2":
			var target: int = level_layer if level_layer >= 0 else int(layers[i])
			if _set_layer(i, layers, heights, water_h, target):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = CliffPropagate.BOTH
		"3":
			if _apply_layer_delta(i, layers, heights, water_h, 1):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = CliffPropagate.RAISE_LOWER
		"4":
			if _apply_layer_delta(i, layers, heights, water_h, 2):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = CliffPropagate.RAISE_LOWER
		"ShallowWater":
			changed_any = _paint_water(i, heights, water_h, flags, WATER_SHALLOW_EXTRA) or changed_any
		"DeepWater":
			changed_any = _paint_water(i, heights, water_h, flags, WATER_DEEP_EXTRA) or changed_any
		"Ramp":
			# 斜坡走条带 API（R1–R5），不再单点 OR 旗
			return paint_ramp_at(ix, iy)
		_:
			return false

	if changed_any and propagate >= 0:
		var raised: Array = _propagate_cliff_adjacency(
			ix, iy, tp_w, tp_h, layers, heights, water_h, propagate
		)
		if not raised.is_empty():
			changed_any = true
			touched.append_array(raised)

	# 策略 B（异种崖折中）：
	# - 本笔种子角 ∪「至少含一个种子角的直崖格」四角 → 强制当前 ctype + groundTile（接触即同化）
	# - 不按 AABB 扫无关旧崖（远处隔离）；接触旧异种崖是「转换类型」，不是远程删除
	# - 蛋糕外扩仍可能改层高而抹平旧形（与 WE 一致）
	# 只写笔刷 2×2 时，外扩崖格 i00 仍是默认泥土崖 → _corner_texture 会强制 Ldrt 硬边。
	var ground_tex: Array = hf.get("groundTextures", []) as Array
	var ground_var: Array = hf.get("groundVariations", []) as Array
	var gti: int = _ground_index_for_cliff_type(ctype)
	if (not cts.is_empty() or gti >= 0) and (
		propagate >= 0 or tool_id in ["0", "1", "2", "3", "4"]
	):
		if _sync_cliff_corner_textures(
			ix, iy, tp_w, tp_h, layers, cliff_tex, cliff_var, ground_tex, ground_var, ctype, gti, touched
		):
			changed_any = true

	if changed_any:
		mark_dirty()
	return changed_any


## 在顶点附近找合格 1×2 / 2×1 崖边条带，写 RAMP 旗并修正中间层高（R5）。
## 非法（角柱、层差≠1、无直边）拒绝并写入 last_ramp_message。
func paint_ramp_at(ix: int, iy: int) -> bool:
	var r: Dictionary = try_paint_ramp_at(ix, iy)
	last_ramp_message = str(r.get("message", ""))
	return bool(r.get("changed", false))


## 返回 { ok, changed, message, axis, sx, sy }。ok=几何合法；changed=数据有改动。
func try_paint_ramp_at(ix: int, iy: int) -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "changed": false, "message": msg}
	if is_empty():
		return fail.call("地图为空")
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return fail.call("顶点越界")
	var layers: Array = hf.get("layerHeights", []) as Array
	var heights: Array = hf.get("heights", []) as Array
	var water_h: Array = hf.get("waterHeights", []) as Array
	var flags: Array = hf.get("flagsPacked", []) as Array
	if layers.is_empty() or flags.is_empty():
		return fail.call("缺少层高/旗数据")

	var found: Dictionary = _find_best_ramp_strip(ix, iy, layers, tp_w, tp_h)
	var best: Dictionary = found.get("spec", {}) as Dictionary
	var nearest_reject: String = str(found.get("reject", "附近没有层差为 1 的直线崖边"))

	if best.is_empty():
		return fail.call(nearest_reject)

	var resolved: Dictionary = _resolve_ramp_strip_flags(best, flags, tp_w)
	var changed := _apply_ramp_strip(resolved, layers, heights, water_h, flags, tp_w)
	if changed:
		mark_dirty()
		return {
			"ok": true,
			"changed": true,
			"message": "已刷斜坡 %s@(%d,%d)" % [str(resolved.get("axis", "")), int(resolved.get("sx", 0)), int(resolved.get("sy", 0))],
			"axis": resolved.get("axis", ""),
			"sx": int(resolved.get("sx", 0)),
			"sy": int(resolved.get("sy", 0)),
			"ramp_left": resolved.get("ramp_left", true),
			"ramp_bottom": resolved.get("ramp_bottom", true),
		}
	return {
		"ok": true,
		"changed": false,
		"message": "斜坡已存在",
		"axis": resolved.get("axis", ""),
		"sx": int(resolved.get("sx", 0)),
		"sy": int(resolved.get("sy", 0)),
	}


## 预览：光标将刷到的条带（已解析 L|R / 底顶旗向，与 apply 一致）。
func peek_ramp_strip_at(ix: int, iy: int) -> Dictionary:
	if is_empty():
		return {}
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return {}
	var layers: Array = hf.get("layerHeights", []) as Array
	var flags: Array = hf.get("flagsPacked", []) as Array
	var spec: Dictionary = _find_best_ramp_strip(ix, iy, layers, tp_w, tp_h).get("spec", {})
	if spec.is_empty():
		return {}
	return _resolve_ramp_strip_flags(spec, flags, tp_w)


## 与 _apply_ramp_strip 相同的旗向解析，供预览与落点对齐。
func _resolve_ramp_strip_flags(spec: Dictionary, flags: Array, tp_w: int) -> Dictionary:
	var out: Dictionary = spec.duplicate()
	var axis := str(out.get("axis", ""))
	var sx: int = int(out.get("sx", 0))
	var sy: int = int(out.get("sy", 0))
	if axis == "v":
		var prefer_left: bool = bool(out.get("ramp_left", true))
		out["ramp_left"] = _choose_vertical_ramp_left(sx, sy, flags, tp_w, prefer_left)
	elif axis == "h":
		var prefer_bottom: bool = bool(out.get("ramp_bottom", true))
		out["ramp_bottom"] = _choose_horizontal_ramp_bottom(sx, sy, flags, tp_w, prefer_bottom)
	return out


func _find_best_ramp_strip(
	ix: int, iy: int, layers: Array, tp_w: int, tp_h: int
) -> Dictionary:
	var flags: Array = hf.get("flagsPacked", []) as Array
	var best: Dictionary = {}
	# (already_complete, not_on_strip, flag_focus, neighbor_gap, face_pen)
	var best_score := Vector4(999999.0, 999999.0, 999999.0, 999999.0)
	var nearest_reject := "附近没有层差为 1 的直线崖边"
	for sy in range(iy - 2, iy + 1):
		for sx in range(ix - 1, ix + 1):
			var av: Dictionary = _analyze_vertical_ramp_strip(sx, sy, layers, tp_w, tp_h)
			if bool(av.get("ok", false)):
				var score := _ramp_strip_score(av, ix, iy, flags, tp_w)
				if _ramp_score_better(score, best_score):
					best_score = score
					best = av
			elif str(av.get("code", "")) != "":
				nearest_reject = str(av.get("message", nearest_reject))
	for sy2 in range(iy - 1, iy + 1):
		for sx2 in range(ix - 2, ix + 1):
			var ah: Dictionary = _analyze_horizontal_ramp_strip(sx2, sy2, layers, tp_w, tp_h)
			if bool(ah.get("ok", false)):
				var score_h := _ramp_strip_score(ah, ix, iy, flags, tp_w)
				if _ramp_score_better(score_h, best_score):
					best_score = score_h
					best = ah
			elif str(ah.get("code", "")) != "":
				nearest_reject = str(ah.get("message", nearest_reject))
	return {"spec": best, "reject": nearest_reject}


## 评分越小越好：
## ①已完整刷过的条带重罚（避免卡在「斜坡已存在」、跳过邻条）
## ②光标须在条带上
## ③优先「紧贴已有同向斜坡」(neighbor_gap==1)——宽2；避免崖沿横 face 抢走邻接竖条
## ④靠近将落 FLAG 的脊线列/行
## ⑤face 略劣于 slope
func _ramp_strip_score(
	spec: Dictionary, ix: int, iy: int, flags: Array, tp_w: int
) -> Vector4:
	var resolved: Dictionary = _resolve_ramp_strip_flags(spec, flags, tp_w)
	var sx: int = int(resolved.get("sx", 0))
	var sy: int = int(resolved.get("sy", 0))
	var axis := str(resolved.get("axis", "v"))
	var already := 1.0 if _ramp_strip_already_applied(resolved, flags, tp_w) else 0.0
	var on_strip := 0.0
	var flag_focus := 0.0
	if axis == "v":
		if ix < sx or ix > sx + 1 or iy < sy or iy > sy + 2:
			on_strip = 1.0
		var ramp_col: int = sx if bool(resolved.get("ramp_left", true)) else sx + 1
		var dx := float(ix) - float(ramp_col)
		var dy := float(iy) - (float(sy) + 1.0)
		flag_focus = dx * dx + dy * dy
	else:
		if ix < sx or ix > sx + 2 or iy < sy or iy > sy + 1:
			on_strip = 1.0
		var ramp_row: int = sy if bool(resolved.get("ramp_bottom", true)) else sy + 1
		var dxh := float(ix) - (float(sx) + 1.0)
		var dyh := float(iy) - float(ramp_row)
		flag_focus = dxh * dxh + dyh * dyh
	var neighbor_gap := _ramp_neighbor_gap(resolved, flags, tp_w)
	# 仅当光标落在「紧邻已有脊的那一列/行」时才优先续宽；
	# 点在隔一列（想刷独立 U 凹）时不得抢成连续 111|111。
	var extends_pen := 1.0
	if neighbor_gap <= 1.01:
		if axis == "v":
			var ramp_col: int = sx if bool(resolved.get("ramp_left", true)) else sx + 1
			var touches_existing := (
				(ramp_col > 0 and _vert_col_all(flags, tp_w, ramp_col - 1, sy, true))
				or _vert_col_all(flags, tp_w, ramp_col + 1, sy, true)
			)
			if touches_existing and ix == ramp_col:
				extends_pen = 0.0
		else:
			var ramp_row: int = sy if bool(resolved.get("ramp_bottom", true)) else sy + 1
			var touches_h := (
				(ramp_row > 0 and _horiz_row_all(flags, tp_w, sx, ramp_row - 1, true))
				or _horiz_row_all(flags, tp_w, sx, ramp_row + 1, true)
			)
			if touches_h and iy == ramp_row:
				extends_pen = 0.0
	# U 凹中间列/行：光标落在两脊之间的空列 → 强制优先同向条带填实；
	# 否则崖沿横 face 会抢走落点并清掉竖脊旗。
	if axis == "v" and ix > 0:
		if (
			not _vert_col_all(flags, tp_w, ix, sy, true)
			and _vert_col_all(flags, tp_w, ix - 1, sy, true)
			and _vert_col_all(flags, tp_w, ix + 1, sy, true)
			and (ix == sx or ix == sx + 1)
		):
			var fill_left := ix == sx
			if bool(resolved.get("ramp_left", true)) == fill_left:
				already = 0.0
				on_strip = 0.0
				extends_pen = 0.0
				flag_focus = 0.0
	elif axis == "h" and iy > 0:
		if (
			not _horiz_row_all(flags, tp_w, sx, iy, true)
			and _horiz_row_all(flags, tp_w, sx, iy - 1, true)
			and _horiz_row_all(flags, tp_w, sx, iy + 1, true)
			and (iy == sy or iy == sy + 1)
		):
			var fill_bottom := iy == sy
			if bool(resolved.get("ramp_bottom", true)) == fill_bottom:
				already = 0.0
				on_strip = 0.0
				extends_pen = 0.0
				flag_focus = 0.0
	# 同分时略优先 slope（沿坡续刷）；但光标若在 face 高侧崖壁上则拉近该 face
	var kind_pen := 0.0 if str(spec.get("kind", "")) == "slope" else 0.01
	if str(spec.get("kind", "")) == "face":
		if axis == "v":
			var high_col: int = sx + 1 if bool(resolved.get("ramp_left", true)) else sx
			if ix == high_col:
				flag_focus = maxf(0.0, flag_focus - 1.0)
				kind_pen = 0.0
		else:
			var high_row: int = sy + 1 if bool(resolved.get("ramp_bottom", true)) else sy
			if iy == high_row:
				flag_focus = maxf(0.0, flag_focus - 1.0)
				kind_pen = 0.0
	return Vector4(already, on_strip, extends_pen, flag_focus + kind_pen)


func _ramp_strip_already_applied(spec: Dictionary, flags: Array, tp_w: int) -> bool:
	var axis := str(spec.get("axis", ""))
	var sx: int = int(spec.get("sx", 0))
	var sy: int = int(spec.get("sy", 0))
	if axis == "v":
		var rl: bool = bool(spec.get("ramp_left", true))
		return _vert_col_all(flags, tp_w, sx, sy, rl) and _vert_col_all(flags, tp_w, sx + 1, sy, not rl)
	if axis == "h":
		var rb: bool = bool(spec.get("ramp_bottom", true))
		return (
			_horiz_row_all(flags, tp_w, sx, sy, rb)
			and _horiz_row_all(flags, tp_w, sx, sy + 1, not rb)
		)
	return false


## 到最近已有脊列/行的距离；邻列差=1 → WE 宽 2。
func _ramp_neighbor_gap(spec: Dictionary, flags: Array, tp_w: int) -> float:
	var axis := str(spec.get("axis", ""))
	var sx: int = int(spec.get("sx", 0))
	var sy: int = int(spec.get("sy", 0))
	var best_gap := 100.0
	if axis == "v":
		for dcol in [-1, 1]:
			var ncol: int = sx + dcol
			if ncol < 0:
				continue
			# 邻列整列是脊，或邻条已刷满
			if _vert_col_all(flags, tp_w, ncol, sy, true):
				best_gap = mini(best_gap, 1.0)
			var left_ok := (
				_vert_col_all(flags, tp_w, ncol, sy, true)
				and _vert_col_all(flags, tp_w, ncol + 1, sy, false)
			)
			var right_ok := (
				_vert_col_all(flags, tp_w, ncol, sy, false)
				and _vert_col_all(flags, tp_w, ncol + 1, sy, true)
			)
			if left_ok or right_ok:
				best_gap = mini(best_gap, float(absi(dcol)))
	else:
		for drow in [-1, 1]:
			var nrow: int = sy + drow
			if nrow < 0:
				continue
			if _horiz_row_all(flags, tp_w, sx, nrow, true):
				best_gap = mini(best_gap, 1.0)
	return best_gap


static func _ramp_score_better(score: Vector4, best: Vector4) -> bool:
	if score.x < best.x - 0.0001:
		return true
	if score.x > best.x + 0.0001:
		return false
	if score.y < best.y - 0.0001:
		return true
	if score.y > best.y + 0.0001:
		return false
	if score.z < best.z - 0.0001:
		return true
	if score.z > best.z + 0.0001:
		return false
	return score.w < best.w - 0.0001


## 竖 1×2：直线崖边（列等高且列差=1）或沿坡（行两端差=1、中间=min）。
func _analyze_vertical_ramp_strip(
	sx: int, sy: int, layers: Array, tp_w: int, tp_h: int
) -> Dictionary:
	if sx < 0 or sy < 0 or sx + 1 >= tp_w or sy + 2 >= tp_h:
		return {"ok": false}
	var bl := int(layers[sy * tp_w + sx])
	var br := int(layers[sy * tp_w + sx + 1])
	var tl := int(layers[(sy + 1) * tp_w + sx])
	var tr := int(layers[(sy + 1) * tp_w + sx + 1])
	var ttl := int(layers[(sy + 2) * tp_w + sx])
	var ttr := int(layers[(sy + 2) * tp_w + sx + 1])

	# 直崖面（南北走向崖）：左右列各自等高，列差必须为 1
	if bl == ttl and br == ttr:
		var d: int = absi(bl - br)
		if d == 0:
			return {"ok": false, "code": "flat", "message": "无崖边（两侧同高）"}
		if d != 1:
			return {
				"ok": false,
				"code": "delta",
				"message": "层差必须为 1（当前 %d）" % d,
			}
		# 中间若已偏离列高，仍可刷（R5 会修）
		return {
			"ok": true,
			"axis": "v",
			"sx": sx,
			"sy": sy,
			"kind": "face",
			"ramp_left": bl < br,
			"mid_l": bl,
			"mid_r": br,
		}

	# 沿坡（南北高差）：南行/北行各自同高，行差=1；禁止列内折角
	if bl == br and ttl == ttr:
		var ds: int = absi(bl - ttl)
		if ds == 0:
			return {"ok": false}
		if ds != 1:
			return {
				"ok": false,
				"code": "delta",
				"message": "层差必须为 1（当前 %d）" % ds,
			}
		var mid := mini(bl, ttl)
		var hi := maxi(bl, ttl)
		# 中间已在高台：再刷会把台面削成低台，破坏对侧已有坡 / 直崖（BUG 源）
		if tl == hi and tr == hi:
			return {
				"ok": false,
				"code": "carve",
				"message": "高台侧会削切台面，请从低处入口刷斜坡",
			}
		return {
			"ok": true,
			"axis": "v",
			"sx": sx,
			"sy": sy,
			"kind": "slope",
			"ramp_left": true, # apply 时按邻接 L|R 重选
			"mid_l": mid,
			"mid_r": mid,
		}

	# 近直边但列不齐 → 角柱/碎折
	if absi(bl - br) >= 1 or absi(ttl - ttr) >= 1 or absi(bl - ttl) >= 1 or absi(br - ttr) >= 1:
		if bl != ttl or br != ttr:
			return {"ok": false, "code": "corner", "message": "角柱/碎折边，不能刷斜坡"}
	return {"ok": false}


## 横 2×1：直线崖边（行等高且行差=1）或沿坡（列两端差=1、中间=min）。
func _analyze_horizontal_ramp_strip(
	sx: int, sy: int, layers: Array, tp_w: int, tp_h: int
) -> Dictionary:
	if sx < 0 or sy < 0 or sx + 2 >= tp_w or sy + 1 >= tp_h:
		return {"ok": false}
	var bl := int(layers[sy * tp_w + sx])
	var br := int(layers[sy * tp_w + sx + 1])
	var brr := int(layers[sy * tp_w + sx + 2])
	var tl := int(layers[(sy + 1) * tp_w + sx])
	var tr := int(layers[(sy + 1) * tp_w + sx + 1])
	var trr := int(layers[(sy + 1) * tp_w + sx + 2])

	# 直崖面（东西走向崖）：上下行各自等高，行差=1
	if bl == br and br == brr and tl == tr and tr == trr:
		var d: int = absi(bl - tl)
		if d == 0:
			return {"ok": false, "code": "flat", "message": "无崖边（两侧同高）"}
		if d != 1:
			return {
				"ok": false,
				"code": "delta",
				"message": "层差必须为 1（当前 %d）" % d,
			}
		return {
			"ok": true,
			"axis": "h",
			"sx": sx,
			"sy": sy,
			"kind": "face",
			"ramp_bottom": bl < tl,
			"mid_b": bl,
			"mid_t": tl,
		}

	# 沿坡（东西高差）
	if bl == tl and brr == trr:
		var ds: int = absi(bl - brr)
		if ds == 0:
			return {"ok": false}
		if ds != 1:
			return {
				"ok": false,
				"code": "delta",
				"message": "层差必须为 1（当前 %d）" % ds,
			}
		var mid := mini(bl, brr)
		var hi := maxi(bl, brr)
		# 中间列已在高台：禁止削切
		if br == hi and tr == hi:
			return {
				"ok": false,
				"code": "carve",
				"message": "高台侧会削切台面，请从低处入口刷斜坡",
			}
		return {
			"ok": true,
			"axis": "h",
			"sx": sx,
			"sy": sy,
			"kind": "slope",
			"ramp_bottom": true, # apply 时按邻接重选
			"mid_b": mid,
			"mid_t": mid,
		}

	if absi(bl - tl) >= 1 or absi(brr - trr) >= 1 or absi(bl - brr) >= 1:
		if not (bl == br and br == brr and tl == tr and tr == trr):
			return {"ok": false, "code": "corner", "message": "角柱/碎折边，不能刷斜坡"}
	return {"ok": false}


func _apply_ramp_strip(
	spec: Dictionary,
	layers: Array,
	heights: Array,
	water_h: Array,
	flags: Array,
	tp_w: int
) -> bool:
	var axis := str(spec.get("axis", ""))
	var sx: int = int(spec.get("sx", 0))
	var sy: int = int(spec.get("sy", 0))
	var changed := false
	if axis == "v":
		var mid_l: int = int(spec.get("mid_l", 0))
		var mid_r: int = int(spec.get("mid_r", 0))
		var i_tl: int = (sy + 1) * tp_w + sx
		var i_tr: int = i_tl + 1
		if _set_layer(i_tl, layers, heights, water_h, mid_l):
			changed = true
		if _set_layer(i_tr, layers, heights, water_h, mid_r):
			changed = true
		# 旗向已定稿。宽2=相邻列菱形(111|111)；勿清掉已是完整脊的邻列
		var ramp_left: bool = bool(spec.get("ramp_left", true))
		for yy in range(sy, sy + 3):
			if ramp_left:
				if _set_ramp_flag(flags, yy * tp_w + sx, true):
					changed = true
			else:
				if _set_ramp_flag(flags, yy * tp_w + sx + 1, true):
					changed = true
		if ramp_left:
			if not _vert_col_all(flags, tp_w, sx + 1, sy, true):
				for yy2 in range(sy, sy + 3):
					if _set_ramp_flag(flags, yy2 * tp_w + sx + 1, false):
						changed = true
		else:
			if not _vert_col_all(flags, tp_w, sx, sy, true):
				for yy3 in range(sy, sy + 3):
					if _set_ramp_flag(flags, yy3 * tp_w + sx, false):
						changed = true
	elif axis == "h":
		var mid_b: int = int(spec.get("mid_b", 0))
		var mid_t: int = int(spec.get("mid_t", 0))
		var i_br: int = sy * tp_w + sx + 1
		var i_tr2: int = (sy + 1) * tp_w + sx + 1
		if _set_layer(i_br, layers, heights, water_h, mid_b):
			changed = true
		if _set_layer(i_tr2, layers, heights, water_h, mid_t):
			changed = true
		var ramp_bottom: bool = bool(spec.get("ramp_bottom", true))
		for xx in range(sx, sx + 3):
			if ramp_bottom:
				if _set_ramp_flag(flags, sy * tp_w + xx, true):
					changed = true
			else:
				if _set_ramp_flag(flags, (sy + 1) * tp_w + xx, true):
					changed = true
		if ramp_bottom:
			if not _horiz_row_all(flags, tp_w, sx, sy + 1, true):
				for xx2 in range(sx, sx + 3):
					if _set_ramp_flag(flags, (sy + 1) * tp_w + xx2, false):
						changed = true
		else:
			if not _horiz_row_all(flags, tp_w, sx, sy, true):
				for xx3 in range(sx, sx + 3):
					if _set_ramp_flag(flags, sy * tp_w + xx3, false):
						changed = true
	return changed


## 西/东邻已是脊时：仅当本条左列/右列是「紧邻续刷」才同向延伸。
## 隔列点击（中间空列）保持 prefer，以便刷出独立 U 凹（111|000|111）。
## 左右皆脊且本左列空：填 U 凹中间 → 连续宽坡（须先于「右脊已存在」分支）。
func _choose_vertical_ramp_left(
	sx: int, sy: int, flags: Array, tp_w: int, prefer_left: bool
) -> bool:
	if _vert_col_all(flags, tp_w, sx, sy, true) and _vert_col_all(flags, tp_w, sx + 1, sy, false):
		return true
	# U 凹中间：左列空、左右邻列皆脊 → 填左列（不可走「右脊已在」返回 false）
	if (
		sx > 0
		and not _vert_col_all(flags, tp_w, sx, sy, true)
		and _vert_col_all(flags, tp_w, sx - 1, sy, true)
		and _vert_col_all(flags, tp_w, sx + 1, sy, true)
	):
		return true
	if _vert_col_all(flags, tp_w, sx + 1, sy, true) and _vert_col_all(flags, tp_w, sx, sy, false):
		return false
	# 西邻已是脊且本左列尚未成脊 → 续宽（111|111）
	if sx > 0 and _vert_col_all(flags, tp_w, sx - 1, sy, true) and not _vert_col_all(flags, tp_w, sx, sy, true):
		return true
	# 东邻已是脊且本左列空 → 向西续宽（填左列）
	if _vert_col_all(flags, tp_w, sx + 1, sy, true) and not _vert_col_all(flags, tp_w, sx, sy, true):
		return true
	return prefer_left


func _choose_horizontal_ramp_bottom(
	sx: int, sy: int, flags: Array, tp_w: int, prefer_bottom: bool
) -> bool:
	if _horiz_row_all(flags, tp_w, sx, sy, true) and _horiz_row_all(flags, tp_w, sx, sy + 1, false):
		return true
	if (
		sy > 0
		and not _horiz_row_all(flags, tp_w, sx, sy, true)
		and _horiz_row_all(flags, tp_w, sx, sy - 1, true)
		and _horiz_row_all(flags, tp_w, sx, sy + 1, true)
	):
		return true
	if _horiz_row_all(flags, tp_w, sx, sy + 1, true) and _horiz_row_all(flags, tp_w, sx, sy, false):
		return false
	if sy > 0 and _horiz_row_all(flags, tp_w, sx, sy - 1, true) and not _horiz_row_all(flags, tp_w, sx, sy, true):
		return true
	if _horiz_row_all(flags, tp_w, sx, sy + 1, true) and not _horiz_row_all(flags, tp_w, sx, sy, true):
		return true
	return prefer_bottom


func _vert_col_all(flags: Array, tp_w: int, ix: int, sy: int, want_ramp: bool) -> bool:
	for yy in range(sy, sy + 3):
		var i: int = yy * tp_w + ix
		if i < 0 or i >= flags.size():
			return false
		var is_r: bool = (int(flags[i]) & FLAG_RAMP) != 0
		if is_r != want_ramp:
			return false
	return true


func _horiz_row_all(flags: Array, tp_w: int, sx: int, iy: int, want_ramp: bool) -> bool:
	for xx in range(sx, sx + 3):
		var i: int = iy * tp_w + xx
		if i < 0 or i >= flags.size():
			return false
		var is_r: bool = (int(flags[i]) & FLAG_RAMP) != 0
		if is_r != want_ramp:
			return false
	return true


func _set_ramp_flag(flags: Array, i: int, want_ramp: bool) -> bool:
	if i < 0 or i >= flags.size():
		return false
	var fl: int = int(flags[i])
	var nf: int = (fl | FLAG_RAMP) if want_ramp else (fl & ~FLAG_RAMP)
	# 斜坡与水面互斥（与 _paint_water 对称）
	if want_ramp:
		nf = nf & ~FLAG_WATER
	if nf == fl:
		return false
	flags[i] = nf
	return true


## 策略 B：同步与落笔/层高变更相关的直崖格四角（cliffTextures + groundTile）。
## 种子 = touched ∪ 落笔 2×2；再并入「至少含一个种子角」的直崖格之四角（整格同化，避免混角）。
## 禁止用 AABB 扫区域内所有直崖（会误改邻近另一座未触及的悬崖）。
func _sync_cliff_corner_textures(
	ix: int,
	iy: int,
	tp_w: int,
	tp_h: int,
	layers: Array,
	cliff_tex: Array,
	cliff_var: Array,
	ground_tex: Array,
	ground_var: Array,
	ctype: int,
	gti: int,
	touched: Array
) -> bool:
	var seed: Dictionary = {}
	for p in touched:
		seed[Vector2i(int(p.x), int(p.y))] = true
	# 落笔点邻域（整平未改层时仍要刷类型/地表）
	for oy in range(-1, 1):
		for ox in range(-1, 1):
			seed[Vector2i(ix + ox, iy + oy)] = true

	var corner_pts: Dictionary = {}
	for key in seed.keys():
		var p: Vector2i = key
		corner_pts[p] = true
		# 以该角为顶点的最多 4 个地表格：若是直崖则并入其四角
		for oy in range(-1, 1):
			for ox in range(-1, 1):
				var tx: int = p.x + ox
				var ty: int = p.y + oy
				if tx < 0 or ty < 0 or tx >= tp_w - 1 or ty >= tp_h - 1:
					continue
				if not Wc3CliffTiles.is_cliff_tile(layers, tp_w, tx, ty):
					continue
				for cy in range(0, 2):
					for cx in range(0, 2):
						corner_pts[Vector2i(tx + cx, ty + cy)] = true

	var any := false
	for key2 in corner_pts.keys():
		var q: Vector2i = key2
		if q.x < 0 or q.y < 0 or q.x >= tp_w or q.y >= tp_h:
			continue
		var ci: int = q.y * tp_w + q.x
		if ctype >= 0 and ci < cliff_tex.size():
			var prev_tex: int = int(cliff_tex[ci])
			if prev_tex != ctype:
				cliff_tex[ci] = ctype
				any = true
			# 类型变化时随机变体；同类型但变体为 0 时写 1..max 避免整墙同模
			if ci < cliff_var.size():
				if prev_tex != ctype:
					cliff_var[ci] = (randi() % 3) + 1
					any = true
				elif int(cliff_var[ci]) == 0:
					cliff_var[ci] = (absi(ci * 2654435761) % 3) + 1
					any = true
		if gti >= 0 and ci < ground_tex.size() and int(ground_tex[ci]) != gti:
			ground_tex[ci] = gti
			any = true
			if ci < ground_var.size():
				ground_var[ci] = Wc3TerrainAutotile.random_ground_variation()
	return any


func _apply_layer_delta(
	i: int, layers: Array, heights: Array, water_h: Array, delta: int
) -> bool:
	return _set_layer(i, layers, heights, water_h, int(layers[i]) + delta)


## 返回 cliffTilesets[ctype] 对应的 groundTilesets 下标；找不到则 -1。
func _ground_index_for_cliff_type(ctype: int) -> int:
	var cts: Array = cliff_tilesets()
	var gs: Array = ground_tilesets()
	if ctype < 0 or ctype >= cts.size() or gs.is_empty():
		return -1
	if _cliff_ground_cache.size() != cts.size():
		_cliff_ground_cache = PackedInt32Array()
		_cliff_ground_cache.resize(cts.size())
		_cliff_ground_cache.fill(-2) # -2=未缓存
	if _cliff_ground_cache[ctype] != -2:
		return _cliff_ground_cache[ctype]
	var tiles := Wc3TerrainTiles.new()
	tiles.load_default()
	var ground_id := tiles.ground_tile_for_cliff_id(str(cts[ctype]))
	var found := -1
	if not ground_id.is_empty():
		for gi in range(gs.size()):
			if str(gs[gi]) == ground_id:
				found = gi
				break
	_cliff_ground_cache[ctype] = found
	return found


## WE：相邻顶点层差不得超过 2，且每个地表格四角跨度 ≤2。
## 升崖：过低点抬到 high−2（蛋糕外扩）；降崖：过高点压到 low+2。BFS 扩散。
## 返回本次被改层高的顶点列表。
func _propagate_cliff_adjacency(
	ix: int,
	iy: int,
	tp_w: int,
	tp_h: int,
	layers: Array,
	heights: Array,
	water_h: Array,
	mode: int
) -> Array:
	var queue: Array = [Vector2i(ix, iy)]
	var changed_pts: Array = []
	var guard := 0
	var guard_max: int = tp_w * tp_h * 16
	var dirs: Array = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	while not queue.is_empty() and guard < guard_max:
		guard += 1
		var p: Vector2i = queue.pop_front()
		var i: int = p.y * tp_w + p.x
		if i < 0 or i >= layers.size():
			continue
		var lv: int = int(layers[i])
		for d in dirs:
			var nx: int = p.x + int(d.x)
			var ny: int = p.y + int(d.y)
			if nx < 0 or ny < 0 or nx >= tp_w or ny >= tp_h:
				continue
			var ni: int = ny * tp_w + nx
			if ni < 0 or ni >= layers.size():
				continue
			var ln: int = int(layers[ni])
			var did := false
			if mode != CliffPropagate.LOWER_HIGHER and lv > ln + MAX_CLIFF_ADJ_DELTA:
				did = _set_layer(ni, layers, heights, water_h, lv - MAX_CLIFF_ADJ_DELTA)
			elif mode != CliffPropagate.RAISE_LOWER and ln > lv + MAX_CLIFF_ADJ_DELTA:
				did = _set_layer(ni, layers, heights, water_h, lv + MAX_CLIFF_ADJ_DELTA)
			if did:
				var np := Vector2i(nx, ny)
				changed_pts.append(np)
				queue.append(np)
		# 以本顶点为角的最多 4 个地表格：强制四角 max−min ≤ 2（补上对角约束）
		_enforce_tile_spans_at(
			p.x, p.y, tp_w, tp_h, layers, heights, water_h, mode, queue, changed_pts
		)
	return changed_pts


## 检查以 (vx,vy) 为角的地表格；若跨度 >2 则按 mode 抬低/压高角点，变更入队。
func _enforce_tile_spans_at(
	vx: int,
	vy: int,
	tp_w: int,
	tp_h: int,
	layers: Array,
	heights: Array,
	water_h: Array,
	mode: int,
	queue: Array,
	changed_pts: Array
) -> void:
	for oy in range(-1, 1):
		for ox in range(-1, 1):
			var tx: int = vx + ox
			var ty: int = vy + oy
			if tx < 0 or ty < 0 or tx >= tp_w - 1 or ty >= tp_h - 1:
				continue
			var i00: int = ty * tp_w + tx
			var i10: int = i00 + 1
			var i01: int = i00 + tp_w
			var i11: int = i01 + 1
			var c0: int = int(layers[i00])
			var c1: int = int(layers[i10])
			var c2: int = int(layers[i01])
			var c3: int = int(layers[i11])
			var lo: int = mini(mini(c0, c1), mini(c2, c3))
			var hi: int = maxi(maxi(c0, c1), maxi(c2, c3))
			if hi - lo <= MAX_CLIFF_ADJ_DELTA:
				continue
			var corners: Array = [
				Vector2i(tx, ty),
				Vector2i(tx + 1, ty),
				Vector2i(tx, ty + 1),
				Vector2i(tx + 1, ty + 1),
			]
			var floor_l: int = hi - MAX_CLIFF_ADJ_DELTA
			var ceil_l: int = lo + MAX_CLIFF_ADJ_DELTA
			for c in corners:
				var ci: int = int(c.y) * tp_w + int(c.x)
				var lv: int = int(layers[ci])
				var did := false
				if mode != CliffPropagate.LOWER_HIGHER and lv < floor_l:
					did = _set_layer(ci, layers, heights, water_h, floor_l)
				elif mode != CliffPropagate.RAISE_LOWER and lv > ceil_l:
					did = _set_layer(ci, layers, heights, water_h, ceil_l)
				if did:
					changed_pts.append(c)
					queue.append(c)


func _set_layer(
	i: int, layers: Array, heights: Array, water_h: Array, new_layer: int
) -> bool:
	var clamped: int = clampi(new_layer, LAYER_MIN, LAYER_MAX)
	var old_layer: int = int(layers[i])
	if clamped == old_layer:
		return false
	var dh: float = float(clamped - old_layer) * LAYER_HEIGHT_STEP
	layers[i] = clamped
	heights[i] = float(heights[i]) + dh
	if i < water_h.size():
		water_h[i] = float(water_h[i]) + dh
	return true


func _paint_water(
	i: int, heights: Array, water_h: Array, flags: Array, water_extra: float
) -> bool:
	var did := false
	var fl: int = int(flags[i])
	var nf: int = (fl | FLAG_WATER) & ~FLAG_RAMP
	if nf != fl:
		flags[i] = nf
		did = true
	var target_w: float = float(heights[i]) + water_extra
	if i < water_h.size() and not is_equal_approx(float(water_h[i]), target_w):
		water_h[i] = target_w
		did = true
	return did


func sample_height_at_tile(tx: int, ty: int) -> float:
	if is_empty():
		return 0.0
	var tp_w: int = int(hf["tilepointWidth"])
	var heights: Array = hf["heights"]
	var sum: float = 0.0
	var n: int = 0
	for c in [
		ty * tp_w + tx,
		ty * tp_w + tx + 1,
		(ty + 1) * tp_w + tx,
		(ty + 1) * tp_w + tx + 1,
	]:
		if c >= 0 and c < heights.size():
			sum += float(heights[c])
			n += 1
	return sum / float(n) if n > 0 else 0.0


func world_godot_to_tile(godot_pos: Vector3) -> Vector2i:
	var ws: float = Wc3Coords.WORLD_SCALE
	var center: Vector2 = center_offset()
	var ts: float = tile_size()
	var wc3_x: float = godot_pos.x / ws
	var wc3_y: float = -godot_pos.z / ws
	var tx: int = int(floor((wc3_x - center.x) / ts))
	var ty: int = int(floor((wc3_y - center.y) / ts))
	return Vector2i(tx, ty)


## 吸附到最近的中级栅格顶点（tilepoint），对齐经典 WE。
func world_godot_to_tilepoint(godot_pos: Vector3) -> Vector2i:
	var ws: float = Wc3Coords.WORLD_SCALE
	var center: Vector2 = center_offset()
	var ts: float = tile_size()
	if ts <= 0.0:
		return Vector2i.ZERO
	var wc3_x: float = godot_pos.x / ws
	var wc3_y: float = -godot_pos.z / ws
	var ix: int = int(round((wc3_x - center.x) / ts))
	var iy: int = int(round((wc3_y - center.y) / ts))
	return Vector2i(ix, iy)


## 双线性采样高度（tilepoint 连续坐标）。
func sample_height_at_xy(fx: float, fy: float) -> float:
	if is_empty():
		return 0.0
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	var heights: Array = hf["heights"]
	var x0: int = int(floor(fx))
	var y0: int = int(floor(fy))
	var x1: int = x0 + 1
	var y1: int = y0 + 1
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)

	var h00 := _corner_height_clamped(x0, y0, tp_w, tp_h, heights)
	var h10 := _corner_height_clamped(x1, y0, tp_w, tp_h, heights)
	var h01 := _corner_height_clamped(x0, y1, tp_w, tp_h, heights)
	var h11 := _corner_height_clamped(x1, y1, tp_w, tp_h, heights)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty)


func _corner_height_clamped(ix: int, iy: int, tp_w: int, tp_h: int, heights: Array) -> float:
	var cx: int = clampi(ix, 0, tp_w - 1)
	var cy: int = clampi(iy, 0, tp_h - 1)
	var i: int = cy * tp_w + cx
	if i < 0 or i >= heights.size():
		return 0.0
	return float(heights[i])


func save_json(path: String = "") -> Error:
	if is_empty():
		return ERR_INVALID_DATA
	var out_path: String = path
	if out_path.is_empty():
		var dir: String = "user://editor_maps"
		var abs_dir: String = ProjectSettings.globalize_path(dir)
		DirAccess.make_dir_recursive_absolute(abs_dir)
		var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
		out_path = dir.path_join("%s_%s.json" % [source_name if not source_name.is_empty() else "map", stamp])
	else:
		var parent: String = out_path.get_base_dir()
		if not parent.is_empty():
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("MapDocument: cannot write %s (err=%s)" % [out_path, FileAccess.get_open_error()])
		return ERR_CANT_CREATE
	f.store_string(JSON.stringify(hf, "\t"))
	clear_dirty()
	print("MapDocument: saved %s" % out_path)
	return OK
