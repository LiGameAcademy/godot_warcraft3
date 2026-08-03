class_name UpgradeEffectMetaDataDef
extends Resource

## Units/UpgradeEffectMetaData.slk 一行定义。

const TABLE_NAME := "UpgradeEffectMetaData"
const SLK_REL_PATH := "Units/UpgradeEffectMetaData.json"
const PRIMARY_KEY := "ID"

@export var id: String = ""
@export var effect_id: String = ""
@export var comment: String = ""
@export var data_type: String = ""
@export var display_name_key: String = ""
@export var type_name: String = ""
@export var min_val: float = 0.0
@export var max_val: float = 0.0
@export var force_non_neg: bool = false
@export var version: int = 0
@export var string_ext: String = ""
@export var case_sens: bool = false
@export var can_be_empty: bool = false
@export var import_type: String = ""
@export var field: String = ""
@export var slk: String = ""
@export var field_index: String = ""
@export var sort_key: String = ""
@export var change_flags: String = ""
@export var category: String = ""
@export var section_name: String = ""

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else id

static func from_slk_record(rec: Dictionary) -> UpgradeEffectMetaDataDef:
	var d := UpgradeEffectMetaDataDef.new()
	d.id = str(rec.get("ID", "")).strip_edges()
	d.effect_id = str(rec.get("effectID", "")).strip_edges()
	d.comment = str(rec.get("comment", "")).strip_edges()
	d.data_type = str(rec.get("dataType", "")).strip_edges()
	d.display_name_key = str(rec.get("displayName", "")).strip_edges()
	d.type_name = str(rec.get("type", "")).strip_edges()
	d.min_val = float(rec.get("minVal", 0.0))
	d.max_val = float(rec.get("maxVal", 0.0))
	d.force_non_neg = int(rec.get("forceNonNeg", 0)) != 0
	d.version = int(rec.get("version", 0))
	d.string_ext = str(rec.get("stringExt", "")).strip_edges()
	d.case_sens = int(rec.get("caseSens", 0)) != 0
	d.can_be_empty = int(rec.get("canBeEmpty", 0)) != 0
	d.import_type = str(rec.get("importType", "")).strip_edges()
	d.field = str(rec.get("field", "")).strip_edges()
	d.slk = str(rec.get("slk", "")).strip_edges()
	d.field_index = str(rec.get("index", "")).strip_edges()
	d.sort_key = str(rec.get("sort", "")).strip_edges()
	d.change_flags = str(rec.get("changeFlags", "")).strip_edges()
	d.category = str(rec.get("category", "")).strip_edges()
	d.section_name = str(rec.get("section", "")).strip_edges()
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("UpgradeEffectMetaDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
