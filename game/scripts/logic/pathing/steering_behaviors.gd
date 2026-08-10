class_name SteeringBehaviors
extends RefCounted

## 5 steering 行为（seek / arrive / pursue / evade / wander）。
##
## 设计口径（WC3 复刻）：
## - 纯函数：不碰 body / 场景树 / 速度字段；只返 Vector2 期望速度（WC3 XY / 秒）。
## - 不做 boids（alignment / cohesion）— 原作没做
## - 不做 RVO / ORCA — 原作没做
##
## 5 行为：
## 1. seek    — 直线朝目标（恒速）
## 2. arrive  — 接近时减速（避免 overshoot）
## 3. pursue  — 追移动目标（用 τ = dist / max_speed 预测）
## 4. evade   — 背向威胁（同上预判）
## 5. wander  — 随机游走（wander_angle 外部维护；本类只算当前帧目标）
##
## 调用方约定：
## - 期望速度**上限** max_speed（已单位/秒）；调用方拿到后**叠加** soft 分离 + 离墙推
## - wander_angle 状态由 UnitNavigator 持有（stateful）


## 1. seek：直线朝 target（恒速）
## 返回：单位向量 × max_speed。
static func seek(self_pos: Vector2, target: Vector2, max_speed: float) -> Vector2:
	var to := target - self_pos
	var dist := to.length()
	if dist < 0.01:
		return Vector2.ZERO
	return to / dist * max_speed


## 2. arrive：朝 target 走，接近时减速
## slow_radius 内：速度线性下降到 0；外：恒速。
## 返回：单位向量 × max_speed × ratio。
static func arrive(self_pos: Vector2, target: Vector2, max_speed: float, slow_radius: float) -> Vector2:
	var to := target - self_pos
	var dist := to.length()
	if dist < 0.01:
		return Vector2.ZERO
	if slow_radius <= 0.0:
		return Vector2.ZERO
	if dist >= slow_radius:
		return to / dist * max_speed
	# 接近 slow_radius：线性减速
	var ratio: float = clampf(dist / slow_radius, 0.0, 1.0)
	return to / dist * max_speed * ratio


## 3. pursue：追移动目标（预测）
## τ = dist / self_max_speed；predicted = target + target_vel * τ；
## 然后对 predicted 调 seek。
static func pursue(self_pos: Vector2, target_pos: Vector2, target_vel: Vector2, max_speed: float) -> Vector2:
	var to := target_pos - self_pos
	var dist := to.length()
	if dist < 0.01:
		return Vector2.ZERO
	if max_speed <= 0.0:
		return Vector2.ZERO
	var tau: float = dist / max_speed
	var predicted := target_pos + target_vel * tau
	return seek(self_pos, predicted, max_speed)


## 4. evade：背向 threat（带预判）
## τ 同上；away = self_pos - predicted_threat。
static func evade(self_pos: Vector2, threat_pos: Vector2, threat_vel: Vector2, max_speed: float) -> Vector2:
	var to := threat_pos - self_pos
	var dist := to.length()
	if dist < 0.01:
		return Vector2.ZERO
	if max_speed <= 0.0:
		return Vector2.ZERO
	var tau: float = dist / max_speed
	var predicted := threat_pos + threat_vel * tau
	var away := self_pos - predicted
	var away_len := away.length()
	if away_len < 0.01:
		return Vector2.ZERO
	return away / away_len * max_speed


## 5. wander：随机游走
## 流程：
##   1. 随机偏移 wander_angle（小范围）
##   2. 算 wander circle 中心：self_pos + heading × wander_radius
##   3. 对 circle 中心调 seek
## 返回：当前帧期望速度（WC3 XY / 秒）。
## 副作用：通过 new_angle 字典回传新角度（caller 存回 state）。
static func wander(self_pos: Vector2, wander_angle: float, wander_radius: float, max_speed: float, dt: float = 1.0 / 60.0) -> Dictionary:
	# 偏移角度（rad / sec）；上限 ±30°/sec 避免急转
	var delta_angle: float = randf_range(-1.0, 1.0) * 0.5 * dt
	var new_angle: float = wander_angle + delta_angle
	var heading := Vector2(cos(new_angle), sin(new_angle))
	var circle_center := self_pos + heading * wander_radius
	var vel := seek(self_pos, circle_center, max_speed)
	return {"vel": vel, "new_angle": new_angle}
