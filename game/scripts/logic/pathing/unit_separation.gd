class_name UnitSeparation
extends RefCounted
## 单位 soft 分离（Logic）：纯数学，不碰场景树 / PathingMap。
##
## PATHFINDING_CHOICE D3：全局仍走网格 A*；叠位用局部 push，不改 WPM。
## 只作用于「正在移动」的单位自身位移；不推动站立单位（对齐原作）。
## neighbors 条目：{ "pos": Vector2, "r": float, "id": int? }（WC3 XY / 半径）。

## 穿透量 → 推开速度增益。略大，否则同终点时仍会挤成一团。
const STRENGTH := 4.0
## 分离速度上限（WC3/秒）。
const MAX_PUSH_SPEED := 220.0


## 计算本帧应叠加的分离速度（WC3 XY / 秒）。
## self_id：用于完全重合时得到稳定且互异的推开方向（同 type 半径相同不能当种子）。
static func compute_push_velocity(
	self_pos: Vector2,
	self_r: float,
	neighbors: Array,
	self_id: int = 0
) -> Vector2:
	var push := Vector2.ZERO
	for n in neighbors:
		if not (n is Dictionary):
			continue
		var d: Dictionary = n
		var np: Vector2 = d.get("pos", self_pos)
		var nr := float(d.get("r", 0.0))
		var delta := self_pos - np
		var dist_sq := delta.length_squared()
		var min_d := self_r + nr
		var min_d_sq := min_d * min_d
		if dist_sq >= min_d_sq:
			continue
		var dist := sqrt(dist_sq)
		if dist < 0.5:
			# 完全重合：用双方 instance id 生成对向分离轴（同半径农民也能拆开）
			var other_id := int(d.get("id", 0))
			var seed_i := self_id * 73856093 ^ other_id * 19349663
			if seed_i == 0:
				seed_i = self_id + 1
			var ang := float(abs(seed_i) % 360) * TAU / 360.0
			# id 较大的一方走 +ang，较小走反向，保证成对推开
			if self_id < other_id:
				ang += PI
			delta = Vector2(cos(ang), sin(ang))
			dist = 0.5
		var pen := min_d - dist
		# 穿透越大推力越大（二次项让叠层更快散开）
		push += (delta / dist) * pen * STRENGTH * (1.0 + pen / maxf(min_d, 1.0))
	if push == Vector2.ZERO:
		return Vector2.ZERO
	var spd := push.length()
	if spd > MAX_PUSH_SPEED:
		push *= MAX_PUSH_SPEED / spd
	return push
