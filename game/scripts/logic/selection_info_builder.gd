class_name SelectionInfoBuilder
extends RefCounted

## 中栏选中信息组装（Logic 侧只读 Def；Present 只展示 Dictionary）。
## 契约见 docs/design/game/HUD.md

const _ATK_TYPE_CN := {
	"normal": "普通",
	"pierce": "穿刺",
	"siege": "攻城",
	"magic": "魔法",
	"chaos": "混乱",
	"hero": "英雄",
	"spells": "法术",
}

const _DEF_TYPE_CN := {
	"small": "轻甲",
	"medium": "中甲",
	"large": "重甲",
	"fort": "城甲",
	"hero": "英雄甲",
	"divine": "神圣",
	"unarmored": "无甲",
	"none": "无",
}

## SLK atkType → Console infocard-attack-* stem
const _ATK_ICON_STEM := {
	"normal": "melee",
	"pierce": "piercing",
	"siege": "siege",
	"magic": "magic",
	"chaos": "chaos",
	"hero": "hero",
	"spells": "magic",
}

## SLK defType → Console infocard-armor-* stem
const _DEF_ICON_STEM := {
	"small": "small",
	"medium": "medium",
	"large": "large",
	"fort": "fortified",
	"hero": "hero",
	"divine": "divine",
	"unarmored": "unarmored",
	"none": "unarmored",
}

const _INFOCARD_DIR := "UI/Widgets/Console/Human"

## UnitBalance.upgrades 中会出现的「攻击骰伤」升级（UpgradeData.effect = ratd）
const _ATK_UPGRADE_IDS := {
	"Rhme": true, "Rhra": true,
	"Rome": true, "Rora": true,
	"Rume": true, "Rura": true,
	"Rema": true, "Rerh": true,
}

## 「护甲」升级（effect = rarm）；含建筑砌石 Rhac / 远程皮甲 Rhla 等
const _ARM_UPGRADE_IDS := {
	"Rhar": true, "Rhla": true, "Rhac": true,
	"Roar": true,
	"Ruar": true,
	"Rnam": true,
}

const _PRIMARY_CN := {
	"STR": "力量",
	"AGI": "敏捷",
	"INT": "智力",
}


static func build_empty() -> Dictionary:
	return {
		"mode": "empty",
		"display_name": "—",
		"type_id": "",
		"hp": 0,
		"hp_max": 0,
		"mana": 0,
		"mana_max": 0,
		"attack": {},
		"armor": {},
		"attack_line": "",
		"armor_line": "",
		"special_lines": PackedStringArray(),
		"portrait_type_id": "",
		"owner_id": 0,
		"is_hero": false,
		"hero_xp_in_level": 0,
		"hero_xp_need": 0,
		"hero_level": 1,
		"hero_at_max_level": false,
		"portrait_bar_mode": "none",
		"timed_life_left": 0.0,
		"timed_life_total": 0.0,
		"buffs": [],
		"multi": [],
		"status_hint": "未选中",
	}


## 轻量：仅攻/甲（含 Buff），供 Buff 条每帧刷新。
static func combat_stats(primary: Node3D) -> Dictionary:
	if primary == null or not is_instance_valid(primary):
		return {"attack": {}, "armor": {}}
	var d: Dictionary = primary.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	var bal := _balance(tid)
	return {
		"attack": _attack_stat(tid, primary),
		"armor": _armor_stat(bal, primary),
	}


## 轻量：生命/魔法，供肖像条每帧刷新。
static func vitals(primary: Node3D) -> Dictionary:
	if primary == null or not is_instance_valid(primary):
		return {"hp": 0, "hp_max": 0, "mana": 0, "mana_max": 0}
	UnitLife.ensure(primary)
	var hp := int(round(UnitLife.get_life(primary)))
	var hp_max := int(round(UnitLife.get_max_life(primary)))
	var mana := 0
	var mana_max := 0
	if UnitMana.has_mana(primary):
		mana_max = UnitMana.get_max_mana(primary)
		mana = UnitMana.get_mana(primary)
	return {"hp": hp, "hp_max": hp_max, "mana": mana, "mana_max": mana_max}


