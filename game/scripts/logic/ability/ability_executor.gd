class_name AbilityExecutor
extends RefCounted

## 技能效果分发（Logic）：按 order / 目标类型路由。


static func try_cast(
	caster: Node3D,
	abil_id: String,
	goal_wc3: Vector2,
	target: Node3D,
	ctx: Dictionary
) -> Dictionary:
	var id := abil_id.strip_edges()
	if id.is_empty():
		return {"ok": false, "reason": "无效技能"}
	match AbilityCatalog.target_kind(id):
		AbilityCatalog.TARGET_UNIT:
			return _try_hostile_unit(caster, id, target, ctx)
		AbilityCatalog.TARGET_ALLY:
			return _try_ally_unit(caster, id, target, ctx)
		AbilityCatalog.TARGET_SELF:
			return _try_self(caster, id, ctx)
		_:
			return PointTargetAbility.try_cast(caster, id, goal_wc3, ctx)


static func _try_hostile_unit(
	caster: Node3D,
	abil_id: String,
	target: Node3D,
	ctx: Dictionary
) -> Dictionary:
	match AbilityCatalog.order_for(abil_id):
		"thunderbolt":
			return StormBoltAbility.try_cast(caster, abil_id, target, ctx)
		"slow":
			return SlowAbility.try_cast(caster, abil_id, target, ctx)
		_:
			return {"ok": false, "reason": "未实现的敌军指向技能"}


static func _try_ally_unit(
	caster: Node3D,
	abil_id: String,
	target: Node3D,
	ctx: Dictionary
) -> Dictionary:
	match AbilityCatalog.order_for(abil_id):
		"heal":
			return HealAbility.try_cast(caster, abil_id, target, ctx)
		"innerfire":
			return InnerFireAbility.try_cast(caster, abil_id, target, ctx)
		_:
			return {"ok": false, "reason": "未实现的友军指向技能"}


static func _try_self(caster: Node3D, abil_id: String, ctx: Dictionary) -> Dictionary:
	match AbilityCatalog.order_for(abil_id):
		"thunderclap":
			return ThunderClapAbility.try_cast(caster, abil_id, ctx)
		"avatar":
			return AvatarAbility.try_cast(caster, abil_id, ctx)
		_:
			return {"ok": false, "reason": "未实现的自身技能"}
