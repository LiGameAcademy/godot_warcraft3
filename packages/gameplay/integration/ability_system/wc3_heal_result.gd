class_name Wc3HealResult
extends RefCounted

## 游戏治疗结果；不占用 GAS 插件的 GameplayEffectResult 全局类名。

enum Outcome {
	APPLIED = 0,
	NO_EFFECT = 1,
	REJECTED = 2,
}

var outcome: int = Outcome.REJECTED
var detail: String = ""
var actual_amount: float = 0.0


static func make(p_outcome: int, p_detail: String = "", p_amount: float = 0.0) -> Wc3HealResult:
	var r: Wc3HealResult = Wc3HealResult.new()
	r.outcome = p_outcome
	r.detail = p_detail
	r.actual_amount = p_amount
	return r
