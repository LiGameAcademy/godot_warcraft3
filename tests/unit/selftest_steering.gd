extends SceneTree
## F-PATH-2 · SteeringBehaviors 5/5 单测。
## godot --headless --path . -s res://tests/unit/selftest_steering.gd
##
## 5 行为单测：
## 1. seek 直线：返回方向 = (target - self_pos).normalized × max_speed
## 2. arrive 减速：dist < slow_radius → 速度 × ratio 线性下降
## 3. pursue 预测：target + target_vel * τ（τ = dist / max_speed）
## 4. evade 反向：away = self - predicted_threat，方向背离
## 5. wander 角变化：30 帧 new_angle 漂移 < 30°/sec（不急转）

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_seek()
	_test_arrive()
	_test_pursue()
	_test_evade()
	_test_wander()
	if failed == 0:
		print("selftest_steering: PASS")
		quit(0)
	else:
		push_error("selftest_steering: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _approx(a: Vector2, b: Vector2, eps: float = 0.5) -> bool:
	return a.distance_to(b) <= eps


# 1. seek
func _test_seek() -> void:
	var v: Vector2 = SteeringBehaviors.seek(Vector2.ZERO, Vector2(100, 0), 50.0)
	if not _approx(v, Vector2(50, 0)):
		_fail("seek(0,0)→(100,0) max=50 应 = (50,0)，实际 %s" % v)
		return
	# 反向
	v = SteeringBehaviors.seek(Vector2(100, 0), Vector2.ZERO, 50.0)
	if not _approx(v, Vector2(-50, 0)):
		_fail("seek 反向应 = (-50,0)，实际 %s" % v)
		return
	# 斜向：(100,100) 距离 100·√2 = 141.42；max=50 沿对角 → 各分量 50/√2 ≈ 35.355
	v = SteeringBehaviors.seek(Vector2.ZERO, Vector2(100, 100), 50.0)
	var exp: Vector2 = Vector2(50.0 / sqrt(2.0), 50.0 / sqrt(2.0))
	if not _approx(v, exp):
		_fail("seek 斜向应 = (35.36, 35.36)，实际 %s" % v)
		return
	# 起点终点重合
	v = SteeringBehaviors.seek(Vector2(50, 50), Vector2(50, 50), 50.0)
	if v != Vector2.ZERO:
		_fail("seek 起点=终点应 = (0,0)，实际 %s" % v)
		return
	print("  seek OK ((50,0)/(-50,0)/(50,50)/零向量)")


# 2. arrive
func _test_arrive() -> void:
	# 远：dist=200, slow=100 → 恒速 (50, 0)
	var v: Vector2 = SteeringBehaviors.arrive(Vector2.ZERO, Vector2(200, 0), 50.0, 100.0)
	if not _approx(v, Vector2(50, 0)):
		_fail("arrive 远应恒速 (50,0)，实际 %s" % v)
		return
	# 边界：dist=100, slow=100 → 刚到边界，恒速
	v = SteeringBehaviors.arrive(Vector2.ZERO, Vector2(100, 0), 50.0, 100.0)
	if not _approx(v, Vector2(50, 0)):
		_fail("arrive 边界=100 应恒速 (50,0)，实际 %s" % v)
		return
	# 接近：dist=50, slow=100 → ratio=0.5 → (25, 0)
	v = SteeringBehaviors.arrive(Vector2.ZERO, Vector2(50, 0), 50.0, 100.0)
	if not _approx(v, Vector2(25, 0)):
		_fail("arrive 50/100 应减速 (25,0)，实际 %s" % v)
		return
	# 极近：dist=10 → ratio=0.1 → (5, 0)
	v = SteeringBehaviors.arrive(Vector2.ZERO, Vector2(10, 0), 50.0, 100.0)
	if not _approx(v, Vector2(5, 0)):
		_fail("arrive 10/100 应极慢 (5,0)，实际 %s" % v)
		return
	# 抵达：dist=0 → 0
	v = SteeringBehaviors.arrive(Vector2.ZERO, Vector2.ZERO, 50.0, 100.0)
	if v != Vector2.ZERO:
		_fail("arrive 抵达应 = (0,0)，实际 %s" % v)
		return
	print("  arrive OK (远 200/恒速 50；近 50/减速 25；抵达 0)")


# 3. pursue
func _test_pursue() -> void:
	# 静止 target（vel=0） → 退化为 seek
	var v: Vector2 = SteeringBehaviors.pursue(Vector2.ZERO, Vector2(100, 0), Vector2.ZERO, 50.0)
	if not _approx(v, Vector2(50, 0)):
		_fail("pursue 静止 target 应 = (50,0)，实际 %s" % v)
		return
	# target 远离 (10, 0) → predicted = (100, 0) + (10, 0) * 2 = (120, 0)
	#   τ = dist(0→100) / 50 = 2
	#   seek(0→120) = (50, 0)
	v = SteeringBehaviors.pursue(Vector2.ZERO, Vector2(100, 0), Vector2(10, 0), 50.0)
	if not _approx(v, Vector2(50, 0)):
		_fail("pursue 远离 target 应 = (50,0)，实际 %s" % v)
		return
	# target 朝我移动 (-20, 0) → predicted = (100, 0) + (-20, 0) * 2 = (60, 0)
	#   seek(0→60) = (50, 0)
	v = SteeringBehaviors.pursue(Vector2.ZERO, Vector2(100, 0), Vector2(-20, 0), 50.0)
	if not _approx(v, Vector2(50, 0)):
		_fail("pursue 朝我 target 应 = (50,0)，实际 %s" % v)
		return
	print("  pursue OK (静止/远离/朝我 3 case)")


# 4. evade
func _test_evade() -> void:
	# 静止 threat（vel=0）→ 远离 (50, 0)
	var v: Vector2 = SteeringBehaviors.evade(Vector2.ZERO, Vector2(50, 0), Vector2.ZERO, 50.0)
	if not _approx(v, Vector2(-50, 0)):
		_fail("evade 静止 threat 应 = (-50,0)，实际 %s" % v)
		return
	# 移动 threat (10, 0) → predicted = (50+10*1, 0) = (60, 0)
	#   τ = dist(0→50) / 50 = 1
	#   away = (0, 0) - (60, 0) = (-60, 0) → normalize × 50 = (-50, 0)
	v = SteeringBehaviors.evade(Vector2.ZERO, Vector2(50, 0), Vector2(10, 0), 50.0)
	if not _approx(v, Vector2(-50, 0)):
		_fail("evade 移动 threat 应 = (-50,0)，实际 %s" % v)
		return
	# threat 在我后面 (0, -50)，朝我 (0, 10)
	#   predicted = (0, -50) + (0, 10) * 1 = (0, -40)
	#   away = (0, 0) - (0, -40) = (0, 40) → (0, 50)
	v = SteeringBehaviors.evade(Vector2.ZERO, Vector2(0, -50), Vector2(0, 10), 50.0)
	if not _approx(v, Vector2(0, 50)):
		_fail("evade 后方 threat 应 = (0,50)，实际 %s" % v)
		return
	print("  evade OK (静止/移动/后方 3 case)")


# 5. wander
func _test_wander() -> void:
	# 30 帧 wander_angle 漂移 < 30°/sec（避免急转）
	# dt = 1/60；delta_angle ∈ [-0.5, 0.5] * dt = [-0.0083, 0.0083] rad/frame
	# 30 帧：理论最大漂移 = 0.0083 * 30 = 0.25 rad = 14.3°
	# 但随机可能累积方向同；用宽松 30° 上限
	var angle: float = 0.0
	var max_drift: float = 0.0
	var dt: float = 1.0 / 60.0
	for i in range(30):
		var r: Dictionary = SteeringBehaviors.wander(Vector2.ZERO, angle, 50.0, 50.0, dt)
		var new_a: float = r.get("new_angle", angle)
		var drift: float = absf(new_a - angle)
		if drift > max_drift:
			max_drift = drift
		angle = new_a
	# 单帧最大漂移：delta_angle ∈ [-0.5, 0.5] * dt = ±0.0083 rad = ±0.48°
	# 允许一些浮点误差，30° 远大于此
	if max_drift > deg_to_rad(30.0):
		_fail("wander 单帧漂移 %f rad > 30°，太急转" % max_drift)
		return
	# 速度大小 = max_speed
	var r2: Dictionary = SteeringBehaviors.wander(Vector2.ZERO, 0.0, 50.0, 50.0, dt)
	var v: Vector2 = r2.get("vel", Vector2.ZERO)
	if absf(v.length() - 50.0) > 0.5:
		_fail("wander 速度应 = 50，实际 %f" % v.length())
		return
	print("  wander OK (30 帧漂移 %f°<30°，速度 50)" % rad_to_deg(max_drift))
