class_name TerrainTileDef
extends Resource

## Terrain.slk 一行定义（静态表数据，不含贴图路径解析）。

const TABLE_NAME := "Terrain"
const SLK_REL_PATH := "TerrainArt/Terrain.json"
const PRIMARY_KEY := "tileID"

@export var tile_id: String = ""					## 地形ID
@export var cliff_set: int = -1						## 悬崖集
@export var dir: String = ""						## 目录
@export var file: String = ""						## 文件
@export var comment: String = ""					## 注释
@export var name_key: String = ""					## 名称键
@export var buildable: bool = true					## 可建造
@export var footprints: bool = true					## 可行走
@export var walkable: bool = true					## 可行走
@export var flyable: bool = true					## 可飞行
@export var blight_pri: int = 0						## 污染优先级
@export var convert_to: String = ""					## 转换为
@export var in_beta: bool = false					## 是否在Beta版
@export var version: int = 0						## 版本

## 显示用名称键：优先 name，空则 comment。
## [return String] 显示用名称键
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

## [static] 从SLK记录创建地形类型定义
## [param rec Dictionary] SLK记录
## [return TerrainTileDef] 地形类型定义
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

## 向 DefStore 注册本表（由 Wc3DefStore._ready 调用）。
## [param store] DefStore
## [return void] 无返回值
static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("TerrainTileDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