## primary / selected：UnitSelector 当前态。
static func build(primary: Node3D, selected: Array) -> Dictionary:
	if primary == null or not is_instance_valid(primary) or selected.is_empty():
		return build_empty()
	var d: Dictionary = primary.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	var owner_id := int(d.get("owner", 0))
	UnitLife.ensure(primary)
	var vit := vitals(primary)
	var hp := int(vit.get("hp", 0))
	var hp_max := int(vit.get("hp_max", 0))
	var bal := _balance(tid)
	var mana := int(vit.get("mana", 0))
	var mana_max := int(vit.get("mana_max", 0))
	var mode := "multi" if selected.size() > 1 else "single"
	var display := _display_name(tid, d)
	var attack := _attack_stat(tid, primary)
	var armor := _armor_stat(bal, primary)
	var info := {
		"mode": mode,
		"display_name": display,
		"type_id": tid,
		"hp": hp,
		"hp_max": hp_max,
		"mana": mana,
		"mana_max": mana_max,
		"attack": attack,
		"armor": armor,
		"attack_line": _stat_line_fallback(attack, "攻击"),
		"armor_line": _stat_line_fallback(armor, "护甲"),
		"special_lines": _special_lines(primary, tid, bal, d),
		"portrait_type_id": tid,
		"owner_id": owner_id,
		"multi": _multi_entries(selected, primary),
		"status_hint": "",
	}
	if mode == "multi":
		info["status_hint"] = "多选 %d · Tab 切换当前" % selected.size()
	if is_hero_balance(bal):
		var prog := HeroProgression.progress_for(primary)
		info["is_hero"] = true
		info["hero_level"] = int(prog.get("level", 1))
		info["hero_xp_in_level"] = int(prog.get("xp_in_level", 0))
		info["hero_xp_need"] = int(prog.get("xp_need", 1))
		info["hero_at_max_level"] = bool(prog.get("at_max", false))
	_apply_portrait_bar_mode(info, primary)
	info["buffs"] = BuffQuery.hud_entries(primary)
	return info


## 限时单位（召唤物 / 民兵）剩余时间；供 HUD 每帧刷新。
static func timed_life_progress(unit: Node3D) -> Dictionary:
	var out := {"show": false, "left": 0.0, "total": 0.0}
	if unit == null or not is_instance_valid(unit):
		return out
	var sl := unit.get_node_or_null("SummonLifetime") as SummonLifetime
	if sl != null:
		var total: float = sl.total_sec()
		if total > 0.0:
			out["show"] = true
			out["left"] = sl.remaining_sec()
			out["total"] = total
			return out
	var mc := MilitiaController.of(unit)
	if mc != null and mc.is_militia():
		var dur: float = mc.duration_sec()
		if dur > 0.0:
			out["show"] = true
			out["left"] = mc.revert_left_sec()
			out["total"] = dur
	return out


static func _apply_portrait_bar_mode(info: Dictionary, primary: Node3D) -> void:
	var timed := timed_life_progress(primary)
	if bool(timed.get("show", false)):
		info["portrait_bar_mode"] = "timed_life"
		info["timed_life_left"] = float(timed.get("left", 0.0))
		info["timed_life_total"] = float(timed.get("total", 0.0))
		return
	if bool(info.get("is_hero", false)):
		info["portrait_bar_mode"] = "hero_xp"
		return
	info["portrait_bar_mode"] = "none"


static func _multi_entries(selected: Array, primary: Node3D) -> Array:
	var out: Array = []
	var primary_id := primary.get_instance_id() if primary != null else 0
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node := n as Node3D
		var ud: Dictionary = node.get_meta("unit_data", {})
		var tid := str(ud.get("typeId", "")).strip_edges()
		out.append({
			"instance_id": node.get_instance_id(),
			"type_id": tid,
			"is_primary": node.get_instance_id() == primary_id,
			"icon": _unit_art(tid),
			"tooltip": _display_name(tid, ud),
		})
	return out


static func _display_name(type_id: String, unit_data: Dictionary) -> String:
	var cat := CommandButtonCatalog.get_shared()
	var row := cat.get_unit_ui(type_id)
	var n := str(row.get("name", "")).strip_edges()
	if not n.is_empty():
		return n
	if type_id == "ngol":
		return "金矿"
	var fallback := str(unit_data.get("typeId", type_id)).strip_edges()
	return fallback if not fallback.is_empty() else "—"


