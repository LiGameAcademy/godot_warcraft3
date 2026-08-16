class_name Wc3RampPaint
extends RefCounted

const AppLogScript = preload("res://scripts/shared/infra/app_log.gd")

## 低侧 fallback 搜索半径（格）
const LOW_SIDE_SEARCH_RADIUS := 2

## HiveWE `CliffOperator::update_ramp` 同构规划（只算标记，不写盘）。
## 权威：docs/ramp/RAMP_WE.md §4
##
## 三层架构：
##   Step 1 — 单列斜坡：沿方向标注连续 3 个顶点
##   Step 2 — 方向变体：
##     同侧扩展 → 增加斜坡宽度（多列，暂未接入路由 @deprecated）
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


## L 补心：对齐 HiveWE —— 仅在本笔允许的横/竖意图象限补中心，不扫四向乱填。
## do_h：可补 (ix+hx, iy±1)；do_v：可补 (ix±1, iy+hy)。无有效意图时四向都试。
## 返回本次新填的中心点数。
static func fill_l_centers(
	ramp: PackedByteArray,
	ix: int,
	iy: int,
	layers: Array,
	target_level: int,
	tp_w: int,
	tp_h: int,
	hx: int = 0,
	hy: int = 0,
	do_h: bool = true,
	do_v: bool = true
) -> int:
	var filled := 0
	var any_intent: bool = (do_h and hx != 0) or (do_v and hy != 0)
	if any_intent:
		if do_h and hx != 0:
			for sy in [-1, 1]:
				if _try_fill_l_center_at(
					ramp, ix, iy, hx, sy, layers, target_level, tp_w, tp_h
				):
					filled += 1
		if do_v and hy != 0:
			for sx in [-1, 1]:
				if _try_fill_l_center_at(
					ramp, ix, iy, sx, hy, layers, target_level, tp_w, tp_h
				):
					filled += 1
	else:
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				if _try_fill_l_center_at(
					ramp, ix, iy, sx, sy, layers, target_level, tp_w, tp_h
				):
					filled += 1
	return filled


static func _try_fill_l_center_at(
	ramp: PackedByteArray,
	ix: int,
	iy: int,
	sx: int,
	sy: int,
	layers: Array,
	target_level: int,
	tp_w: int,
	tp_h: int
) -> bool:
	if sx == 0 or sy == 0:
		return false
	if not _has_ramp(ramp, tp_w, tp_h, ix, iy):
		return false
	if not (
		_has_ramp(ramp, tp_w, tp_h, ix + sx, iy)
		and _has_ramp(ramp, tp_w, tp_h, ix + 2 * sx, iy)
	):
		return false
	if not (
		_has_ramp(ramp, tp_w, tp_h, ix, iy + sy)
		and _has_ramp(ramp, tp_w, tp_h, ix, iy + 2 * sy)
	):
		return false
	var cx: int = ix + sx
	var cy: int = iy + sy
	if _has_ramp(ramp, tp_w, tp_h, cx, cy):
		return false
	if not _in_bounds(cx, cy, tp_w, tp_h):
		return false
	if int(layers[cy * tp_w + cx]) != target_level:
		return false
	_set_ramp(ramp, tp_w, tp_h, cx, cy, true)
	return true


## 不改 ramp，只判断在给定意图下是否会写入至少一点。
static func _would_fill_l_center(
	ix: int,
	iy: int,
	layers: Array,
	ramp: PackedByteArray,
	target_level: int,
	tp_w: int,
	tp_h: int,
	hx: int = 0,
	hy: int = 0,
	do_h: bool = true,
	do_v: bool = true
) -> bool:
	var tmp: PackedByteArray = ramp.duplicate()
	return (
		fill_l_centers(tmp, ix, iy, layers, target_level, tp_w, tp_h, hx, hy, do_h, do_v)
		> 0
	)

## 原点是否已有任一轴向完整 3 点臂（L 转角进行中）。
static func _origin_has_any_full_arm(
	ix: int, iy: int, ramp: PackedByteArray, tp_w: int, tp_h: int
) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _has_full_ramp_arm(ix, iy, d.x, d.y, ramp, tp_w, tp_h):
			return true
	return false


