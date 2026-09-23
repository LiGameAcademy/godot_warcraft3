class_name UnitMoveSlots
extends RefCounted
## 多单位右键移动：为每个单位分配错开的终点（WC3 XY）。
##
## 为何不靠 Godot 物理 / 完整 RVO：
## - 全局权威仍是网格 A*（PATHFINDING_CHOICE）；物理体会和 WPM 抢真相。
## - 原作群体移动主要靠「落点散开 + 途中轻碰撞」，不是流体仿真。
## - 站着不被挤开：本模块只改 Move 终点，不推动静止单位。

## 黄金角螺旋：比纯圆环更省空间，5 个农民不会围成大空心圈。
const GOLDEN_ANGLE := 2.399963229728653


## units: Array[Node3D]（已过滤建筑）；radii 与 units 对齐（WC3）。
## 返回与 units 等长的 PackedVector2Array 终点。
static func assign_goals(
	units: Array,
	radii: PackedFloat32Array,
	center_wc3: Vector2,
	path_query: RefCounted = null
) -> PackedVector2Array:
	var n := units.size()
	var out := PackedVector2Array()
	out.resize(n)
	if n <= 0:
		return out
	if n == 1:
		out[0] = _snap(center_wc3, path_query)
		return out
	var spacing := _avg_spacing(radii)
	for i in range(n):
		var offset := _spiral_offset(i, spacing)
		var goal := center_wc3 + offset
		out[i] = _snap(goal, path_query)
	return out


static func _avg_spacing(radii: PackedFloat32Array) -> float:
	if radii.is_empty():
		return 32.0
	var s := 0.0
	for r in radii:
		s += float(r)
	var avg := s / float(radii.size())
	# 圆心距 ≈ 2r * 1.15，略留缝，避免选中环完全贴死
	return maxf(avg * 2.3, 28.0)


static func _spiral_offset(index: int, spacing: float) -> Vector2:
	if index <= 0:
		return Vector2.ZERO
	var radius := spacing * sqrt(float(index))
	var ang := float(index) * GOLDEN_ANGLE
	return Vector2(cos(ang), sin(ang)) * radius


static func _snap(wc3: Vector2, path_query: RefCounted) -> Vector2:
	if path_query == null or not path_query.has_method("snap_to_walkable"):
		return wc3
	var d: Dictionary = path_query.call("snap_to_walkable", wc3.x, wc3.y, 8)
	if bool(d.get("ok", false)):
		return d.get("wc3", wc3) as Vector2
	return wc3
