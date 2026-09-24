class_name HudLayout
extends RefCounted

## 按视口计算 HUD 底栏尺寸（U1 响应式）。
## 参考 docs/design/game/HUD_LAYOUT_REDESIGN.md：完整 / 紧凑 / 窄窗三档。

enum Tier { FULL = 0, COMPACT = 1, TIGHT = 2 }

## 设计参考分辨率与底栏高度（逻辑像素）。
const REF_W := 1920.0
const REF_H := 1080.0
const REF_BOTTOM_H := 224.0

## 宽度分档（视口宽）。
const WIDTH_FULL := 1440.0
const WIDTH_COMPACT := 1100.0

## 底栏高度占比上限，避免小窗吞掉大半世界。
const MAX_BOTTOM_RATIO := 0.26
const MIN_BOTTOM_H := 132.0
const MAX_BOTTOM_H := 240.0

## 命令格最小可点尺寸。
const MIN_CMD_BTN := 40.0


class Metrics extends RefCounted:
	var tier: int = Tier.FULL
	var scale: float = 1.0
	var margin: float = 8.0
	var gap: float = 12.0
	var bottom_h: float = 200.0
	var minimap_side: float = 176.0
	var selection_w: float = 480.0
	var command_w: float = 240.0
	var command_btn: float = 52.0
	var inventory_w: float = 144.0
	var inventory_h: float = 260.0
	var activity_w: float = 212.0
	var resource_w: float = 308.0
	var resource_h: float = 36.0


static func compute(viewport_size: Vector2, prefer_height_ratio: float = 0.2) -> Metrics:
	var m := Metrics.new()
	var vw := maxf(viewport_size.x, 1.0)
	var vh := maxf(viewport_size.y, 1.0)

	# 高度以参考 1080 为基准缩放，并夹在占比/绝对上下限内。
	var scale_h := clampf(vh / REF_H, 0.62, 1.05)
	var scale_w := clampf(vw / REF_W, 0.62, 1.05)
	m.scale = minf(scale_h, scale_w)

	if vw >= WIDTH_FULL:
		m.tier = Tier.FULL
	elif vw >= WIDTH_COMPACT:
		m.tier = Tier.COMPACT
	else:
		m.tier = Tier.TIGHT

	m.margin = 8.0 if m.tier != Tier.TIGHT else 6.0
	m.gap = 12.0 if m.tier == Tier.FULL else (10.0 if m.tier == Tier.COMPACT else 8.0)

	var max_h := minf(MAX_BOTTOM_H, vh * MAX_BOTTOM_RATIO)
	var min_h := minf(MIN_BOTTOM_H, max_h)
	var preferred := clampf(prefer_height_ratio, 0.12, MAX_BOTTOM_RATIO) * vh
	var scaled_ref := REF_BOTTOM_H * scale_h
	m.bottom_h = clampf(minf(preferred, scaled_ref), min_h, max_h)

	match m.tier:
		Tier.FULL:
			m.minimap_side = clampf(176.0 * m.scale, 144.0, 224.0)
			m.selection_w = clampf(480.0 * m.scale, 360.0, 520.0)
			m.command_w = clampf(240.0 * m.scale, 220.0, 260.0)
			m.command_btn = clampf(52.0 * m.scale, 44.0, 56.0)
			m.inventory_w = 144.0
			m.inventory_h = 260.0
			m.activity_w = 212.0
			m.resource_w = 308.0
			m.resource_h = 36.0
		Tier.COMPACT:
			m.minimap_side = clampf(160.0 * m.scale, 128.0, 192.0)
			m.selection_w = clampf(300.0 * m.scale, 260.0, 360.0)
			m.command_w = clampf(224.0 * m.scale, 200.0, 240.0)
			m.command_btn = clampf(48.0 * m.scale, MIN_CMD_BTN, 52.0)
			m.inventory_w = 128.0
			m.inventory_h = 220.0
			m.activity_w = 180.0
			m.resource_w = 280.0
			m.resource_h = 32.0
		_:
			m.minimap_side = clampf(136.0 * m.scale, 112.0, 160.0)
			m.selection_w = clampf(260.0 * m.scale, 200.0, 300.0)
			m.command_w = clampf(200.0 * m.scale, 176.0, 220.0)
			m.command_btn = clampf(44.0 * m.scale, MIN_CMD_BTN, 48.0)
			m.inventory_w = 112.0
			m.inventory_h = 190.0
			m.activity_w = 160.0
			m.resource_w = 240.0
			m.resource_h = 30.0

	# 底栏高度与小地图/命令区对齐：取较大者，但仍受 max_h 约束。
	var content_need := maxf(m.minimap_side, m.command_w * 0.85) + m.margin * 2.0
	m.bottom_h = clampf(maxf(m.bottom_h, content_need), min_h, max_h)
	# 小地图不超过底栏可用高度（减外边距）。
	m.minimap_side = minf(m.minimap_side, maxf(m.bottom_h - m.margin * 2.0, 96.0))

	_fit_horizontal(m, vw)
	return m


static func _fit_horizontal(m: Metrics, vw: float) -> void:
	## 左小地图 + 中详情 + 右命令，不允许普通面板横向重叠。
	var budget := vw - m.margin * 2.0 - m.gap * 2.0
	var need := m.minimap_side + m.selection_w + m.command_w
	if need <= budget:
		return
	var overflow := need - budget
	# 先砍详情，再砍小地图，最后砍命令宽（保持按钮下限）。
	var cut_sel := minf(overflow, maxf(m.selection_w - 200.0, 0.0))
	m.selection_w -= cut_sel
	overflow -= cut_sel
	if overflow <= 0.0:
		return
	var cut_mm := minf(overflow, maxf(m.minimap_side - 112.0, 0.0))
	m.minimap_side -= cut_mm
	overflow -= cut_mm
	if overflow <= 0.0:
		return
	var min_cmd_w := MIN_CMD_BTN * 4.0 + 24.0
	var cut_cmd := minf(overflow, maxf(m.command_w - min_cmd_w, 0.0))
	m.command_w -= cut_cmd
	# 命令格随面板宽微调
	m.command_btn = clampf((m.command_w - 28.0) / 4.0 - 6.0, MIN_CMD_BTN, 56.0)
