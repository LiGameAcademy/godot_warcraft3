class_name Wc3CliffCatalog
extends RefCounted

## 直崖 Catalog：CliffTypeDef（表列）+ 岩壁 PNG / 模型目录解析（资源映射）。
## 与 Wc3TerrainTiles（地表）分离；斜坡目录见 ramp_model_dir + Wc3CliffTransCatalog。

## 仅缓存解析后的岩壁贴图路径
var _cliff_to_png: Dictionary[String, String] = {}


func load_default() -> void:
	_cliff_to_png.clear()
	_rebuild_cliff_png_cache()


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


func png_for_cliff_id(cliff_id: String) -> String:
	return str(_cliff_to_png.get(cliff_id, ""))


func ground_tile_for_cliff_id(cliff_id: String) -> String:
	var d := _cliff_def(cliff_id)
	return d.ground_tile if d != null else ""


func cliff_model_dir(cliff_id: String) -> String:
	var d := _cliff_def(cliff_id)
	return d.cliff_model_dir if d != null else "Cliffs"


func ramp_model_dir(cliff_id: String) -> String:
	var d := _cliff_def(cliff_id)
	return d.ramp_model_dir if d != null else "CliffTrans"


func png_for_cliff_index(cliff_tilesets: Array, index: int) -> String:
	if index < 0 or index >= cliff_tilesets.size():
		return ""
	return png_for_cliff_id(str(cliff_tilesets[index]))


## 表行：DefStore → CliffTypeDef。
func get_def(cliff_id: String) -> CliffTypeDef:
	return _cliff_def(cliff_id)


## —— 资源映射：Def 列 → converted PNG ——

func _rebuild_cliff_png_cache() -> void:
	var store := _def_store()
	if store == null:
		MapLog.warn(MapLog.Layer.CATALOG, "CliffCatalog", "DefStore 不可用，无法解析悬崖贴图")
		return
	store.ensure_table(CliffTypeDef.TABLE_NAME)
	for id in store.get_ids(CliffTypeDef.TABLE_NAME):
		var d: CliffTypeDef = store.get_row(CliffTypeDef.TABLE_NAME, id) as CliffTypeDef
		if d == null or d.tex_dir.is_empty() or d.tex_file.is_empty():
			continue
		_cliff_to_png[id] = resolve_cliff_png(d.tex_dir, d.tex_file, id)
	MapLog.debug(
		MapLog.Layer.CATALOG,
		"CliffCatalog",
		"cliff png cache count=%d" % _cliff_to_png.size()
	)


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


## cliffID 如 CIsn → 优先 I_Cliff1.png；缺则按 tileset 回退。
static func resolve_cliff_png(dir: String, tex_file: String, cliff_id: String) -> String:
	var tileset := ""
	if cliff_id.length() >= 2:
		tileset = cliff_id.substr(1, 1).to_upper()
	var alt := tileset_texture_fallback(tileset)
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


## 地形集贴图字母回退（无独立 MPQ 前缀时）。崖壁/水面帧共用。
static func tileset_texture_fallback(tileset: String) -> String:
	match tileset:
		"I":
			return "N" # Icecrown → Northrend
		"L":
			return "" # 走无前缀 Cliff0/1
		_:
			return ""
