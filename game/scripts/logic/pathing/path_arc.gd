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
	var out2 := PackedVector2Array()
	out2.append(start)
	for i in range(1, n_samples + 1):
		var t_i: float = t_s + theta * float(i) / float(n_samples)
		var pos: Vector2 = center + R * Vector2(cos(t_i), sin(t_i))
		out2.append(pos)
	return out2


## 完整路径弧线平滑（F-PATH-8 集成层）。
## 给定离散 waypoints（A* 输出 / 走廊固定路径），对每个连续 waypoint pair
## (wp[i-1], wp[i], wp[i+1]) 算转角，> MIN_ARC_ANGLE 时沿弧线插值 n_samples 个中间点。
##
## 拼接：每段弧线返 n_samples+1 个点（首 wp[i-1] / 尾 wp[i]）。拼接时去重共享端点：
## - 第 1 段加 samples[1..n_samples]（含 wp[1]）
## - 中间段加 samples[1..n_samples-1]（不含端点，prev/cur 在相邻段共享）
## - 最后一段直接加 wp[n-1]
##
## 输入：PackedVector2Array / Array[Vector2] / Array（每个元素 Vector2；size >= 2）
## 输出：Array[Vector2]（>= 2 个点；含原 waypoints + 弧线中间点）
##
## WC3 复刻：低切角（农民）走直线；>30° 转弯画弧线（骑士 / 英雄 / 高速）。
static func smooth_path(waypoints, n_samples: int = 8) -> Array:
	var out: Array = []
	var n: int = waypoints.size() if waypoints != null else 0
	if n < 2:
		for w in waypoints:
			if w is Vector2:
				out.append(w)
		return out
	# 转 Vector2 列表（容错）
	var pts: Array[Vector2] = []
	for w in waypoints:
		if w is Vector2:
			pts.append(w)
	n = pts.size()
	if n < 2:
		return pts
	# 第 1 段：samples[0] = wp[0]，samples[1..n_samples] = wp[0]→wp[1] 弧线（含 wp[1]）
	out.append(pts[0])  # 起点（画弧 / 不画弧都要保留）
	var incoming0: Vector2 = pts[1] - pts[0]
	var outgoing0: Vector2 = incoming0  # 默认同方向（n = 2 时无 next）
	if n >= 3:
		outgoing0 = pts[2] - pts[1]
	var theta0: float = turn_angle(incoming0, outgoing0)
	if absf(theta0) >= MIN_ARC_ANGLE:
		var samples0: PackedVector2Array = arc_samples(
			pts[0], incoming0, outgoing0, incoming0.length(), n_samples
		)
		# samples0[0] = pts[0]（已加），samples0[1..n_samples] = 中间点 + pts[1]
		for j in range(1, samples0.size()):
			out.append(samples0[j])
	else:
		out.append(pts[1])
	# 中间段：i = 2..n-2（如果有）
	for i in range(2, n - 1):
		var prev: Vector2 = pts[i - 1]
		var cur: Vector2 = pts[i]
		var nxt: Vector2 = pts[i + 1]
		var incoming: Vector2 = cur - prev
		var outgoing: Vector2 = nxt - cur
		var theta: float = turn_angle(incoming, outgoing)
		if absf(theta) >= MIN_ARC_ANGLE:
			var samples: PackedVector2Array = arc_samples(
				prev, incoming, outgoing, incoming.length(), n_samples
			)
			# samples[0] = prev，samples[1..n_samples-1] = 中间点，samples[n_samples] = cur
			for j in range(1, samples.size() - 1):
				out.append(samples[j])
			out.append(cur)
		else:
			out.append(cur)
	# 最后一段：直接加 wp[n-1]
	if n >= 2:
		out.append(pts[n - 1])
	return out
