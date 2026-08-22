class_name PointTargetAbility
extends RefCounted

## 点目标技能分发（Logic）：按 order 路由到具体实现。


static func try_cast(caster: Node3D, abil_id: String, goal_wc3: Vector2, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "unit": null}
	var id := abil_id.strip_edges()
	if id.is_empty():
		out["reason"] = "无效技能"
		return out
	match AbilityCatalog.order_for(id):
		"waterelemental":
			return SummonUnitAbility.try_cast(caster, id, goal_wc3, ctx)
		"blizzard":
			return BlizzardAbility.try_cast(caster, id, goal_wc3, ctx)
		"massteleport":
			return MassTeleportAbility.try_cast(caster, id, goal_wc3, ctx)
		_:
			out["reason"] = "未实现的技能"
			return out
