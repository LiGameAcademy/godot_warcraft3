class_name MapMinimapRaster
extends RefCounted
## Heightfield → 小地图 Image（对齐 HiveWE Terrain::minimap_image）。
## 工作分辨率 1 px / tilepoint；UI / 存盘统一 Nearest 放大到 256²。

const CLIFF_COLOR := Color8(128, 128, 128, 255)
const WATER_DEEP_MUL := 0.5625
const WATER_DEEP_ADD := Color(0.0, 0.0, 80.0 / 255.0, 112.0 / 255.0)
const WATER_SHALLOW_MUL := 0.75
const WATER_SHALLOW_ADD := Color(0.0, 0.0, 48.0 / 255.0, 64.0 / 255.0)
## HiveWE：深水阈值为 0.5「层」；本仓库高度为 WC3 单位（128/层）。
const WATER_DEEP_DELTA_WC3 := 64.0
const UNPLAYABLE_DARKEN := 0.55
const BAKE_SIZE := 256

var hf: Wc3Heightfield
var _img: Image
var _img_w: int
var _img_h: int
var _dirty_rects: Array[Rect2i]
var _colors: PackedColorArray = PackedColorArray()
var _cliff_to_ground: PackedInt32Array = PackedInt32Array()
var _romp: PackedByteArray = PackedByteArray()
var _water_offset_wc3: float = 0.0


## 1:1 tilepoint 工作图（HiveWE 同尺寸）。
func _init(p_hf: Wc3Heightfield, _max_side_unused: int = 0) -> void:
	hf = p_hf
	_img_w = maxi(hf.width, 1)
	_img_h = maxi(hf.height, 1)
	_img = Image.create(_img_w, _img_h, false, Image.FORMAT_RGBA8)
	_water_offset_wc3 = _resolve_water_offset(hf)


## 注入地表代表色与崖→地表映射（打开地图 / 换 tileset 时调用）。
func setup_terrain(
	colors: PackedColorArray,
	cliff_to_ground: PackedInt32Array = PackedInt32Array(),
	romp: PackedByteArray = PackedByteArray(),
	water_offset_wc3: float = NAN,
) -> void:
	_colors = colors
	_cliff_to_ground = cliff_to_ground
	_romp = romp
	if not is_nan(water_offset_wc3):
		_water_offset_wc3 = water_offset_wc3


## 全量光栅化（HiveWE 着色：崖灰 / 可见水深浅 / 不可玩区压暗）。
func rasterize() -> Image:
	if hf == null or not hf.is_valid():
		return _img
	var w: int = hf.width
	var h: int = hf.height
	var ground_tex: Array = hf.ground_textures
	var layers: Array = hf.layer_heights
	var cliff_tex: Array = hf.cliff_textures
	var flags: Array = hf.flags_packed
	var heights: Array = hf.heights
	var water_h: Array = hf.water_heights
	for j in range(h):
		for i in range(w):
			var col: Color
			if Wc3CliffLogic.is_cliff_tile_corner(layers, w, h, i, j):
				col = CLIFF_COLOR
			else:
				var tex_i: int = Wc3TerrainLogic.real_tile_texture(
					ground_tex,
					layers,
					cliff_tex,
					_cliff_to_ground,
					flags,
					_romp,
					w,
					h,
					i,
					j,
				)
				if tex_i >= 0 and tex_i < _colors.size():
					col = _colors[tex_i]
				else:
					col = Color(0.4, 0.45, 0.35, 1.0)
			var idx: int = j * w + i
			var f: int = int(flags[idx]) if idx < flags.size() else 0
			col = _apply_water_tint(col, f, idx, heights, water_h)
			if Wc3Coords.is_unplayable_cell_flags(f):
				col = col.darkened(UNPLAYABLE_DARKEN)
			_img.set_pixel(i, h - 1 - j, col)
	_dirty_rects.clear()
	return _img


## 仅重绘 dirty region（第一版：忽略 rect，全量重绘）。
func rasterize_dirty() -> Image:
	return rasterize()


func mark_dirty(rect: Rect2i) -> void:
	_dirty_rects.push_back(rect)


