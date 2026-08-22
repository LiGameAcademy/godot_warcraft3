class_name AbilityCastRules
extends RefCounted

## 施法前校验（Logic）：冷却 / 魔法 / 距离。不执行效果。


static func can_cast_point(
	caster: Node3D,
	abil_id: String,
	goal_wc3: Vector2,
	level: int = -1
) -> Dictionary:
	var out := {"ok": false, "reason": ""}
	if caster == null or not is_instance_valid(caster):
		out["reason"] = "无施法者"
		return out
	if goal_wc3 == Vector2.INF:
		out["reason"] = "无效落点"
		return out
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		out["reason"] = "未知技能"
		return out
	var lv := level if level > 0 else AbilityCatalog.level_for(caster, abil_id)
	if lv <= 0:
		out["reason"] = "等级不足"
		return out
	if not AbilityCooldowns.is_ready(caster, abil_id):
		out["reason"] = "冷却中"
		return out
	var cost := ab.cost_at(lv)
	if UnitMana.has_mana(caster) and not UnitMana.can_spend(caster, cost):
		out["reason"] = "魔法不足"
		return out
	var rng := ab.cast_range_at(lv)
	var caster_xy := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	if caster_xy.distance_to(goal_wc3) > rng:
		out["reason"] = "距离过远"
		return out
	out["ok"] = true
	return out


static func can_cast_self(caster: Node3D, abil_id: String, level: int = -1) -> Dictionary:
	var out := {"ok": false, "reason": ""}
	if caster == null or not is_instance_valid(caster):
		out["reason"] = "无施法者"
		return out
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		out["reason"] = "未知技能"
		return out
	var lv := level if level > 0 else AbilityCatalog.level_for(caster, abil_id)
	if lv <= 0:
		out["reason"] = "等级不足"
		return out
	if not AbilityCooldowns.is_ready(caster, abil_id):
		out["reason"] = "冷却中"
		return out
	var cost := ab.cost_at(lv)
	if UnitMana.has_mana(caster) and not UnitMana.can_spend(caster, cost):
		out["reason"] = "魔法不足"
		return out
	out["ok"] = true
	return out


static func can_cast_unit(
	caster: Node3D,
	abil_id: String,
	target: Node3D,
	level: int = -1
) -> Dictionary:
	var out := {"ok": false, "reason": ""}
	if caster == null or target == null or not is_instance_valid(caster) or not is_instance_valid(target):
		out["reason"] = "无效目标"
		return out
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		out["reason"] = "未知技能"
		return out
	var lv := level if level > 0 else AbilityCatalog.level_for(caster, abil_id)
	if lv <= 0:
		out["reason"] = "等级不足"
		return out
	if not AbilityCooldowns.is_ready(caster, abil_id):
		out["reason"] = "冷却中"
		return out
	var cost := ab.cost_at(lv)
	if UnitMana.has_mana(caster) and not UnitMana.can_spend(caster, cost):
		out["reason"] = "魔法不足"
		return out
	var rng := ab.cast_range_at(lv)
	var caster_xy := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	var target_xy := Wc3Coords.godot_to_wc3_xy(target.global_position)
	if caster_xy.distance_to(target_xy) > rng:
		out["reason"] = "距离过远"
		return out
	out["ok"] = true
	return out


static func commit_cost(caster: Node3D, abil_id: String, level: int) -> void:
	var ab := AbilityCatalog.data(abil_id)
	if ab == null or caster == null:
		return
	var lv := ab.clamp_level(level)
	UnitMana.spend(caster, ab.cost_at(lv))
	AbilityCooldowns.start(caster, abil_id, ab.cool_at(lv))
