class_name AbilityCatalog
extends RefCounted

## 技能 SLK 查询门面（Game · data）。
## 权威：AbilityDataDef / UnitAbilitiesDef + CommandButtonCatalog（order/图标）。
## behavior / target / passive 注册见 AbilityBehaviorCatalog。

const META_HERO_LEVEL := "hero_level"
const META_ABILITY_LEVELS := "ability_levels" ## abil_id → int

## 瞄准模式（与 AbilityBehaviorCatalog 数值一致，勿改序）。
const TARGET_POINT := 0
const TARGET_UNIT := 1
const TARGET_SELF := 2
const TARGET_ALLY := 3


static func is_passive_ability(abil_id: String) -> bool:
	return AbilityBehaviorCatalog.is_passive_ability(abil_id)


static func is_passive_aura(abil_id: String) -> bool:
	return is_passive_ability(abil_id)


static func target_kind(abil_id: String) -> int:
	return AbilityBehaviorCatalog.target_kind(abil_id)


static func data(abil_id: String) -> AbilityDataDef:
	var id := abil_id.strip_edges()
	if id.is_empty():
		return null
	Wc3DefStore.ensure_table(AbilityDataDef.TABLE_NAME)
	return Wc3DefStore.get_row(AbilityDataDef.TABLE_NAME, id) as AbilityDataDef


static func unit_abilities(type_id: String) -> UnitAbilitiesDef:
	var uid := type_id.strip_edges()
	if uid.is_empty():
		return null
	Wc3DefStore.ensure_table(UnitAbilitiesDef.TABLE_NAME)
	return Wc3DefStore.get_row(UnitAbilitiesDef.TABLE_NAME, uid) as UnitAbilitiesDef


static func ability_ids_for_unit(type_id: String) -> PackedStringArray:
	var def := unit_abilities(type_id)
	if def == null:
		return PackedStringArray()
	return def.all_ability_ids()


## 英雄可学技能（heroAbilList；不含 AInv 等普通技能）。
static func hero_ability_ids_for_unit(type_id: String) -> PackedStringArray:
	var def := unit_abilities(type_id)
	if def == null:
		return PackedStringArray()
	return def.hero_ability_ids()


static func order_for(abil_id: String) -> String:
	return CommandButtonCatalog.get_shared().get_ability_order(abil_id)


static func is_supported(abil_id: String) -> bool:
	return AbilityBehaviorCatalog.is_supported(abil_id)


## 英雄/单位对该技能的当前等级。
## 英雄：仅已学 rank>0；非英雄：默认 1（若 SLK 存在）。
static func learned_level(caster: Node3D, abil_id: String) -> int:
	if caster == null:
		return 0
	if caster.has_meta(META_ABILITY_LEVELS):
		var m: Variant = caster.get_meta(META_ABILITY_LEVELS)
		if m is Dictionary:
			return maxi(int((m as Dictionary).get(abil_id.strip_edges(), 0)), 0)
	return 0


static func learned_levels_map(unit: Node3D) -> Dictionary:
	if unit == null:
		return {}
	if unit.has_meta(META_ABILITY_LEVELS):
		var m: Variant = unit.get_meta(META_ABILITY_LEVELS)
		if m is Dictionary:
			return m as Dictionary
	return {}


static func level_for(caster: Node3D, abil_id: String) -> int:
	if caster == null:
		return 0
	var id := abil_id.strip_edges()
	var tid := str(caster.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	if TechPresence.is_hero_id(tid):
		return learned_level(caster, id)
	var lv := learned_level(caster, id)
	if lv > 0:
		return lv
	var ab := data(id)
	if ab == null:
		return 0
	return 1


static func hero_level_of(caster: Node3D) -> int:
	if caster == null:
		return 1
	if caster.has_meta(META_HERO_LEVEL):
		return maxi(int(caster.get_meta(META_HERO_LEVEL)), 1)
	return 1


## 命令卡组装：typeId + hero_level + ability_levels（英雄已学技能）。
static func level_for_unit_type(
	type_id: String,
	abil_id: String,
	hero_level: int = 1,
	ability_levels: Dictionary = {}
) -> int:
	var uid := type_id.strip_edges()
	var id := abil_id.strip_edges()
	if TechPresence.is_hero_id(uid):
		return maxi(int(ability_levels.get(id, 0)), 0)
	var ab := data(id)
	if ab == null:
		return 0
	var hl := maxi(hero_level, 1)
	if ab.req_level > 0 and hl < ab.req_level:
		return 0
	return 1
