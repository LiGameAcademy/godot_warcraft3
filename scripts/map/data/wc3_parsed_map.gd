class_name Wc3ParsedMap
extends RefCounted
## map-parsed/<slug>/ 目录的薄包装。heightfield 必载；doodads / units 按需 SoA。


var slug: String = ""
var dir_res: String = "" ## 如 res://assets/map-parsed/losttemple
var heightfield: Wc3Heightfield
var doodads: Wc3DoodadList
var units: Wc3UnitList
var terrain_header: Dictionary = {} ## terrain.json 原始（后续换成专用类）
var info: Dictionary = {} ## info.json 原始
var summary: Dictionary = {}


static func load_dir(dir_res_path: String) -> Wc3ParsedMap:
	var m := Wc3ParsedMap.new()
	m.dir_res = dir_res_path.rstrip("/")
	m.slug = m.dir_res.get_file()
	var hf_path: String = m.dir_res.path_join("terrain-heightfield.json")
	m.heightfield = Wc3Heightfield.load_json_path(hf_path)
	if m.heightfield == null or not m.heightfield.is_valid():
		push_error("Wc3ParsedMap: heightfield 无效 %s" % hf_path)
		return null
	m.terrain_header = _load_json_dict(m.dir_res.path_join("terrain.json"))
	m.info = _load_json_dict(m.dir_res.path_join("info.json"))
	m.summary = _load_json_dict(m.dir_res.path_join("summary.json"))
	var dood_path: String = m.dir_res.path_join("doodads.json")
	if FileAccess.file_exists(RuntimeAssets.project_abs(dood_path)):
		m.doodads = Wc3DoodadList.load_json_path(dood_path)
	var unit_path: String = m.dir_res.path_join("units.json")
	if FileAccess.file_exists(RuntimeAssets.project_abs(unit_path)):
		m.units = Wc3UnitList.load_json_path(unit_path)
	return m


static func _load_json_dict(res_path: String) -> Dictionary:
	var disk_path := RuntimeAssets.project_abs(res_path)
	if not FileAccess.file_exists(disk_path):
		return {}
	var text := RuntimeAssets.read_utf8_text(disk_path)
	if text.is_empty():
		return {}
	var parsed: Variant = RuntimeAssets.parse_json_text(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func vertex_at(ix: int, iy: int) -> Wc3TileVertex:
	if heightfield == null:
		return null
	return heightfield.vertex_at(ix, iy)


func doodad_at(index: int) -> Wc3Doodad:
	if doodads == null:
		return null
	return doodads.at(index)


func unit_at(index: int) -> Wc3UnitPlacement:
	if units == null:
		return null
	return units.at(index)
