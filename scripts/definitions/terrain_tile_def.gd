class_name TerrainTileDef
extends Resource

## Terrain.slk 一行定义（静态表数据，不含贴图路径解析）。

const TABLE_NAME := "Terrain"
const SLK_REL_PATH := "TerrainArt/Terrain.json"
const PRIMARY_KEY := "tileID"

@export var tile_id: String = ""
@export var cliff_set: int = -1
@export var dir: String = ""
@export var file: String = ""
@export var comment: String = ""
@export var name_key: String = ""
@export var buildable: bool = true
@export var footprints: bool = true
@export var walkable: bool = true
@export var flyable: bool = true
@export var blight_pri: int = 0
@export var convert_to: String = ""
@export var in_beta: bool = false
@export var version: int = 0


## 显示用名称键：优先 name，空则 comment。
func display_name_key() -> String:
	if not name_key.is_empty() and name_key != "_":
		return name_key
	if not comment.is_empty() and comment != "_":
		return comment
	return tile_id


## 地形集字母：tileID 首字符（Ldrt → L）。
func get_tileset_letter() -> String:
	if tile_id.is_empty():
		return ""
	return tile_id.substr(0, 1).to_upper()


static func from_slk_record(rec: Dictionary) -> TerrainTileDef:
	var d := TerrainTileDef.new()
	d.tile_id = str(rec.get("tileID", "")).strip_edges()
	d.cliff_set = int(rec.get("cliffSet", -1))
	d.dir = str(rec.get("dir", "")).replace("\\", "/").strip_edges()
	d.file = str(rec.get("file", "")).strip_edges()
	d.comment = str(rec.get("comment", "")).strip_edges()
	d.name_key = str(rec.get("name", "")).strip_edges()
	d.buildable = int(rec.get("buildable", 1)) != 0
	d.footprints = int(rec.get("footprints", 1)) != 0
	d.walkable = int(rec.get("walkable", 1)) != 0
	d.flyable = int(rec.get("flyable", 1)) != 0
	d.blight_pri = int(rec.get("blightPri", 0))
	d.convert_to = str(rec.get("convertTo", "")).strip_edges()
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	d.version = int(rec.get("version", 0))
	return d


static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("TerrainTileDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
