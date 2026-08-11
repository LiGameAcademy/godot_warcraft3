extends SceneTree
## F-PATH-8 · PathArc.smooth_path 单测。
## 完整路径弧线平滑：连续 waypoint pair 转角 > MIN_ARC_ANGLE 时沿弧线插值。
## godot --headless --path . -s res://tests/unit/selftest_path_arc_smooth.gd

const PathArcScr = preload("res://game/scripts/logic/pathing/path_arc.gd")

var passed: int = 0
var total: int = 5


func _init() -> void:
	_test_straight_path()
	_test_l_shape_90()
	_test_zero_turn_straight()
	_test_single_waypoint()
	_test_min_arc_angle_boundary()

	if passed == total:
		print("selftest_path_arc_smooth: PASS")
		quit(0)
	else:
		push_error("selftest_path_arc_smooth: FAIL %d/%d" % [passed, total])
		quit(1)


# Test 1: 直线 0° 转弯（3 waypoint 共线）→ 不画弧，原样 3 点返回
func _test_straight_path() -> void:
	var wp: Array = [Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)]
	var out: Array = PathArcScr.smooth_path(wp, 8)
	if out.size() == 3:
		print("  straight 0° turn → 原样 3 点 OK (size=%d)" % out.size())
		passed += 1
	else:
		push_error("test_1 FAIL: expected 3 got %d" % out.size())


# Test 2: L 形 90° 转弯（3 waypoint L 形）→ 第 1 段画弧（10 点：起点 + 弧 8 + 终点）
# 路径平滑语义：起点 wp[0] / 终点 wp[n-1] 必须经过；中间 wp[i] 是"控制点"不一定经过。
# 弧线 end = 圆周交点（按 chord_length + outgoing/incoming 算），不是 wp[1] 本身。
func _test_l_shape_90() -> void:
	var wp: Array = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)]
	var out: Array = PathArcScr.smooth_path(wp, 8)
	# 起点 wp[0] + 第 1 段 samples[1..8]（弧 8 点：7 中间 + 1 圆周 end）+ 最后 wp[2] = 1 + 8 + 1 = 10
	if out.size() == 10:
		var first_ok: bool = out[0].is_equal_approx(Vector2(0, 0))
		var last_ok: bool = out[out.size() - 1].is_equal_approx(Vector2(100, 100))
		# 弧线 end = (70.71, 70.71)（90° 圆弧，半径 70.71）
		var arc_end_ok: bool = out[8].is_equal_approx(Vector2(70.7107, 70.7107))
		# 弧线中间点应落在 (0,0)-(100,100) 象限
		var mid: Vector2 = out[4]
		var mid_in_quad: bool = mid.x >= 0.0 and mid.x <= 100.0 and mid.y >= 0.0 and mid.y <= 100.0
		if first_ok and last_ok and arc_end_ok and mid_in_quad:
			print("  L-shape 90° → 10 点 + 起点/终点/圆周 end 对齐 OK")
			passed += 1
		else:
			push_error("test_2 FAIL: first=%s last=%s arc_end=%s mid=%s" % [first_ok, last_ok, arc_end_ok, mid_in_quad])
	else:
		push_error("test_2 FAIL: expected 10 got %d" % out.size())


# Test 3: 直线 0° 转弯（2 waypoint）→ 不画弧，原样 2 点返回
func _test_zero_turn_straight() -> void:
	var wp: Array = [Vector2(0, 0), Vector2(50, 0), Vector2(100, 0)]
	var out: Array = PathArcScr.smooth_path(wp, 8)
	if out.size() == 3:
		var first_ok: bool = out[0].is_equal_approx(Vector2(0, 0))
		var last_ok: bool = out[2].is_equal_approx(Vector2(100, 0))
		if first_ok and last_ok:
			print("  0° turn (2 waypoint) → 原样 3 点 OK")
			passed += 1
		else:
			push_error("test_3 FAIL: first=%s last=%s" % [first_ok, last_ok])
	else:
		push_error("test_3 FAIL: expected 3 got %d" % out.size())


# Test 4: 单 waypoint → 原样 1 点返回
func _test_single_waypoint() -> void:
	var wp: Array = [Vector2(42, 42)]
	var out: Array = PathArcScr.smooth_path(wp, 8)
	if out.size() == 1 and out[0].is_equal_approx(Vector2(42, 42)):
		print("  single waypoint → 原样 1 点 OK")
		passed += 1
	else:
		push_error("test_4 FAIL: size=%d out=%s" % [out.size(), str(out)])


# Test 5: MIN_ARC_ANGLE 边界（theta = 0.5 rad）→ 行为 absf(theta) >= 0.5 触发画弧
# 0.5 rad ≈ 28.65°（小于 30° 但 close）；刚好 >= 0.5 触发弧线 → 10 点
func _test_min_arc_angle_boundary() -> void:
	# wp[0]=(0,0), wp[1]=(100,0)
	# 让 outgoing 方向 = (cos 0.5, sin 0.5)（α = 0.5）→ theta = turn_angle((1,0), (cos 0.5, sin 0.5)) = 0.5
	# wp[2] = wp[1] + outgoing * 100
	var wp: Array = [
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100 + 100 * cos(0.5), 100 * sin(0.5)),
	]
	var out: Array = PathArcScr.smooth_path(wp, 8)
	# theta = 0.5 >= MIN_ARC_ANGLE (0.5) → 画弧
	# 起点 wp[0] + samples[1..8]（弧 8 点：7 中间 + 1 圆周 end）+ 最后 wp[2] = 1 + 8 + 1 = 10
	if out.size() == 10:
		var first_ok: bool = out[0].is_equal_approx(Vector2(0, 0))
		var last_ok: bool = out[out.size() - 1].is_equal_approx(wp[2])
		if first_ok and last_ok:
			print("  MIN_ARC_ANGLE 边界 (theta=0.5) → 10 点 + 起点/终点对齐 OK")
			passed += 1
		else:
			push_error("test_5 FAIL: first=%s last=%s" % [first_ok, last_ok])
	else:
		push_error("test_5 FAIL: expected 10 got %d" % out.size())
