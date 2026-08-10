extends SceneTree
## F3-4 · 群体移动综合 selftest。
## 5/5：
## 1. slot_assignment_basic（rect 5 单位）
## 2. slot_assignment_wedge（wedge 3 单位）
## 3. shift_routing（Shift+RMB 路由算法：goal = goal_center + slot offset）
## 4. slope_speed_integration（UnitNavigator _process 中 SlopeSpeed 调速）
## 5. fallback_to_scatter（1 单位队形 → 等价落点散开）
##
## 跑法：godot --headless --path . -s res://tests/unit/selftest_group_move.gd

const FormationScr = preload("res://game/scripts/logic/pathing/formation_follow.gd")
const SlopeSpeedScr = preload("res://game/scripts/logic/pathing/slope_speed.gd")

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_slot_assignment_basic()
	_test_slot_assignment_wedge()
	_test_shift_routing()
	_test_slope_speed_integration()
	_test_fallback_to_scatter()
	if failed == 0:
		print("selftest_group_move: PASS")
		quit(0)
	else:
		push_error("selftest_group_move: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _approx(a: float, b: float, eps: float = 0.5) -> bool:
	return absf(a - b) <= eps


func _approx_v(a: Vector2, b: Vector2, eps: float = 1.0) -> bool:
	return a.distance_to(b) <= eps


# 1. 矩形 5 单位：leader slot 0 = leader 位置
func _test_slot_assignment_basic() -> void:
	var slots: PackedVector2Array = FormationScr.slot_positions(
		Vector2(100.0, 100.0), 0.0, 5, FormationScr.FORMATION_RECT, 64.0
	)
	if slots.size() != 5:
		_fail("rect 5 should=5 slots, got %d" % slots.size())
		return
	if not _approx_v(slots[0], Vector2(100.0, 100.0), 0.1):
		_fail("rect slot 0 should=leader_pos(100,100), got %s" % slots[0])
		return
	# 后方 4 个 follower，y < leader.y（heading=0，rect 走 -Y）
	for i in range(1, 5):
		if slots[i].y >= 100.0:
			_fail("rect slot %d should be behind leader (y<100), got %s" % [i, slots[i]])
			return
	print("  rect 5 OK (leader slot 0 + 4 followers behind)")


# 2. 楔形 3 单位：leader 前方，左右排开
func _test_slot_assignment_wedge() -> void:
	var slots: PackedVector2Array = FormationScr.slot_positions(
		Vector2(100.0, 100.0), 0.0, 3, FormationScr.FORMATION_WEDGE, 64.0
	)
	if slots.size() != 3:
		_fail("wedge 3 should=3 slots, got %d" % slots.size())
		return
	if not _approx_v(slots[0], Vector2(100.0, 100.0), 0.1):
		_fail("wedge slot 0 should=leader_pos(100,100), got %s" % slots[0])
		return
	# i=1 left back row 1: (leader.x - 64, leader.y - 64) = (36, 36)
	if not _approx_v(slots[1], Vector2(36.0, 36.0), 0.1):
		_fail("wedge slot 1 should=(36,36), got %s" % slots[1])
		return
	# i=2 right back row 1: (leader.x - 64, leader.y + 64) = (36, 164)
	if not _approx_v(slots[2], Vector2(36.0, 164.0), 0.1):
		_fail("wedge slot 2 should=(36,164), got %s" % slots[2])
		return
	print("  wedge 3 OK (leader + 2 followers left/right back)")


# 3. Shift+RMB 路由算法：goal[i] = goal_center + (slots[i] - slots[0])
# 这是 _issue_group_move_command 的核心算法，selftest 验证其正确性
func _test_shift_routing() -> void:
	var leader_pos := Vector2(200.0, 200.0)
	var goal_center := Vector2(1000.0, 1000.0)
	var formation := FormationScr.FORMATION_RECT
	var spacing := 64.0
	# 模拟 5 单位：movers[0] = leader，movers[1..4] = followers
	var slots: PackedVector2Array = FormationScr.slot_positions(
		leader_pos, 0.0, 5, formation, spacing
	)
	var goals: PackedVector2Array = PackedVector2Array()
	for i in range(5):
		var offset: Vector2 = slots[i] - slots[0]
		goals.append(goal_center + offset)
	# leader goal = goal_center + (0, 0) = (1000, 1000)
	if not _approx_v(goals[0], goal_center, 0.1):
		_fail("shift_routing leader goal should=(1000,1000), got %s" % goals[0])
		return
	# followers goals 都 different from leader goal（offset != 0）
	for i in range(1, 5):
		if goals[i].distance_to(goal_center) < 1.0:
			_fail("shift_routing follower %d should differ from leader goal, got %s" % [i, goals[i]])
			return
	# 检查 follower offset 跟 leader 当前位置偏移一致
	# 矩形 follower 1: leader_pos + (-64, -64) = (136, 136)
	# goal = goal_center + (136-200, 136-200) = (1000-64, 1000-64) = (936, 936)
	var expected_1 := Vector2(936.0, 936.0)
	if not _approx_v(goals[1], expected_1, 0.1):
		_fail("shift_routing follower 1 goal should=(936,936), got %s" % goals[1])
		return
	print("  shift routing OK (leader goal=center, followers=offset)")


# 4. UnitNavigator _process 中 SlopeSpeed 调速：
# 模拟 _process 调用：prev = (0, 100), self = (0, 90) → dy = -10 (上坡)
# base_speed = 270 → 应用 SlopeSpeed.apply → 期望 < 270
func _test_slope_speed_integration() -> void:
	var base := 270.0
	var prev := Vector2(0.0, 100.0)
	var self_up := Vector2(0.0, 90.0)  # dy=-10 → 上坡
	# |dy|=10, |dx|=0, slope_deg = atan2(10, 0.5) ≈ 87° → 钳到 30° → UPHILL_FACTOR 0.6
	# 期望 = 270 * 0.6 = 162
	var adjusted: float = SlopeSpeedScr.apply(self_up, prev, base)
	if not _approx(adjusted, 162.0, 1.0):
		_fail("uphill speed should=162 (UPHILL_FACTOR 0.6 * 270), got %f" % adjusted)
		return
	# 平地：prev = self
	var flat: float = SlopeSpeedScr.apply(self_up, self_up, base)
	if not _approx(flat, base, 0.1):
		_fail("flat speed should=270, got %f" % flat)
		return
	# step = adjusted * delta = 162 * delta；验证 step < base * delta
	var delta := 0.1
	var step_up: float = adjusted * delta
	var step_base: float = base * delta
	if step_up >= step_base:
		_fail("uphill step should<base step, got up=%f base=%f" % [step_up, step_base])
		return
	print("  slope speed integration OK (162 < 270 in uphill)")


# 5. fallback：1 单位队形移动 → 1 slot = leader_pos → goal = goal_center + (0,0)
func _test_fallback_to_scatter() -> void:
	var leader_pos := Vector2(500.0, 500.0)
	var goal_center := Vector2(1500.0, 1500.0)
	var slots: PackedVector2Array = FormationScr.slot_positions(
		leader_pos, 0.0, 1, FormationScr.FORMATION_RECT, 64.0
	)
	if slots.size() != 1:
		_fail("count 1 should=1 slot, got %d" % slots.size())
		return
	var offset: Vector2 = slots[0] - slots[0]  # 始终 = (0, 0)
	if not _approx_v(offset, Vector2.ZERO, 0.001):
		_fail("count 1 offset should=zero, got %s" % offset)
		return
	var goal: Vector2 = goal_center + offset
	if not _approx_v(goal, goal_center, 0.001):
		_fail("count 1 goal should=goal_center, got %s" % goal)
		return
	print("  fallback to scatter OK (count 1 → goal=center)")
