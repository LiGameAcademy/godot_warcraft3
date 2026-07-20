class_name Wc3TerrainTiles
extends RefCounted
## tileID / cliffID → 转换后 PNG 的 res:// 路径。


var _tile_to_png: Dictionary = {}
var _cliff_to_png: Dictionary = {}


func load_default() -> void:
	_load_terrain_slk("res://assets/slk-exported/TerrainArt/Terrain.json")
	_load_cliff_slk("res://assets/slk-exported/TerrainArt/CliffTypes.json")


func png_for_tile_id(tile_id: String) -> String:
	return str(_tile_to_png.get(tile_id, ""))


func png_for_cliff_id(cliff_id: String) -> String:
	return str(_cliff_to_png.get(cliff_id, ""))


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
		var png := "res://assets/asset-converted/%s/%s.png" % [dir, file]
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
		if dir.is_empty() or file.is_empty():
			continue
		_cliff_to_png[id] = "res://assets/asset-converted/%s/%s.png" % [dir, file]