## 从原点沿 (dx,dy) 是否已有完整 3 点 ramp 臂。
static func _has_full_ramp_arm(
	ix: int, iy: int, dx: int, dy: int, ramp: PackedByteArray, tp_w: int, tp_h: int
) -> bool:
	if dx == 0 and dy == 0:
		return false
	for step in range(3):
		if not _has_ramp(ramp, tp_w, tp_h, ix + step * dx, iy + step * dy):
			return false
	return true


## ============================================================
## Step 3：路由判断
## ============================================================

## ============================================================
## Phase A：边界 + 层差 + 方向规范
## ============================================================
static func _plan_phase_a(
	ix: int, iy: int, layers: Array, tp_w: int, tp_h: int,
	horizontal: int, vertical: int
) -> Dictionary:
	if layers.is_empty() or ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return Wc3RampLogic.plan_fail("顶点越界")
	var origin_level: int = int(layers[iy * tp_w + ix])
	var target_level: int = origin_level - 1
	if target_level < 0:
		return Wc3RampLogic.plan_fail("已在最低层，无法向更低刷坡")
	var hx: int = clampi(horizontal, -1, 1)
	var hy: int = clampi(vertical, -1, 1)
	if hx == 0 and hy == 0:
		var inferred: Vector2i = _infer_dirs(ix, iy, layers, tp_w, tp_h, target_level)
		hx = inferred.x
		hy = inferred.y
		if hx == 0 and hy == 0:
			return Wc3RampLogic.plan_fail("附近没有层差为 1 的低侧（请点在高台侧）")
	return {"origin_level": origin_level, "target_level": target_level, "hx": hx, "hy": hy}


## ============================================================
## Phase B：ramp 快照 + 三重门禁
## ============================================================
static func _plan_phase_b(
	ix: int, iy: int,
	layers: Array, flags: Array,
	origin_level: int, target_level: int,
	hx: int, hy: int,
	tp_w: int, tp_h: int
) -> Dictionary:
	var ramp: PackedByteArray = PackedByteArray()
	ramp.resize(tp_w * tp_h)
	for i in range(flags.size()):
		ramp[i] = 1 if (int(flags[i]) & Wc3Coords.FLAG_RAMP) != 0 else 0
	var allow_h: bool = (hx != 0) and _check_column(
		ix, iy, hx, 0, origin_level, target_level, layers, ramp, tp_w, tp_h
	)
	var allow_v: bool = (hy != 0) and _check_column(
		ix, iy, 0, hy, origin_level, target_level, layers, ramp, tp_w, tp_h
	)
	var allow_d: bool = (hx != 0 and hy != 0) and _check_diagonal_box(
		ix, iy, hx, hy, origin_level, target_level, layers, tp_w, tp_h
	)
	return {"ramp": ramp, "allow_h": allow_h, "allow_v": allow_v, "allow_d": allow_d}


## ============================================================
## Phase C：L 状态机 + 门禁压制
## ============================================================
static func _plan_phase_c(
	ix: int, iy: int, hx: int, hy: int,
	allow_h: bool, allow_v: bool, allow_d: bool,
	ramp: PackedByteArray, layers: Array, target_level: int,
	tp_w: int, tp_h: int
) -> Dictionary:
	var had_arm: bool = _origin_has_any_full_arm(ix, iy, ramp, tp_w, tp_h)
	var lst: LRampState = _compute_l_state(
		ix, iy, hx, hy, allow_h, allow_v, allow_d, ramp, tp_w, tp_h, layers, target_level
	)
	if allow_d and had_arm and lst != LRampState.READY:
		allow_d = false
	if had_arm and not allow_d:
		if hx != 0 and _has_full_ramp_arm(ix, iy, hx, 0, ramp, tp_w, tp_h):
			allow_h = false
		if hy != 0 and _has_full_ramp_arm(ix, iy, 0, hy, ramp, tp_w, tp_h):
			allow_v = false
	return {
		"had_arm": had_arm, "lst": lst,
		"allow_h": allow_h, "allow_v": allow_v, "allow_d": allow_d,
		"ramp": ramp,
	}


