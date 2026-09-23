class_name CooldownButtonOverlay
extends Control

## 命令格冷却扇形遮罩（Present）。
## 用 `_draw` 画饼图，不依赖 ColorRect+shader（透明 ColorRect 常被引擎跳过绘制 →「看不见 CD」）。
## progress = 剩余比例（1=刚进 CD 全暗，0=可放）；自 12 点顺时针扫过。

const OVERLAY_COLOR := Color(0.04, 0.05, 0.08, 0.78)
const EDGE_COLOR := Color(0.15, 0.16, 0.2, 0.35)
const SEGMENTS := 48

var _ratio: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_cooldown_ratio(ratio: float) -> void:
	var r := clampf(ratio, 0.0, 1.0)
	if is_equal_approx(r, _ratio):
		visible = _ratio > 0.001
		return
	_ratio = r
	visible = _ratio > 0.001
	queue_redraw()


func _draw() -> void:
	if _ratio <= 0.001:
		return
	var sz := size
	if sz.x < 2.0 or sz.y < 2.0:
		return
	var center := sz * 0.5
	# 覆盖整格（略大于半对角线，避免四角露光）
	var radius := maxf(sz.x, sz.y) * 0.72
	var points := PackedVector2Array()
	points.append(center)
	# Control 坐标 Y 向下：-PI/2 为正上；角增大为顺时针
	var start := -PI * 0.5
	var sweep := _ratio * TAU
	var steps := maxi(ceili(float(SEGMENTS) * _ratio), 3)
	for i in range(steps + 1):
		var a := start + sweep * (float(i) / float(steps))
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(points, OVERLAY_COLOR)
	# 外圈淡边，让扇形在图标上更可读
	draw_arc(center, minf(sz.x, sz.y) * 0.48, start, start + sweep, steps, EDGE_COLOR, 1.5, true)
