extends RefCounted

## 可编辑地图文档：权威数据为 Wc3Heightfield。
## （不用 class_name；编辑器通过 preload 引用）

signal changed
signal dirty_changed(is_dirty: bool)

const _PathingMapScript := preload("res://scripts/map/data/wc3_pathing_map.gd")

const DEFAULT_MAP_DIR := "res://assets/map-parsed/losttemple"
const PARSED_MAPS_ROOT := "res://assets/map-parsed"
const BLANK_TILEPOINTS := 33 ## → 32×32 格
const DEFAULT_TILESET := "I"
const DEFAULT_TILESET_NAME := "Icecrown"
const DEFAULT_GROUND := ["Idrt", "Idtr", "Idki", "Ibkb", "Irbk", "Itbk", "Iice", "Ibsq", "Isnw"]
const DEFAULT_CLIFF := ["CIsn", "CIrb"]
## layerHeight=2 时 groundHeightRaw=0x2000 → 高度 0
const FLAT_HEIGHT := 0.0
const FLAT_LAYER := 2
const FLAG_WATER := Wc3Coords.FLAG_WATER

## 权威地形 SoA
var heightfield: Wc3Heightfield = null
## 高度图 / 地表逻辑（绑定 heightfield）
var terrain: Wc3TerrainLogic = Wc3TerrainLogic.new()
## 悬崖逻辑（蛋糕 / 策略 B / 层高）
var cliff: Wc3CliffLogic = Wc3CliffLogic.new()
## 斜坡逻辑（HiveWE：只写 FLAG_RAMP）
var ramp: Wc3RampLogic = Wc3RampLogic.new()
var info: Dictionary = {}
var map_dir: String = ""
var source_name: String = ""
var brush_tile_index: int = 0
var brush_cliff_type: int = 0
## 装饰物 / 单位权威（内存 SoA；存盘 to_dict → AoS JSON）
var doodads: Wc3DoodadList = Wc3DoodadList.new()
var units: Wc3UnitList = Wc3UnitList.new()
## 寻路面（WPM / 合成）；放置校验与 View→路径-地面
var pathing = null
var _next_creation_number: int = 1
var _next_unit_creation_number: int = 1
var _dirty: bool = false
## 最近一次斜坡笔刷结果（状态栏 / 自测）
var last_ramp_message: String = ""


## 扫描 `assets/map-parsed/<slug>/`，返回可打开条目（含 heightfield 的目录）。
## 每项：`{ dir, slug, name, detail }`；`detail` 为尺寸 / 推荐人数摘要。
static func list_parsed_maps() -> Array:
	var out: Array = []
	var da := DirAccess.open(PARSED_MAPS_ROOT)
	if da == null:
		return out
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if not entry.begins_with(".") and da.current_is_dir():
			var dir_path: String = PARSED_MAPS_ROOT.path_join(entry)
			var hf_path: String = dir_path.path_join("terrain-heightfield.json")
			if FileAccess.file_exists(hf_path):
				out.append(_parsed_map_entry(dir_path, entry))
		entry = da.get_next()
	da.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)
	return out


