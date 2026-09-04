class_name HealAbility
extends RefCounted

## 治疗 Ahea（Logic）：EffectHeal + Present。

const ABIL_ID := "Ahea"


static func try_cast(
	caster: Node3D,
	abil_id: String,
	target: Node3D,
	ctx: Dictionary
) -> Dictionary:
	if abil_id.strip_edges() != ABIL_ID:
		return {"ok": false, "reason": "未实现的技能", "unit": null}
	var ec := EffectContext.from_cast(caster, ABIL_ID, ctx, target)
	if caster == null or target == null or not is_instance_valid(caster) or not is_instance_valid(target):
		return ec.fail("无效目标")
	if not CombatQuery.is_valid_ability_unit_target(caster, target, ABIL_ID):
		return ec.fail("无效友军目标")
	var check := AbilityCastRules.can_cast_unit(caster, ABIL_ID, target, ec.level)
	if not bool(check.get("ok", false)):
		return check
	if EffectHeal.run(ec) <= 0.0:
		return ec.fail("无治疗量")
	EffectPlayPresent.hit_target(ec)
	EffectPlayPresent.cast_gesture(ec)
	AbilityCastRules.commit_cost(caster, ABIL_ID, ec.level)
	return ec.succeed()
