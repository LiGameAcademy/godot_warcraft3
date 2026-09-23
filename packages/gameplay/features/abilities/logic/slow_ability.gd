class_name SlowAbility
extends RefCounted

## 减速 Aslo（Logic）：敌军减速 + Present。

const ABIL_ID := "Aslo"


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
		return ec.fail("无效敌军目标")
	var check := AbilityCastRules.can_cast_unit(caster, ABIL_ID, target, ec.level)
	if not bool(check.get("ok", false)):
		return check
	var ab := AbilityCatalog.data(ABIL_ID)
	if ab == null:
		return ec.fail("无技能数据")
	var dur := maxf(ab.duration_at(ec.level), 0.0)
	var move_mul := clampf(ab.data_a_at(ec.level), 0.05, 1.0)
	var attack_mul := clampf(ab.data_b_at(ec.level), 0.05, 1.0)
	EffectApplyBuff.apply_slow(target, dur, move_mul, attack_mul)
	EffectPlayPresent.hit_target(ec)
	EffectPlayPresent.hit_caster(ec)
	EffectPlayPresent.cast_gesture(ec)
	AbilityCastRules.commit_cost(caster, ABIL_ID, ec.level)
	return ec.succeed({"spell_target": target})
