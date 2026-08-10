extends SceneTree

## F-PATH-7 集成 selftest：unit_navigator.gd steering override API
## + enable_steering_override 开关 + 预加载 module 不挂。
##
## 不测 _process 行为（需要 body scene tree）— 留 F4 战斗时 e2e 验。
## 这里只验 5 个 API / 状态 / preload 行为。

const UnitNavigatorScr = preload("res://game/scripts/presentation/unit_navigator.gd")
const SteeringScr = preload("res://game/scripts/logic/pathing/steering_behaviors.gd")
const PathArcScr = preload("res://game/scripts/logic/pathing/path_arc.gd")


func _init() -> void:
	var passed := 0
	var total := 5

	# Test 1: 初始无 override + has API
	var nav = UnitNavigatorScr.new()
	if not nav.has_steering_override():
		print("  initial no override OK")
		passed += 1
	else:
		push_error("test_1 FAIL: initial has override")

	# Test 2: apply + has
	var override_fn := func(_p: Vector2, _d: float) -> Vector2:
		return Vector2(50, 0)
	nav.apply_steering_override(override_fn)
	if nav.has_steering_override():
		print("  apply_steering_override → has_steering_override OK")
		passed += 1
	else:
		push_error("test_2 FAIL: after apply no override")

	# Test 3: clear + has
	nav.clear_steering_override()
	if not nav.has_steering_override():
		print("  clear_steering_override → no override OK")
		passed += 1
	else:
		push_error("test_3 FAIL: after clear has override")

	# Test 4: enable_steering_override 默认 true + 关闭后 has 仍 true（_process 跳过）
	var nav2 = UnitNavigatorScr.new()
	if nav2.enable_steering_override == true:
		print("  enable_steering_override default true OK")
		passed += 1
	else:
		push_error("test_4 FAIL: default should be true")
	nav2.queue_free()
	nav.queue_free()

	# Test 5: override Callable 实际能跑（独立于 _process）
	# 用 SteeringScr.seek 当 override 算 desired 速度；seek 距离 100 / 速度 270 → 期望 Vector2(270, 0)
	var nav3 = UnitNavigatorScr.new()
	var fn_target := Vector2(100, 0)
	nav3._steering_override = func(self_pos: Vector2, _d: float) -> Vector2:
		return SteeringScr.seek(self_pos, fn_target, 270.0)
	if nav3.has_steering_override():
		var v: Vector2 = nav3._steering_override.call(Vector2.ZERO, 0.1)
		var expected := Vector2(270, 0)
		if v.is_equal_approx(expected):
			print("  override callable runs + SteeringScr.seek OK (vec=%s)" % v)
			passed += 1
		else:
			push_error("test_5 FAIL: expected %s got %s" % [expected, v])
	else:
		push_error("test_5 FAIL: no override set")
	nav3.queue_free()

	if passed == total:
		print("selftest_f_path_7: PASS")
		quit(0)
	else:
		push_error("selftest_f_path_7: FAIL %d/%d" % [passed, total])
		quit(1)
