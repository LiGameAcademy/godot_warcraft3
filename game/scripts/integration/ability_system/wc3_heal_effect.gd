class_name Wc3HealEffect
extends GameplayEffect

## GAS effect, WC3 state backend. Does not own mana, cooldowns or item charges.
@export var amount: float = 0.0

func _apply_result(target: Node, _instigator: Node, _context: Dictionary) -> GameplayEffectResult:
	if not target is Node3D or not CombatQuery.is_alive_in_world(target):
		return GameplayEffectResult.make(GameplayEffectResult.Outcome.REJECTED, "无效治疗目标")
	var before := UnitLife.get_life(target)
	var actual := minf(maxf(amount, 0.0), maxf(UnitLife.get_max_life(target) - before, 0.0))
	if actual <= 0.0:
		return GameplayEffectResult.make(GameplayEffectResult.Outcome.NO_EFFECT, "生命已满，未产生治疗")
	UnitLife.set_life(target, before + actual)
	return GameplayEffectResult.make(GameplayEffectResult.Outcome.APPLIED, "", actual)

func _apply(target: Node, instigator: Node, context: Dictionary) -> void:
	_apply_result(target, instigator, context)
