class_name PointTargetAbility
extends RefCounted

## 点目标技能分发（Logic）：按 behavior 路由到具体实现。


static func try_cast(caster: Node3D, abil_id: String, goal_wc3: Vector2, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "unit": null}
	var id := abil_id.strip_edges()
	if id.is_empty():
		out["reason"] = "无效技能"
		return out
	match AbilityBehaviorCatalog.behavior_for(id):
		AbilityBehaviorCatalog.BEHAVIOR_SUMMON_POINT:
			return SummonUnitAbility.try_cast(caster, id, goal_wc3, ctx)
		AbilityBehaviorCatalog.BEHAVIOR_CHANNEL_AOE:
			return BlizzardAbility.try_cast(caster, id, goal_wc3, ctx)
		AbilityBehaviorCatalog.BEHAVIOR_MASS_TELEPORT:
			return MassTeleportAbility.try_cast(caster, id, goal_wc3, ctx)
		_:
			out["reason"] = "未实现的技能"
			return out
