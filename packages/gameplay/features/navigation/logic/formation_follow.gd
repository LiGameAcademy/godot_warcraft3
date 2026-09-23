class_name FormationFollow
extends RefCounted

## 编队跟随：leader 走 path，follower 按 slot 偏移。
## WC3 复刻：圣骑士 + 农民 / 步兵队列。
## 纯函数：输入 leader_pos / leader_heading（WC3 弧度，0 = +X 方向）/ count / formation / spacing；
## 返 PackedVector2Array（count 个 slot 位置；leader 在第 0 位）。
##
## formation 字符串：wedge / rect / circle。
## 不做：菱形 / 圆弧阵（远期）。

const FORMATION_WEDGE := "wedge"
const FORMATION_RECT := "rect"
const FORMATION_CIRCLE := "circle"

## 楔形：leader 前方，左右交替排，间隔 = spacing
## 永远在 heading=0 坐标系（leader 朝 +X）下生成 local slots；
## 旋转由 slot_positions 统一做，避免重复旋转。
static func _wedge_slots(count: int, spacing: float) -> PackedVector2Array:
	var slots := PackedVector2Array()
	if count <= 0:
		return slots
	slots.append(Vector2.ZERO)  # leader
	if count == 1:
		return slots
	# heading=0：前方 = +X → back = -X
	var back := Vector2(-spacing, 0.0)
	# heading=0：横向 = +Y
	var side := Vector2(0.0, spacing)
	# 楔形 5 单位：leader + 2 排（每排 2 人）
	#   i=1: left back row 1
	#   i=2: right back row 1
	#   i=3: left back row 2
	#   i=4: right back row 2
	for i in range(1, count):
		@warning_ignore("integer_division")
		var row: int = (i + 1) / 2  # 1, 1, 2, 2, 3, 3, ...
		var is_left: bool = (i % 2 == 1)
		var lateral: float = -1.0 if is_left else 1.0
		var pos: Vector2 = back * float(row) + side * lateral
		slots.append(pos)
	return slots


## 矩形：leader 居中，count - 1 follower 按行排列（cols × rows）
##  默认列数 = 3（WC3 经典编队宽度）
static func _rect_slots(count: int, spacing: float) -> PackedVector2Array:
	var slots := PackedVector2Array()
	if count <= 0:
		return slots
	slots.append(Vector2.ZERO)
	if count == 1:
		return slots
	# 默认列数 3；行数 = ceil((count-1) / cols)
	var cols: int = 3
	var followers: int = count - 1
	var _rows: int = int(ceil(float(followers) / float(cols)))
	# leader 在 (0, 0)，后方（-Y）排列 follower
	# 行间距 = spacing；列间距 = spacing
	# 居中：列偏移 = -(cols-1) * spacing / 2
	for i in range(followers):
		@warning_ignore("integer_division")
		var row: int = i / cols
		var col: int = i % cols
		var x: float = (float(col) - float(cols - 1) * 0.5) * spacing
		var y: float = -float(row + 1) * spacing
		slots.append(Vector2(x, y))
	return slots


## 圆形：leader 居中，count - 1 follower 绕 leader 等分
static func _circle_slots(count: int, spacing: float) -> PackedVector2Array:
	var slots := PackedVector2Array()
	if count <= 0:
		return slots
	slots.append(Vector2.ZERO)
	if count == 1:
		return slots
	# follower 半径 = spacing
	var radius: float = spacing
	var followers: int = count - 1
	# 从 heading 方向（前方）开始顺时针排
	for i in range(followers):
		var ang: float = float(i) * TAU / float(followers)
		var pos: Vector2 = Vector2(cos(ang), sin(ang)) * radius
		slots.append(pos)
	return slots


## 计算 slot 位置（绝对 WC3 XY）。
## 入口：
##   leader_pos     — leader 当前位置
##   leader_heading — leader 正面朝向（WC3 弧度，0 = +X）
##   count          — 总单位数（含 leader）
##   formation      — FORMATION_WEDGE / RECT / CIRCLE
##   spacing        — 队形间距（WC3 单位）
## 返 PackedVector2Array（count 个）
static func slot_positions(
	leader_pos: Vector2,
	leader_heading: float,
	count: int,
	formation: String,
	spacing: float = 64.0
) -> PackedVector2Array:
	if count <= 0:
		return PackedVector2Array()
	var local_slots: PackedVector2Array
	match formation:
		FORMATION_WEDGE:
			local_slots = _wedge_slots(count, spacing)
		FORMATION_RECT:
			local_slots = _rect_slots(count, spacing)
		FORMATION_CIRCLE:
			local_slots = _circle_slots(count, spacing)
		_:
			# 默认 rect
			local_slots = _rect_slots(count, spacing)
	# local → world：旋转 leader_heading + 平移 leader_pos
	var cos_h: float = cos(leader_heading)
	var sin_h: float = sin(leader_heading)
	var out := PackedVector2Array()
	for p in local_slots:
		var lp: Vector2 = p
		# 旋转：(x*cos - y*sin, x*sin + y*cos)
		var wx: float = lp.x * cos_h - lp.y * sin_h
		var wy: float = lp.x * sin_h + lp.y * cos_h
		out.append(leader_pos + Vector2(wx, wy))
	return out
