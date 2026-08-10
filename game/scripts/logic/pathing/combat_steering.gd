class_name CombatSteering
extends RefCounted

## F4-1 战斗 steering（pursue/evade/select）。
##
## 设计口径（WC3 复刻 + 锦上添花）：
## - 纯函数：不碰 body / 场景树 / 状态字段；只返 Vector2 期望速度（WC3 XY / 秒）。
## - 追兵：追移动目标（用 SteeringScr.pursue + 距离衰减）
## - 逃兵：背向威胁（SteeringScr.evade + 距离触发）
## - 切换：当 threat_in_range 且 low_health → evade；否则 → pursue
##
## WC3 真实观感（本类只算期望速度，攻击/动画/死亡不在）：
## - 攻击范围外：pursue（全速）
## - 进入攻击范围：stop + attack（GameDirector 处理）
## - 生命值低（< 25%）：evade
## - 敌对消失：clear_steering_override（GameDirector 处理）
##
## 调用方约定：
## - 本类只算"期望速度"，UnitNavigator 拿到后 * delta 得位移 + _with_separation 软分离
## - GameDirector 维护 _low_health / _threat_in_range / target_pos / target_vel 状态
## - 调用方定期（如每帧）调 apply_steering_override(self._combat_steering_fn) 或 clear


const SteeringScr = preload("res://game/scripts/logic/pathing/steering_behaviors.gd")


## 追兵：朝 target 直冲；target 移动时预判 τ = dist / max_speed。
## 返回：单位向量 × max_speed（WC3 XY / 秒）。
static func pursue(self_pos: Vector2, target_pos: Vector2, target_vel: Vector2, max_speed: float) -> Vector2:
	return SteeringScr.pursue(self_pos, target_pos, target_vel, max_speed)


## 逃兵：背向 threat 跑；threat 移动时预判。
## 返回：单位向量（背向 threat_predicted）× max_speed（WC3 XY / 秒）。
static func evade(self_pos: Vector2, threat_pos: Vector2, threat_vel: Vector2, max_speed: float) -> Vector2:
	return SteeringScr.evade(self_pos, threat_pos, threat_vel, max_speed)


## 选择 pursue / evade（WC3 决策树）：
## - threat_in_range=true 且 low_health=true → evade（保命优先）
## - target_pos == Vector2.INF → Vector2.ZERO（无目标，停下）
## - 否则 → pursue
##
## 参数：
## - self_pos: 当前单位位置（WC3）
## - target_pos: 追的目标位置（WC3；Vector2.INF = 无目标）
## - target_vel: 目标当前速度（WC3/秒）
## - threat_pos: 威胁位置（WC3；Vector2.INF = 无威胁）
## - threat_vel: 威胁速度（WC3/秒）
## - low_health: 生命值低于阈值（< 25%）
## - threat_in_range: 威胁在攻击范围内（WC3 100 之内）
## - max_speed: 当前单位最大速度
static func select(
	self_pos: Vector2,
	target_pos: Vector2,
	target_vel: Vector2,
	threat_pos: Vector2,
	threat_vel: Vector2,
	low_health: bool,
	threat_in_range: bool,
	max_speed: float
) -> Vector2:
	if threat_in_range and low_health:
		return evade(self_pos, threat_pos, threat_vel, max_speed)
	if target_pos == Vector2.INF:
		return Vector2.ZERO
	return pursue(self_pos, target_pos, target_vel, max_speed)


## 闭包封装：给 UnitNavigator.apply_steering_override 用。
## 返回 Callable(self_pos, delta) -> Vector2。
## 调用方负责在闭包外维护 target_pos/target_vel/threat_pos/threat_vel/low_health/threat_in_range。
##
## 用法（GameDirector 风格）：
##   var combat_fn := CombatSteering.make_steering_fn(
##       func(): return [self_pos, target_pos, target_vel, threat_pos, threat_vel, low_health, threat_in_range, max_speed]
##   )
##   unit_navigator.apply_steering_override(combat_fn)
static func make_steering_fn(state_fn: Callable) -> Callable:
	return func(self_pos: Vector2, _delta: float) -> Vector2:
		var state: Array = state_fn.call()
		return select(
			state[0], state[1], state[2],
			state[3], state[4],
			state[5], state[6], state[7]
		)
