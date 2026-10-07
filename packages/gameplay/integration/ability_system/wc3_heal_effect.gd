class_name Wc3HealEffect
extends GameplayEffect

## GAS effect, WC3 state backend. Does not own mana, cooldowns or item charges.
@export var amount: float = 0.0


## 供 [Wc3AbilityEffects.heal] 调用；返回结构化结果。
func apply_result(target: Node, instigator: Node, context: Dictionary = {}) -> GameplayEffectResult:
	return _apply_result(target, instigator, context)


func _apply_result(target: Node, _instigator: Node, _context: Dictionary) -> GameplayEffectResult:
	if not target is Node3D or not CombatQuery.is_alive_in_world(target):
		return GameplayEffectResult.make(GameplayEffectResult.Outcome.REJECTED, "无效治疗目标")
	# 施工血量由建造进度驱动；治疗会浪费魔法并干扰血条表现。
	if UnitLife.is_under_construction(target as Node3D):
		return GameplayEffectResult.make(GameplayEffectResult.Outcome.REJECTED, "建造中不可治疗")
	var before: float = UnitLife.get_life(target)
	var actual: float = minf(maxf(amount, 0.0), maxf(UnitLife.get_max_life(target) - before, 0.0))
	if actual <= 0.0:
		return GameplayEffectResult.make(GameplayEffectResult.Outcome.NO_EFFECT, "生命已满，未产生治疗")
	UnitLife.set_life(target, before + actual)
	return GameplayEffectResult.make(GameplayEffectResult.Outcome.APPLIED, "", actual)


func _apply(target: Node, instigator: Node, context: Dictionary) -> void:
	_apply_result(target, instigator, context)
