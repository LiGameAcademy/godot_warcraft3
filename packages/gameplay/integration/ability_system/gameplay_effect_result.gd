class_name GameplayEffectResult
extends RefCounted

## GAS 效果应用结果（WC3 集成层）。供治疗等原子效果返回实际数值。

enum Outcome {
	APPLIED = 0,
	NO_EFFECT = 1,
	REJECTED = 2,
}

var outcome: int = Outcome.REJECTED
var detail: String = ""
var actual_amount: float = 0.0


static func make(p_outcome: int, p_detail: String = "", p_amount: float = 0.0) -> GameplayEffectResult:
	var r: GameplayEffectResult = GameplayEffectResult.new()
	r.outcome = p_outcome
	r.detail = p_detail
	r.actual_amount = p_amount
	return r