static func _unit_art(type_id: String) -> String:
	var cat := CommandButtonCatalog.get_shared()
	var row := cat.get_unit_ui(type_id)
	var art := str(row.get("art", "")).strip_edges()
	if art.is_empty():
		return ""
	return cat.icon_path(art)


static func _balance(type_id: String) -> UnitBalanceDef:
	if type_id.is_empty():
		return null
	Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
	return Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, type_id) as UnitBalanceDef


static func _weapons(type_id: String) -> UnitWeaponsDef:
	if type_id.is_empty():
		return null
	Wc3DefStore.ensure_table(UnitWeaponsDef.TABLE_NAME)
	return Wc3DefStore.get_row(UnitWeaponsDef.TABLE_NAME, type_id) as UnitWeaponsDef


## 英雄：UnitBalance.Primary ∈ {STR,AGI,INT}（步兵等为 "_" / 空）。
static func is_hero_balance(bal: UnitBalanceDef) -> bool:
	if bal == null:
		return false
	var p := str(bal.primary_attr).strip_edges().to_upper()
	return p == "STR" or p == "AGI" or p == "INT"


static func _attack_stat(type_id: String, unit: Node3D = null) -> Dictionary:
	var w := _weapons(type_id)
	if w == null:
		return {}
	if w.weaps_on == 0 and w.dice1 <= 0 and w.dmgplus1 <= 0.0 and w.avgdmg1 <= 0.0:
		return {}
	var at := str(w.atk_type1).strip_edges().to_lower()
	var at_cn := str(_ATK_TYPE_CN.get(at, at if not at.is_empty() else "—"))
	var dmg := _damage_text(w)
	var dmg_mul := 1.0
	if unit != null:
		dmg_mul = BuffQuery.damage_mul(unit)
	if dmg_mul > 1.001:
		dmg = _scale_damage_text(dmg, dmg_mul)
	var bal := _balance(type_id)
	var upgradeable := _has_upgrade(bal, _ATK_UPGRADE_IDS) and not is_hero_balance(bal)
	# 铁匠实际等级后接 PlayerStock / Tech；此处先 0
	var upgrade_lv := 0
	var tip := "攻击 · %s %s" % [at_cn, dmg]
	if dmg_mul > 1.001:
		tip += " · 伤害 x%.0f%%" % int(round(dmg_mul * 100.0))
	if upgradeable:
		tip += " · 升级 %d" % upgrade_lv
	return {
		"kind": "attack",
		"type": at,
		"type_label": at_cn,
		"value": dmg,
		"icon": _infocard_icon("attack", str(_ATK_ICON_STEM.get(at, ""))),
		"upgradeable": upgradeable,
		"upgrade_level": upgrade_lv,
		"tooltip": tip,
	}


static func _armor_stat(bal: UnitBalanceDef, unit: Node3D = null) -> Dictionary:
	if bal == null:
		return {}
	var dt := str(bal.def_type).strip_edges().to_lower()
	if dt == "divine" and bal.def >= 100.0:
		return {
			"kind": "armor",
			"type": "divine",
			"type_label": "无敌",
			"value": "—",
			"icon": _infocard_icon("armor", "divine"),
			"upgradeable": false,
			"upgrade_level": 0,
			"tooltip": "护甲 · 无敌",
		}
	var dt_cn := str(_DEF_TYPE_CN.get(dt, dt if not dt.is_empty() else "—"))
	var def_v := bal.realdef if bal.realdef != 0.0 else bal.def
	var bonus := 0.0
	if unit != null:
		bonus = BuffQuery.bonus_armor(unit)
	def_v += bonus
	var def_s := (
		str(int(round(def_v)))
		if absf(def_v - round(def_v)) < 0.05
		else "%.1f" % def_v
	)
	var upgradeable := _has_upgrade(bal, _ARM_UPGRADE_IDS) and not is_hero_balance(bal)
	var upgrade_lv := 0
	var tip := "护甲 · %s %s" % [dt_cn, def_s]
	if bonus > 0.05:
		tip += " · 加成 +%.0f" % bonus
	if upgradeable:
		tip += " · 升级 %d" % upgrade_lv
	return {
		"kind": "armor",
		"type": dt,
		"type_label": dt_cn,
		"value": def_s,
		"icon": _infocard_icon("armor", str(_DEF_ICON_STEM.get(dt, "unarmored"))),
		"upgradeable": upgradeable,
		"upgrade_level": upgrade_lv,
		"tooltip": tip,
	}


