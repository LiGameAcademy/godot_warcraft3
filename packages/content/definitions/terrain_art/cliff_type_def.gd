class_name CliffTypeDef
extends Resource

## TerrainArt/CliffTypes.slk 一行定义。
##
## 职责：悬崖类型（模型目录、纹理、关联地面/上层瓦片、悬崖分类）。

const TABLE_NAME := "CliffTypes"
const SLK_REL_PATH := "TerrainArt/CliffTypes.json"
const PRIMARY_KEY := "cliffID"

@export var cliff_id: String = "" ## 主键（如 CLdi；第 2 字符为地形集字母）
@export var cliff_model_dir: String = "Cliffs" ## 悬崖模型目录名
@export var ramp_model_dir: String = "CliffTrans" ## 斜坡/过渡模型目录名
@export var tex_dir: String = "" ## 悬崖纹理目录
@export var tex_file: String = "" ## 悬崖纹理文件名
@export var name_key: String = "" ## 显示名字符串键
@export var ground_tile: String = "" ## 关联的底层地形瓦片 ID
@export var upper_tile: String = "" ## 关联的上层地形瓦片 ID（可空）
@export var cliff_class: String = "" ## 悬崖分类（Cliff / Ramp 等）
@export var old_id: int = 0 ## 旧版数字 ID（兼容）
@export var version: int = 0 ## 数据版本标记
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记

## 悬崖所属地形集字母：cliffID 第 2 字符（CLdi → L，CIsn → I）。
func get_tileset_letter() -> String:
	if cliff_id.length() < 2:
		return ""
	return cliff_id.substr(1, 1).to_upper()

static func from_slk_record(rec: Dictionary) -> CliffTypeDef:
	var d := CliffTypeDef.new()
	d.cliff_id = str(rec.get("cliffID", "")).strip_edges()
	d.cliff_model_dir = str(rec.get("cliffModelDir", "Cliffs")).strip_edges()
	if d.cliff_model_dir.is_empty():
		d.cliff_model_dir = "Cliffs"
	d.ramp_model_dir = str(rec.get("rampModelDir", "CliffTrans")).strip_edges()
	if d.ramp_model_dir.is_empty():
		d.ramp_model_dir = "CliffTrans"
	d.tex_dir = str(rec.get("texDir", "")).replace("\\", "/").strip_edges()
	d.tex_file = str(rec.get("texFile", "")).strip_edges()
	d.name_key = str(rec.get("name", "")).strip_edges()
	var ground := str(rec.get("groundTile", "")).strip_edges()
	d.ground_tile = "" if ground.is_empty() or ground == "_" else ground
	var upper := str(rec.get("upperTile", "")).strip_edges()
	d.upper_tile = "" if upper.is_empty() or upper == "_" else upper
	d.cliff_class = str(rec.get("cliffClass", "")).strip_edges()
	d.old_id = int(rec.get("oldID", 0))
	d.version = int(rec.get("version", 0))
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	return d

## 向 DefStore 注册本表（由 Wc3DefStore._ready 调用）。
static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("CliffTypeDef: 无法注册到 DefStore: store 为空或没有 register_table 方法")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
