class_name Wc3WaterParams
extends RefCounted
## 从 Water.slk 读取地形集水体参数（如 ISha），对齐 HiveWE / mdx-m3-viewer。


## HiveWE 深度阈值（tile 高度单位，1 tile = 128 WC3）
const MIN_DEPTH := 10.0 / 128.0
const DEEP_LEVEL := 64.0 / 128.0
const MAX_DEPTH := 72.0 / 128.0

var water_id: String = ""
var height_offset_tiles: float = 0.0 ## Water.slk height（tile 单位）
var num_tex: int = 0
var tex_rate: float = 15.0 ## 约帧/秒；shader 用 TIME*tex_rate（viewer 等价于每帧 += texRate/60）
## Water.slk cells：一张水面贴图覆盖的格数（ISha=2 → UV 按格坐标 / 2）
var cells: float = 2.0
var tex_file_prefix: String = "ReplaceableTextures/Water/Water"
var shore_dir: String = "Doodads/LordaeronSummer/Water"
var shore_s_file: String = "Shoreline"
var shore_oc_file: String = "ShorelineOutsideCorner"
var shore_ic_file: String = "ShorelineInsideCorner"
var shallow_min: Color = Color(1, 1, 1, 0.04)
var shallow_max: Color = Color(0.94, 0.94, 0.94, 0.86)
var deep_min: Color = Color(0.46, 0.46, 0.46, 0.86)
var deep_max: Color = Color(0.59, 0.71, 0.86, 0.71)
var frame_pngs: PackedStringArray = PackedStringArray()


static func load_for_tileset(main_tileset: String) -> Wc3WaterParams:
	var p := Wc3WaterParams.new()
	var tid := main_tileset.strip_edges()
	if tid.is_empty():
		tid = "I"
	p.water_id = tid.substr(0, 1).to_upper() + "Sha"
	p._load_slk("res://assets/slk-exported/TerrainArt/Water.json")
	p._resolve_frames()
	return p


func height_offset_wc3() -> float:
	return height_offset_tiles * 128.0


func _load_slk(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("Wc3WaterParams: 缺少 %s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var hit: Dictionary = {}
	for rec in data.get("records", []):
		if str(rec.get("waterID", "")) == water_id:
			hit = rec
			break
	if hit.is_empty():
		push_warning("Wc3WaterParams: 未找到 waterID=%s，回退 ISha" % water_id)
		water_id = "ISha"
		for rec in data.get("records", []):
			if str(rec.get("waterID", "")) == water_id:
				hit = rec
				break
	if hit.is_empty():
		return
	height_offset_tiles = float(hit.get("height", 0.0))
	num_tex = int(hit.get("numTex", 0))
	tex_rate = float(hit.get("texRate", 15))
	cells = maxf(float(hit.get("cells", 2)), 1.0)
	tex_file_prefix = str(hit.get("texFile", "ReplaceableTextures\\Water\\Water")).replace("\\", "/")
	shore_dir = str(hit.get("shoreDir", "Doodads\\LordaeronSummer\\Water")).replace("\\", "/")
	shore_s_file = str(hit.get("shoreSFile", "Shoreline"))
	shore_oc_file = str(hit.get("shoreOCFile", "ShorelineOutsideCorner"))
	shore_ic_file = str(hit.get("shoreICFile", "ShorelineInsideCorner"))
	shallow_min = _rgba(hit, "Smin")
	shallow_max = _rgba(hit, "Smax")
	deep_min = _rgba(hit, "Dmin")
	deep_max = _rgba(hit, "Dmax")


static func _rgba(rec: Dictionary, prefix: String) -> Color:
	var r := float(rec.get(prefix + "_R", 255)) / 255.0
	var g := float(rec.get(prefix + "_G", 255)) / 255.0
	var b := float(rec.get(prefix + "_B", 255)) / 255.0
	var a := float(rec.get(prefix + "_A", 255)) / 255.0
	return Color(r, g, b, a)


func _resolve_frames() -> void:
	frame_pngs.clear()
	if num_tex <= 0:
		return
	var tileset := water_id.substr(0, 1) if water_id.length() >= 1 else "I"
	var base_name := tex_file_prefix.get_file() # Water
	var dir := "res://assets/asset-converted/" + tex_file_prefix.get_base_dir()
	for i in range(num_tex):
		var frame := "%s%02d" % [base_name, i]
		var candidates: Array[String] = [
			"%s/%s_%s.png" % [dir, tileset, frame],
			"%s/%s.png" % [dir, frame],
		]
		var found := ""
		for c in candidates:
			if RuntimeAssets.file_exists(c):
				found = c
				break
		if found.is_empty():
			push_warning("Wc3WaterParams: 缺水面帧 %s" % candidates[0])
			continue
		frame_pngs.append(found)


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
