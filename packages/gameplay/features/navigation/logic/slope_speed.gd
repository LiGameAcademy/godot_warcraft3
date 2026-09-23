class_name SlopeSpeed
extends RefCounted

## 斜坡速度衰减：上坡减速 / 下坡限速（防滑）；WC3 实际行为。
## 纯函数：输入 self_pos / prev_pos / base_speed；返衰减后速度。
##
## 屏 y-down 坐标：
## - self.y < prev.y → 上坡（屏上）→ 减速（UPHILL_FACTOR）
## - self.y > prev.y → 下坡（屏下）→ 减速（DOWNHILL_FACTOR）
## - 角度 |slope_deg| > MAX_SLOPE_DEG → 钳到 MAX_SLOPE_DEG 计算（更陡等同）

## 上坡速度因子（屏 y 向上；0-1 范围）
const UPHILL_FACTOR := 0.6
## 下坡速度因子（防滑；0-1 范围）
const DOWNHILL_FACTOR := 0.85
## 生效坡度上限（超过此值等同此值）
const MAX_SLOPE_DEG := 30.0


## 衰减后速度。
## 入口：self_pos / prev_pos（WC3 XY；屏 y-down）；base_speed；max_deg（可选，默认 30°）。
static func apply(
	self_pos: Vector2,
	prev_pos: Vector2,
	base_speed: float,
	max_deg: float = MAX_SLOPE_DEG
) -> float:
	if base_speed <= 0.0:
		return 0.0
	if max_deg <= 0.0:
		max_deg = MAX_SLOPE_DEG
	var dx: float = self_pos.x - prev_pos.x
	var dy: float = self_pos.y - prev_pos.y
	var horiz: float = absf(dx)
	if horiz < 0.5 and absf(dy) < 0.5:
		return base_speed  # 静止或水平
	# 屏 y-down：上坡 = dy < 0；下坡 = dy > 0
	var slope_rad: float = atan2(absf(dy), maxf(horiz, 0.5))
	var slope_deg: float = rad_to_deg(slope_rad)
	if slope_deg > max_deg:
		slope_deg = max_deg
	# 线性插值：0° → 1.0；max_deg → up_factor（screen y-up = 上坡）
	# 屏幕坐标 dy < 0 → 上坡（屏向上）→ UPHILL_FACTOR
	# 屏幕坐标 dy > 0 → 下坡（屏向下）→ DOWNHILL_FACTOR
	var factor: float = 1.0
	if dy < 0.0:
		# 上坡
		factor = lerpf(1.0, UPHILL_FACTOR, slope_deg / max_deg)
	else:
		# 下坡（包含水平 dy=0）
		factor = lerpf(1.0, DOWNHILL_FACTOR, slope_deg / max_deg)
	return base_speed * factor


## 仅供测试：算当前坡度（度）。dy < 0 = 上坡（屏向上）。
static func slope_deg_of(self_pos: Vector2, prev_pos: Vector2) -> float:
	var dx: float = self_pos.x - prev_pos.x
	var dy: float = self_pos.y - prev_pos.y
	var horiz: float = absf(dx)
	if horiz < 0.5 and absf(dy) < 0.5:
		return 0.0
	var slope_rad: float = atan2(absf(dy), maxf(horiz, 0.5))
	return rad_to_deg(slope_rad)
