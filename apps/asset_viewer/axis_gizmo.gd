extends Control
## Read-only camera orientation widget. Directions use Godot world axes.
signal view_selected(direction: Vector3)
var camera_basis: Basis = Basis.IDENTITY
var _points: Array[Vector2] = []
var _directions: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
var _labels: Array[String] = ["+X", "−X", "+Y", "−Y", "+Z", "−Z"]

func _draw() -> void:
	var center: Vector2 = size * 0.5
	draw_circle(center, 62.0, Color(0.08, 0.09, 0.12, 0.9))
	_points.clear()
	for index: int in range(6):
		var axis: Vector3 = camera_basis.inverse() * _directions[index]
		var point: Vector2 = center + Vector2(axis.x, -axis.y) * 43.0
		_points.append(point)
		var color: Color = [Color(1, 0.35, 0.35), Color(0.4, 1, 0.5), Color(0.4, 0.65, 1)][index / 2]
		draw_line(center, point, color, 2.0)
		draw_circle(point, 13.0, Color(0.15, 0.17, 0.2))
		draw_string(ThemeDB.fallback_font, point + Vector2(-10, 5), _labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var chosen: int = -1
		var nearest: float = 18.0
		for index: int in range(_points.size()):
			var distance: float = event.position.distance_to(_points[index])
			if distance < nearest:
				nearest = distance
				chosen = index
		if chosen >= 0:
			view_selected.emit(_directions[chosen])
		accept_event()
