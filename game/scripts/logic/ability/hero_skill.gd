class_name HeroSkill
extends RefCounted

## 英雄技能点 / 学习（Logic）：未学技能不在命令卡；学习在二级面板。


static func ability_levels(unit: Node3D) -> Dictionary:
	return AbilityCatalog.learned_levels_map(unit)


static func learned_level(unit: Node3D, abil_id: String) -> int:
	return AbilityCatalog.learned_level(unit, abil_id)


static func points_spent(unit: Node3D) -> int:
	var total := 0
	for v in ability_levels(unit).values():
		total += maxi(int(v), 0)
	return total


## 可用技能点 = 英雄等级 - 已投入等级总和（1 级起即有 1 点可学技能）。
static func points_available(unit: Node3D) -> int:
	if unit == null:
		return 0
	var hl := 1
	if unit.has_meta(AbilityCatalog.META_HERO_LEVEL):
		hl = maxi(int(unit.get_meta(AbilityCatalog.META_HERO_LEVEL)), 1)
	return maxi(hl - points_spent(unit), 0)


static func ensure_levels_meta(unit: Node3D) -> void:
	if unit == null:
		return
	if not unit.has_meta(AbilityCatalog.META_ABILITY_LEVELS):
		unit.set_meta(AbilityCatalog.META_ABILITY_LEVELS, {})


static func can_learn(unit: Node3D, abil_id: String) -> Dictionary:
	var out := {"ok": false, "reason": ""}
	if unit == null or not is_instance_valid(unit):
		out["reason"] = "无效单位"
		return out
	var id := abil_id.strip_edges()
	if id.is_empty():
		out["reason"] = "无效技能"
		return out
	var tid := str(unit.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	if not TechPresence.is_hero_id(tid):
		out["reason"] = "非英雄"
		return out
	var listed := false
	for aid in AbilityCatalog.hero_ability_ids_for_unit(tid):
		if str(aid) == id:
			listed = true
			break
	if not listed:
		out["reason"] = "该英雄无此技能"
		return out
	var ab := AbilityCatalog.data(id)
	if ab == null:
		out["reason"] = "无技能数据"
		return out
	var hl := AbilityCatalog.hero_level_of(unit)
	var cur := learned_level(unit, id)
	var req_hl := ab.required_hero_level_for_rank(cur)
	if hl < req_hl:
		out["reason"] = "需要英雄等级 %d" % req_hl
		return out
	if cur >= ab.clamp_level(ab.levels):
		out["reason"] = "已达最高等级"
		return out
	if points_available(unit) <= 0:
		out["reason"] = "无可用技能点"
		return out
	out["ok"] = true
	return out


static func learn(unit: Node3D, abil_id: String) -> Dictionary:
	var check := can_learn(unit, abil_id)
	if not bool(check.get("ok", false)):
		return check
	ensure_levels_meta(unit)
	var id := abil_id.strip_edges()
	var levels: Dictionary = ability_levels(unit).duplicate(true)
	levels[id] = learned_level(unit, id) + 1
	unit.set_meta(AbilityCatalog.META_ABILITY_LEVELS, levels)
	return {"ok": true, "reason": "", "level": int(levels[id])}
