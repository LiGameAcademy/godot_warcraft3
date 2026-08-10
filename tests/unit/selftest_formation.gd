extends SceneTree
## F-PATH-5 · FormationFollow 单测。
## godot --headless --path . -s res://tests/unit/selftest_formation.gd

const FormationScr = preload("res://game/scripts/logic/pathing/formation_follow.gd")

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_wedge_5()
	_test_rect_9()
	_test_circle_8()
	_test_heading_rotation()
	_test_count_1()
	if failed == 0:
		print("selftest_formation: PASS")
		quit(0)
	else:
		push_error("selftest_formation: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _approx(a: Vector2, b: Vector2, eps: float = 1.0) -> bool:
	return a.distance_to(b) <= eps


# 1. 楔形 5 单位：leader 在 (100, 100), heading 0 (+X), spacing 64
# leader (0, 0)
# i=1: row=1, is_left, lateral=-64 → (-64, -64)
# i=2: row=1, is_right, lateral=+64 → (+64, -64)
# i=3: row=2, is_left, lateral=-64 → (-128, -128) 等等？row=2, back*2 = (-128, 0)
#   pos = (-128, 0) + (-64, 0) = (-192, 0)
# 等等，重读代码：back = -spacing × heading = (-64, 0); pos = back × row + side × lateral
# row=2: pos = (-64, 0) × 2 + (-64, 0) = (-192, 0)
# i=4: row=2, is_right → (-128, 0) + (64, 0) = (-64, 0)
# local slots (5): (0,0), (-64,-64), (64,-64), (-192, 0), (-64, 0)
# Hmm，这看起来不对称。让我重新读 _wedge_slots 代码：
# back = Vector2(cos h, sin h) × -spacing  → (-64, 0)
# side = Vector2(-sin h, cos h) = (0, 1)
# for i=1, row=1, is_left=true, lateral=-64
#   pos = back * row + side * lateral = (-64,0)*1 + (0,1)*(-64) = (-64, -64) ✓
# for i=2, row=1, is_right=false, lateral=64
#   pos = (-64,0) + (0,64) = (-64, 64)
# 等等！lateral=64 在 (0,1) 方向 → y 增 64
# i=3: row=(3+1)/2=2, is_left=true (3%2=1), lateral=-64
#   pos = (-64,0)*2 + (0,-64) = (-128, -64)
# i=4: row=2, is_right=false (4%2=0), lateral=64
#   pos = (-128,0) + (0,64) = (-128, 64)
#
# 楔形 5 local: (0,0), (-64,-64), (-64, 64), (-128, -64), (-128, 64)
# 平移 (100, 100) 后 world: (100, 100), (36, 36), (36, 164), (-28, 36), (-28, 164)
# heading 0 → rotation = identity，local = world 偏移
func _test_wedge_5() -> void:
	var slots: PackedVector2Array = FormationScr.slot_positions(
		Vector2(100, 100), 0.0, 5, FormationScr.FORMATION_WEDGE, 64.0
	)
	if slots.size() != 5:
		_fail("wedge 5 should=5 slots, got %d" % slots.size())
		return
	if not _approx(slots[0], Vector2(100, 100), 0.1):
		_fail("slot 0 (leader) should=(100, 100), got %s" % slots[0])
		return
	# i=1: (-64, -64) + leader = (36, 36)
	if not _approx(slots[1], Vector2(36, 36), 0.1):
		_fail("slot 1 should=(36, 36), got %s" % slots[1])
		return
	# i=2: (-64, 64) + leader = (36, 164)
	if not _approx(slots[2], Vector2(36, 164), 0.1):
		_fail("slot 2 should=(36, 164), got %s" % slots[2])
		return
	# i=3: (-128, -64) + leader = (-28, 36)
	if not _approx(slots[3], Vector2(-28, 36), 0.1):
		_fail("slot 3 should=(-28, 36), got %s" % slots[3])
		return
	# i=4: (-128, 64) + leader = (-28, 164)
	if not _approx(slots[4], Vector2(-28, 164), 0.1):
		_fail("slot 4 should=(-28, 164), got %s" % slots[4])
		return
	print("  wedge 5 OK (leader + 4 follower 楔形)")


# 2. 矩形 9 单位：3 列 × 3 行
# leader (0, 0)
# 8 follower: 行 1-3，列 0-2
# i=0: row=0, col=0, x=(-1)*64=-64, y=-1*64=-64 → (-64, -64)
# i=1: row=0, col=1, x=0, y=-64 → (0, -64)
# i=2: row=0, col=2, x=+64, y=-64 → (+64, -64)
# i=3-5: row=1, y=-128
# i=6-8: row=2, y=-192
func _test_rect_9() -> void:
	var slots: PackedVector2Array = FormationScr.slot_positions(
		Vector2.ZERO, 0.0, 9, FormationScr.FORMATION_RECT, 64.0
	)
	if slots.size() != 9:
		_fail("rect 9 should=9 slots, got %d" % slots.size())
		return
	# leader
	if not _approx(slots[0], Vector2.ZERO, 0.1):
		_fail("slot 0 should=(0,0), got %s" % slots[0])
		return
	# 第一个 follower: (-64, -64)
	if not _approx(slots[1], Vector2(-64, -64), 0.1):
		_fail("slot 1 should=(-64,-64), got %s" % slots[1])
		return
	# 第二个: (0, -64)
	if not _approx(slots[2], Vector2(0, -64), 0.1):
		_fail("slot 2 should=(0,-64), got %s" % slots[2])
		return
	# 第六个 (i=5, row=1, col=2): (64, -128)
	if not _approx(slots[6], Vector2(64, -128), 0.1):
		_fail("slot 6 should=(64,-128), got %s" % slots[6])
		return
	print("  rect 9 OK (3×3 网格)")


# 3. 圆形 8 单位：8 等分（不含 leader → 7 follower）
# radius=64, 7 follower at i*2π/7
# i=0: 0° → (64, 0)
# i=1: 360/7 ≈ 51.43° → (64cos, 64sin)
func _test_circle_8() -> void:
	var slots: PackedVector2Array = FormationScr.slot_positions(
		Vector2.ZERO, 0.0, 8, FormationScr.FORMATION_CIRCLE, 64.0
	)
	if slots.size() != 8:
		_fail("circle 8 should=8 slots, got %d" % slots.size())
		return
	# leader 在中心
	if not _approx(slots[0], Vector2.ZERO, 0.1):
		_fail("slot 0 should=(0,0), got %s" % slots[0])
		return
	# 7 follower 都在半径 64 圆上
	for i in range(1, 8):
		var dist: float = slots[i].length()
		if absf(dist - 64.0) > 0.5:
			_fail("slot %d dist should~64, got %f" % [i, dist])
			return
	# 第一个 follower at 0° → (64, 0)
	if not _approx(slots[1], Vector2(64, 0), 0.1):
		_fail("slot 1 should=(64, 0), got %s" % slots[1])
		return
	print("  circle 8 OK (7 follower 半径 64)")


# 4. heading 旋转 90°：楔形 slots 跟着转
# heading 90° = (0, 1) 方向 = 屏下
# local slot 1: (-64, -64) 旋转 90° → (64, -64)
# 平移 leader (100, 100) → (164, 36)
func _test_heading_rotation() -> void:
	var slots: PackedVector2Array = FormationScr.slot_positions(
		Vector2(100, 100), PI / 2.0, 5, FormationScr.FORMATION_WEDGE, 64.0
	)
	# 旋转 90°：local (-64, -64) → (64, -64)
	# 加上 leader (100, 100) → (164, 36)
	if not _approx(slots[1], Vector2(164, 36), 0.1):
		_fail("rotated slot 1 should=(164, 36), got %s" % slots[1])
		return
	# 旋转 180° (heading = π): local (-64, -64) → (64, 64) + leader = (164, 164)
	slots = FormationScr.slot_positions(
		Vector2(100, 100), PI, 5, FormationScr.FORMATION_WEDGE, 64.0
	)
	if not _approx(slots[1], Vector2(164, 164), 0.1):
		_fail("rotated 180° slot 1 should=(164, 164), got %s" % slots[1])
		return
	print("  heading rotation OK (90°/180°)")


# 5. count=1：只 leader
func _test_count_1() -> void:
	var slots: PackedVector2Array = FormationScr.slot_positions(
		Vector2(50, 50), 0.0, 1, FormationScr.FORMATION_WEDGE, 64.0
	)
	if slots.size() != 1:
		_fail("count 1 should=1 slot, got %d" % slots.size())
		return
	if not _approx(slots[0], Vector2(50, 50), 0.1):
		_fail("count 1 should=(50, 50), got %s" % slots[0])
		return
	print("  count 1 OK (only leader)")
