class_name Wc3RampPaint
extends RefCounted

const MapLogScript = preload("res://scripts/map/map_log.gd")

## HiveWE `CliffOperator::update_ramp` 同构规划（只算标记，不写盘）。
## 权威：docs/RAMP_WE.md §4
##
## 三层架构：
##   Step 1 — 单列斜坡：沿方向标注连续 3 个顶点
##   Step 2 — 方向变体：
##     同侧扩展 → 增加斜坡宽度（多列）
##     邻侧扩展 → 对角斜坡，3×3 box（9点）
##   Step 3 — 路由：根据顶点信息 + 门禁校验，决定落哪种变体
##
## WC3 网格坐标系：ix=X（列），iy=Y（行），iy 增加 = 屏幕下方（对应 Godot -Z）


## 鼠标相对角点偏移 → 离散 ±1 方向；弱轴（不足强轴一半）软化为 0。
static func soften_dirs(dx: float, dy: float) -> Vector2i:
	var ax := absf(dx)
	var ay := absf(dy)
	var hx := 0 if ax < 0.0001 else (1 if dx > 0.0 else -1)
	var hy := 0 if ay < 0.0001 else (1 if dy > 0.0 else -1)
	if hx != 0 and hy != 0:
		if ax >= ay * 2.0:
			hy = 0
		elif ay >= ax * 2.0:
			hx = 0
	return Vector2i(hx, hy)


## ============================================================
## Step 1：单列斜坡
## ============================================================

## 沿方向标注连续 3 个顶点（origin, +1, +2）
## dir: Vector2i(hx, hy)，hx/hy ∈ {-1, 0, 1}，至少有一个非零
static func mark_column(
	ramp: PackedByteArray,
	ix: int,
	iy: int,
	dir: Vector2i,
	tp_w: int,
	tp_h: int
) -> void:
	for step in range(3):
		var x: int = ix + step * dir.x
		var y: int = iy + step * dir.y
		_set_ramp(ramp, tp_w, tp_h, x, y, true)


## ============================================================
## Step 2：方向变体
## ============================================================

## 2a. 同侧扩展：增加斜坡宽度（沿侧方向扩展多列）
## origin: 坡的起点（高侧角点）
## main_dir: 坡的方向（单列的延伸方向）
## side_dir: 侧方向（垂直于 main_dir，决定往哪侧扩宽）
## width: 总宽度（1=单列，2=双列，3=三列...）
## ramp: PackedByteArray 可直接修改
static func extend_same_side(
	ramp: PackedByteArray,
	origin: Vector2i,
	main_dir: Vector2i,
	side_dir: Vector2i,
	width: int,
	tp_w: int,
	tp_h: int
) -> void:
	## side_dir 必须是垂直于 main_dir 的单位向量
	## main_dir.x != 0 → 水平坡，side_dir 沿 Y 轴
	## main_dir.y != 0 → 竖直坡，side_dir 沿 X 轴
	for col in range(width):
		if main_dir.x != 0:
			## 水平坡：同列不同 X，Y = origin.y + col * side_dir.y
			var y: int = origin.y + col * side_dir.y
			for step in range(3):
				var x: int = origin.x + step * main_dir.x
				_set_ramp(ramp, tp_w, tp_h, x, y, true)
		else:
			## 竖直坡：同行的不同 Y，X = origin.x + col * side_dir.x
			var x: int = origin.x + col * side_dir.x
			for step in range(3):
				var y: int = origin.y + step * main_dir.y
				_set_ramp(ramp, tp_w, tp_h, x, y, true)


## 2b. 邻侧扩展：对角斜坡，标注 3×3 box
## 从 origin 出发，沿 hx/hy 各走 0,1,2 步，共 9 点
## hx, hy ∈ {-1, 1}，两者都必须非零（对角）
static func extend_adjacent_side(
	ramp: PackedByteArray,
	ix: int,
	iy: int,
	hx: int,
	hy: int,
	tp_w: int,
	tp_h: int
) -> void:
	for dx in range(3):
		for dy in range(3):
			var x: int = ix + hx * dx
			var y: int = iy + hy * dy
			_set_ramp(ramp, tp_w, tp_h, x, y, true)


## ============================================================
## Step 3：路由判断
## ============================================================

