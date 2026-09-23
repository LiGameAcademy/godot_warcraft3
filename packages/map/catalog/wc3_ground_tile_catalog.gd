class_name Wc3GroundTileCatalog
extends RefCounted

## 地表纹理资源映射：groundTilesets → Texture2DArray / extended 标志。
## 运行时经 Wc3TerrainTileCatalog + RuntimeAssets 加载，不检入 .tres。

const ATLAS_W := 512								## 纹理宽度
const ATLAS_H := 256								## 纹理高度
static var _warned_missing_png: Dictionary = {}

## 各 tileset PNG 组成 Texture2DArray（shader `tilesets` 采样）。
## [param ground_tilesets: Array] 地面纹理集
## [param tiles: Wc3TerrainTileCatalog] 地形瓷砖
## [return Texture2DArray] 纹理数组
static func build_texture_array(ground_tilesets: Array, tiles: Wc3TerrainTileCatalog) -> Texture2DArray:
	var images: Array[Image] = []
	for i in range(ground_tilesets.size()):
		var png := tiles.png_for_ground_index(ground_tilesets, i)
		var img := RuntimeAssets.load_image(png)
		if img == null:
			if not _warned_missing_png.has(png):
				_warned_missing_png[png] = true
				push_warning("Wc3GroundTileCatalog: 缺少贴图 %s" % png)
			img = Image.create(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.4, 0.45, 0.35, 1))
		else:
			img = _pad_to_atlas(img)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		images.append(img)

	var tex := Texture2DArray.new()
	var err := tex.create_from_images(images)
	if err != OK:
		AppLog.error(
			AppLog.Layer.CATALOG,
			"GroundTiles",
			"Texture2DArray 失败 %s" % error_string(err)
		)
		return null
	AppLog.info(
		AppLog.Layer.CATALOG,
		"GroundTiles",
		"Texture2DArray layers=%d" % tex.get_layers()
	)
	return tex


## 各地表 tileset 的小地图代表色（对齐 HiveWE：取变体 0 块平均色 ≈ 最低 mip）。
## [param ground_tilesets: Array] 地面纹理集 ID 列表
## [param tiles: Wc3TerrainTileCatalog] 地形瓷砖 Catalog
## [return PackedColorArray] 与 ground_tilesets 等长；缺图时灰绿占位
static func build_minimap_colors(ground_tilesets: Array, tiles: Wc3TerrainTileCatalog) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(ground_tilesets.size())
	for i in range(ground_tilesets.size()):
		var png := tiles.png_for_ground_index(ground_tilesets, i) if is_instance_valid(tiles) else ""
		var img := RuntimeAssets.load_image(png) if not png.is_empty() else null
		if img == null:
			colors[i] = Color(0.4, 0.45, 0.35, 1.0)
			continue
		colors[i] = _average_tile_color(img)
	return colors


## 对 atlas 左上角变体 0（tile_size×tile_size）求平均色。
static func _average_tile_color(atlas: Image) -> Color:
	var h: int = atlas.get_height()
	var w: int = atlas.get_width()
	if h < 1 or w < 1:
		return Color(0.4, 0.45, 0.35, 1.0)
	var tile_size: int = maxi(int(h * 0.25), 1)
	tile_size = mini(tile_size, mini(w, h))
	var src := atlas
	if src.get_format() != Image.FORMAT_RGBA8:
		src = atlas.duplicate()
		src.convert(Image.FORMAT_RGBA8)
	var sum := Color(0, 0, 0, 0)
	var n: int = 0
	# 降采样步进，大图不必逐像素（仍逼近 mip 平均）
	var step: int = maxi(int(tile_size / 16.0), 1)
	for y in range(0, tile_size, step):
		for x in range(0, tile_size, step):
			sum += src.get_pixel(x, y)
			n += 1
	if n <= 0:
		return Color(0.4, 0.45, 0.35, 1.0)
	return sum / float(n)


## 宽图集（过渡块）标记：1=extended，0=普通。
## [param ground_tilesets: Array] 地面纹理集
## [param tiles: Wc3TerrainTileCatalog] 地形瓷砖
## [return PackedByteArray] 标记数组
static func build_extended_flags(ground_tilesets: Array, tiles: Wc3TerrainTileCatalog) -> PackedByteArray:
	var extended := PackedByteArray()
	extended.resize(ground_tilesets.size())
	for i in range(ground_tilesets.size()):
		var png := tiles.png_for_ground_index(ground_tilesets, i)
		var img := RuntimeAssets.load_image(png)
		extended[i] = 1 if (img and img.get_width() > img.get_height()) else 0
	return extended

## 获取纹理路径
## [param ground_tilesets: Array] 地面纹理集
## [param index: int] 索引
## [param tiles: Wc3TerrainTileCatalog] 地形瓷砖
## [return String] 纹理路径
static func png_for_index(ground_tilesets: Array, index: int, tiles: Wc3TerrainTileCatalog) -> String:
	if not is_instance_valid(tiles):
		push_warning("Wc3GroundTileCatalog: 地形瓷砖为空")
		return ""
	return tiles.png_for_ground_index(ground_tilesets, index)

## 填充到纹理集
## [param src: Image] 源图像
## [return Image] 填充后的图像
static func _pad_to_atlas(src: Image) -> Image:
	if src.get_width() == ATLAS_W and src.get_height() == ATLAS_H:
		return src.duplicate()
	var out := Image.create(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(
		src,
		Rect2i(0, 0, mini(src.get_width(), ATLAS_W), mini(src.get_height(), ATLAS_H)),
		Vector2i(0, 0)
	)
	return out
