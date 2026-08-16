class_name Wc3TerrainTileCatalog
extends RefCounted

## 地表 Catalog：TerrainTileDef（表列）+ 地表 PNG 路径解析（资源映射）。
## 直崖见 Wc3CliffCatalog；Texture2DArray 组装见 Wc3GroundTileCatalog。

## 仅缓存「解析后的贴图路径」
var _tile_to_png: Dictionary[String, String] = {}


func load_default() -> void:
	_tile_to_png.clear()
	_rebuild_tile_png_cache()


## 指定地形集字母（如 "L"）下的地表 tileID（Terrain 表顺序）。
func tile_ids_for_tileset(tileset_letter: String) -> PackedStringArray:
	var letter := tileset_letter.strip_edges().to_upper()
	if letter.is_empty():
		letter = "L"
	var store := _def_store()
	if store == null:
		return PackedStringArray()
	return store.find_ids(
		TerrainTileDef.TABLE_NAME,
		func(id: String, row: Resource) -> bool:
			var d := row as TerrainTileDef
			return d != null and id.length() == 4 and d.get_tileset_letter() == letter
	)

## 地形ID → 显示名称键
## [param tile_id] 地形ID
## [return String] 显示名称键
func name_key_for_tile_id(tile_id: String) -> String:
	var d := _terrain_def(tile_id)
	return d.display_name_key() if d != null else ""

## 地形ID → 显示名称
## [param tile_id] 地形ID
## [return String] 显示名称
func display_name_for_tile_id(tile_id: String) -> String:
	var n := name_key_for_tile_id(tile_id)
	return tile_id if n.is_empty() else n

## 地形ID → 是否可建造
## Terrain.slk `buildable`；缺省视为可建造。
## [param tile_id] 地形ID
## [return bool] 是否可建造
func is_buildable(tile_id: String) -> bool:
	var d := _terrain_def(tile_id)
	return true if d == null else d.buildable


## Terrain.slk `walkable`；缺省视为可行走。
func is_walkable(tile_id: String) -> bool:
	var d := _terrain_def(tile_id)
	return true if d == null else d.walkable

## 地形ID → 贴图路径
## [param tile_id] 地形ID
## [return String] 贴图路径
func png_for_tile_id(tile_id: String) -> String:
	return str(_tile_to_png.get(tile_id, ""))

## 地面纹理集 → 贴图路径
## [param ground_tilesets] 地面纹理集
## [param index] 索引
## [return String] 贴图路径
func png_for_ground_index(ground_tilesets: Array, index: int) -> String:
	if index < 0 or index >= ground_tilesets.size():
		return ""
	return png_for_tile_id(str(ground_tilesets[index]))

## 重建地表贴图缓存
func _rebuild_tile_png_cache() -> void:
	var store := _def_store()
	if store == null:
		AppLog.warn(AppLog.Layer.CATALOG, "TerrainTileCatalog", "DefStore 不可用，无法解析地表贴图")
		return
	store.ensure_table(TerrainTileDef.TABLE_NAME)
	for id in store.get_ids(TerrainTileDef.TABLE_NAME):
		var d: TerrainTileDef = store.get_row(TerrainTileDef.TABLE_NAME, id) as TerrainTileDef
		if d == null or d.dir.is_empty() or d.file.is_empty():
			continue
		_tile_to_png[id] = RuntimeAssets.converted_path("%s/%s.png" % [d.dir, d.file])
	AppLog.debug(
		AppLog.Layer.CATALOG,
		"TerrainTileCatalog",
		"tile png cache from DefStore count=%d" % _tile_to_png.size()
	)


func _terrain_def(tile_id: String) -> TerrainTileDef:
	var store := _def_store()
	if store == null:
		return null
	return store.get_row(TerrainTileDef.TABLE_NAME, tile_id) as TerrainTileDef


func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")