## 主入口：规划斜坡落点
## horizontal/vertical ∈ {-1, 0, 1} — 鼠标相对格子的偏移方向
## 返回 plan dict（含 ok, variant, axis, sx, sy, marked）
static func plan(
	ix: int,
	iy: int,
	layers: Array,
	flags: Array,
	tp_w: int,
	tp_h: int,
	horizontal: int = 0,
	vertical: int = 0
) -> Dictionary:
	## 边界检查
	if layers.is_empty() or ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return Wc3RampLogic.plan_fail("顶点越界")

	## 计算层差
	var origin_level: int = int(layers[iy * tp_w + ix])
	var target_level: int = origin_level - 1
	if target_level < 0:
		return Wc3RampLogic.plan_fail("已在最低层，无法向更低刷坡")

	## 规范方向
	var hx: int = clampi(horizontal, -1, 1)
	var hy: int = clampi(vertical, -1, 1)

	## 零方向时按邻域推断
	if hx == 0 and hy == 0:
		var inferred: Vector2i = _infer_dirs(ix, iy, layers, tp_w, tp_h, target_level)
		hx = inferred.x
		hy = inferred.y
		if hx == 0 and hy == 0:
			return Wc3RampLogic.plan_fail("附近没有层差为 1 的低侧（请点在高台侧）")

	## 建立 ramp 快照（只读当前已有标记，用于门禁判断）
	var ramp: PackedByteArray = PackedByteArray()
	ramp.resize(tp_w * tp_h)
	for i in range(flags.size()):
		ramp[i] = 1 if (int(flags[i]) & Wc3Coords.FLAG_RAMP) != 0 else 0

	## 校验各方向是否可落
	var allow_h: bool = (hx != 0) and _check_column(
		ix, iy, hx, 0, origin_level, target_level, layers, ramp, tp_w, tp_h
	)
	var allow_v: bool = (hy != 0) and _check_column(
		ix, iy, 0, hy, origin_level, target_level, layers, ramp, tp_w, tp_h
	)
	var allow_d: bool = (hx != 0 and hy != 0) and _check_diagonal_box(
		ix, iy, hx, hy, origin_level, target_level, layers, tp_w, tp_h
	)

	## 至少有一个方向可落
	if not allow_h and not allow_v and not allow_d:
		MapLogScript.debug(
			MapLogScript.Layer.LOGIC, "RampPaint",
			"reject @(ix=%d,iy=%d) hx=%d hy=%d origin=%d target=%d allow_h=%s allow_v=%s allow_d=%s"
			% [ix, iy, hx, hy, origin_level, target_level,
			   str(allow_h), str(allow_v), str(allow_d)]
		)
		return Wc3RampLogic.plan_fail("侧脊限制或不完整低侧，无法落坡")

	## 根据路由落标记
	if allow_d:
		## 邻侧扩展：对角斜坡 3×3 box
		extend_adjacent_side(ramp, ix, iy, hx, hy, tp_w, tp_h)
	elif allow_h and allow_v:
		## 两臂都合法但对角不合法：标注 L 形（横+竖）
		mark_column(ramp, ix, iy, Vector2i(hx, 0), tp_w, tp_h)
		mark_column(ramp, ix, iy, Vector2i(0, hy), tp_w, tp_h)
	elif allow_h:
		## 只有水平臂
		mark_column(ramp, ix, iy, Vector2i(hx, 0), tp_w, tp_h)
	elif allow_v:
		## 只有竖直臂
		mark_column(ramp, ix, iy, Vector2i(0, hy), tp_w, tp_h)

	## 收集本次落标记的顶点（与旧标记的差集）
	var marked: Array[Vector2i] = _collect_new_marks(
		ramp, flags, tp_w, tp_h
	)
	if marked.is_empty():
		return Wc3RampLogic.plan_fail("斜坡已存在")

	## 确定轴向和变体
	var axis: String
	var variant: String
	if allow_d:
		axis = Wc3RampLogic.AXIS_D
		variant = Wc3RampLogic.VARIANT_DIAGONAL
	elif allow_h:
		axis = Wc3RampLogic.AXIS_H
		variant = Wc3RampLogic.VARIANT_STRAIGHT
	else:
		axis = Wc3RampLogic.AXIS_V
		variant = Wc3RampLogic.VARIANT_STRAIGHT

	return Wc3RampLogic.plan_ok(variant, axis, ix, iy, marked, hx, hy)