static func _has_upgrade(bal: UnitBalanceDef, id_set: Dictionary) -> bool:
	if bal == null:
		return false
	var raw := str(bal.upgrades).strip_edges()
	if raw.is_empty() or raw == "_" or raw == "-":
		return false
	for part in raw.split(",", false):
		var id := str(part).strip_edges()
		if id_set.has(id):
			return true
	return false


static func _damage_text(w: UnitWeaponsDef) -> String:
	if w.mindmg1 > 0.0 and w.maxdmg1 > 0.0:
		return "%d–%d" % [int(round(w.mindmg1)), int(round(w.maxdmg1))]
	if w.dice1 > 0 and w.sides1 > 0:
		var lo := w.dice1 + int(w.dmgplus1)
		var hi := w.dice1 * w.sides1 + int(w.dmgplus1)
		return "%d–%d" % [lo, hi]
	if w.avgdmg1 > 0.0:
		return str(int(round(w.avgdmg1)))
	if w.dmgplus1 > 0.0:
		return str(int(round(w.dmgplus1)))
	return "—"


static func _scale_damage_text(raw: String, mul: float) -> String:
	var s := raw.strip_edges()
	if s.is_empty() or s == "—" or mul <= 0.0:
		return s
	# 兼容 en-dash / hyphen / 全角破折号
	var parts := PackedStringArray()
	for sep in ["–", "-", "—"]:
		if s.contains(sep):
			parts = s.split(sep)
			break
	if parts.size() == 2:
		var a_s := str(parts[0]).strip_edges()
		var b_s := str(parts[1]).strip_edges()
		if a_s.is_valid_int() and b_s.is_valid_int():
			return "%d–%d" % [
				int(round(float(a_s.to_int()) * mul)),
				int(round(float(b_s.to_int()) * mul)),
			]
	if s.is_valid_int():
		return str(int(round(float(s.to_int()) * mul)))
	return s


static func _infocard_icon(kind: String, stem: String) -> String:
	if stem.is_empty():
		return ""
	var rel := "%s/infocard-%s-%s.png" % [_INFOCARD_DIR, kind, stem]
	return RuntimeAssets.converted_path(rel)


static func _stat_line_fallback(stat: Dictionary, prefix: String) -> String:
	if stat.is_empty():
		return "%s —" % prefix
	var type_label := str(stat.get("type_label", "")).strip_edges()
	var value_s := str(stat.get("value", "—"))
	if type_label.is_empty():
		return "%s %s" % [prefix, value_s]
	return "%s %s %s" % [prefix, type_label, value_s]


static func _special_lines(
	primary: Node3D, type_id: String, bal: UnitBalanceDef, unit_data: Dictionary
) -> PackedStringArray:
	var lines := PackedStringArray()
	if type_id == "ngol" or GoldMineRuntime.is_gold_mine(primary):
		var gold_left := int(unit_data.get("goldAmount", -1))
		var rt := GoldMineRuntime.ensure(primary)
		if rt != null:
			gold_left = rt.remaining_gold
		elif gold_left < 0:
			gold_left = 12500
		lines.append("储量 %d 金" % gold_left)
	# 英雄属性压成一行，避免详情面板比普通单位更高
	if is_hero_balance(bal):
		var pri := str(bal.primary_attr).strip_edges().to_upper()
		var pri_cn := str(_PRIMARY_CN.get(pri, pri))
		lines.append(
			"主%s · 力%d 敏%d 智%d" % [pri_cn, bal.str_base, bal.agi_base, bal.int_base]
		)
	if bal != null and bal.spd > 0.0 and not bal.isbldg:
		lines.append("移动 %.0f" % bal.spd)
	if UnitLife.is_under_construction(primary):
		lines.append("建造中 %d%%" % int(round(UnitLife.ratio(primary) * 100.0)))
	return lines
