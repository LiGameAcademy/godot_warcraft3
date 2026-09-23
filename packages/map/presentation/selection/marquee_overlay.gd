class_name MarqueeOverlay
extends Control

## 框选绿矩形绘制层（挂在 CanvasLayer 下，mouse_filter=IGNORE）。

const FILL := Color(0.15, 1.0, 0.25, 0.12)
const BORDER := Color(0.2, 1.0, 0.35, 0.95)
const BORDER_W := 1.5

var _marquee: MarqueeSelection = null
var _rect: Rect2 = Rect2()
var _drawing: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 80


func bind(marquee: MarqueeSelection) -> void:
	if _marquee != null and _marquee.changed.is_connected(_on_changed):
		_marquee.changed.disconnect(_on_changed)
	_marquee = marquee
	if _marquee != null:
		_marquee.changed.connect(_on_changed)


func _on_changed(rect: Rect2, active: bool) -> void:
	_rect = rect
	# 拖超过 1px 即显示，避免阈值过大「拖了没框」
	_drawing = active and (rect.size.x >= 1.0 or rect.size.y >= 1.0)
	visible = _drawing
	queue_redraw()


func _draw() -> void:
	if not _drawing:
		return
	draw_rect(_rect, FILL, true)
	draw_rect(_rect, BORDER, false, BORDER_W)