## ============================================================
## 低侧意图解析（当点在低侧时自动向上找到高侧落点）
## ============================================================

## 笔刷入口：先在点击角尝试；仅当失败源于「附近无层差」时才触发低侧 fallback。
## horizontal/vertical ∈ {-1, 0, 1}
static func plan_from_pointer(
	ix: int,
	iy: int,
	layers: Array,
	flags: Array,
	tp_w: int,
	tp_h: int,
	horizontal: int = 0,
	vertical: int = 0
) -> Dictionary:
	var direct: Dictionary = plan(ix, iy, layers, flags, tp_w, tp_h, horizontal, vertical)
	if bool(direct.get("ok", false)):
		return direct

	# 只有「附近无层差为1的低侧」或「侧脊限制」或「不完整」才值得尝试低侧解析
	var msg: String = str(direct.get("message", ""))
	if not (msg.contains("层差") or msg.contains("侧脊") or msg.contains("不完整")):
		return direct

	var resolved: Dictionary = _resolve_from_low_side(
		ix, iy, layers, flags, tp_w, tp_h, horizontal, vertical
	)
	if bool(resolved.get("ok", false)):
		return resolved
	return direct


## 从低侧向上解析到高侧角点
static func _resolve_from_low_side(
	click_x: int,
	click_y: int,
	layers: Array,
	flags: Array,
	tp_w: int,
	tp_h: int,
	pref_hx: int,
	pref_hy: int
) -> Dictionary:
	if layers.is_empty() or not _in_bounds(click_x, click_y, tp_w, tp_h):
		return Wc3RampLogic.plan_fail("顶点越界")

	var click_lv: int = int(layers[click_y * tp_w + click_x])
	var best: Dictionary = {}
	var best_score: int = -1

	## 在 click 周围 2 格内找「高一层」的角点
	for cy in range(click_y - 2, click_y + 3):
		for cx in range(click_x - 2, click_x + 3):
			if not _in_bounds(cx, cy, tp_w, tp_h):
				continue
			if cx == click_x and cy == click_y:
				continue
			if int(layers[cy * tp_w + cx]) != click_lv + 1:
				continue

			## 计算朝向 click 的方向
			var toward: Vector2i = Vector2i(
				clampi(click_x - cx, -1, 1),
				clampi(click_y - cy, -1, 1)
			)
			if toward.x == 0 and toward.y == 0:
				continue

			## 尝试在该高角点落坡
			var dir_opts: Array[Vector2i] = _dir_candidates(toward, pref_hx, pref_hy)
			for d in dir_opts:
				if d.x == 0 and d.y == 0:
					continue
				var sub_plan: Dictionary = plan(cx, cy, layers, flags, tp_w, tp_h, d.x, d.y)
				if not bool(sub_plan.get("ok", false)):
					continue
				if not _covers_click(sub_plan, click_x, click_y):
					continue

				var score: int = _score_plan(sub_plan, click_x, click_y, pref_hx, pref_hy)
				if score > best_score:
					best_score = score
					best = sub_plan

	if best_score < 0:
		return Wc3RampLogic.plan_fail("附近没有可用的高侧落点")
	return best


