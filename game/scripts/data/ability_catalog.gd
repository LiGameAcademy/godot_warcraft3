class_name AbilityCatalog
extends RefCounted

## 技能 SLK 查询门面（Game · data）。
## 权威：AbilityDataDef / UnitAbilitiesDef + CommandButtonCatalog（order/图标）。

const META_HERO_LEVEL := "hero_level"
const META_ABILITY_LEVELS := "ability_levels" ## abil_id → int

## 竖切已接线的 order → 行为（其余有 Art 也不上卡）。
const SUPPORTED_ORDERS := {
	"harvest": true,
	"defend": true,
	"townbellon": true,
	"waterelemental": true,
	"blizzard": true,
	"massteleport": true,
	"thunderbolt": true,
	"thunderclap": true,
	"avatar": true,
	"heal": true,
	"innerfire": true,
	"slow": true,
}

const TARGET_POINT := 0
const TARGET_UNIT := 1
const TARGET_SELF := 2
const TARGET_ALLY := 3

const TARGET_KIND_BY_ORDER := {
	"waterelemental": TARGET_POINT,
	"blizzard": TARGET_POINT,
	"massteleport": TARGET_POINT,
	"thunderbolt": TARGET_UNIT,
	"thunderclap": TARGET_SELF,
	"avatar": TARGET_SELF,
	"heal": TARGET_ALLY,
	"innerfire": TARGET_ALLY,
	"slow": TARGET_UNIT,
}

## 被动（光环 / 重击等；命令格展示不可点）。
const PASSIVE_AURAS := {
	"AHab": true,
}

const PASSIVE_PROCS := {
	"AHbh": true,
}


static func is_passive_ability(abil_id: String) -> bool:
	var id := abil_id.strip_edges()
	return bool(PASSIVE_AURAS.get(id, false)) or bool(PASSIVE_PROCS.get(id, false))


static func is_passive_aura(abil_id: String) -> bool:
	return is_passive_ability(abil_id)


static func target_kind(abil_id: String) -> int:
	var ord := order_for(abil_id)
	if TARGET_KIND_BY_ORDER.has(ord):
		return int(TARGET_KIND_BY_ORDER[ord])
	return TARGET_POINT


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


static func order_for(abil_id: String) -> String:
	return CommandButtonCatalog.get_shared().get_ability_order(abil_id)


static func is_supported(abil_id: String) -> bool:
	var ord := order_for(abil_id)
	return not ord.is_empty() and bool(SUPPORTED_ORDERS.get(ord, false))


## 英雄/单位对该技能的当前等级（P0：默认 1；meta 可覆盖）。
static func level_for(caster: Node3D, abil_id: String) -> int:
	if caster == null:
		return 1
	if caster.has_meta(META_ABILITY_LEVELS):
		var m: Variant = caster.get_meta(META_ABILITY_LEVELS)
		if m is Dictionary:
			var lv := int((m as Dictionary).get(abil_id.strip_edges(), 0))
			if lv > 0:
				return lv
	var ab := data(abil_id)
	if ab == null:
		return 1
	var hero_lv := 1
	if caster.has_meta(META_HERO_LEVEL):
		hero_lv = maxi(int(caster.get_meta(META_HERO_LEVEL)), 1)
	if ab.req_level > 0 and hero_lv < ab.req_level:
		return 0
	return clampi(hero_lv, 1, ab.clamp_level(ab.levels))


static func hero_level_of(caster: Node3D) -> int:
	if caster == null:
		return 1
	if caster.has_meta(META_HERO_LEVEL):
		return maxi(int(caster.get_meta(META_HERO_LEVEL)), 1)
	return 1


## 仅 typeId 时（命令卡组装）：默认 hero_level=1。
static func level_for_unit_type(
	type_id: String,
	abil_id: String,
	hero_level: int = 1
) -> int:
	var ab := data(abil_id)
	if ab == null:
		return 0
	var hl := maxi(hero_level, 1)
	if ab.req_level > 0 and hl < ab.req_level:
		return 0
	return clampi(hl, 1, ab.clamp_level(ab.levels))
