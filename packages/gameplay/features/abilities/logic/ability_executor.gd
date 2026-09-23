class_name AbilityExecutor
extends RefCounted

## 技能效果分发（Logic）：按 target_kind + behavior 路由。


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
	match AbilityBehaviorCatalog.behavior_for(abil_id):
		AbilityBehaviorCatalog.BEHAVIOR_STORM_BOLT:
			return StormBoltAbility.try_cast(caster, abil_id, target, ctx)
		AbilityBehaviorCatalog.BEHAVIOR_SLOW:
			return SlowAbility.try_cast(caster, abil_id, target, ctx)
		_:
			return {"ok": false, "reason": "未实现的敌军指向技能"}


static func _try_ally_unit(
	caster: Node3D,
	abil_id: String,
	target: Node3D,
	ctx: Dictionary
) -> Dictionary:
	match AbilityBehaviorCatalog.behavior_for(abil_id):
		AbilityBehaviorCatalog.BEHAVIOR_HEAL:
			return HealAbility.try_cast(caster, abil_id, target, ctx)
		AbilityBehaviorCatalog.BEHAVIOR_INNER_FIRE:
			return InnerFireAbility.try_cast(caster, abil_id, target, ctx)
		_:
			return {"ok": false, "reason": "未实现的友军指向技能"}


static func _try_self(caster: Node3D, abil_id: String, ctx: Dictionary) -> Dictionary:
	match AbilityBehaviorCatalog.behavior_for(abil_id):
		AbilityBehaviorCatalog.BEHAVIOR_THUNDER_CLAP:
			return ThunderClapAbility.try_cast(caster, abil_id, ctx)
		AbilityBehaviorCatalog.BEHAVIOR_AVATAR:
			return AvatarAbility.try_cast(caster, abil_id, ctx)
		AbilityBehaviorCatalog.BEHAVIOR_SUMMON_INSTANT:
			return SummonUnitAbility.try_cast_instant(caster, abil_id, ctx)
		_:
			return {"ok": false, "reason": "未实现的自身技能"}
