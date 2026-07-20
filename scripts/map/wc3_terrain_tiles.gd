class_name Wc3TerrainTiles
extends RefCounted

## tileID / cliffID → 贴图路径与悬崖模型目录。
##
## 悬崖贴图路径在 SLK 里始终是 ReplaceableTextures/Cliff/Cliff0|1，
## 但经典客户端按地图 mainTileset 从 A.mpq / I.mpq 等子包解析不同内容。
## 解包时用 {tileset}_Cliff0.png 保存（如 I_Cliff1 = Icecrown）。

var _tile_to_png: Dictionary = {}
var _cliff_to_png: Dictionary = {}
var _cliff_model_dir: Dictionary = {}
var _cliff_ramp_dir: Dictionary = {}
var _cliff_ground_tile: Dictionary = {}


func load_default() -> void:
	_load_terrain_slk(RuntimeAssets.slk_path("TerrainArt/Terrain.json"))
	_load_cliff_slk(RuntimeAssets.slk_path("TerrainArt/CliffTypes.json"))


func png_for_tile_id(tile_id: String) -> String:
	return str(_tile_to_png.get(tile_id, ""))


func png_for_cliff_id(cliff_id: String) -> String:
	return str(_cliff_to_png.get(cliff_id, ""))


func ground_tile_for_cliff_id(cliff_id: String) -> String:
	return str(_cliff_ground_tile.get(cliff_id, ""))


func cliff_model_dir(cliff_id: String) -> String:
	return str(_cliff_model_dir.get(cliff_id, "Cliffs"))


func cliff_ramp_dir(cliff_id: String) -> String:
	return str(_cliff_ramp_dir.get(cliff_id, "CliffTrans"))


func png_for_ground_index(ground_tilesets: Array, index: int) -> String:
	if index < 0 or index >= ground_tilesets.size():
		return ""
	return png_for_tile_id(str(ground_tilesets[index]))


func png_for_cliff_index(cliff_tilesets: Array, index: int) -> String:
	if index < 0 or index >= cliff_tilesets.size():
		return ""
	return png_for_cliff_id(str(cliff_tilesets[index]))


func _load_terrain_slk(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("Wc3TerrainTiles: 缺少 %s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	for rec in data.get("records", []):
		var id := str(rec.get("tileID", ""))
		if id.is_empty():
			continue
		var dir := str(rec.get("dir", "")).replace("\\", "/")
		var file := str(rec.get("file", ""))
		if dir.is_empty() or file.is_empty():
			continue
		var png := RuntimeAssets.converted_path("%s/%s.png" % [dir, file])
		_tile_to_png[id] = png


func _load_cliff_slk(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("Wc3TerrainTiles: 缺少 %s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	for rec in data.get("records", []):
		var id := str(rec.get("cliffID", ""))
		if id.is_empty():
			continue
		var dir := str(rec.get("texDir", "")).replace("\\", "/")
		var file := str(rec.get("texFile", ""))
		if not dir.is_empty() and not file.is_empty():
			_cliff_to_png[id] = _resolve_cliff_png(dir, file, id)
		var ground := str(rec.get("groundTile", "")).strip_edges()
		if not ground.is_empty() and ground != "_":
			_cliff_ground_tile[id] = ground
		var model_dir := str(rec.get("cliffModelDir", "")).strip_edges()
		var ramp_dir := str(rec.get("rampModelDir", "")).strip_edges()
		if not model_dir.is_empty():
			_cliff_model_dir[id] = model_dir
		if not ramp_dir.is_empty():
			_cliff_ramp_dir[id] = ramp_dir


## cliffID 如 CIsn → 地形集字母 I；优先 I_Cliff1.png，再回退 Cliff1.png。
static func _resolve_cliff_png(dir: String, tex_file: String, cliff_id: String) -> String:
	var tileset := ""
	if cliff_id.length() >= 2:
		tileset = cliff_id.substr(1, 1)
	var candidates: Array[String] = []
	if not tileset.is_empty():
		candidates.append("%s/%s_%s.png" % [dir, tileset, tex_file])
		candidates.append("%s/%s_%s.png" % [dir, tileset, tex_file.to_lower()])
		candidates.append("%s/%s%s.png" % [dir, tileset, tex_file])
	candidates.append("%s/%s.png" % [dir, tex_file])
	for c in candidates:
		var res_path := RuntimeAssets.converted_path(c)
		if RuntimeAssets.file_exists(res_path):
			return res_path
	return RuntimeAssets.converted_path(candidates[candidates.size() - 1])