## 根据 toward（高→点击）和 pref（鼠标）产生候选方向。
## 低侧回退时必须优先 toward，否则单轴鼠标偏好会把坡刷到高台对侧。
static func _dir_candidates(toward: Vector2i, pref_hx: int, pref_hy: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pref: Vector2i = Vector2i(clampi(pref_hx, -1, 1), clampi(pref_hy, -1, 1))
	_append_dir(out, toward)
	if toward.x != 0 and toward.y != 0:
		_append_dir(out, Vector2i(toward.x, 0))
		_append_dir(out, Vector2i(0, toward.y))
	_append_dir(out, pref)
	if pref.x != 0 and pref.y != 0:
		_append_dir(out, Vector2i(pref.x, 0))
		_append_dir(out, Vector2i(0, pref.y))
	return out


static func _append_dir(out: Array[Vector2i], d: Vector2i) -> void:
	if d.x == 0 and d.y == 0:
		return
	for e in out:
		if e == d:
			return
	out.append(d)


## 检查 click 是否被 plan 的落旗点覆盖（不能只靠 origin 距离，否则对侧坡也会过）。
static func _covers_click(p: Dictionary, click_x: int, click_y: int) -> bool:
	for v in p.get("marked", []):
		var pt: Vector2i = v as Vector2i
		if maxi(absi(pt.x - click_x), absi(pt.y - click_y)) <= 2:
			return true
	return false


## 评分 plan 与 click 的匹配度
static func _score_plan(p: Dictionary, click_x: int, click_y: int, pref_hx: int, pref_hy: int) -> int:
	var score := 0
	for v in p.get("marked", []):
		var pt: Vector2i = v as Vector2i
		var d: int = maxi(absi(pt.x - click_x), absi(pt.y - click_y))
		if d == 0:
			score += 100
		elif d == 1:
			score += 40
		elif d == 2:
			score += 8

	var od: int = maxi(absi(int(p.get("sx", -1)) - click_x), absi(int(p.get("sy", -1)) - click_y))
	score += maxi(0, 6 - od) * 4

	var single_pref: bool = (pref_hx != 0) != (pref_hy != 0)
	var is_diag: bool = str(p.get("variant", "")) == Wc3RampLogic.VARIANT_DIAGONAL
	var n: int = (p.get("marked", []) as Array).size()
	if single_pref:
		if is_diag:
			score -= 80
		elif n > 3:
			score -= 40
		else:
			score += 25
	elif pref_hx != 0 and pref_hy != 0:
		if is_diag:
			score += 20
	return score


## ============================================================
## 辅助：方向推断（零方向时自动推断）
## ============================================================

static func _infer_dirs(
	ix: int, iy: int, layers: Array, tp_w: int, tp_h: int, target_level: int
) -> Vector2i:
	var hx := 0
	var hy := 0
	for d in [-1, 1]:
		if _two_steps_reach(ix, iy, d, 0, layers, tp_w, tp_h, target_level):
			hx = d
		if _two_steps_reach(ix, iy, 0, d, layers, tp_w, tp_h, target_level):
			hy = d
	return Vector2i(hx, hy)


static func _two_steps_reach(
	ix: int, iy: int, dx: int, dy: int,
	layers: Array, tp_w: int, tp_h: int, target: int
) -> bool:
	for step in range(1, 3):
		var x: int = ix + step * dx
		var y: int = iy + step * dy
		if x < 0 or y < 0 or x >= tp_w or y >= tp_h:
			return false
		if int(layers[y * tp_w + x]) != target:
			return false
	return true


## ============================================================
## 辅助：门禁校验
## ============================================================

## 单列门禁（检查 hx 或 hy 某一轴向是否可落）
## dir_x/dir_y 其中一个必须为 0，另一个 ∈ {-1, 1}
static func _check_column(
	ix: int,
	iy: int,
	dir_x: int,
	dir_y: int,
	origin_level: int,
	target_level: int,
	layers: Array,
	ramp: PackedByteArray,
	tp_w: int,
	tp_h: int
) -> bool:
	## 3 点都在地图内
	if ix + 2 * dir_x < 0 or ix + 2 * dir_x >= tp_w:
		return false
	if iy + 2 * dir_y < 0 or iy + 2 * dir_y >= tp_h:
		return false

	## 后两步必须是 target_level
	for step in range(1, 3):
		var x: int = ix + step * dir_x
		var y: int = iy + step * dir_y
		if int(layers[y * tp_w + x]) != target_level:
			return false

	## 侧邻检查：垂直于坡向的两侧，层高不得高于 origin_level
	## 坡向为 (dir_x, dir_y)，法向为 (-dir_y, dir_x) 和 (dir_y, -dir_x)
	var nx1: int = -dir_y
	var ny1: int = dir_x
	var nx2: int = dir_y
	var ny2: int = -dir_x
	if _in_bounds(ix + nx1, iy + ny1, tp_w, tp_h):
		if int(layers[(iy + ny1) * tp_w + (ix + nx1)]) > origin_level:
			return false
	if _in_bounds(ix + nx2, iy + ny2, tp_w, tp_h):
		if int(layers[(iy + ny2) * tp_w + (ix + nx2)]) > origin_level:
			return false

	## 对侧斜坡禁止：原点反方向已有落在低层的 ramp（同一崖脊双向落坡，无对应模型）
	var back_x: int = ix - dir_x
	var back_y: int = iy - dir_y
	if _in_bounds(back_x, back_y, tp_w, tp_h):
		if (
			_has_ramp(ramp, tp_w, tp_h, back_x, back_y)
			and int(layers[back_y * tp_w + back_x]) == target_level
		):
			return false

	## 侧翼禁贴：侧邻有 ramp 时须是「平行加宽」或「L/半侧转角」，禁止畸形对贴
	for side in [-1, 1]:
		var sx: int = ix + side * (-dir_y)
		var sy: int = iy + side * dir_x
		if not _in_bounds(sx, sy, tp_w, tp_h):
			continue
		if not _has_ramp(ramp, tp_w, tp_h, sx, sy):
			continue
		# 平行加宽：侧邻沿本坡向有完整臂
		var parallel_ok: bool = (
			_has_ramp(ramp, tp_w, tp_h, sx + dir_x, sy + dir_y)
			and _has_ramp(ramp, tp_w, tp_h, sx + 2 * dir_x, sy + 2 * dir_y)
		)
		if parallel_ok:
			continue
		# L / 半侧：侧邻属于从原点出发的垂直臂（完整 3 点）
		if _side_is_l_arm(ix, iy, sx, sy, ramp, tp_w, tp_h):
			continue
		return false

	return true


## 侧邻 (sx,sy) 是否与原点构成已有垂直臂（L 的一肢），允许再刷另一肢/对角。
static func _side_is_l_arm(
	ix: int, iy: int, sx: int, sy: int, ramp: PackedByteArray, tp_w: int, tp_h: int
) -> bool:
	var pdx: int = sx - ix
	var pdy: int = sy - iy
	if absi(pdx) + absi(pdy) != 1:
		return false
	# 原点须已在坡上；沿 (pdx,pdy) 再走一步也须有 ramp → 完整 3 点臂
	if not _has_ramp(ramp, tp_w, tp_h, ix, iy):
		return false
	if not _has_ramp(ramp, tp_w, tp_h, sx + pdx, sy + pdy):
		return false
	return true


## 对角 3×3 box 门禁：原点须为 origin_level；其余 8 点须为 target_level（RAMP_WE §4.2）。
static func _check_diagonal_box(
	ix: int,
	iy: int,
	hx: int,
	hy: int,
	origin_level: int,
	target_level: int,
	layers: Array,
	tp_w: int,
	tp_h: int
) -> bool:
	if not _in_bounds(ix, iy, tp_w, tp_h):
		return false
	if int(layers[iy * tp_w + ix]) != origin_level:
		return false
	for dx in range(3):
		for dy in range(3):
			if dx == 0 and dy == 0:
				continue
			var x: int = ix + hx * dx
			var y: int = iy + hy * dy
			if not _in_bounds(x, y, tp_w, tp_h):
				return false
			if int(layers[y * tp_w + x]) != target_level:
				return false
	return true


## ============================================================
## 辅助：标记收集与工具函数
## ============================================================

## 收集 ramp 中新标记的顶点（相对于原始 flags 的差集）
static func _collect_new_marks(
	ramp: PackedByteArray,
	flags: Array,
	tp_w: int,
	tp_h: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(tp_h):
		for x in range(tp_w):
			var i: int = y * tp_w + x
			var was_ramp: bool = (int(flags[i]) & Wc3Coords.FLAG_RAMP) != 0
			var now_ramp: bool = ramp[i] != 0
			if now_ramp and not was_ramp:
				out.append(Vector2i(x, y))
	return out


static func _in_bounds(x: int, y: int, tp_w: int, tp_h: int) -> bool:
	return x >= 0 and y >= 0 and x < tp_w and y < tp_h


static func _has_ramp(ramp: PackedByteArray, tp_w: int, tp_h: int, x: int, y: int) -> bool:
	if not _in_bounds(x, y, tp_w, tp_h):
		return false
	return ramp[y * tp_w + x] != 0


static func _set_ramp(ramp: PackedByteArray, tp_w: int, tp_h: int, x: int, y: int, on: bool) -> void:
	if not _in_bounds(x, y, tp_w, tp_h):
		return
	ramp[y * tp_w + x] = 1 if on else 0
