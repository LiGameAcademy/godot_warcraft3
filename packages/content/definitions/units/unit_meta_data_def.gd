class_name UnitMetaDataDef
extends Resource

## Units/UnitMetaData.slk 一行定义。
##
## 职责：对象编辑器「单位」字段元数据（字段落到哪张 SLK、类型与适用范围）。

const TABLE_NAME := "UnitMetaData"
const SLK_REL_PATH := "Units/UnitMetaData.json"
const PRIMARY_KEY := "ID"

@export var id: String = "" ## 元数据行主键
@export var field: String = "" ## 对应 SLK/对象编辑器字段名
@export var slk: String = "" ## 所属 SLK 表名（UnitUI / UnitBalance / UnitData…）
@export var field_index: int = 0 ## 字段索引
@export var category: String = "" ## 编辑器分类页签
@export var display_name_key: String = "" ## 显示名字符串键
@export var sort_key: String = "" ## 编辑器内排序
@export var type_name: String = "" ## 字段值类型
@export var change_flags: String = "" ## 修改标志
@export var import_type: String = "" ## 导入资源类型
@export var string_ext: int = 0 ## 字符串扩展标志
@export var case_sens: bool = false ## 字符串是否区分大小写
@export var can_be_empty: bool = false ## 是否允许空值
@export var min_val: float = 0.0 ## 数值下限
@export var max_val: float = 0.0 ## 数值上限
@export var force_non_neg: bool = false ## 是否强制非负
@export var use_hero: int = 0 ## 是否用于英雄（>0 适用）
@export var use_unit: int = 0 ## 是否用于普通单位
@export var use_building: int = 0 ## 是否用于建筑
@export var use_item: int = 0 ## 是否用于物品（单位编辑器交叉字段）
@export var use_specific: String = "" ## 仅限特定单位 ID 列表
@export var version: int = 0 ## 数据版本标记
@export var section_name: String = "" ## 编辑器分区名

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	return id

static func from_slk_record(rec: Dictionary) -> UnitMetaDataDef:
	var d := UnitMetaDataDef.new()
	d.id = str(rec.get("ID", "")).strip_edges()
	d.field = str(rec.get("field", "")).strip_edges()
	d.slk = str(rec.get("slk", "")).strip_edges()
	d.field_index = int(rec.get("index", 0))
	d.category = str(rec.get("category", "")).strip_edges()
	d.display_name_key = str(rec.get("displayName", "")).strip_edges()
	d.sort_key = str(rec.get("sort", "")).strip_edges()
	d.type_name = str(rec.get("type", "")).strip_edges()
	d.change_flags = str(rec.get("changeFlags", "")).strip_edges()
	d.import_type = str(rec.get("importType", "")).strip_edges()
	d.string_ext = int(rec.get("stringExt", 0))
	d.case_sens = int(rec.get("caseSens", 0)) != 0
	d.can_be_empty = int(rec.get("canBeEmpty", 0)) != 0
	d.min_val = float(rec.get("minVal", 0.0))
	d.max_val = float(rec.get("maxVal", 0.0))
	d.force_non_neg = int(rec.get("forceNonNeg", 0)) != 0
	d.use_hero = int(rec.get("useHero", 0))
	d.use_unit = int(rec.get("useUnit", 0))
	d.use_building = int(rec.get("useBuilding", 0))
	d.use_item = int(rec.get("useItem", 0))
	d.use_specific = str(rec.get("useSpecific", "")).strip_edges()
	d.version = int(rec.get("version", 0))
	d.section_name = str(rec.get("section", "")).strip_edges()
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("UnitMetaDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
