class_name AvatarAbility
extends RefCounted

## 天神下凡 AHav（Logic）：EffectApplyBuff.apply_avatar。

const ABIL_ID := "AHav"


static func try_cast(caster: Node3D, abil_id: String, ctx: Dictionary) -> Dictionary:
	if abil_id.strip_edges() != ABIL_ID:
		return {"ok": false, "reason": "未实现的技能", "unit": null}
	var ec := EffectContext.from_cast(caster, ABIL_ID, ctx)
	var check := AbilityCastRules.can_cast_self(caster, ABIL_ID, ec.level)
	if not bool(check.get("ok", false)):
		return check
	var ctrl := AvatarController.of(caster)
	if ctrl != null and ctrl.is_active():
		return ec.fail("已在天神下凡")
	if not EffectApplyBuff.apply_avatar(ec):
		return ec.fail("无法激活天神")
	AbilityCastRules.commit_cost(caster, ABIL_ID, ec.level)
	EffectPlayPresent.cast_gesture(ec)
	return ec.succeed()
