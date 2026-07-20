class_name Wc3IdCatalog
extends RefCounted
## 从 slk-exported JSON 建立四字符 ID → 显示信息 / GLB 路径。

var _units: Dictionary = {}
var _destructables: Dictionary = {}
var _doodads: Dictionary = {}


func load_default() -> void:
	_load_unit_ui("res://assets/slk-exported/Units/unitUI.json")
	_load_destructables("res://assets/slk-exported/Units/DestructableData.json")
	_load_doodads("res://assets/slk-exported/Doodads/Doodads.json")


func lookup(type_id: String) -> Dictionary:
	if _units.has(type_id):
		return _units[type_id]
	if _destructables.has(type_id):
		return _destructables[type_id]
	if _doodads.has(type_id):
		return _doodads[type_id]
	return {"id": type_id, "name": type_id, "file": "", "kind": "unknown", "num_var": 1}


func model_base_path(type_id: String) -> String:
	var info: Dictionary = lookup(type_id)
	var file := str(info.get("file", "")).replace("\\", "/")
	if file.is_empty() or file == "_":
		return ""
	if file.to_lower().ends_with(".mdx") or file.to_lower().ends_with(".mdl"):
		file = file.substr(0, file.length() - 4)
	return file


## 解析已转换 GLB；树木等带 variation 后缀（LordaeronTree0.glb）。
func converted_glb_path(type_id: String, variation: int = 0) -> String:
	var base := model_base_path(type_id)
	if base.is_empty():
		return ""
	var candidates: PackedStringArray = [
		"res://assets/asset-converted/%s%d.glb" % [base, variation],
		"res://assets/asset-converted/%s.glb" % base,
		"res://assets/asset-converted/%s0.glb" % base,
	]
	for p in candidates:
		# asset-converted 被 .gdignore，不能用 ResourceLoader
		if RuntimeAssets.file_exists(p):
			return p
	return ""


func _load_unit_ui(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty():
		return
	for rec in data.get("records", []):
		var id := str(rec.get("unitUIID", ""))
		if id.is_empty():
			continue
		_units[id] = {
			"id": id,
			"name": str(rec.get("name", id)),
			"file": str(rec.get("file", "")),
			"kind": "unit",
			"num_var": 1,
		}


func _load_destructables(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty():
		return
	for rec in data.get("records", []):
		var id := str(rec.get("DestructableID", ""))
		if id.is_empty():
			continue
		_destructables[id] = {
			"id": id,
			"name": str(rec.get("comment", id)),
			"file": str(rec.get("file", "")),
			"kind": "destructable",
			"num_var": int(rec.get("numVar", 1)),
			"tex_file": str(rec.get("texFile", "")),
		}


func _load_doodads(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty():
		return
	for rec in data.get("records", []):
		var id := str(rec.get("doodID", ""))
		if id.is_empty():
			continue
		_doodads[id] = {
			"id": id,
			"name": str(rec.get("comment", id)),
			"file": str(rec.get("file", "")),
			"kind": "doodad",
			"num_var": int(rec.get("numVar", 1)),
		}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Wc3IdCatalog: 缺少 %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Wc3IdCatalog: 无法打开 %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Wc3IdCatalog: JSON 无效 %s" % path)
		return {}
	return parsed
