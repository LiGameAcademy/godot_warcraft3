class_name DoodadMetaDataDef
extends Resource

## Doodads/DoodadMetaData.slk 一行定义。
##
## 职责：对象编辑器「装饰物」字段元数据（字段名、类型、取值范围、页签），
## 不是装饰物实例数据（实例见 DoodadDataDef / Doodads.slk）。

const TABLE_NAME := "DoodadMetaData"
const SLK_REL_PATH := "Doodads/DoodadMetaData.json"
const PRIMARY_KEY := "ID"

@export var id: String = "" ## 元数据行主键（四字符，如 dnam / dcat）
@export var field: String = "" ## 对应 SLK/对象编辑器字段名（Name、category、vertR01…）
@export var slk: String = "" ## 所属 SLK 逻辑名（常为 DoodadData）
@export var field_index: int = 0 ## 字段索引（index；重复组内序号）
@export var category: String = "" ## 编辑器分类页签（text / editor / art / stats…）
@export var display_name_key: String = "" ## 显示名字符串键（WESTRING_DEVAL_*）
@export var sort_key: String = "" ## 编辑器内排序键
@export var type_name: String = "" ## 字段值类型（string / real / bool / model / doodadCategory…）
@export var change_flags: String = "" ## 修改标志（何种操作可改此字段）
@export var import_type: String = "" ## 导入资源类型（模型/图标等；可空）
@export var string_ext: int = 0 ## 字符串扩展/本地化相关标志
@export var case_sens: bool = false ## 字符串是否区分大小写
@export var can_be_empty: bool = false ## 是否允许空值
@export var min_val: String = "" ## 下限（数值或 WE 约束键；原表可为字符串）
@export var max_val: String = "" ## 上限（数值或 WE 约束键，如 TTName）
@export var force_non_neg: bool = false ## 是否强制非负
@export var version: int = 0 ## 数据版本标记
@export var section_name: String = "" ## 编辑器分区名（section；可空）

## 显示名：主键。
func display_name() -> String:
	return id


static func from_slk_record(rec: Dictionary) -> DoodadMetaDataDef:
	var d := DoodadMetaDataDef.new()
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
	d.min_val = str(rec.get("minVal", "")).strip_edges()
	d.max_val = str(rec.get("maxVal", "")).strip_edges()
	d.force_non_neg = int(rec.get("forceNonNeg", 0)) != 0
	d.version = int(rec.get("version", 0))
	d.section_name = str(rec.get("section", "")).strip_edges()
	return d


static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("DoodadMetaDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
