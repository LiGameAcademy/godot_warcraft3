class_name AbilityMetaDataDef
extends Resource

## Units/AbilityMetaData.slk 一行定义。

const TABLE_NAME := "AbilityMetaData"
const SLK_REL_PATH := "Units/AbilityMetaData.json"
const PRIMARY_KEY := "ID"

@export var id: String = ""
@export var field: String = ""
@export var slk: String = ""
@export var field_index: int = 0
@export var repeat_count: int = 0
@export var data: int = 0
@export var category: String = ""
@export var display_name_key: String = ""
@export var sort_key: String = ""
@export var type_name: String = ""
@export var change_flags: String = ""
@export var import_type: String = ""
@export var string_ext: int = 0
@export var case_sens: bool = false
@export var can_be_empty: bool = false
@export var min_val: float = 0.0
@export var max_val: float = 0.0
@export var force_non_neg: bool = false
@export var use_unit: int = 0
@export var use_hero: int = 0
@export var use_item: int = 0
@export var use_creep: int = 0
@export var use_specific: String = ""
@export var not_specific: String = ""
@export var version: int = 0
@export var section_name: String = ""

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	return id

static func from_slk_record(rec: Dictionary) -> AbilityMetaDataDef:
	var d := AbilityMetaDataDef.new()
	d.id = str(rec.get("ID", "")).strip_edges()
	d.field = str(rec.get("field", "")).strip_edges()
	d.slk = str(rec.get("slk", "")).strip_edges()
	d.field_index = int(rec.get("index", 0))
	d.repeat_count = int(rec.get("repeat", 0))
	d.data = int(rec.get("data", 0))
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
	d.use_unit = int(rec.get("useUnit", 0))
	d.use_hero = int(rec.get("useHero", 0))
	d.use_item = int(rec.get("useItem", 0))
	d.use_creep = int(rec.get("useCreep", 0))
	d.use_specific = str(rec.get("useSpecific", "")).strip_edges()
	d.not_specific = str(rec.get("notSpecific", "")).strip_edges()
	d.version = int(rec.get("version", 0))
	d.section_name = str(rec.get("section", "")).strip_edges()
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("AbilityMetaDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