func get_image() -> Image:
	return _img


## UI 显示用：Nearest 放大到 256²（与官方 war3mapMap / 存盘一致）。
func get_display_image() -> Image:
	return upscale_nearest(_img, BAKE_SIZE)


func get_size() -> Vector2i:
	return Vector2i(_img_w, _img_h)


func get_water_offset_wc3() -> float:
	return _water_offset_wc3


func create_texture() -> ImageTexture:
	return ImageTexture.create_from_image(get_display_image())


## 工作图 → 目标边长 Nearest（正方形源直接放大；非方图按比例 contain + 居中 pad，避免拉伸）。
static func upscale_nearest(src: Image, side: int = BAKE_SIZE) -> Image:
	if src == null:
		return null
	var out: Image = src.duplicate()
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	var sw: int = out.get_width()
	var sh: int = out.get_height()
	if sw == side and sh == side:
		return out
	if sw == sh:
		out.resize(side, side, Image.INTERPOLATE_NEAREST)
		return out
	# 非方图：按较长边缩到 side，短边 letterbox（背景透明）
	var scale: float = float(side) / float(maxi(sw, sh))
	var nw: int = maxi(int(round(float(sw) * scale)), 1)
	var nh: int = maxi(int(round(float(sh) * scale)), 1)
	out.resize(nw, nh, Image.INTERPOLATE_NEAREST)
	var canvas := Image.create(side, side, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var ox: int = int((side - nw) / 2.0)
	var oy: int = int((side - nh) / 2.0)
	canvas.blit_rect(out, Rect2i(0, 0, nw, nh), Vector2i(ox, oy))
	return canvas


## 烘焙为官方风格 256×256 PNG（Nearest）。
static func bake_war3map_png(src: Image, path: String) -> Error:
	if src == null or path.is_empty():
		return ERR_INVALID_PARAMETER
	var out: Image = upscale_nearest(src, BAKE_SIZE)
	var abs_path := path
	if abs_path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(abs_path)
	var parent := abs_path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	return out.save_png(abs_path)


## 便捷：从 Heightfield + Catalog 一次生成工作图（1:1）。
static func rasterize_from(
	p_hf: Wc3Heightfield,
	tiles: Wc3TerrainTileCatalog,
	cliff_catalog: Wc3CliffCatalog = null,
	romp: PackedByteArray = PackedByteArray(),
) -> Image:
	if p_hf == null or not p_hf.is_valid():
		return null
	var colors: PackedColorArray = Wc3GroundTileCatalog.build_minimap_colors(
		p_hf.ground_tilesets, tiles
	)
	var c2g := PackedInt32Array()
	if cliff_catalog != null:
		c2g = cliff_catalog.build_cliff_to_ground_map(p_hf.cliff_tilesets, p_hf.ground_tilesets)
	var r := MapMinimapRaster.new(p_hf)
	r.setup_terrain(colors, c2g, romp)
	return r.rasterize()


## HiveWE：可见水 = FLAG_WATER 且 waterH+offset > groundH；深浅按 Δh > 0.5 层。
func _apply_water_tint(
	col: Color, flags: int, idx: int, heights: Array, water_heights: Array
) -> Color:
	if (flags & Wc3Coords.FLAG_WATER) == 0:
		return col
	if idx < 0 or idx >= heights.size():
		return col
	var ground_h: float = float(heights[idx])
	var wh: float = float(water_heights[idx]) if idx < water_heights.size() else ground_h
	var water_final: float = wh + _water_offset_wc3
	if water_final <= ground_h:
		return col
	var delta: float = water_final - ground_h
	if delta > WATER_DEEP_DELTA_WC3:
		col = col * WATER_DEEP_MUL + WATER_DEEP_ADD
	else:
		col = col * WATER_SHALLOW_MUL + WATER_SHALLOW_ADD
	col.a = 1.0
	return col


static func _resolve_water_offset(p_hf: Wc3Heightfield) -> float:
	if p_hf == null:
		return 0.0
	var params := Wc3WaterParams.new()
	params.setup_for_tileset(p_hf.main_tileset)
	return params.height_offset_wc3()
