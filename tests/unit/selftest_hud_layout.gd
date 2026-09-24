extends Node

## HudLayout 响应式分档与防重叠。

func _ready() -> void:
	var failed := 0
	failed += _check_full()
	failed += _check_compact()
	failed += _check_tight()
	failed += _check_short_window()
	failed += _check_no_overlap()
	if failed == 0:
		print("selftest_hud_layout: PASS")
		get_tree().quit(0)
	else:
		push_error("selftest_hud_layout: FAIL (%d)" % failed)
		get_tree().quit(1)


func _check(cond: bool, msg: String) -> int:
	if cond:
		return 0
	push_error("FAIL: %s" % msg)
	return 1


func _check_full() -> int:
	var m := HudLayout.compute(Vector2(1920, 1080), 0.2)
	var n := 0
	n += _check(m.tier == HudLayout.Tier.FULL, "1920 tier FULL")
	n += _check(m.bottom_h <= 1080.0 * HudLayout.MAX_BOTTOM_RATIO + 0.1, "1080 bottom ratio capped")
	n += _check(m.minimap_side >= 144.0, "full minimap usable")
	n += _check(m.command_btn >= 44.0, "full command btn >= 44")
	return n


func _check_compact() -> int:
	var m := HudLayout.compute(Vector2(1280, 720), 0.2)
	var n := 0
	n += _check(m.tier == HudLayout.Tier.COMPACT, "1280 tier COMPACT")
	n += _check(m.bottom_h <= 720.0 * HudLayout.MAX_BOTTOM_RATIO + 0.1, "720 bottom ratio capped")
	n += _check(m.selection_w <= 360.0, "compact selection shrunk")
	return n


func _check_tight() -> int:
	var m := HudLayout.compute(Vector2(1024, 600), 0.2)
	var n := 0
	n += _check(m.tier == HudLayout.Tier.TIGHT, "1024 tier TIGHT")
	n += _check(m.bottom_h <= 600.0 * HudLayout.MAX_BOTTOM_RATIO + 0.1, "600 bottom ratio capped")
	n += _check(m.command_btn >= HudLayout.MIN_CMD_BTN - 0.01, "tight cmd btn floor")
	return n


func _check_short_window() -> int:
	## 矮窗：底栏不得按偏好占比无限放大，也不能超过硬顶。
	var m := HudLayout.compute(Vector2(1280, 500), 0.35)
	var max_allowed := 500.0 * HudLayout.MAX_BOTTOM_RATIO
	var n := 0
	n += _check(m.bottom_h <= max_allowed + 0.1, "short window ratio hard cap")
	n += _check(m.bottom_h >= minf(HudLayout.MIN_BOTTOM_H, max_allowed) - 0.1, "short window still usable height")
	n += _check(m.minimap_side >= 96.0, "short window minimap readable")
	return n


func _check_no_overlap() -> int:
	var sizes: Array[Vector2] = [
		Vector2(1920, 1080),
		Vector2(1366, 768),
		Vector2(1280, 720),
		Vector2(1024, 600),
		Vector2(900, 500),
	]
	var n := 0
	for sz in sizes:
		var m := HudLayout.compute(sz, 0.2)
		var need := m.minimap_side + m.selection_w + m.command_w + m.margin * 2.0 + m.gap * 2.0
		n += _check(need <= sz.x + 0.5, "no overlap @ %dx%d (need=%.0f)" % [int(sz.x), int(sz.y), need])
		n += _check(m.minimap_side <= m.bottom_h - m.margin + 0.5, "minimap fits bottom @ %d" % int(sz.x))
	return n
