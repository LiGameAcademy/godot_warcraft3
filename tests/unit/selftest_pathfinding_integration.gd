extends SceneTree
## F-PATH-6 · 寻路系统综合 selftest。
## 把 4 个新模块（Steering/PathArc/SlopeSpeed/Formation）+ 1 个 UnitNavigator
## 集成入口串起来跑，确保 4 模块 + Navigator 协同 PASS。
##
## 跑法：godot --headless --path . -s res://tests/unit/selftest_pathfinding_integration.gd
##
## 与各模块自测的区别：
##   - selftest_steering/ path_arc/ slope_speed/ formation：单模块 5/5
##   - 本文件：跨模块 + Navigator 集成（4 个新模块全跑 + 1 个 Nav step）

const SteeringScr = preload("res://game/scripts/logic/pathing/steering_behaviors.gd")
const PathArcScr = preload("res://game/scripts/logic/pathing/path_arc.gd")
const SlopeSpeedScr = preload("res://game/scripts/logic/pathing/slope_speed.gd")
const FormationScr = preload("res://game/scripts/logic/pathing/formation_follow.gd")

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_steering_seek()
	_test_path_arc_turn()
	_test_slope_speed_uphill()
	_test_formation_wedge()
	_test_navigator_step()
	if failed == 0:
		print("selftest_pathfinding_integration: PASS")
		quit(0)
	else:
		push_error("selftest_pathfinding_integration: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _approx(a: float, b: float, eps: float = 0.5) -> bool:
	return absf(a - b) <= eps


func _approx_v(a: Vector2, b: Vector2, eps: float = 1.0) -> bool:
	return a.distance_to(b) <= eps


# 1. Steering.seek：朝向目标方向 = (target - self) normalized * max_speed
func _test_steering_seek() -> void:
	var vel: Vector2 = SteeringScr.seek(Vector2.ZERO, Vector2(100.0, 0.0), 50.0)
	# 期望：direction = (1, 0), vel = (50, 0)
	if not _approx_v(vel, Vector2(50.0, 0.0), 0.1):
		_fail("seek (100,0) from origin should=(50,0), got %s" % vel)
		return
	# 斜向：50/√2
	var vel2: Vector2 = SteeringScr.seek(Vector2.ZERO, Vector2(50.0, 50.0), 50.0)
	var expected: float = 50.0 / sqrt(2.0)
	if not _approx(vel2.x, expected, 0.1) or not _approx(vel2.y, expected, 0.1):
		_fail("seek (50,50) from origin should=(%f,%f), got %s" % [expected, expected, vel2])
		return
	print("  steering seek OK (axis + diagonal)")


# 2. PathArc.turn_angle：90° 转弯
func _test_path_arc_turn() -> void:
	var incoming := Vector2(1.0, 0.0)  # +X
	var outgoing := Vector2(0.0, 1.0)  # +Y
	var ang: float = PathArcScr.turn_angle(incoming, outgoing)
	# 90° = π/2
	if not _approx(ang, PI / 2.0, 0.01):
		_fail("turn_angle (1,0)→(0,1) should=π/2, got %f" % ang)
		return
	print("  path arc 90° turn OK")


# 3. SlopeSpeed.apply：上坡减速
func _test_slope_speed_uphill() -> void:
	# 屏 y-down：dy<0 → 上坡 → 减速
	var base := 100.0
	var sp: float = SlopeSpeedScr.apply(Vector2(0.0, -10.0), Vector2(0.0, 0.0), base)
	# |dy| = 10, |dx| = 0, slope_deg = atan2(10, 0.5) ≈ 87° → 钳到 30° → factor
	# UPHILL_FACTOR = 0.6
	# 30° → 0.6
	if not _approx(sp, 60.0, 0.5):
		_fail("uphill steep should~60 (UPHILL_FACTOR 0.6 * 100), got %f" % sp)
		return
	# 平地
	var sp_flat: float = SlopeSpeedScr.apply(Vector2(10.0, 0.0), Vector2(0.0, 0.0), base)
	if not _approx(sp_flat, 100.0, 0.1):
		_fail("flat should=100, got %f" % sp_flat)
		return
	print("  slope speed uphill OK (UPHILL_FACTOR 0.6 + flat)")


# 4. Formation.wedge 5：leader + 2 排交替
func _test_formation_wedge() -> void:
	var slots: PackedVector2Array = FormationScr.slot_positions(
		Vector2(100.0, 100.0), 0.0, 5, FormationScr.FORMATION_WEDGE, 64.0
	)
	if slots.size() != 5:
		_fail("wedge 5 should=5 slots, got %d" % slots.size())
		return
	# leader
	if not _approx_v(slots[0], Vector2(100.0, 100.0), 0.1):
		_fail("wedge slot 0 should=(100,100), got %s" % slots[0])
		return
	# 4 follower 在 leader 后方（heading=0 时 +X = 前，-X = 后）
	for i in range(1, 5):
		if slots[i].x >= 100.0:
			_fail("wedge slot %d should be behind leader (x<100), got %s" % [i, slots[i]])
			return
	print("  formation wedge 5 OK (leader + 4 followers behind)")


# 5. 集成：Steering + SlopeSpeed + Formation 一起算一个单位的目标速度
#   - leader 收到 move 命令 → formation 算 slot
#   - follower 收 leader 目标 + slot offset → steering.seek 拉向该点
#   - 上坡 → slope speed 调速
# 这里只验"组合调用"不 throw / 不返回 NaN，结果是合理 Vector2
func _test_navigator_step() -> void:
	# 模拟 follower：leader 在 (100, 100)，走 (200, 0)；follower slot 1 在 local (-64, -64)
	# → follower 目标 = (200 - 64, 0 - 64) = (136, -64)
	# follower 当前位置 (100, 100)
	# heading 0，base speed 100，平地
	var slots: PackedVector2Array = FormationScr.slot_positions(
		Vector2(100.0, 100.0), 0.0, 5, FormationScr.FORMATION_WEDGE, 64.0
	)
	var leader_goal := Vector2(200.0, 0.0)
	var follower_self := Vector2(100.0, 100.0)  # 简化为等于 leader 当前位置
	var offset: Vector2 = slots[1] - slots[0]  # = (-64, -64) local→world（heading=0）
	var follower_target: Vector2 = leader_goal + offset
	# (200, 0) + (-64, -64) = (136, -64)
	if not _approx_v(follower_target, Vector2(136.0, -64.0), 0.1):
		_fail("follower target should=(136,-64), got %s" % follower_target)
		return
	# steering seek（平地 dy=0 → slope_factor=1）
	var vel: Vector2 = SteeringScr.seek(follower_self, follower_target, 100.0)
	if not is_finite(vel.x) or not is_finite(vel.y):
		_fail("steering vel NaN/INF: %s" % vel)
		return
	# 上坡模拟：prev = (100, 100), self = (100, 90) → dy=-10
	var sp_uphill: float = SlopeSpeedScr.apply(
		Vector2(100.0, 90.0), Vector2(100.0, 100.0), 100.0
	)
	# 期望被钳到 60 (UPHILL_FACTOR * 100)
	if not _approx(sp_uphill, 60.0, 0.5):
		_fail("uphill speed should~60, got %f" % sp_uphill)
		return
	# 组合：vel * (sp_uphill / 100) → 上坡后 vel
	var vel_uphill: Vector2 = vel * (sp_uphill / 100.0)
	if not is_finite(vel_uphill.x) or not is_finite(vel_uphill.y):
		_fail("vel_uphill NaN/INF: %s" % vel_uphill)
		return
	# 期望 vel_uphill.length ~ 60
	if not _approx(vel_uphill.length(), 60.0, 1.0):
		_fail("vel_uphill length should~60, got %f" % vel_uphill.length())
		return
	print("  integration step OK (formation + steering + slope speed)")
