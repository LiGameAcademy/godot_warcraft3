class_name MovementRouteView
extends MeshInstance3D

var _lines: ImmediateMesh = ImmediateMesh.new()


func _ready() -> void:
	mesh = _lines
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func clear_routes() -> void:
	_lines.clear_surfaces()


func show_routes(routes: Array[Dictionary]) -> void:
	clear_routes()
	if not visible or routes.is_empty():
		return
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for route: Dictionary in routes:
		var points: PackedVector3Array = route.points
		var color: Color = Color.ORANGE if bool(route.temporary) else Color.CYAN
		for index: int in range(1, points.size()):
			_segment(_point(points[index - 1]), _point(points[index]), color)
		if not points.is_empty():
			_cross(_point(points[-1]), Color.YELLOW, 0.18)
		if route.has("preferred_goal"):
			_cross(_point(route.preferred_goal as Vector3), Color.GREEN, 0.28)
	_lines.surface_end()


func _point(wc3: Vector3) -> Vector3:
	return Wc3Coords.wc3_to_godot(wc3) + Vector3.UP * 0.1


func _cross(point: Vector3, color: Color, size: float) -> void:
	_segment(point - Vector3.RIGHT * size, point + Vector3.RIGHT * size, color)
	_segment(point - Vector3.FORWARD * size, point + Vector3.FORWARD * size, color)


func _segment(from: Vector3, to: Vector3, color: Color) -> void:
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(from)
	_lines.surface_add_vertex(to)
