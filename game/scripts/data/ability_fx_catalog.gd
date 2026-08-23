class_name AbilityFxCatalog
extends RefCounted

## 技能特效路径（Game · data）：优先 HumanAbilityFunc，非规则 id 走 fallback。
## Present / Logic 只读本 Catalog，不直接硬编码 .mdl 路径。

## AHxx → 命中/附着（Func 无 targetart 或读扩展行）
const _FALLBACK_TARGET := {
	"AHbz": "Abilities/Spells/Other/FrostDamage/FrostDamage.mdl",
	"AHtb": "Abilities/Spells/Human/StormBolt/StormBoltTarget.mdl",
	"Ahea": "Abilities/Spells/Human/Heal/HealTarget.mdl",
	"Ainf": "Abilities/Spells/Human/InnerFire/InnerFireTarget.mdl",
	"Aslo": "Abilities/Spells/Human/Slow/SlowTarget.mdl",
}

const _FALLBACK_GROUND := {
	"AHbz": "Abilities/Spells/Human/Blizzard/BlizzardTarget.mdl",
	"AHmt": "Abilities/Spells/Human/MassTeleport/MassTeleportTo.mdl",
}

const _FALLBACK_MISSILE := {
	"AHtb": "Abilities/Spells/Human/StormBolt/StormBoltMissile.mdl",
}

const _FALLBACK_CASTER := {
	"AHtc": "Abilities/Spells/Human/Thunderclap/ThunderClapCaster.mdl",
	"AHav": "Abilities/Spells/Human/Avatar/AvatarCaster.mdl",
	"Aslo": "Abilities/Spells/Human/Slow/SlowCaster.mdl",
}

## AHxx → BHxx 例外（非 B+suffix）
const _BUFF_ROW_OVERRIDE := {
	"AHab": "BHab",
}

## Buff 受益附着 fallback
const _FALLBACK_BUFF_TARGET := {
	"AHab": "Abilities/Spells/Other/GeneralAuraTarget/GeneralAuraTarget.mdl",
}


static func caster_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _FALLBACK_CASTER.has(id):
		return _normalize(str(_FALLBACK_CASTER[id]))
	return _first_art(_row(id), ["casterart", "targetart"])


static func target_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _FALLBACK_TARGET.has(id):
		return _normalize(str(_FALLBACK_TARGET[id]))
	return _first_art(_row(id), ["targetart"])


static func hit_effect_art(abil_id: String) -> String:
	return target_art(abil_id)


static func ground_effect_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _FALLBACK_GROUND.has(id):
		return _normalize(str(_FALLBACK_GROUND[id]))
	var art := _first_art(_row(id), ["areaeffectart", "effectart"])
	if not art.is_empty():
		return art
	if id.length() >= 4 and id.begins_with("A"):
		var ext_id := "X" + id.substr(1)
		art = _first_art(_row(ext_id), ["effectart", "areaeffectart"])
	return art


static func missile_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _FALLBACK_MISSILE.has(id):
		return _normalize(str(_FALLBACK_MISSILE[id]))
	return _first_art(_row(id), ["missileart", "effectart"])


static func buff_row_id(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _BUFF_ROW_OVERRIDE.has(id):
		return str(_BUFF_ROW_OVERRIDE[id])
	if id.length() >= 4 and id.begins_with("A"):
		return "B" + id.substr(1)
	return id


static func buff_beneficiary_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _FALLBACK_BUFF_TARGET.has(id):
		return _normalize(str(_FALLBACK_BUFF_TARGET[id]))
	var buff_id := buff_row_id(id)
	return _first_art(_row(buff_id), ["targetart"])


static func _row(abil_id: String) -> Dictionary:
	if abil_id.is_empty():
		return {}
	return CommandButtonCatalog.get_shared().get_ability(abil_id)


static func _first_art(row: Dictionary, keys: PackedStringArray) -> String:
	for k in keys:
		var raw := str(row.get(k, "")).strip_edges()
		if not raw.is_empty():
			return _normalize(raw)
	return ""


static func _normalize(raw: String) -> String:
	if raw.is_empty():
		return ""
	return CombatQuery.normalize_model_art(raw)
