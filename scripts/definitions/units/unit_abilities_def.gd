class_name UnitAbilitiesDef
extends Resource

## Units/UnitAbilities.slk 一行定义。
##
## 职责：单位自带技能列表（普通技能 + 英雄技能），以及默认自动施法技能。

const TABLE_NAME := "UnitAbilities"
const SLK_REL_PATH := "Units/UnitAbilities.json"
const PRIMARY_KEY := "unitAbilID"

@export var unit_abil_id: String = "" ## 主键，与 unitID 对齐
@export var sort_abil: String = "" ## 编辑器排序键
@export var comment: String = "" ## 人类可读备注
@export var auto: String = "" ## 默认自动施法技能 ID（空则无）
@export var abil_list: String = "" ## 普通技能 ID 列表（逗号分隔）
@export var hero_abil_list: String = "" ## 英雄技能 ID 列表（逗号分隔）
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else unit_abil_id


## 普通技能 id 列表（逗号分隔 → 数组）。
func normal_ability_ids() -> PackedStringArray:
	return _split_ids(abil_list)


## 英雄技能 id 列表。
func hero_ability_ids() -> PackedStringArray:
	return _split_ids(hero_abil_list)


## 普通 + 英雄（去重，顺序：普通 → 英雄）。
func all_ability_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var seen: Dictionary = {}
	for id in normal_ability_ids():
		if seen.has(id):
			continue
		seen[id] = true
		out.append(id)
	for id in hero_ability_ids():
		if seen.has(id):
			continue
		seen[id] = true
		out.append(id)
	return out


static func _split_ids(raw: String) -> PackedStringArray:
	var out := PackedStringArray()
	var seen: Dictionary = {}
	for piece in raw.split(","):
		var s := str(piece).strip_edges()
		if s.is_empty() or s == "_" or seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	return out

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
