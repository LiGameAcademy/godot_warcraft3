class_name UnitAbilitiesDef
extends Resource

## Units/UnitAbilities.slk 一行定义。

const TABLE_NAME := "UnitAbilities"
const SLK_REL_PATH := "Units/UnitAbilities.json"
const PRIMARY_KEY := "unitAbilID"

@export var unit_abil_id: String = ""
@export var sort_abil: String = ""
@export var comment: String = ""
@export var auto: String = ""
@export var abil_list: String = ""
@export var hero_abil_list: String = ""
@export var in_beta: bool = false

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else unit_abil_id

static func from_slk_record(rec: Dictionary) -> UnitAbilitiesDef:
	var d := UnitAbilitiesDef.new()
	d.unit_abil_id = str(rec.get("unitAbilID", "")).strip_edges()
	d.sort_abil = str(rec.get("sortAbil", "")).strip_edges()
	d.comment = str(rec.get("comment(s)", "")).strip_edges()
	d.auto = str(rec.get("auto", "")).strip_edges()
	d.abil_list = str(rec.get("abilList", "")).strip_edges()
	d.hero_abil_list = str(rec.get("heroAbilList", "")).strip_edges()
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("UnitAbilitiesDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
