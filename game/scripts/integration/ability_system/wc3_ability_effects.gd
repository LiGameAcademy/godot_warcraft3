class_name Wc3AbilityEffects
extends RefCounted

## Sole healing effect factory for spells and items; all numbers remain in SLK.
static func heal(target: Node3D, source: Node3D, amount: float) -> GameplayEffectResult:
	var effect := Wc3HealEffect.new()
	effect.amount = amount
	return effect.apply_result(target, source)
