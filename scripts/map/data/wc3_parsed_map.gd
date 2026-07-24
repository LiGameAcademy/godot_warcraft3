class_name Wc3ParsedMap
extends RefCounted
## map-parsed/<slug>/ 目录的薄包装。第一阶段只强制加载 heightfield；其余 JSON 按需扩展。


const HeightfieldScript := preload("res://scripts/map/data/wc3_heightfield.gd")


var slug: String = ""
var dir_res: String = "" ## 如 res://assets/map-parsed/losttemple
var heightfield ## Wc3Heightfield
var terrain_header: Dictionary = {} ## terrain.json 原始（后续换成专用类）
var info: Dictionary = {} ## info.json 原始
var summary: Dictionary = {}


static func load_dir(dir_res_path: String):
	var m = new()
	m.dir_res = dir_res_path.rstrip("/")
	m.slug = String(m.dir_res).get_file()
	var hf_path: String = String(m.dir_res).path_join("terrain-heightfield.json")
	m.heightfield = HeightfieldScript.load_json_path(hf_path)
	if m.heightfield == null or not m.heightfield.is_valid():
		push_error("Wc3ParsedMap: heightfield 无效 %s" % hf_path)
		return null
	m.terrain_header = _load_json_dict(String(m.dir_res).path_join("terrain.json"))
	m.info = _load_json_dict(String(m.dir_res).path_join("info.json"))
	m.summary = _load_json_dict(String(m.dir_res).path_join("summary.json"))
	return m


static func _load_json_dict(res_path: String) -> Dictionary:
	var abs := RuntimeAssets.project_abs(res_path)
	if not FileAccess.file_exists(abs):
		return {}
	var f := FileAccess.open(abs, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func vertex_at(ix: int, iy: int):
	if heightfield == null:
		return null
	return heightfield.vertex_at(ix, iy)
