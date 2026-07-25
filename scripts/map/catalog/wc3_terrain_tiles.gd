class_name Wc3TerrainTiles
extends RefCounted

## 地表 / 悬崖 Catalog：读 DefStore 表行 + 解析贴图资源路径。
##
## 两套逻辑分开：
## - 表列：TerrainTileDef / CliffTypeDef（SLK → Resource）
## - 资源：本类把 dir/file、texDir/texFile 解析成 converted PNG 路径
##
## 悬崖贴图在 SLK 里是 ReplaceableTextures/Cliff/Cliff0|1，
## 经典客户端按 mainTileset 从子包解析；解包用 {tileset}_Cliff0.png。

## 仅缓存「解析后的贴图路径」（资源映射，非 SLK 列副本）
var _tile_to_png: Dictionary[String, String] = {}
var _cliff_to_png: Dictionary[String, String] = {}


func load_default() -> void:
	_tile_to_png.clear()
	_cliff_to_png.clear()
	_rebuild_tile_png_cache()
	_rebuild_cliff_png_cache()


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


## 悬崖类型：cliffID 第 2 字符为地形集字母（如 CLdi → L）。
func cliff_ids_for_tileset(tileset_letter: String) -> PackedStringArray:
	var letter := tileset_letter.strip_edges().to_upper()
	var store := _def_store()
	if store == null:
		return PackedStringArray()
	return store.find_ids(
		CliffTypeDef.TABLE_NAME,
		func(_id: String, row: Resource) -> bool:
			var d := row as CliffTypeDef
			return d != null and d.get_tileset_letter() == letter
	)


func name_key_for_tile_id(tile_id: String) -> String:
	var d := _terrain_def(tile_id)
	return d.display_name_key() if d != null else ""


func display_name_for_tile_id(tile_id: String) -> String:
	var n := name_key_for_tile_id(tile_id)
	return tile_id if n.is_empty() else n


## Terrain.slk `buildable`；缺省视为可建造。
func is_buildable(tile_id: String) -> bool:
	var d := _terrain_def(tile_id)
	return true if d == null else d.buildable


func png_for_tile_id(tile_id: String) -> String:
	return str(_tile_to_png.get(tile_id, ""))


func png_for_cliff_id(cliff_id: String) -> String:
	return str(_cliff_to_png.get(cliff_id, ""))


func ground_tile_for_cliff_id(cliff_id: String) -> String:
	var d := _cliff_def(cliff_id)
	return d.ground_tile if d != null else ""


func cliff_model_dir(cliff_id: String) -> String:
	var d := _cliff_def(cliff_id)
	return d.cliff_model_dir if d != null else "Cliffs"


func cliff_ramp_dir(cliff_id: String) -> String:
	var d := _cliff_def(cliff_id)
	return d.ramp_model_dir if d != null else "CliffTrans"


func png_for_ground_index(ground_tilesets: Array, index: int) -> String:
	if index < 0 or index >= ground_tilesets.size():
		return ""
	return png_for_tile_id(str(ground_tilesets[index]))


func png_for_cliff_index(cliff_tilesets: Array, index: int) -> String:
	if index < 0 or index >= cliff_tilesets.size():
		return ""
	return png_for_cliff_id(str(cliff_tilesets[index]))


## —— 资源映射：Def 列 → converted PNG ——

func _rebuild_tile_png_cache() -> void:
	var store := _def_store()
	if store == null:
		MapLog.warn(MapLog.Layer.CATALOG, "TerrainTiles", "DefStore 不可用，无法解析地表贴图")
		return
	store.ensure_table(TerrainTileDef.TABLE_NAME)
	for id in store.get_ids(TerrainTileDef.TABLE_NAME):
		var d: TerrainTileDef = store.get_row(TerrainTileDef.TABLE_NAME, id) as TerrainTileDef
		if d == null or d.dir.is_empty() or d.file.is_empty():
			continue
		_tile_to_png[id] = RuntimeAssets.converted_path("%s/%s.png" % [d.dir, d.file])
	MapLog.debug(
		MapLog.Layer.CATALOG,
		"TerrainTiles",
		"tile png cache from DefStore count=%d" % _tile_to_png.size()
	)


func _rebuild_cliff_png_cache() -> void:
	var store := _def_store()
	if store == null:
		MapLog.warn(MapLog.Layer.CATALOG, "TerrainTiles", "DefStore 不可用，无法解析悬崖贴图")
		return
	store.ensure_table(CliffTypeDef.TABLE_NAME)
	for id in store.get_ids(CliffTypeDef.TABLE_NAME):
		var d: CliffTypeDef = store.get_row(CliffTypeDef.TABLE_NAME, id) as CliffTypeDef
		if d == null or d.tex_dir.is_empty() or d.tex_file.is_empty():
			continue
		_cliff_to_png[id] = _resolve_cliff_png(d.tex_dir, d.tex_file, id)
	MapLog.debug(
		MapLog.Layer.CATALOG,
		"TerrainTiles",
		"cliff png cache from DefStore count=%d" % _cliff_to_png.size()
	)


func _terrain_def(tile_id: String) -> TerrainTileDef:
	var store := _def_store()
	if store == null:
		return null
	return store.get_row(TerrainTileDef.TABLE_NAME, tile_id) as TerrainTileDef


func _cliff_def(cliff_id: String) -> CliffTypeDef:
	var store := _def_store()
	if store == null:
		return null
	return store.get_row(CliffTypeDef.TABLE_NAME, cliff_id) as CliffTypeDef


func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


## cliffID 如 CIsn → 地形集字母 I；优先 I_Cliff1.png。
## Icecrown（I）经典解包常无独立 I_Cliff*，回退 Northrend（N）。
## 洛丹伦夏天（L）常无 L_Cliff*，回退无前缀 Cliff0/Cliff1。
static func _resolve_cliff_png(dir: String, tex_file: String, cliff_id: String) -> String:
	var tileset := ""
	if cliff_id.length() >= 2:
		tileset = cliff_id.substr(1, 1).to_upper()
	var alt := _tileset_texture_fallback(tileset)
	var candidates: Array[String] = []
	for ts in [tileset, alt]:
		if ts.is_empty():
			continue
		candidates.append("%s/%s_%s.png" % [dir, ts, tex_file])
		candidates.append("%s/%s_%s.png" % [dir, ts, tex_file.to_lower()])
		candidates.append("%s/%s%s.png" % [dir, ts, tex_file])
	candidates.append("%s/%s.png" % [dir, tex_file])
	candidates.append("%s/%s.png" % [dir, tex_file.to_lower()])
	for c in candidates:
		var res_path := RuntimeAssets.converted_path(c)
		if RuntimeAssets.file_exists(res_path):
			return res_path
	return RuntimeAssets.converted_path(candidates[candidates.size() - 1])


## 地形集贴图字母回退（无独立 MPQ 前缀时）。
static func _tileset_texture_fallback(tileset: String) -> String:
	match tileset:
		"I":
			return "N" # Icecrown → Northrend
		"L":
			return "" # 走无前缀 Cliff0/1
		_:
			return ""
