class_name UberSplatDef
extends Resource

## Splats/UberSplatData.slk 一行（建筑 Ground Texture / 临时贴花）。

const TABLE_NAME := "UberSplatData"
const SLK_REL_PATH := "Splats/UberSplatData.json"
const PRIMARY_KEY := "Name"

@export var name_id: String = ""
@export var comment: String = ""
@export var dir: String = ""
@export var file: String = ""
@export var blend_mode: int = 0
@export var scale: float = 0.0
@export var birth_time: float = 0.0
@export var pause_time: float = 0.0
@export var decay: float = 0.0


static func from_slk_record(rec: Dictionary) -> UberSplatDef:
	var d := UberSplatDef.new()
	d.name_id = str(rec.get("Name", "")).strip_edges()
	d.comment = str(rec.get("comment", "")).strip_edges()
	d.dir = str(rec.get("Dir", "")).replace("\\", "/").strip_edges()
	d.file = str(rec.get("file", "")).replace("\\", "/").strip_edges()
	d.blend_mode = int(rec.get("BlendMode", 0))
	d.scale = float(rec.get("Scale", 0.0))
	d.birth_time = float(rec.get("BirthTime", 0.0))
	d.pause_time = float(rec.get("PauseTime", 0.0))
	d.decay = float(rec.get("Decay", 0.0))
	return d


static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("UberSplatDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
