extends CanvasLayer
class_name PerfOverlay
## 简易性能叠层（Present）：F3 开关。FPS / Process ms（含尖峰）/ Draw Calls。

const NODE_NAME := "PerfOverlay"
const LAYER := 128
## 尖峰窗口（秒）：每隔一段时间把 peak 重置为当前值，方便记「这一段」的毛刺。
const PEAK_WINDOW_SEC := 3.0

var _label: Label = null
var _enabled: bool = false
var _peak_process_ms: float = 0.0
var _peak_window_left: float = 0.0


static func ensure_on(parent: Node) -> PerfOverlay:
	if parent == null:
		return null
	var existing := parent.get_node_or_null(NODE_NAME) as PerfOverlay
	if existing != null:
		return existing
	var overlay := PerfOverlay.new()
	overlay.name = NODE_NAME
	parent.add_child.call_deferred(overlay)
	return overlay


func is_overlay_enabled() -> bool:
	return _enabled


func toggle() -> void:
	set_overlay_enabled(not _enabled)


func set_overlay_enabled(on: bool) -> void:
	_enabled = on
	visible = on
	set_process(on)
	if on:
		_peak_process_ms = 0.0
		_peak_window_left = PEAK_WINDOW_SEC
		_refresh(0.0)


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	set_process(false)


func _build_ui() -> void:
	var root := MarginContainer.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.offset_left = 10.0
	root.offset_top = 10.0
	root.offset_right = 280.0
	root.offset_bottom = 120.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.72)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	_label = Label.new()
	_label.name = "Stats"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.75, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.text = "FPS —\nProcess — ms\nDrawCalls —\n[F3]"
	panel.add_child(_label)


func _process(delta: float) -> void:
	_refresh(delta)


func _refresh(delta: float) -> void:
	if _label == null:
		return
	var fps := Engine.get_frames_per_second()
	var process_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var physics_ms := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	if process_ms > _peak_process_ms:
		_peak_process_ms = process_ms
	_peak_window_left -= delta
	if _peak_window_left <= 0.0:
		_peak_window_left = PEAK_WINDOW_SEC
		_peak_process_ms = process_ms

	var warn := process_ms >= 16.0 or _peak_process_ms >= 16.0
	_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.55, 0.4, 1.0) if warn else Color(0.85, 0.95, 0.75, 1.0)
	)
	_label.text = (
		"FPS %d\nProcess %.1f ms  peak %.1f\nPhysics %.1f ms\nDrawCalls %d\nNodes %d\n[F3] peak/%.0fs"
		% [fps, process_ms, _peak_process_ms, physics_ms, draws, nodes, PEAK_WINDOW_SEC]
	)
