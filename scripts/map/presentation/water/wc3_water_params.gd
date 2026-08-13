class_name Wc3WaterParams
extends RefCounted

## 水体运行时参数：表列来自 WaterTypeDef；帧 PNG 在此做资源映射。

# HiveWE 深度常量（tile 高度单位，1 tile = 128 WC3）
const MIN_DEPTH := 10.0 / 128.0
const DEEP_LEVEL := 64.0 / 128.0
const MAX_DEPTH := 72.0 / 128.0

## water_id → Texture2DArray（同 tileset 重复进局 / 笔刷重建复用）
static var _tex_array_cache: Dictionary = {}

var water_id: String = ""
var height_offset_tiles: float = 0.0 ## Water.slk height（tile 单位）
var num_tex: int = 0
var tex_rate: float = 15.0 ## 约帧/秒；shader 用 TIME*tex_rate
## Water.slk cells：一张水面贴图覆盖的格数（ISha=2 → UV 按格坐标 / 2）
var cells: float = 2.0
var tex_file_prefix: String = "ReplaceableTextures/Water/Water"
var shallow_min: Color = Color(1, 1, 1, 0.04)
var shallow_max: Color = Color(0.94, 0.94, 0.94, 0.86)
var deep_min: Color = Color(0.46, 0.46, 0.46, 0.86)
var deep_max: Color = Color(0.59, 0.71, 0.86, 0.71)
var frame_pngs: PackedStringArray = PackedStringArray()


## 按地形集填充表列并解析水面帧（对外入口；内部再用私有步骤）。
func setup_for_tileset(main_tileset: String) -> void:
	var tid := main_tileset.strip_edges()
	if tid.is_empty():
		tid = "I"
	water_id = tid.substr(0, 1).to_upper() + "Sha"
	_apply_from_def_store()
	_resolve_frames()


func height_offset_wc3() -> float:
	return height_offset_tiles * 128.0


## 表列：WaterTypeDef → 本对象字段（不做 PNG 解析）。
func _apply_from_def_store() -> void:
	var store := _def_store()
	if store == null:
		push_warning("Wc3WaterParams: DefStore 不可用")
		return
	store.ensure_table(WaterTypeDef.TABLE_NAME)
	var def: WaterTypeDef = store.get_row(WaterTypeDef.TABLE_NAME, water_id) as WaterTypeDef
	if def == null:
		push_warning("Wc3WaterParams: 未找到 waterID=%s，回退 ISha" % water_id)
		water_id = "ISha"
		def = store.get_row(WaterTypeDef.TABLE_NAME, water_id) as WaterTypeDef
	if def == null:
		return
	height_offset_tiles = def.height
	num_tex = def.num_tex
	tex_rate = def.tex_rate
	cells = maxf(def.cells, 1.0)
	tex_file_prefix = def.tex_file
	shallow_min = def.shallow_min
	shallow_max = def.shallow_max
	deep_min = def.deep_min
	deep_max = def.deep_max


func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


## 资源映射：tex_file + num_tex → 各帧 converted PNG。
func _resolve_frames() -> void:
	frame_pngs.clear()
	if num_tex <= 0:
		return
	var tileset := water_id.substr(0, 1).to_upper() if water_id.length() >= 1 else "I"
	var alt := Wc3CliffCatalog.tileset_texture_fallback(tileset)
	var base_name := tex_file_prefix.get_file() # Water
	var dir := tex_file_prefix.get_base_dir()
	for i in range(num_tex):
		var frame := "%s%02d" % [base_name, i]
		var candidates: Array[String] = []
		for ts in [tileset, alt]:
			if ts.is_empty():
				continue
			candidates.append("%s/%s_%s.png" % [dir, ts, frame])
		candidates.append("%s/%s.png" % [dir, frame])
		var found := ""
		for c in candidates:
			var res_path := RuntimeAssets.converted_path(c)
			if RuntimeAssets.file_exists(res_path):
				found = res_path
				break
		if found.is_empty():
			push_warning("Wc3WaterParams: 缺水面帧 %s" % RuntimeAssets.converted_path(candidates[0]))
			continue
		frame_pngs.append(found)


## 组装 / 复用水面帧 Texture2DArray；命中缓存时不再读盘。
## 返回 { tex, cache_hit }
func build_texture_array_cached() -> Dictionary:
	if water_id.is_empty() or frame_pngs.is_empty():
		return {"tex": null, "cache_hit": false}
	if _tex_array_cache.has(water_id):
		return {"tex": _tex_array_cache[water_id] as Texture2DArray, "cache_hit": true}
	var tex := build_texture_array()
	if tex != null:
		_tex_array_cache[water_id] = tex
	return {"tex": tex, "cache_hit": false}


func build_texture_array() -> Texture2DArray:
	if frame_pngs.is_empty():
		return null
	var images: Array[Image] = []
	var w := 0
	var h := 0
	for p in frame_pngs:
		var img := RuntimeAssets.load_image(p)
		if img == null:
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		if w == 0:
			w = img.get_width()
			h = img.get_height()
		elif img.get_width() != w or img.get_height() != h:
			img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		images.append(img)
	if images.is_empty():
		return null
	var tex := Texture2DArray.new()
	var err := tex.create_from_images(images)
	if err != OK:
		push_error("Wc3WaterParams: Texture2DArray 失败 %s" % error_string(err))
		return null
	return tex


## depth_tiles = (water - ground) / 128，已含 offset 的最终水面高度。
static func depth_color(
	depth_tiles: float,
	smin: Color,
	smax: Color,
	dmin: Color,
	dmax: Color
) -> Color:
	var value := clampf(depth_tiles, 0.0, 1.0)
	if value <= DEEP_LEVEL:
		var t := maxf(0.0, value - MIN_DEPTH) / (DEEP_LEVEL - MIN_DEPTH)
		return smin.lerp(smax, t)
	var t2 := clampf(value - DEEP_LEVEL, 0.0, MAX_DEPTH - DEEP_LEVEL) / (MAX_DEPTH - DEEP_LEVEL)
	return dmin.lerp(dmax, t2)

static func load_for_tileset(main_tileset: String) -> Wc3WaterParams:
	var p := Wc3WaterParams.new()
	p.setup_for_tileset(main_tileset)
	return p

