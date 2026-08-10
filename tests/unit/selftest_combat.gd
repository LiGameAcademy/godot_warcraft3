extends SceneTree

## F4-1 combat_steering 5/5 selftest。
##
## 不测 _process 行为（需要 body scene tree）— 留 F4-2 GameDirector e2e 验。
## 这里只验 5 个 纯函数 / 状态机 / 闭包行为。

const CombatSteeringScr = preload("res://game/scripts/logic/pathing/combat_steering.gd")
const SteeringScr = preload("res://game/scripts/logic/pathing/steering_behaviors.gd")


func _init() -> void:
	var passed := 0
	var total := 5

	# Test 1: pursue 朝 target + 预判
	# self (0,0) / target (100,0) / target_vel (50,0) / max_speed 270
	# τ = 100/270 ≈ 0.370；predicted = (100+50*0.370, 0) ≈ (118.5, 0)
	# seek 朝 (118.5, 0) → 期望 (270, 0)
	var v1: Vector2 = CombatSteeringScr.pursue(Vector2.ZERO, Vector2(100, 0), Vector2(50, 0), 270.0)
	var expected1 := Vector2(270, 0)
	if v1.is_equal_approx(expected1):
		print("  pursue 朝 target + 预判 OK (vec=%s)" % v1)
		passed += 1
	else:
		push_error("test_1 FAIL: expected %s got %s" % [expected1, v1])

	# Test 2: evade 背向 threat + 预判
	# self (0,0) / threat (50,0) / threat_vel (0,0) / max_speed 270
	# 远离 threat → 朝 (-270, 0)
	var v2: Vector2 = CombatSteeringScr.evade(Vector2.ZERO, Vector2(50, 0), Vector2.ZERO, 270.0)
	var expected2 := Vector2(-270, 0)
	if v2.is_equal_approx(expected2):
		print("  evade 背向 threat OK (vec=%s)" % v2)
		passed += 1
	else:
		push_error("test_2 FAIL: expected %s got %s" % [expected2, v2])

	# Test 3: select 无 target → Vector2.ZERO
	var v3: Vector2 = CombatSteeringScr.select(
		Vector2.ZERO, Vector2.INF, Vector2.ZERO,
		Vector2.INF, Vector2.ZERO,
		false, false, 270.0
	)
	if v3 == Vector2.ZERO:
		print("  select 无 target → ZERO OK")
		passed += 1
	else:
		push_error("test_3 FAIL: expected ZERO got %s" % v3)

	# Test 4: select low_health + threat_in_range → evade
	# self (0,0) / target (100,0) / threat (50,0)
	# low_health=true + threat_in_range=true → evade → 朝 (-270, 0)
	var v4: Vector2 = CombatSteeringScr.select(
		Vector2.ZERO, Vector2(100, 0), Vector2.ZERO,
		Vector2(50, 0), Vector2.ZERO,
		true, true, 270.0
	)
	var expected4 := Vector2(-270, 0)
	if v4.is_equal_approx(expected4):
		print("  select low_health + threat_in_range → evade OK (vec=%s)" % v4)
		passed += 1
	else:
		push_error("test_4 FAIL: expected %s got %s" % [expected4, v4])

	# Test 5: make_steering_fn 闭包跑通（state_fn 返 8 元数组）
	# self (0,0) / target (100,0) / threat 不在范围 / max_speed 270
	# → pursue → (270, 0)
	var state_arr: Array = [
		Vector2.ZERO,        # self_pos
		Vector2(100, 0),     # target_pos
		Vector2.ZERO,        # target_vel
		Vector2(500, 0),     # threat_pos（远）
		Vector2.ZERO,        # threat_vel
		false,               # low_health
		false,               # threat_in_range
		270.0                # max_speed
	]
	var fn := CombatSteeringScr.make_steering_fn(func() -> Array: return state_arr)
	var v5: Vector2 = fn.call(Vector2.ZERO, 0.1)
	var expected5 := Vector2(270, 0)
	if v5.is_equal_approx(expected5):
		print("  make_steering_fn 闭包 OK (vec=%s)" % v5)
		passed += 1
	else:
		push_error("test_5 FAIL: expected %s got %s" % [expected5, v5])

	if passed == total:
		print("selftest_combat: PASS")
		quit(0)
	else:
		push_error("selftest_combat: FAIL %d/%d" % [passed, total])
		quit(1)
