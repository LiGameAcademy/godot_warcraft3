class_name BuffCatalog
extends RefCounted

## Buff 静态定义（Logic · data）：id、可驱散、与 Ability 映射。

const ID_STUN := "stun"
const ID_SLOW := "slow"
const ID_INNER_FIRE := "inner_fire"
const ID_BONUS_ARMOR := "bonus_armor"
const ID_AVATAR := "avatar"
const ID_BRILLIANCE := "brilliance"

const DISPELLABLE := {
	ID_SLOW: true,
	ID_INNER_FIRE: true,
	ID_BONUS_ARMOR: false,
	ID_AVATAR: false,
	ID_STUN: false,
	ID_BRILLIANCE: false,
}

## buff_id → 展示用技能 id（CommandButtonCatalog Art）
const DISPLAY_ABIL := {
	ID_SLOW: "Aslo",
	ID_INNER_FIRE: "Ainf",
	ID_STUN: "AHtb",
	ID_BONUS_ARMOR: "AHav",
	ID_AVATAR: "AHav",
	ID_BRILLIANCE: "AHab",
}

## buff_id → 中文名（tooltip 标题）
const DISPLAY_NAME := {
	ID_SLOW: "减速",
	ID_INNER_FIRE: "心灵之火",
	ID_STUN: "眩晕",
	ID_BONUS_ARMOR: "护甲加成",
	ID_AVATAR: "天神下凡",
	ID_BRILLIANCE: "辉煌光环",
}

## 技能 → buff id（Phase C 竖切）
const BUFF_BY_ABIL := {
	"Aslo": ID_SLOW,
	"Ainf": ID_INNER_FIRE,
	"AHab": ID_BRILLIANCE,
}


static func is_dispellable(buff_id: String) -> bool:
	return bool(DISPELLABLE.get(buff_id.strip_edges(), false))


static func buff_id_for_ability(abil_id: String) -> String:
	return str(BUFF_BY_ABIL.get(abil_id.strip_edges(), ""))


static func display_ability_id(buff_id: String) -> String:
	return str(DISPLAY_ABIL.get(buff_id.strip_edges(), ""))


static func display_name(buff_id: String) -> String:
	return str(DISPLAY_NAME.get(buff_id.strip_edges(), buff_id))


static func icon_path(buff_id: String) -> String:
	var abil := display_ability_id(buff_id)
	if abil.is_empty():
		return ""
	## 优先 Buff 行 Buffart（如 Binf→BTNInnerFire），避免命令卡 On/Off 角标图
	var art := AbilityFxCatalog.buff_icon_art(abil)
	if art.is_empty():
		return ""
	return CommandButtonCatalog.get_shared().icon_path(art)


static func tooltip_text(buff_id: String, params: Dictionary, left_sec: float) -> String:
	var id := buff_id.strip_edges()
	var title := display_name(id)
	var lines: PackedStringArray = PackedStringArray([title])
	match id:
		ID_INNER_FIRE:
			var armor := maxf(float(params.get("armor", 0.0)), 0.0)
			var dmg := maxf(float(params.get("dmg_mul", 1.0)), 1.0)
			lines.append("护甲 +%.0f · 伤害 x%.2f" % [armor, dmg])
		ID_SLOW:
			var move_mul := float(params.get("move_mul", 1.0))
			var atk_mul := float(params.get("attack_mul", 1.0))
			if move_mul < 1.0:
				lines.append("移速 x%.0f%%" % int(round(move_mul * 100.0)))
			if atk_mul > 0.0 and atk_mul < 1.0:
				lines.append("攻速 x%.0f%%" % int(round(atk_mul * 100.0)))
		ID_STUN:
			lines.append("无法行动")
		ID_AVATAR, ID_BONUS_ARMOR:
			var armor_a := maxf(float(params.get("armor", params.get("amount", 0.0))), 0.0)
			if armor_a > 0.0:
				lines.append("护甲 +%.0f" % armor_a)
			if id == ID_AVATAR:
				var hp := maxf(float(params.get("bonus_hp", 0.0)), 0.0)
				if hp > 0.0:
					lines.append("生命 +%.0f" % hp)
		ID_BRILLIANCE:
			var regen := maxf(float(params.get("mana_regen", 0.0)), 0.0)
			if regen > 0.0:
				lines.append("魔法恢复 +%.2f/秒" % regen)
	# 光环（aura:true）不显示剩余时间；由范围续期/离场移除
	var is_aura := bool(params.get("aura", false)) or id == ID_BRILLIANCE
	if not is_aura and left_sec > 0.0 and left_sec < 86400.0:
		lines.append("剩余 %.1fs" % left_sec)
	return "\n".join(lines)
