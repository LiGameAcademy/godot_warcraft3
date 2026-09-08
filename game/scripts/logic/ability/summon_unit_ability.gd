class_name SummonUnitAbility
extends RefCounted

## 召唤单位（Logic）：委托 EffectSpawnSummon。

const ABIL_WATER_ELEMENTAL := "AHwe"


static func try_cast(caster: Node3D, abil_id: String, goal_wc3: Vector2, ctx: Dictionary) -> Dictionary:
	var id := abil_id.strip_edges()
	if id == ABIL_WATER_ELEMENTAL:
		return try_cast_instant(caster, id, ctx)
	return {"ok": false, "reason": "未实现的召唤技能", "unit": null}


static func try_cast_instant(caster: Node3D, abil_id: String, ctx: Dictionary) -> Dictionary:
	var id := abil_id.strip_edges()
	var ec := EffectContext.from_cast(caster, id, ctx)
	if caster == null or not is_instance_valid(caster):
		return ec.fail("无施法者")
	var check := AbilityCastRules.can_cast_self(caster, id, ec.level)
	if not bool(check.get("ok", false)):
		return check
	var goal := EffectSpawnSummon.goal_in_front(caster, id, ec.level)
	ec.goal_wc3 = goal
	EffectPlayPresent.cast_gesture(ec, goal)
	var node := EffectSpawnSummon.run(ec, goal)
	if node == null:
		return ec.fail("召唤失败")
	AbilityCastRules.commit_cost(caster, id, ec.level)
	return ec.succeed()


static func summon_goal_in_front(caster: Node3D, abil_id: String, level: int) -> Vector2:
	return EffectSpawnSummon.goal_in_front(caster, abil_id, level)
