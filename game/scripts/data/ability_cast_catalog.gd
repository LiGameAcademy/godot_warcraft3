class_name AbilityCastCatalog
extends RefCounted

## 技能施法表现映射（Game · data）：Sequence / 地面特效路径。
## 权威：HumanAbilityFunc（XHbz 等）+ 大法师模型 Sequence 名。

const _SPELL_SEQ_BY_ORDER := {
	"blizzard": "Spell Channel",
	"waterelemental": "Spell Throw",
	"massteleport": "Spell Throw",
}

## abil_id → Effectart / Areaeffectart（HumanAbilityFunc）
const _GROUND_EFFECT_BY_ABIL := {
	"AHbz": "Abilities/Spells/Human/Blizzard/BlizzardTarget.mdl",
	"AHmt": "Abilities/Spells/Human/MassTeleport/MassTeleportTo.mdl",
}

## 命中附着特效（HumanAbilityFunc [BH*] Targetart）
const _HIT_EFFECT_BY_ABIL := {
	"AHbz": "Abilities/Spells/Other/FrostDamage/FrostDamage.mdl",
}

const _CHANNEL_ORDERS := {
	"blizzard": true,
}


static func is_channel_ability(abil_id: String) -> bool:
	var order := AbilityCatalog.order_for(abil_id)
	return bool(_CHANNEL_ORDERS.get(order, false))


static func channel_duration_sec(abil_id: String, level: int) -> float:
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		return 0.0
	var waves := maxi(int(round(ab.data_a_at(level))), 1)
	var interval := maxf(ab.data_d_at(level), 0.05)
	return float(waves) * interval


static func hit_effect_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _HIT_EFFECT_BY_ABIL.has(id):
		return CombatQuery.normalize_model_art(str(_HIT_EFFECT_BY_ABIL[id]))
	return ""


static func spell_sequence_for(abil_id: String) -> String:
	var order := AbilityCatalog.order_for(abil_id)
	return str(_SPELL_SEQ_BY_ORDER.get(order, "Spell Throw"))


static func ground_effect_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _GROUND_EFFECT_BY_ABIL.has(id):
		return CombatQuery.normalize_model_art(str(_GROUND_EFFECT_BY_ABIL[id]))
	return ""
