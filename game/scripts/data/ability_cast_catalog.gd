class_name AbilityCastCatalog
extends RefCounted

## 技能施法表现映射（Game · data）：Sequence / 地面特效路径。
## 权威：HumanAbilityFunc（XHbz 等）+ 大法师模型 Sequence 名。

const _SPELL_SEQ_BY_ORDER := {
	"blizzard": "Spell Channel",
	"waterelemental": "Spell Throw",
	"massteleport": "Spell Throw",
	"thunderbolt": "Spell Throw",
	"thunderclap": "Spell Slam",
	"avatar": "Spell Throw",
	"heal": "Spell Throw",
	"innerfire": "Spell Throw",
	"slow": "Spell Throw",
}

## abil_id → Effectart / Areaeffectart（HumanAbilityFunc）
const _GROUND_EFFECT_BY_ABIL := {
	"AHbz": "Abilities/Spells/Human/Blizzard/BlizzardTarget.mdl",
	"AHmt": "Abilities/Spells/Human/MassTeleport/MassTeleportTo.mdl",
}

const _MISSILE_BY_ABIL := {
	"AHtb": "Abilities/Spells/Human/StormBolt/StormBoltMissile.mdl",
}

const _CASTER_ART_BY_ABIL := {
	"AHtc": "Abilities/Spells/Human/Thunderclap/ThunderClapCaster.mdl",
	"AHav": "Abilities/Spells/Human/Avatar/AvatarCaster.mdl",
	"Aslo": "Abilities/Spells/Human/Slow/SlowCaster.mdl",
}

## 命中附着特效（HumanAbilityFunc [BH*] Targetart）
const _HIT_EFFECT_BY_ABIL := {
	"AHbz": "Abilities/Spells/Other/FrostDamage/FrostDamage.mdl",
	"AHtb": "Abilities/Spells/Human/StormBolt/StormBoltTarget.mdl",
	"Ahea": "Abilities/Spells/Human/Heal/HealTarget.mdl",
	"Ainf": "Abilities/Spells/Human/InnerFire/InnerFireTarget.mdl",
	"Aslo": "Abilities/Spells/Human/Slow/SlowTarget.mdl",
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


static func missile_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _MISSILE_BY_ABIL.has(id):
		return CombatQuery.normalize_model_art(str(_MISSILE_BY_ABIL[id]))
	return ""


static func caster_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _CASTER_ART_BY_ABIL.has(id):
		return CombatQuery.normalize_model_art(str(_CASTER_ART_BY_ABIL[id]))
	var row := CommandButtonCatalog.get_shared().get_ability(id)
	var raw := str(row.get("casterart", "")).strip_edges()
	if raw.is_empty():
		raw = str(row.get("targetart", "")).strip_edges()
	if raw.is_empty():
		return ""
	return CombatQuery.normalize_model_art(raw)
