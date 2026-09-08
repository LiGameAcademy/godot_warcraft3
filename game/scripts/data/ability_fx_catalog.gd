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

## AHab 无 Casterart；施法者环权威是 Targetart=Brilliance（Func 空时兜底）
const _FALLBACK_AURA_CASTER := {
	"AHab": "Abilities/Spells/Human/Brilliance/Brilliance.mdl",
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
	"AHmt": "Abilities/Spells/Human/MassTeleport/MassTeleportCaster.mdl",
}

## 出发脚印 / 单位闪现（Func specialart 空时）
const _FALLBACK_SPECIAL := {
	"AHmt": "Abilities/Spells/Human/MassTeleport/MassTeleportTarget.mdl",
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
	var art := _first_art(_row(id), ["targetart"])
	if not art.is_empty():
		return art
	if _FALLBACK_AURA_CASTER.has(id):
		return _normalize(str(_FALLBACK_AURA_CASTER[id]))
	return ""


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
	var buff_id := buff_row_id(id)
	var art := _first_art(_row(buff_id), ["targetart"])
	if not art.is_empty():
		return art
	if _FALLBACK_BUFF_TARGET.has(id):
		return _normalize(str(_FALLBACK_BUFF_TARGET[id]))
	return ""


## Buff 面板图标（Buffart）；无则回退技能 Art 并去掉 On/Off 后缀。
static func buff_icon_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if id.is_empty():
		return ""
	var buff_id := buff_row_id(id)
	var art := str(_row(buff_id).get("buffart", "")).strip_edges()
	if art.is_empty():
		art = str(_row(id).get("art", "")).strip_edges()
		art = strip_autocast_art_suffix(art)
	return art.replace("\\", "/")


## Targetattach（如 overhead）；优先读 Buff 行。
static func target_attach(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	var buff_id := buff_row_id(id)
	var a := str(_row(buff_id).get("targetattach", "")).strip_edges().to_lower()
	if a.is_empty():
		a = str(_row(id).get("targetattach", "")).strip_edges().to_lower()
	return a


## BTNHealOn.blp → BTNHeal.blp（Buff 条勿用带角标的 On/Off 图）
static func strip_autocast_art_suffix(art: String) -> String:
	var a := art.strip_edges().replace("\\", "/")
	if a.is_empty():
		return ""
	var dir := a.get_base_dir()
	var file := a.get_file()
	var ext := ""
	var stem := file
	var dot := file.rfind(".")
	if dot >= 0:
		ext = file.substr(dot)
		stem = file.substr(0, dot)
	if stem.ends_with("Off"):
		stem = stem.substr(0, stem.length() - 3)
	elif stem.ends_with("On"):
		stem = stem.substr(0, stem.length() - 2)
	if dir.is_empty() or dir == ".":
		return stem + ext
	return dir.path_join(stem + ext)


static func special_art(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if _FALLBACK_SPECIAL.has(id):
		return _normalize(str(_FALLBACK_SPECIAL[id]))
	return _first_art(_row(id), ["specialart"])


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
