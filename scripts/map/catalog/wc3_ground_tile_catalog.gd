class_name Wc3GroundTileCatalog
extends RefCounted

## 地表纹理资源映射：groundTilesets → Texture2DArray / extended 标志。
## 运行时经 Wc3TerrainTiles + RuntimeAssets 加载，不检入 .tres。


## 各 tileset PNG 组成 Texture2DArray（shader `tilesets` 采样）。
static func build_texture_array(ground_tilesets: Array, tiles: Wc3TerrainTiles) -> Texture2DArray:
	return Wc3TerrainAutotile.build_tileset_array(ground_tilesets, tiles)


## 宽图集（过渡块）标记：1=extended，0=普通。
static func build_extended_flags(ground_tilesets: Array, tiles: Wc3TerrainTiles) -> PackedByteArray:
	return Wc3TerrainAutotile.build_extended_flags(ground_tilesets, tiles)


## 解析某 tileset 下标对应 PNG 逻辑路径（委托 TerrainTiles）。
static func png_for_index(ground_tilesets: Array, index: int, tiles: Wc3TerrainTiles) -> String:
	if tiles == null:
		return ""
	return tiles.png_for_ground_index(ground_tilesets, index)