static func _parsed_map_entry(dir_path: String, slug: String) -> Dictionary:
	var display_name := slug
	var detail := ""
	var sum_path: String = dir_path.path_join("summary.json")
	if FileAccess.file_exists(sum_path):
		var f: FileAccess = FileAccess.open(sum_path, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var root: Dictionary = parsed
				var map_info: Dictionary = root.get("map", {}) as Dictionary
				if not map_info.is_empty():
					var n := str(map_info.get("name", "")).strip_edges()
					if not n.is_empty():
						display_name = n
					var pw := int(map_info.get("playableWidth", 0))
					var ph := int(map_info.get("playableHeight", 0))
					var players := str(map_info.get("recommendedPlayers", "")).strip_edges()
					var bits: PackedStringArray = PackedStringArray()
					if pw > 0 and ph > 0:
						bits.append("%d×%d" % [pw, ph])
					if not players.is_empty():
						bits.append(players)
					detail = " · ".join(bits)
				elif str(root.get("slug", "")).is_empty() == false:
					display_name = str(root.get("slug"))
	if detail.is_empty():
		detail = slug
	return {
		"dir": dir_path,
		"slug": slug,
		"name": display_name,
		"detail": detail,
	}


## Present / rebuild 过渡：共享数组的 JSON 形视图。Layer 全面吃 Heightfield 后删除。
func as_build_dict() -> Dictionary:
	if heightfield == null:
		return {}
	return heightfield.as_dict_view()


func _rebind_logic() -> void:
	terrain.bind(heightfield)
	cliff.bind(heightfield)
	cliff.ensure_catalog()
	cliff.clear_ground_tile_cache()
	ramp.bind(heightfield, cliff)


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
	return heightfield == null or heightfield.width < 2


func tilepoint_size() -> Vector2i:
	if heightfield == null:
		return Vector2i.ZERO
	return Vector2i(heightfield.width, heightfield.height)


func map_size() -> Vector2i:
	if heightfield == null:
		return Vector2i.ZERO
	return Vector2i(heightfield.map_width, heightfield.map_height)


func center_offset() -> Vector2:
	if heightfield == null:
		return Vector2.ZERO
	return heightfield.center_offset


func tile_size() -> float:
	if heightfield == null:
		return Wc3Coords.TILE_SIZE
	return heightfield.tile_size


func ground_tilesets() -> Array:
	if heightfield == null:
		return []
	return heightfield.ground_tilesets


func cliff_tilesets() -> Array:
	if heightfield == null:
		return []
	return heightfield.cliff_tilesets


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
	return terrain.layer_at(ix, iy)


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
	heightfield = Wc3Heightfield.from_dict(parsed as Dictionary, false)
	_rebind_logic()
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
	_load_doodads_from_map_dir(path)
	_load_units_from_map_dir(path)
	_load_pathing_from_map_dir(path)
	# 已解析图若 flags 未含 MAP_EDGE，用 info.cameraBoundsComplements 补写
	_ensure_map_edge_from_info()
	_dirty = false
	ensure_brush_index_valid()
	dirty_changed.emit(false)
	changed.emit()
	return OK


## 从 info 补写 FLAG_MAP_EDGE（兼容旧 map-parse 未打包 boundary1 的 JSON）。
func _ensure_map_edge_from_info() -> void:
	if heightfield == null or terrain == null:
		return
	var complements: Dictionary = {}
	if typeof(info.get("cameraBoundsComplements", null)) == TYPE_DICTIONARY:
		complements = info.get("cameraBoundsComplements", {}) as Dictionary
	if complements.is_empty():
		# 有 playable 尺寸则反推对称补边；否则用默认
		var pw: int = int(info.get("playableWidth", 0))
		var ph: int = int(info.get("playableHeight", 0))
		if pw > 0 and ph > 0 and heightfield.map_width > 0:
			var lx: int = maxi(heightfield.map_width - pw, 0)
			var ly: int = maxi(heightfield.map_height - ph, 0)
			complements = {
				"left": lx / 2,
				"right": lx - lx / 2,
				"bottom": ly / 2,
				"top": ly - ly / 2,
			}
		else:
			complements = Wc3Coords.default_camera_bounds_complements()
	terrain.apply_unplayable_boundaries(complements)


## Nothing / 移除边界：写 cell BL 的 FLAG_BOUNDARY（不改 MAP_EDGE）。
func paint_boundary_cell(ix: int, iy: int, enable: bool) -> bool:
	if is_empty() or terrain == null:
		return false
	# cell 左下角必须能当 BL：ix/iy 落在 [0, map_w) × [0, map_h)
	if heightfield == null:
		return false
	if ix < 0 or iy < 0 or ix >= heightfield.map_width or iy >= heightfield.map_height:
		return false
	if not terrain.set_boundary(ix, iy, enable):
		return false
	mark_dirty()
	return true


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
		ground_var[i] = Wc3TerrainLogic.random_ground_variation(rng)
		cliff_var[i] = 0
		cliff_tex[i] = 0
		layers[i] = cliff_level
		flags[i] = FLAG_WATER if water_mode > 0 else 0

	heightfield = Wc3Heightfield.from_dict({
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
	}, false)
	_rebind_logic()
	var complements: Dictionary = Wc3Coords.default_camera_bounds_complements()
	var play_w: int = maxi(map_w - int(complements.left) - int(complements.right), 0)
	var play_h: int = maxi(map_h - int(complements.bottom) - int(complements.top), 0)
	info = {
		"name": "Untitled",
		"flags": {},
		"cameraBoundsComplements": complements.duplicate(),
		"playableWidth": play_w,
		"playableHeight": play_h,
	}
	# 实用区外缘 → FLAG_MAP_EDGE（对齐 HiveWE set_unplayable_boundaries）
	if terrain != null:
		terrain.apply_unplayable_boundaries(complements)
	map_dir = ""
	source_name = "untitled"
	brush_tile_index = tile_index
	doodads = Wc3DoodadList.new()
	units = Wc3UnitList.new()
	pathing = null
	_next_creation_number = 1
	_next_unit_creation_number = 1
	_dirty = true
	dirty_changed.emit(true)
	changed.emit()


## 将整格四角写成当前笔刷地表索引。tx/ty 为地形格（非 tilepoint）。
func paint_tile(tx: int, ty: int, tex_index: int = -1) -> bool:
	if is_empty():
		return false
	var idx: int = tex_index if tex_index >= 0 else brush_tile_index
	if not terrain.paint_tile(tx, ty, idx):
		return false
	mark_dirty()
	return true


## 写单个中级栅格顶点（tilepoint）的地表索引。对齐 WE / HiveWE 角点笔刷。
func paint_corner(ix: int, iy: int, tex_index: int = -1) -> bool:
	if is_empty():
		AppLog.warn(AppLog.Layer.EDITOR, "Document", "paint_corner: 文档空")
		return false
	var idx: int = tex_index if tex_index >= 0 else brush_tile_index
	var i: int = heightfield.index_at(ix, iy) if heightfield != null and heightfield.in_bounds(ix, iy) else -1
	var old_tex: int = int(heightfield.ground_textures[i]) if i >= 0 else -1
	if not terrain.paint_corner(ix, iy, idx):
		return false
	var new_tex: int = int(heightfield.ground_textures[i]) if i >= 0 else -1
	AppLog.debug(
		AppLog.Layer.EDITOR,
		"Document",
		"paint_corner (%d,%d) %d→%d (brush=%d)" % [ix, iy, old_tex, new_tex, idx]
	)
	mark_dirty()
	return true


## 悬崖笔刷：委托 Wc3CliffLogic；Ramp 走 paint_ramp_at。
## tool_id: "0".."4" | "ShallowWater" | "DeepWater" | "Ramp"
func paint_cliff_corner(
	ix: int,
	iy: int,
	tool_id: String,
	cliff_type_idx: int = -1,
	level_layer: int = -1
) -> bool:
	if tool_id == "Ramp":
		return paint_ramp_at(ix, iy)
	if is_empty():
		return false
	var ctype: int = cliff_type_idx if cliff_type_idx >= 0 else brush_cliff_type
	if cliff.paint_corner(ix, iy, tool_id, ctype, level_layer):
		# 清坡已在 CliffLogic 内按「变更点所在坡臂」处理；勿再 clear_flags_around 方阵误伤邻列
		mark_dirty()
		return true
	return false


## 斜坡笔刷：委托 Wc3RampLogic（只写 FLAG_RAMP）。
## horizontal/vertical ∈ {-1,0,1}；皆 0 时由 Logic 按层差推断。
func paint_ramp_at(ix: int, iy: int, horizontal: int = 0, vertical: int = 0) -> bool:
	var r: Dictionary = try_paint_ramp_at(ix, iy, horizontal, vertical)
	last_ramp_message = str(r.get("message", ""))
	return bool(r.get("changed", false))


func try_paint_ramp_at(ix: int, iy: int, horizontal: int = 0, vertical: int = 0) -> Dictionary:
	if is_empty():
		return {
			"ok": false,
			"changed": false,
			"message": "地图为空",
			"variant": "",
			"axis": "",
			"sx": 0,
			"sy": 0,
			"marked": [],
		}
	var r: Dictionary = ramp.try_paint_at(
		ix, iy, horizontal, vertical, brush_cliff_type
	)
	if bool(r.get("changed", false)):
		mark_dirty()
	return r


func peek_ramp_spine_at(ix: int, iy: int, horizontal: int = 0, vertical: int = 0) -> Array[Vector2i]:
	if is_empty():
		var empty: Array[Vector2i] = []
		return empty
	return ramp.peek_spine_at(ix, iy, horizontal, vertical)


## 删邻域内所有 FLAG_RAMP（HivEWE 经典：右击斜坡 = 删邻域）。
## radius=1 → 3×3 邻域，覆盖 3 点直坡 / L 补心 / 对角部分；
## radius=2 → 5×5 邻域（用于 erase 中心点位跨变体时更彻底）。
## 返回清除的顶点数。
func erase_ramp_at(ix: int, iy: int, radius: int = 1) -> int:
	if is_empty():
		return 0
	var rmin: Vector2i = Vector2i(ix - radius, iy - radius)
	var rmax: Vector2i = Vector2i(ix + radius, iy + radius)
	var n: int = ramp.clear_flags_in_rect(rmin, rmax, 0)
	if n > 0:
		mark_dirty()
	return n


func sample_height_at_tile(tx: int, ty: int) -> float:
	return terrain.sample_height_at_tile(tx, ty)


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
	var tp_w: int = heightfield.width
	var tp_h: int = heightfield.height
	var heights: Array = heightfield.heights
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
	f.store_string(JSON.stringify(heightfield.to_dict(), "\t"))
	# 若落在 map-parsed 目录旁，同步 doodads.json / units.json
	if out_path.get_file().begins_with("terrain") or not map_dir.is_empty():
		var base: String = map_dir if not map_dir.is_empty() else out_path.get_base_dir()
		_save_doodads_json(base.path_join("doodads.json"))
		_save_units_json(base.path_join("units.json"))
	clear_dirty()
	print("MapDocument: saved %s" % out_path)
	return OK


## —— 装饰物 CRUD（对外仍用 Dictionary；内部写 SoA）——

func doodads_as_dict() -> Dictionary:
	return doodads.to_dict() if doodads != null else {"formatVersion": 8, "count": 0, "doodads": []}


## Present / 旧 API 过渡：AoS 条目数组（勿长期缓存）。
func doodad_entries() -> Array:
	return doodads.to_entries_array() if doodads != null else []


func add_doodad(entry: Dictionary) -> int:
	if doodads == null:
		doodads = Wc3DoodadList.new()
	var d: Dictionary = entry.duplicate(true)
	if int(d.get("creationNumber", -1)) < 0:
		d["creationNumber"] = _alloc_creation_number()
	else:
		_next_creation_number = maxi(_next_creation_number, int(d["creationNumber"]) + 1)
	var idx: int = doodads.append_dict(d)
	mark_dirty()
	return idx


func remove_doodad(index: int) -> Dictionary:
	if doodads == null or not doodads.in_bounds(index):
		return {}
	var removed: Dictionary = doodads.at(index).to_dict()
	doodads.remove_at(index)
	mark_dirty()
	return removed


func remove_doodad_by_creation_number(creation_number: int) -> Dictionary:
	var i: int = find_doodad_index_by_creation_number(creation_number)
	if i < 0:
		return {}
	return remove_doodad(i)


func find_doodad_index_by_creation_number(creation_number: int) -> int:
	if doodads == null:
		return -1
	return doodads.find_index_by_creation_number(creation_number)


## 按 creationNumber 整体替换条目（移动 / 旋转）；保留 cn。
func update_doodad_by_creation_number(creation_number: int, entry: Dictionary) -> bool:
	var idx: int = find_doodad_index_by_creation_number(creation_number)
	if idx < 0 or entry.is_empty() or doodads == null:
		return false
	var d: Dictionary = entry.duplicate(true)
	d["creationNumber"] = creation_number
	if not doodads.set_dict_at(idx, d):
		return false
	mark_dirty()
	return true


func get_doodad(index: int) -> Dictionary:
	if doodads == null or not doodads.in_bounds(index):
		return {}
	return doodads.at(index).to_dict()


## 在 WC3 世界 XY 处建一条可放置条目（Z 由 heightfield 插值）。
## scale 可为 float（三轴相同）或 Vector3（WC3 x/y/z）。
func make_doodad_entry(
	type_id: String,
	wc3_x: float,
	wc3_y: float,
	variation: int = 0,
	angle_deg: float = 270.0,
	scale: Variant = 1.0,
) -> Dictionary:
	var z: float = 0.0
	if heightfield != null and heightfield.is_valid():
		z = heightfield.interpolated_height(wc3_x, wc3_y)
	var ang := deg_to_rad(angle_deg)
	var sx := 1.0
	var sy := 1.0
	var sz := 1.0
	if scale is Vector3:
		var v: Vector3 = scale
		sx = maxf(v.x, 0.01)
		sy = maxf(v.y, 0.01)
		sz = maxf(v.z, 0.01)
	else:
		var u: float = maxf(float(scale), 0.01)
		sx = u
		sy = u
		sz = u
	return {
		"id": type_id,
		"variation": variation,
		"position": {"x": wc3_x, "y": wc3_y, "z": z},
		"angle": ang,
		"angleDegrees": angle_deg,
		"scale": {"x": sx, "y": sy, "z": sz},
		"flags": 2,
		"life": 100,
		"itemTablePtr": -1,
		"droppedItemSets": [],
		"creationNumber": -1,
	}


func _alloc_creation_number() -> int:
	var n: int = _next_creation_number
	_next_creation_number += 1
	return n


func _alloc_unit_creation_number() -> int:
	var n: int = _next_unit_creation_number
	_next_unit_creation_number += 1
	return n


func _load_doodads_from_map_dir(path: String) -> void:
	_next_creation_number = 1
	var dood_path: String = path.path_join("doodads.json")
	if not FileAccess.file_exists(dood_path):
		doodads = Wc3DoodadList.new()
		return
	var loaded: Wc3DoodadList = Wc3DoodadList.load_json_path(dood_path)
	doodads = loaded if loaded != null else Wc3DoodadList.new()
	for i in range(doodads.count()):
		_next_creation_number = maxi(_next_creation_number, int(doodads.creation_numbers[i]) + 1)


func _save_doodads_json(path: String) -> Error:
	var parent: String = path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MapDocument: cannot write %s" % path)
		return ERR_CANT_CREATE
	f.store_string(JSON.stringify(doodads_as_dict(), "\t"))
	return OK


## —— 单位放置（权威 SoA；Present 仍用 unit_entries）——

func units_as_dict() -> Dictionary:
	return units.to_dict() if units != null else {"formatVersion": 8, "count": 0, "units": []}


func unit_entries() -> Array:
	return units.to_entries_array() if units != null else []


func add_unit(entry: Dictionary) -> int:
	if units == null:
		units = Wc3UnitList.new()
	var d: Dictionary = entry.duplicate(true)
	if int(d.get("creationNumber", -1)) < 0:
		d["creationNumber"] = _alloc_unit_creation_number()
	else:
		_next_unit_creation_number = maxi(_next_unit_creation_number, int(d["creationNumber"]) + 1)
	var idx: int = units.append_dict(d)
	mark_dirty()
	return idx


func remove_unit(index: int) -> Dictionary:
	if units == null or not units.in_bounds(index):
		return {}
	var removed: Dictionary = units.at(index).to_dict()
	units.remove_at(index)
	mark_dirty()
	return removed


func remove_unit_by_creation_number(creation_number: int) -> Dictionary:
	var i: int = find_unit_index_by_creation_number(creation_number)
	if i < 0:
		return {}
	return remove_unit(i)


func find_unit_index_by_creation_number(creation_number: int) -> int:
	if units == null:
		return -1
	return units.find_index_by_creation_number(creation_number)


func update_unit_by_creation_number(creation_number: int, entry: Dictionary) -> bool:
	var idx: int = find_unit_index_by_creation_number(creation_number)
	if idx < 0 or entry.is_empty() or units == null:
		return false
	var d: Dictionary = entry.duplicate(true)
	d["creationNumber"] = creation_number
	if not units.set_dict_at(idx, d):
		return false
	mark_dirty()
	return true


func get_unit(index: int) -> Dictionary:
	if units == null or not units.in_bounds(index):
		return {}
	return units.at(index).to_dict()


## 在 WC3 世界 XY 处建一条可放置单位（Z 由 heightfield 插值）。
func make_unit_entry(
	type_id: String,
	wc3_x: float,
	wc3_y: float,
	owner: int = 0,
	angle_deg: float = 270.0,
	variation: int = 0,
) -> Dictionary:
	var z: float = 0.0
	if heightfield != null and heightfield.is_valid():
		z = heightfield.interpolated_height(wc3_x, wc3_y)
	var ang := deg_to_rad(angle_deg)
	return {
		"typeId": type_id,
		"variation": variation,
		"position": {"x": wc3_x, "y": wc3_y, "z": z},
		"angle": ang,
		"angleDegrees": angle_deg,
		"scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"flags": 2,
		"owner": clampi(owner, 0, 15),
		"unknown": [0, 0],
		"hitPoints": -1,
		"manaPoints": -1,
		"itemTablePtr": -1,
		"droppedItemSets": [],
		"goldAmount": 12500,
		"targetAcquisition": -2,
		"heroLevel": 1,
		"strength": 0,
		"agility": 0,
		"intelligence": 0,
		"inventory": [],
		"abilities": [],
		"random": {"flag": 0, "level": 1, "itemClass": 0},
		"customColor": -1,
		"waygate": -1,
		"creationNumber": -1,
	}


func _load_units_from_map_dir(path: String) -> void:
	_next_unit_creation_number = 1
	var unit_path: String = path.path_join("units.json")
	if not FileAccess.file_exists(unit_path):
		units = Wc3UnitList.new()
		return
	var loaded: Wc3UnitList = Wc3UnitList.load_json_path(unit_path)
	units = loaded if loaded != null else Wc3UnitList.new()
	for i in range(units.count()):
		_next_unit_creation_number = maxi(
			_next_unit_creation_number, int(units.creation_numbers[i]) + 1
		)


func _load_pathing_from_map_dir(path: String) -> void:
	pathing = null
	var p: String = path.path_join("pathing.json")
	if FileAccess.file_exists(p):
		pathing = _PathingMapScript.load_json_path(p)
	ensure_pathing(null)


## tiles 可空：仅在已有 pathing 时同步 origin；无 pathing 时用合成（需 tiles）。
func ensure_pathing(tiles: Wc3TerrainTileCatalog) -> void:
	if heightfield == null or not heightfield.is_valid():
		return
	if pathing != null and pathing.is_valid():
		pathing.sync_origin_from_heightfield(heightfield)
		return
	if tiles == null:
		return
	pathing = _PathingMapScript.synthesize_from_heightfield(heightfield, tiles)


func _save_units_json(path: String) -> Error:
	var parent: String = path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MapDocument: cannot write %s" % path)
		return ERR_CANT_CREATE
	f.store_string(JSON.stringify(units_as_dict(), "\t"))
	return OK
