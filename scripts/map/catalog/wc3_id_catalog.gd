class_name Wc3IdCatalog
extends RefCounted
## 从 slk-exported JSON 建立四字符 ID → 显示信息 / GLB 路径。


var _units: Dictionary = {}
var _destructables: Dictionary = {}
var _doodads: Dictionary = {}


func load_default() -> void:
	_load_unit_ui(RuntimeAssets.slk_path("Units/unitUI.json"))
	_load_destructables(RuntimeAssets.slk_path("Units/DestructableData.json"))
	_load_doodads(RuntimeAssets.slk_path("Doodads/Doodads.json"))


func lookup(type_id: String) -> Dictionary:
	if _units.has(type_id):
		return _units[type_id]
	if _destructables.has(type_id):
		return _destructables[type_id]
	if _doodads.has(type_id):
		return _doodads[type_id]
	return {"id": type_id, "name": type_id, "file": "", "kind": "unknown", "num_var": 1}


## 可放置物列表（装饰物 + 可破坏物），按显示名排序。
## 每项为 lookup() 同形 Dictionary。
func list_placeables(include_doodads: bool = true, include_destructables: bool = true) -> Array:
	return list_placeables_filtered("", "", include_doodads, include_destructables)


## 按地形集字母 + 分类码筛选。
## tileset_letter 空/"*" = 不限；条目 tilesets 含 "*" 或含该字母才通过。
## category_code 空/"*" = 不限；否则精确匹配 entry.category。
func list_placeables_filtered(
	tileset_letter: String = "",
	category_code: String = "",
	include_doodads: bool = true,
	include_destructables: bool = true,
) -> Array:
	var out: Array = []
	var ts := tileset_letter.strip_edges().to_upper()
	var cat := category_code.strip_edges().to_upper()
	if include_doodads:
		for id in _doodads.keys():
			var e: Dictionary = _doodads[id]
			if _entry_matches(e, ts, cat):
				out.append(e)
	if include_destructables:
		for id in _destructables.keys():
			var e2: Dictionary = _destructables[id]
			if _entry_matches(e2, ts, cat):
				out.append(e2)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)
	return out


func doodad_count() -> int:
	return _doodads.size()


func destructable_count() -> int:
	return _destructables.size()


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
		"%s%d.glb" % [base, variation],
		"%s.glb" % base,
		"%s0.glb" % base,
	]
	for rel in candidates:
		var p := RuntimeAssets.converted_path(rel)
		if RuntimeAssets.file_exists(p):
			return p
	return ""


func _entry_matches(e: Dictionary, tileset_letter: String, category_code: String) -> bool:
	if not category_code.is_empty() and category_code != "*":
		if str(e.get("category", "")).to_upper() != category_code:
			return false
	if not tileset_letter.is_empty() and tileset_letter != "*":
		if not _tilesets_allow(str(e.get("tilesets", "")), tileset_letter):
			return false
	return true


## tilesets 字段如 "A,G" / "*" / "L"。
static func _tilesets_allow(tilesets_field: String, letter: String) -> bool:
	var raw := tilesets_field.strip_edges()
	if raw.is_empty() or raw == "*":
		return true
	var want := letter.to_upper()
	for part in raw.split(","):
		var p := part.strip_edges().to_upper()
		if p == "*" or p == want:
			return true
	return false


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
		var comment := str(rec.get("comment", ""))
		_destructables[id] = {
			"id": id,
			"name": comment if not comment.is_empty() else id,
			"name_key": str(rec.get("Name", "")),
			"file": str(rec.get("file", "")),
			"kind": "destructable",
			"category": str(rec.get("category", "")).to_upper(),
			"tilesets": str(rec.get("tilesets", "*")),
			"num_var": int(rec.get("numVar", 1)),
			"tex_file": str(rec.get("texFile", "")),
			"def_scale": float(rec.get("minScale", 1.0)),
			"min_scale": float(rec.get("minScale", 1.0)),
			"max_scale": float(rec.get("maxScale", 1.0)),
			"can_place_rand_scale": int(rec.get("canPlaceRandScale", 0)) != 0,
			"use_click_helper": int(rec.get("useClickHelper", 0)) != 0,
			"sel_size": float(rec.get("selSize", 0.0)),
			"ignore_model_click": int(rec.get("ignoreModelClick", 0)) != 0,
		}


func _load_doodads(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty():
		return
	for rec in data.get("records", []):
		var id := str(rec.get("doodID", ""))
		if id.is_empty():
			continue
		var comment := str(rec.get("comment", ""))
		_doodads[id] = {
			"id": id,
			"name": comment if not comment.is_empty() else id,
			"name_key": str(rec.get("Name", "")),
			"file": str(rec.get("file", "")),
			"kind": "doodad",
			"category": str(rec.get("category", "")).to_upper(),
			"tilesets": str(rec.get("tilesets", "*")),
			"num_var": int(rec.get("numVar", 1)),
			"def_scale": float(rec.get("defScale", 1.0)),
			"min_scale": float(rec.get("minScale", 1.0)),
			"max_scale": float(rec.get("maxScale", 1.0)),
			"can_place_rand_scale": int(rec.get("canPlaceRandScale", 0)) != 0,
			"use_click_helper": int(rec.get("useClickHelper", 0)) != 0,
			"sel_size": float(rec.get("selSize", 0.0)),
			"ignore_model_click": int(rec.get("ignoreModelClick", 0)) != 0,
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