## ============================================================
## Phase D：落旗 + 变体解析
## ============================================================
static func _plan_phase_d(
	ix: int, iy: int,
	hx: int, hy: int,
	layers: Array, flags: Array,
	allow_h: bool, allow_v: bool, allow_d: bool,
	had_arm: bool, lst: LRampState,
	target_level: int,
	tp_w: int, tp_h: int,
	ramp: PackedByteArray
) -> Dictionary:
	if not allow_h and not allow_v and not allow_d and lst != LRampState.FILL_ONLY:
		AppLogScript.debug(
			AppLogScript.Layer.LOGIC, "RampPaint",
			"reject @(ix=%d,iy=%d) hx=%d hy=%d origin=%d target=%d allow_h=%s allow_v=%s allow_d=%s had_arm=%s"
			% [ix, iy, hx, hy, target_level + 1, target_level,
			   str(allow_h), str(allow_v), str(allow_d), str(had_arm)]
		)
		return Wc3RampLogic.plan_fail("侧脊限制或不完整低侧，无法落坡")

	if allow_h:
		mark_column(ramp, ix, iy, Vector2i(hx, 0), tp_w, tp_h)
	if allow_v:
		mark_column(ramp, ix, iy, Vector2i(0, hy), tp_w, tp_h)
	if allow_d:
		extend_adjacent_side(ramp, ix, iy, hx, hy, tp_w, tp_h)

	var filled_l: int = fill_l_centers(
		ramp, ix, iy, layers, target_level, tp_w, tp_h,
		hx, hy,
		allow_h or allow_d or lst == LRampState.FILL_ONLY,
		allow_v or allow_d or lst == LRampState.FILL_ONLY
	)

	var marked: Array[Vector2i] = _collect_new_marks(ramp, flags, tp_w, tp_h)
	if marked.is_empty():
		return Wc3RampLogic.plan_fail("斜坡已存在")

	var axis: String
	var variant: String
	if allow_d:
		axis = Wc3RampLogic.AXIS_D
		variant = Wc3RampLogic.VARIANT_DIAGONAL
	elif (
		filled_l > 0
		or lst == LRampState.FILL_ONLY
		or (had_arm and (allow_h or allow_v))
		or (allow_h and allow_v)
	):
		## L 变体使用 AXIS_D：L 本质是两臂交汇的角点，与对角共享「角轴」语义。
		## 后续 footprint 判断只用 H/V；D 轴仅作标记用途，不影响 Present 建模。
		axis = Wc3RampLogic.AXIS_D
		variant = Wc3RampLogic.VARIANT_L
	elif allow_h:
		axis = Wc3RampLogic.AXIS_H
		variant = Wc3RampLogic.VARIANT_STRAIGHT
	else:
		axis = Wc3RampLogic.AXIS_V
		variant = Wc3RampLogic.VARIANT_STRAIGHT

	AppLogScript.debug(
		AppLogScript.Layer.LOGIC, "RampPaint",
		"ok @(ix=%d,iy=%d) hx=%d hy=%d variant=%s allow_h=%s allow_v=%s allow_d=%s filled_l=%d marked=%s"
		% [ix, iy, hx, hy, variant, str(allow_h), str(allow_v), str(allow_d),
		   filled_l, str(marked)]
	)
	return Wc3RampLogic.plan_ok(variant, axis, ix, iy, marked, hx, hy)


