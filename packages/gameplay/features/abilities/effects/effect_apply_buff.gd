class_name EffectApplyBuff
extends RefCounted

## Buff 原子：委托现有 Controller / UnitStatusEffects（BuffHost 迁移后改读 Catalog）。


static func apply_inner_fire(ec: EffectContext) -> bool:
	if ec == null or ec.target == null or not is_instance_valid(ec.target):
		return false
	var ctrl := InnerFireController.ensure_on(ec.target)
	if ctrl == null:
		return false
	var cache := ec.model_cache()
	if ctrl.is_active():
		ctrl.refresh(ec.level, cache)
	else:
		if not ctrl.activate(ec.level, cache):
			return false
	ec.result["buff_target"] = ec.target
	return true


static func apply_avatar(ec: EffectContext) -> bool:
	if ec == null or ec.caster == null or not is_instance_valid(ec.caster):
		return false
	var ctrl := AvatarController.ensure_on(ec.caster)
	if ctrl == null:
		return false
	if ctrl.is_active():
		return false
	if not ctrl.activate(ec.level, ec.model_cache()):
		return false
	return true


static func apply_slow(
	unit: Node3D,
	duration_sec: float,
	move_mul: float,
	attack_mul: float = -1.0
) -> void:
	if unit == null or not is_instance_valid(unit) or duration_sec <= 0.0:
		return
	UnitStatusEffects.apply_slow(unit, duration_sec, move_mul)
	if attack_mul > 0.0:
		UnitStatusEffects.apply_attack_slow(unit, duration_sec, attack_mul)
