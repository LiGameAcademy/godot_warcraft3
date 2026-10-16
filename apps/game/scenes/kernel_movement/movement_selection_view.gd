extends Control

var _region: Rect2 = Rect2()
var _dragging: bool = false


func show_region(region: Rect2, dragging: bool) -> void:
	_region = region
	_dragging = dragging
	queue_redraw()


func _draw() -> void:
	if _dragging and _region.size.length_squared() > 36.0:
		draw_rect(_region, Color(0.3, 1.0, 0.5, 0.12))
		draw_rect(_region, Color(0.3, 1.0, 0.5), false, 1.0)
