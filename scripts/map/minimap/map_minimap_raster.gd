class_name MapMinimapRaster
extends RefCounted
## 将 Wc3Heightfield 光栅化为小地图 Image。
## 逻辑与 editor_inspect_window.gd 原版 refresh_minimap 完全一致。

var hf: Wc3Heightfield
var _img: Image
var _img_w: int
var _img_h: int
var _dirty_rects: Array[Rect2i]

## max_side: 小地图较长边的像素数（较短边按地图比例）。
func _init(p_hf: Wc3Heightfield, max_side: int = 256) -> void:
	hf = p_hf
	var w: int = hf.width
	var h: int = hf.height
	var scale_x: float = float(max_side) / float(w)
	var scale_y: float = float(max_side) / float(h)
	var s: float = minf(scale_x, scale_y)
	_img_w = maxi(int(round(w * s)), 1)
	_img_h = maxi(int(round(h * s)), 1)
	_img = Image.create(_img_w, _img_h, false, Image.FORMAT_RGBA8)


## 全量光栅化（与原版 refresh_minimap 逻辑一致）。
func rasterize() -> Image:
	var w: int = hf.width
	var h: int = hf.height
	# 计算高度范围（与原版一致）
	var min_l := 99
	var max_l := 0
	for i in range(hf.layer_heights.size()):
		var lv: int = int(hf.layer_heights[i])
		min_l = mini(min_l, lv)
		max_l = maxi(max_l, lv)
	var span: float = maxf(float(max_l - min_l), 1.0)
	# 光栅化（逐像素，与原版逻辑逐行对应）
	for py in range(_img_h):
		var iy: int = clampi(int(float(py) / float(_img_h) * float(h)), 0, h - 1)
		var src_y: int = h - 1 - iy
		for px in range(_img_w):
			var ix: int = clampi(int(float(px) / float(_img_w) * float(w)), 0, w - 1)
			var idx: int = src_y * w + ix
			var lv: int = int(hf.layer_heights[idx]) if idx < hf.layer_heights.size() else 2
			var t: float = (float(lv) - float(min_l)) / span
			var col := Color(0.18 + t * 0.55, 0.42 + t * 0.35, 0.22 + t * 0.15)
			var flags: int = int(hf.flags_packed[idx]) if idx < hf.flags_packed.size() else 0
			if (flags & Wc3Coords.FLAG_WATER) != 0:
				col = Color(0.15, 0.35, 0.72).lerp(Color(0.35, 0.55, 0.9), t)
			_img.set_pixel(px, py, col)
	_dirty_rects.clear()
	return _img


## 仅重绘 dirty region（增量更新）。
func rasterize_dirty() -> Image:
	if _dirty_rects.is_empty():
		return _img
	# 增量模式暂时全量重绘（性能优化后续再做）
	for py in range(_img_h):
		for px in range(_img_w):
			_raster_pixel_dirty(px, py)
	_dirty_rects.clear()
	return _img


## 标记某区域需要更新（坐标是 Image 像素坐标）。
func mark_dirty(rect: Rect2i) -> void:
	_dirty_rects.push_back(rect)


func get_image() -> Image:
	return _img


func get_size() -> Vector2i:
	return Vector2i(_img_w, _img_h)


## 将小地图 Image 转换为 ImageTexture。
func create_texture() -> ImageTexture:
	return ImageTexture.create_from_image(_img)


## 内部：增量模式单个像素（与 rasterize 相同的颜色逻辑）。
func _raster_pixel_dirty(px: int, py: int) -> void:
	var w: int = hf.width
	var h: int = hf.height
	var iy: int = clampi(int(float(py) / float(_img_h) * float(h)), 0, h - 1)
	var src_y: int = h - 1 - iy
	var ix: int = clampi(int(float(px) / float(_img_w) * float(w)), 0, w - 1)
	var idx: int = src_y * w + ix
	if idx < 0 or idx >= hf.layer_heights.size():
		_img.set_pixel(px, py, Color.BLACK)
		return
	var flags: int = int(hf.flags_packed[idx])
	var t: float = 0.5  # 简化：固定中间高度
	var col := Color(0.18 + t * 0.55, 0.42 + t * 0.35, 0.22 + t * 0.15)
	if (flags & Wc3Coords.FLAG_WATER) != 0:
		col = Color(0.15, 0.35, 0.72).lerp(Color(0.35, 0.55, 0.9), t)
	_img.set_pixel(px, py, col)
