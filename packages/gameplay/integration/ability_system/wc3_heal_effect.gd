class_name Wc3HealEffect
extends GameplayEffect

## GAS effect, WC3 state backend. Does not own mana, cooldowns or item charges.
@export var amount: float = 0.0


## 游戏专用入口；与插件的 _apply_result 扩展点分开，兼容旧 _apply 协议。
func apply_heal(target: Node, instigator: Node, context: Dictionary = {}) -> Wc3HealResult:
	return _apply_heal(target, instigator, context)


func _apply_heal(target: Node, _instigator: Node, _context: Dictionary) -> Wc3HealResult:
	if not target is Node3D or not CombatQuery.is_alive_in_world(target):
		return Wc3HealResult.make(Wc3HealResult.Outcome.REJECTED, "无效治疗目标")
	# 施工血量由建造进度驱动；治疗会浪费魔法并干扰血条表现。
	if UnitLife.is_under_construction(target as Node3D):
		return Wc3HealResult.make(Wc3HealResult.Outcome.REJECTED, "建造中不可治疗")
	var before: float = UnitLife.get_life(target)
	var actual: float = minf(maxf(amount, 0.0), maxf(UnitLife.get_max_life(target) - before, 0.0))
	if actual <= 0.0:
		return Wc3HealResult.make(Wc3HealResult.Outcome.NO_EFFECT, "生命已满，未产生治疗")
	UnitLife.set_life(target, before + actual)
	return Wc3HealResult.make(Wc3HealResult.Outcome.APPLIED, "", actual)


func _apply(target: Node, instigator: Node, context: Dictionary) -> void:
	_apply_heal(target, instigator, context)
