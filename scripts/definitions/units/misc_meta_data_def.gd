class_name MiscMetaDataDef
extends Resource

## Units/MiscMetaData.slk 一行定义。
##
## 职责：杂项游戏常量/Gameplay Constants 字段的元数据（非具体常数值）。

const TABLE_NAME := "MiscMetaData"
const SLK_REL_PATH := "Units/MiscMetaData.json"
const PRIMARY_KEY := "ID"

@export var id: String = "" ## 元数据行主键
@export var field: String = "" ## 对应字段名
@export var slk: String = "" ## 所属 SLK / 配置节
@export var section_name: String = "" ## 配置分区名（section）
@export var field_index: int = 0 ## 字段索引
@export var display_name_key: String = "" ## 显示名字符串键
@export var sort_key: String = "" ## 编辑器内排序
@export var type_name: String = "" ## 字段值类型
@export var import_type: String = "" ## 导入资源类型
@export var string_ext: int = 0 ## 字符串扩展标志
@export var case_sens: bool = false ## 字符串是否区分大小写
@export var can_be_empty: bool = false ## 是否允许空值
@export var min_val: float = 0.0 ## 数值下限
@export var max_val: float = 0.0 ## 数值上限
@export var force_non_neg: bool = false ## 是否强制非负
@export var version: int = 0 ## 数据版本标记
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记
@export var change_flags: String = "" ## 修改标志
@export var category: String = "" ## 编辑器分类

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	return id

static func from_slk_record(rec: Dictionary) -> MiscMetaDataDef:
	var d := MiscMetaDataDef.new()
	d.id = str(rec.get("ID", "")).strip_edges()
	d.field = str(rec.get("field", "")).strip_edges()
	d.slk = str(rec.get("slk", "")).strip_edges()
	d.section_name = str(rec.get("section", "")).strip_edges()
	d.field_index = int(rec.get("index", 0))
	d.display_name_key = str(rec.get("displayName", "")).strip_edges()
	d.sort_key = str(rec.get("sort", "")).strip_edges()
	d.type_name = str(rec.get("type", "")).strip_edges()
	d.import_type = str(rec.get("importType", "")).strip_edges()
	d.string_ext = int(rec.get("stringExt", 0))
	d.case_sens = int(rec.get("caseSens", 0)) != 0
	d.can_be_empty = int(rec.get("canBeEmpty", 0)) != 0
	d.min_val = float(rec.get("minVal", 0.0))
	d.max_val = float(rec.get("maxVal", 0.0))
	d.force_non_neg = int(rec.get("forceNonNeg", 0)) != 0
	d.version = int(rec.get("version", 0))
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	d.change_flags = str(rec.get("changeFlags", "")).strip_edges()
	d.category = str(rec.get("category", "")).strip_edges()
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("MiscMetaDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
