extends SceneTree
## F-PATH-4 · SlopeSpeed 单测。
## godot --headless --path . -s res://tests/unit/selftest_slope_speed.gd

const SlopeSpeedScr = preload("res://game/scripts/logic/pathing/slope_speed.gd")

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_horizontal()
	_test_uphill_30()
	_test_downhill_30()
	_test_steep_clamp()
	_test_uphill_15()
	if failed == 0:
		print("selftest_slope_speed: PASS")
		quit(0)
	else:
		push_error("selftest_slope_speed: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _approx(a: float, b: float, eps: float = 0.5) -> bool:
	return absf(a - b) <= eps


# 1. 水平 / 静止 → 1.0 因子（base_speed 不变）
func _test_horizontal() -> void:
	# 水平移动（dy=0）
	var v: float = SlopeSpeedScr.apply(Vector2(100, 100), Vector2(0, 100), 270.0)
	if not _approx(v, 270.0):
		_fail("horizontal should=270, got %f" % v)
		return
	# 静止（dx=0, dy=0）
	v = SlopeSpeedScr.apply(Vector2(100, 100), Vector2(100, 100), 270.0)
	if not _approx(v, 270.0):
		_fail("static should=270, got %f" % v)
		return
	print("  horizontal OK (270 unchanged)")


# 2. 上坡 30°：base 270 × UPHILL_FACTOR 0.6 = 162
func _test_uphill_30() -> void:
	# 上坡：屏向上（dy < 0）；30° = 水平 100 / 屏上 tan(30°)=57.735
	# prev (0, 100) → self (100, 100-57.735) = (100, 42.265)
	var v: float = SlopeSpeedScr.apply(
		Vector2(100, 42.265), Vector2(0, 100), 270.0
	)
	# 30° 应 = 0.6 × 270 = 162
	if not _approx(v, 162.0):
		_fail("uphill 30° should~162, got %f" % v)
		return
	# 验证 slope_deg_of
	var deg: float = SlopeSpeedScr.slope_deg_of(Vector2(100, 42.265), Vector2(0, 100))
	if not _approx(deg, 30.0, 1.0):
		_fail("uphill 30° slope_deg should~30, got %f" % deg)
		return
	print("  uphill 30 OK (162 / slope_deg 30)")


# 3. 下坡 30°：base 270 × DOWNHILL_FACTOR 0.85 = 229.5
func _test_downhill_30() -> void:
	# 下坡：屏向下（dy > 0）；30°
	# prev (0, 0) → self (100, 57.735)
	var v: float = SlopeSpeedScr.apply(
		Vector2(100, 57.735), Vector2(0, 0), 270.0
	)
	if not _approx(v, 229.5, 1.0):
		_fail("downhill 30° should~229.5, got %f" % v)
		return
	print("  downhill 30 OK (229.5)")


# 4. 极陡坡（80°）→ 钳到 30° 计算 → 162
func _test_steep_clamp() -> void:
	# 80° 上坡：水平 10 / 屏上 tan(80°) = 56.7
	# prev (0, 100) → self (10, 43.3)
	var v: float = SlopeSpeedScr.apply(
		Vector2(10, 43.3), Vector2(0, 100), 270.0
	)
	# 80° 钳到 30° → 162
	if not _approx(v, 162.0, 1.0):
		_fail("steep 80° (clamp 30°) should~162, got %f" % v)
		return
	print("  steep 80° clamp OK (162)")


# 5. 上坡 15°（介于 0 与 30 之间）：线性插值
func _test_uphill_15() -> void:
	# 15° 上坡：水平 100 / 屏上 tan(15°) = 26.8
	# prev (0, 100) → self (100, 73.2)
	var v: float = SlopeSpeedScr.apply(
		Vector2(100, 73.2), Vector2(0, 100), 270.0
	)
	# 15° 因子 = lerp(1.0, 0.6, 0.5) = 0.8
	# 速度 = 270 × 0.8 = 216
	if not _approx(v, 216.0, 2.0):
		_fail("uphill 15° should~216, got %f" % v)
		return
	print("  uphill 15 OK (216)")
