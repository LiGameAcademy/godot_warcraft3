extends SceneTree
## F-PATH-3 · PathArc 单测。
## godot --headless --path . -s res://tests/unit/selftest_path_arc.gd

const PathArcScr = preload("res://game/scripts/logic/pathing/path_arc.gd")

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_turn_angle()
	_test_arc_length()
	_test_arc_samples_90()
	_test_arc_samples_0()
	_test_arc_samples_180()
	if failed == 0:
		print("selftest_path_arc: PASS")
		quit(0)
	else:
		push_error("selftest_path_arc: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _approx(a: float, b: float, eps: float = 0.05) -> bool:
	return absf(a - b) <= eps


# 1. turn_angle
func _test_turn_angle() -> void:
	var a: float = PathArcScr.turn_angle(Vector2(1, 0), Vector2(1, 0))
	if not _approx(a, 0.0):
		_fail("turn_angle same dir should=0, got %f" % a)
		return
	a = PathArcScr.turn_angle(Vector2(1, 0), Vector2(0, 1))
	if not _approx(a, PI / 2.0):
		_fail("turn_angle 90 CCW should=PI/2, got %f" % a)
		return
	a = PathArcScr.turn_angle(Vector2(1, 0), Vector2(0, -1))
	if not _approx(a, -PI / 2.0):
		_fail("turn_angle 90 CW should=-PI/2, got %f" % a)
		return
	a = PathArcScr.turn_angle(Vector2(1, 0), Vector2(-1, 0))
	if not _approx(absf(a), PI):
		_fail("turn_angle 180 should=±PI, got %f" % a)
		return
	print("  turn_angle OK (0 / ±90 / 180)")


# 2. arc_length
func _test_arc_length() -> void:
	var l: float = PathArcScr.arc_length(270.0, 0.5)
	if not _approx(l, 540.0):
		_fail("arc_length(270, 0.5) should=540, got %f" % l)
		return
	l = PathArcScr.arc_length(270.0, 0.0)
	if not _approx(l, 0.0):
		_fail("arc_length turn_rate=0 should=0, got %f" % l)
		return
	print("  arc_length OK (540 / fallback)")


# 3. arc_samples 90° turn (chord_length 100)
# Geometry: S=(0,0), outgoing=(1,0), incoming=(0,1)
#   theta = π/2, R = 100/(2*sin(π/4)) = 100/√2 ≈ 70.71
#   t_s = atan2(-a.x, a.y) = atan2(-1, 0) = -π/2
#   center = start - R × (cos t_s, sin t_s) = (0,0) - 70.71 × (0, -1) = (0, 70.71) 屏下
#   t_e = t_s + π/2 = 0
#   end = C + R × (cos 0, sin 0) = (0, 70.71) + (70.71, 0) = (70.71, 70.71) 屏上
#   |end - S| = sqrt(70.71² + 70.71²) = 100 ✓
#   mid (i=2, n=4): t = -π/2 + π/4 = -π/4
#     pos = C + R × (cos(-π/4), sin(-π/4)) = (0, 70.71) + 70.71 × (0.707, -0.707) = (50, 20.71)
func _test_arc_samples_90() -> void:
	var samples: PackedVector2Array = PathArcScr.arc_samples(
		Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), 100.0, 4
	)
	if samples.size() != 5:
		_fail("arc_samples n=4 should=5 points, got %d" % samples.size())
		return
	if samples[0] != Vector2.ZERO:
		_fail("start should=(0,0), got %s" % samples[0])
		return
	# end = (70.71, 70.71) 屏上
	var exp_end := Vector2(100.0 / sqrt(2.0), 100.0 / sqrt(2.0))
	if samples[4].distance_to(exp_end) > 0.5:
		_fail("end should~%s, got %s" % [exp_end, samples[4]])
		return
	# mid = (50, 20.71) 屏上
	var exp_mid := Vector2(50.0, 70.71 - 50.0)
	if samples[2].distance_to(exp_mid) > 0.5:
		_fail("mid should~%s, got %s" % [exp_mid, samples[2]])
		return
	# 弦长 = chord_length 100
	var chord: float = samples[0].distance_to(samples[4])
	if absf(chord - 100.0) > 0.5:
		_fail("chord should=100, got %f" % chord)
		return
	print("  arc_samples 90 OK (end~(70.71,70.71)/mid~(50,20.71)/chord=100)")


# 4. arc_samples 0° turn = straight
func _test_arc_samples_0() -> void:
	var samples: PackedVector2Array = PathArcScr.arc_samples(
		Vector2.ZERO, Vector2(1, 0), Vector2(1, 0), 100.0, 4
	)
	# 0° 转弯：走直线 start + b × 100 = (100, 0)
	if samples.size() < 2:
		_fail("0° should at least 2 points, got %d" % samples.size())
		return
	if samples[0] != Vector2.ZERO:
		_fail("start should=(0,0), got %s" % samples[0])
		return
	if samples[samples.size() - 1].distance_to(Vector2(100, 0)) > 0.5:
		_fail("end should~(100,0), got %s" % samples[samples.size() - 1])
		return
	print("  arc_samples 0 OK (straight, %d points)" % samples.size())


# 5. arc_samples 180° U-turn (chord_length 100)
# Geometry: S=(0,0), outgoing=(1,0), incoming=(-1,0)
#   theta = π, R = 100/(2*sin(π/2)) = 50
#   t_s = atan2(-1, 0) = -π/2
#   center = (0,0) - 50 × (cos(-π/2), sin(-π/2)) = (0,0) - 50 × (0,-1) = (0, 50) 屏下
#   t_e = t_s + π = π/2
#   end = C + R × (cos(π/2), sin(π/2)) = (0, 50) + 50 × (0, 1) = (0, 100) 屏下
#   |end - S| = 100 ✓
#   mid (i=2, t=0): pos = C + 50 × (1, 0) = (50, 50) 屏上
func _test_arc_samples_180() -> void:
	var samples: PackedVector2Array = PathArcScr.arc_samples(
		Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), 100.0, 4
	)
	if samples.size() != 5:
		_fail("180° should=5 points, got %d" % samples.size())
		return
	if samples[0] != Vector2.ZERO:
		_fail("start should=(0,0), got %s" % samples[0])
		return
	# end = (0, 100) 屏下
	if samples[4].distance_to(Vector2(0, 100)) > 0.5:
		_fail("end should~(0, 100), got %s" % samples[4])
		return
	# mid = (50, 50) 屏上
	if samples[2].distance_to(Vector2(50, 50)) > 1.0:
		_fail("180° mid should~(50, 50), got %s" % samples[2])
		return
	print("  arc_samples 180 OK (U-turn; end~(0,100)/mid~(50,50))")
