class_name PathArc
extends RefCounted

## 路点转角弧线插值（不切直角；高速单位必要）。
## WC3 复刻：低切角（农民）仍可切；>30° 转弯画弧线（骑士 / 英雄 / 高速）。
##
## 纯函数 / 静态；不碰场景树。
## 几何：圆心法 + 切向反推。
## 给定 start / outgoing / incoming / chord_length = |start - end|，找圆心 C 使 S, E 都在圆上且切向正确，
## 沿圆周采样 n_samples 点。
## R = chord_length / (2 sin(θ/2))。
## C = start - R × (cos(φ_s), sin(φ_s))；其中 φ_s 是 S 切向 (outgoing) 对应的"起点角"。

## < 此角度不画弧（仍走直线切角）。约 30°。
const MIN_ARC_ANGLE := 0.5


## 两段方向夹角（弧度，有向；逆时针为正）。
static func turn_angle(incoming: Vector2, outgoing: Vector2) -> float:
	if incoming.length_squared() < 0.01 or outgoing.length_squared() < 0.01:
		return 0.0
	var a := incoming.normalized()
	var b := outgoing.normalized()
	var cross := a.x * b.y - a.y * b.x
	var dot := a.x * b.x + a.y * b.y
	return atan2(cross, dot)


## 弧线长度 = speed / turn_rate。
static func arc_length(speed_wc3: float, turn_rate_rps: float) -> float:
	if turn_rate_rps <= 0.0:
		return 0.0
	return speed_wc3 / turn_rate_rps


## 弧线半径。
static func arc_radius(chord_length: float, theta_rad: float) -> float:
	if chord_length <= 0.0:
		return 0.0
	var h := absf(theta_rad) * 0.5
	if h < 0.001:
		return INF
	return (chord_length * 0.5) / sin(h)


## 弧线采样（沿圆心法）。
## 输入：
##   start        — 弧线起点
##   outgoing     — 起点切向
##   incoming     — 终点切向
##   chord_length — 起点到终点的直线距离（= |start - end|）
##   n_samples    — 采样数
## 返回：PackedVector2Array（n_samples+1 个点，含首尾）
static func arc_samples(
	start: Vector2,
	outgoing: Vector2,
	incoming: Vector2,
	chord_length: float,
	n_samples: int = 8
) -> PackedVector2Array:
	var out := PackedVector2Array()
	if chord_length <= 0.0 or n_samples <= 0 or outgoing.length_squared() < 0.01:
		out.append(start)
		return out
	var a := outgoing.normalized()
	var b := incoming.normalized()
	var cross := a.x * b.y - a.y * b.x
	var dot := a.x * b.x + a.y * b.y
	var theta := atan2(cross, dot)
	if absf(theta) < 0.001:
		# 0° 转弯走直线
		out.append(start)
		out.append(start + b * chord_length)
		return out
	# 半径 R = chord / (2 sin(θ/2))
	var R: float = arc_radius(chord_length, theta)
	# 圆心求解：S = (0, 0)（局部坐标），outgoing = a，incoming = b，|S - E| = chord_length
	# 解几何：旋转 outgoing 至 incoming 转 θ 角
	# C = S - R × (-a.y, a.x) = S + R × (a.y, -a.x)（圆心在 outgoing 屏顺时针 90° 方向）
	# 验证：起点角 φ_s 使 P(φ_s) = S + R × (sin θ_s, -cos θ_s)
	# 简化：直接用导数反推
	# P(t) = C + R × (cos t, sin t)
	# P'(t) = R × (-sin t, cos t)
	# S 处 outgoing = P'(t_s) / R = (-sin t_s, cos t_s) = a
	#  → sin t_s = -a.x; cos t_s = a.y
	var t_s: float = atan2(-a.x, a.y)
	# 圆心 C = S - R × (cos t_s, sin t_s) = -R × (cos t_s, sin t_s)
	var center: Vector2 = start - R * Vector2(cos(t_s), sin(t_s))
	# 终点角：转 θ 角
	var t_e: float = t_s + theta
	var out2 := PackedVector2Array()
	out2.append(start)
	for i in range(1, n_samples + 1):
		var t_i: float = t_s + theta * float(i) / float(n_samples)
		var pos: Vector2 = center + R * Vector2(cos(t_i), sin(t_i))
		out2.append(pos)
	return out2
