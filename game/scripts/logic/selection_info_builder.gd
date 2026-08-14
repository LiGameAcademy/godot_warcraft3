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
		"attack_line": "",
		"armor_line": "",
		"special_lines": PackedStringArray(),
		"portrait_type_id": "",
		"owner_id": 0,
		"multi": [],
		"status_hint": "未选中",
	}


## primary / selected：UnitSelector 当前态。
static func build(primary: Node3D, selected: Array) -> Dictionary:
	if primary == null or not is_instance_valid(primary) or selected.is_empty():
		return build_empty()
	var d: Dictionary = primary.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	var owner_id := int(d.get("owner", 0))
	UnitLife.ensure(primary)
	var hp := int(round(UnitLife.get_life(primary)))
	var hp_max := int(round(UnitLife.get_max_life(primary)))
	var bal := _balance(tid)
	var mana_max := 0
	var mana := 0
	if bal != null and bal.mana_n > 0:
		mana_max = bal.mana_n
		mana = int(primary.get_meta("mana", mana_max if bal.mana0 <= 0 else bal.mana0))
		mana = clampi(mana, 0, mana_max)
	var mode := "multi" if selected.size() > 1 else "single"
	var display := _display_name(tid, d)
	var info := {
		"mode": mode,
		"display_name": display,
		"type_id": tid,
		"hp": hp,
		"hp_max": hp_max,
		"mana": mana,
		"mana_max": mana_max,
		"attack_line": _attack_line(tid),
		"armor_line": _armor_line(bal),
		"special_lines": _special_lines(primary, tid, bal, d),
		"portrait_type_id": tid,
		"owner_id": owner_id,
		"multi": _multi_entries(selected, primary),
		"status_hint": "",
	}
	if mode == "multi":
		info["status_hint"] = "多选 %d · Tab 切换当前" % selected.size()
	return info


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


static func _attack_line(type_id: String) -> String:
	var w := _weapons(type_id)
	if w == null:
		return "攻击 —"
	if w.weaps_on == 0 and w.dice1 <= 0 and w.dmgplus1 <= 0.0 and w.avgdmg1 <= 0.0:
		return "攻击 —"
	var at := str(w.atk_type1).strip_edges().to_lower()
	var at_cn := str(_ATK_TYPE_CN.get(at, at if not at.is_empty() else "—"))
	var dmg := ""
	if w.mindmg1 > 0.0 and w.maxdmg1 > 0.0:
		dmg = "%d–%d" % [int(round(w.mindmg1)), int(round(w.maxdmg1))]
	elif w.dice1 > 0 and w.sides1 > 0:
		var lo := w.dice1 + int(w.dmgplus1)
		var hi := w.dice1 * w.sides1 + int(w.dmgplus1)
		dmg = "%d–%d" % [lo, hi]
	elif w.avgdmg1 > 0.0:
		dmg = str(int(round(w.avgdmg1)))
	elif w.dmgplus1 > 0.0:
		dmg = str(int(round(w.dmgplus1)))
	else:
		dmg = "—"
	return "攻击 %s %s" % [at_cn, dmg]


static func _armor_line(bal: UnitBalanceDef) -> String:
	if bal == null:
		return "护甲 —"
	var dt := str(bal.def_type).strip_edges().to_lower()
	if dt == "divine" and bal.def >= 100.0:
		return "护甲 无敌"
	var dt_cn := str(_DEF_TYPE_CN.get(dt, dt if not dt.is_empty() else "—"))
	var def_v := bal.realdef if bal.realdef != 0.0 else bal.def
	# 取整显示；小数护甲保留一位
	var def_s := (
		str(int(round(def_v)))
		if absf(def_v - round(def_v)) < 0.05
		else "%.1f" % def_v
	)
	return "护甲 %s %s" % [dt_cn, def_s]


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
	if bal != null and not str(bal.primary_attr).strip_edges().is_empty():
		var pri := str(bal.primary_attr).strip_edges().to_upper()
		var pri_cn := str(_PRIMARY_CN.get(pri, pri))
		lines.append("主属性 %s" % pri_cn)
		lines.append(
			"力量 %d · 敏捷 %d · 智力 %d" % [bal.str_base, bal.agi_base, bal.int_base]
		)
	if bal != null and bal.spd > 0.0 and not bal.isbldg:
		lines.append("移动 %.0f" % bal.spd)
	if UnitLife.is_under_construction(primary):
		lines.append("建造中 %d%%" % int(round(UnitLife.ratio(primary) * 100.0)))
	return lines