## 主入口：规划斜坡落点（对齐 HiveWE `CliffOperator::update_ramp`）
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
	## Phase A：边界 + 层差 + 方向规范
	var ctx_a: Dictionary = _plan_phase_a(ix, iy, layers, tp_w, tp_h, horizontal, vertical)
	if not ctx_a.has("origin_level"):  ## 无此键 → plan_fail
		return Wc3RampLogic.plan_fail(str(ctx_a.get("message", "")))
	var origin_level: int = ctx_a.origin_level
	var target_level: int = ctx_a.target_level
	var hx: int = ctx_a.hx
	var hy: int = ctx_a.hy

	## Phase B：ramp 快照 + 三重门禁
	var ctx_b: Dictionary = _plan_phase_b(
		ix, iy, layers, flags, origin_level, target_level, hx, hy, tp_w, tp_h
	)
	var ramp: PackedByteArray = ctx_b.ramp
	var allow_h: bool = ctx_b.allow_h
	var allow_v: bool = ctx_b.allow_v
	var allow_d: bool = ctx_b.allow_d

	## Phase C：L 状态机 + 门禁压制
	var ctx_c: Dictionary = _plan_phase_c(
		ix, iy, hx, hy, allow_h, allow_v, allow_d, ramp, layers, target_level, tp_w, tp_h
	)
	var had_arm: bool = ctx_c.had_arm
	var lst: LRampState = ctx_c.lst
	allow_h = ctx_c.allow_h
	allow_v = ctx_c.allow_v
	allow_d = ctx_c.allow_d

	## Phase D：落旗 + 变体解析（ramp 来自 ctx_c，不再重建）
	return _plan_phase_d(
		ix, iy, hx, hy, layers, flags,
		allow_h, allow_v, allow_d,
		had_arm, lst, target_level,
		tp_w, tp_h, ctx_c.ramp
	)


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
		AppLogScript.debug(
			AppLogScript.Layer.LOGIC, "RampPaint",
			"low_side_fallback ok @(click=%d,%d) origin=(%d,%d) variant=%s"
			% [ix, iy, resolved.get("sx", 0), resolved.get("sy", 0), resolved.get("variant", "")]
		)
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

	## 在 click 周围 LOW_SIDE_SEARCH_RADIUS 格内找「高一层」的角点
	for cy in range(click_y - LOW_SIDE_SEARCH_RADIUS, click_y + LOW_SIDE_SEARCH_RADIUS + 1):
		for cx in range(click_x - LOW_SIDE_SEARCH_RADIUS, click_x + LOW_SIDE_SEARCH_RADIUS + 1):
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

			## 尝试在该高角点落坡（单轴候选，不会自动升 3×3）
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
## 单轴 pref：绝不把对角 toward 放进候选（避免评到 diagonal×6）。
static func _dir_candidates(toward: Vector2i, pref_hx: int, pref_hy: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pref: Vector2i = Vector2i(clampi(pref_hx, -1, 1), clampi(pref_hy, -1, 1))
	var single_pref: bool = (pref.x != 0) != (pref.y != 0)
	if single_pref:
		# 偏好轴 ∩ toward 分量优先，再补 toward 单轴拆分与 pref
		if pref.x != 0 and toward.x != 0:
			_append_dir(out, Vector2i(toward.x, 0))
		if pref.y != 0 and toward.y != 0:
			_append_dir(out, Vector2i(0, toward.y))
		if toward.x != 0:
			_append_dir(out, Vector2i(toward.x, 0))
		if toward.y != 0:
			_append_dir(out, Vector2i(0, toward.y))
		_append_dir(out, pref)
		return out
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
##
## 评分因子说明：
##   标记点距离：d=0 → +100, d=1 → +40, d=2 → +8（Chebyshev 距离，幂次衰减）
##   原点距离：od = max(|dx|,|dy|)，每少 1 格 +4，上限 6 格 → 0
##   轴向对齐：click 落在「沿本笔坡向的轴上」→ +60（真·转角原点）
##   变体偏好（单轴 pref）：
##     diagonal -80（避免对角蹭入单轴意图）
##     L +10（可接受）
##     n>3 单列 -40（宽列不符单轴意图）
##     单列 +25（最佳匹配）
##   变体偏好（双轴 pref）：
##     diagonal +20, L +15
##   L 紧邻：od≤1 且 L 变体 → +20
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

	var osx: int = int(p.get("sx", -1))
	var osy: int = int(p.get("sy", -1))
	var od: int = maxi(absi(osx - click_x), absi(osy - click_y))
	score += maxi(0, 6 - od) * 4

	# 点击落在「从原点沿本笔坡向」的轴上 → 真·转角原点（避免邻列 L 补心蹭到点击）
	var ph: int = int(p.get("horizontal", 0))
	var pv: int = int(p.get("vertical", 0))
	if pv != 0 and click_x == osx and (click_y - osy) * pv > 0:
		score += 60
	if ph != 0 and click_y == osy and (click_x - osx) * ph > 0:
		score += 60

	var variant: String = str(p.get("variant", ""))
	var is_diag: bool = variant == Wc3RampLogic.VARIANT_DIAGONAL
	var is_l: bool = variant == Wc3RampLogic.VARIANT_L
	var n: int = (p.get("marked", []) as Array).size()
	var single_pref: bool = (pref_hx != 0) != (pref_hy != 0)
	if is_l and od <= 1:
		score += 20
	if single_pref:
		if is_diag:
			score -= 80
		elif is_l:
			score += 10
		elif n > 3:
			score -= 40
		else:
			score += 25
	elif pref_hx != 0 and pref_hy != 0:
		if is_diag:
			score += 20
		elif is_l:
			score += 15
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

## 侧翼禁贴检查：侧邻有 ramp 时须是「平行加宽」或「L/半侧转角」，禁止畸形对贴
## completing_l：原点已有垂直于本坡向的完整臂时，允许侧邻有旗（邻列异源坡不再误拒）
static func _check_side_clearance(
	ix: int,
	iy: int,
	dir_x: int,
	dir_y: int,
	ramp: PackedByteArray,
	tp_w: int,
	tp_h: int
) -> bool:
	var completing_l: bool = false
	if dir_x != 0:
		completing_l = (
			_has_full_ramp_arm(ix, iy, 0, 1, ramp, tp_w, tp_h)
			or _has_full_ramp_arm(ix, iy, 0, -1, ramp, tp_w, tp_h)
		)
	elif dir_y != 0:
		completing_l = (
			_has_full_ramp_arm(ix, iy, 1, 0, ramp, tp_w, tp_h)
			or _has_full_ramp_arm(ix, iy, -1, 0, ramp, tp_w, tp_h)
		)
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
		# 本原点正在补 L 的第二臂：邻列已有坡不阻挡
		if completing_l:
			continue
		return false
	return true


## L 状态枚举：替代 5 个布尔量（had_arm / has_h_arm / has_v_arm / l_ready / l_fill_only）
enum LRampState {
	NONE,      # 原点无臂
	HAS_H,     # 仅有水平臂
	HAS_V,     # 仅有竖直臂
	READY,     # 两臂齐（L 成型）
	FILL_ONLY, # 列门禁全拒但能补 L 中心
}


## 根据臂状态和门禁结果计算 L 状态
static func _compute_l_state(
	ix: int,
	iy: int,
	hx: int,
	hy: int,
	allow_h: bool,
	allow_v: bool,
	allow_d: bool,
	ramp: PackedByteArray,
	tp_w: int,
	tp_h: int,
	layers: Array,
	target_level: int
) -> LRampState:
	var has_h: bool = (
		_has_full_ramp_arm(ix, iy, 1, 0, ramp, tp_w, tp_h)
		or _has_full_ramp_arm(ix, iy, -1, 0, ramp, tp_w, tp_h)
	)
	var has_v: bool = (
		_has_full_ramp_arm(ix, iy, 0, 1, ramp, tp_w, tp_h)
		or _has_full_ramp_arm(ix, iy, 0, -1, ramp, tp_w, tp_h)
	)
	if not has_h and not has_v:
		return LRampState.NONE
	if has_h and has_v:
		return LRampState.READY
	if not allow_h and not allow_v and not allow_d:
		if _would_fill_l_center(
			ix, iy, layers, ramp, target_level, tp_w, tp_h, hx, hy, true, true
		):
			return LRampState.FILL_ONLY
	return LRampState.HAS_H if has_h else LRampState.HAS_V


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

	## 紧贴对侧斜坡禁门（侧翼 ramp 不齐 → 拒绝，避免细脊双侧落坡）
	## 对齐 HiveWE `CliffOperator::check_ramp_direction` line 448-459。
	## 仅当"侧翼 corner 已有 ramp 但沿本坡向延伸不齐"时拒绝。
	for side in [-1, 1]:
		# Y 方向侧翼：(ix, iy+side) 有 ramp + 沿坡向延伸不齐
		if _has_ramp(ramp, tp_w, tp_h, ix, iy + side):
			var ok_y: bool = (
				_has_ramp(ramp, tp_w, tp_h, ix + dir_x, iy + side + dir_y)
				and _has_ramp(ramp, tp_w, tp_h, ix + 2 * dir_x, iy + side + 2 * dir_y)
			)
			if not ok_y:
				return false
		# X 方向侧翼：(ix+side, iy) 有 ramp + 沿坡向延伸不齐
		if _has_ramp(ramp, tp_w, tp_h, ix + side, iy):
			var ok_x: bool = (
				_has_ramp(ramp, tp_w, tp_h, ix + side + dir_x, iy + dir_y)
				and _has_ramp(ramp, tp_w, tp_h, ix + side + 2 * dir_x, iy + 2 * dir_y)
			)
			if not ok_x:
				return false

	## 侧翼禁贴：侧邻有 ramp 时须是「平行加宽」或「L/半侧转角」，禁止畸形对贴
	if not _check_side_clearance(ix, iy, dir_x, dir_y, ramp, tp_w, tp_h):
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
