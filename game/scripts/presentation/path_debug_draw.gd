class_name PathDebugDraw
extends Node3D
## 选中单位路径调试线（Present）：WC3 路点 → 贴地折线。
## F9 / GameDirector.show_path_debug 开关。

const LINE_Y_BIAS := 0.12
const PATH_COLOR := Color(0.2, 0.95, 1.0, 0.9)
const WAYPOINT_COLOR := Color(1.0, 0.85, 0.2, 0.95)

var _heightfield: Wc3Heightfield = null
var _line_mi: MeshInstance3D = null
var _dot_mi: MeshInstance3D = null
var _enabled: bool = true


func setup(heightfield: Wc3Heightfield) -> void:
	_heightfield = heightfield
	if _line_mi == null:
		_line_mi = MeshInstance3D.new()
		_line_mi.name = "PathLines"
		_line_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_line_mi)
	if _dot_mi == null:
		_dot_mi = MeshInstance3D.new()
		_dot_mi.name = "PathDots"
		_dot_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_dot_mi)


func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on
	if not on:
		_clear_meshes()


func is_enabled() -> bool:
	return _enabled


## paths: Array，每项 { "points": Array[Vector2] }（WC3 XY）
func redraw(paths: Array) -> void:
	if not _enabled:
		_clear_meshes()
		return
	var line_mesh := ImmediateMesh.new()
	var dot_mesh := ImmediateMesh.new()
	var line_mat := _make_mat(PATH_COLOR)
	var dot_mat := _make_mat(WAYPOINT_COLOR)
	var any_line := false
	var any_dot := false
	for item in paths:
		if not (item is Dictionary):
			continue
		var pts: Array = item.get("points", [])
		if pts.size() < 1:
			continue
		var godot_pts: Array[Vector3] = []
		for p in pts:
			if p is Vector2:
				godot_pts.append(_to_godot(p))
		if godot_pts.size() >= 2:
			line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, line_mat)
			for g in godot_pts:
				line_mesh.surface_add_vertex(g)
			line_mesh.surface_end()
			any_line = true
		# 路点小十字
		for g in godot_pts:
			var s := 0.18
			dot_mesh.surface_begin(Mesh.PRIMITIVE_LINES, dot_mat)
			dot_mesh.surface_add_vertex(g + Vector3(-s, 0, 0))
			dot_mesh.surface_add_vertex(g + Vector3(s, 0, 0))
			dot_mesh.surface_add_vertex(g + Vector3(0, 0, -s))
			dot_mesh.surface_add_vertex(g + Vector3(0, 0, s))
			dot_mesh.surface_end()
			any_dot = true
	if _line_mi:
		_line_mi.mesh = line_mesh if any_line else null
	if _dot_mi:
		_dot_mi.mesh = dot_mesh if any_dot else null


func _to_godot(wc3: Vector2) -> Vector3:
	var z := 0.0
	if _heightfield != null and _heightfield.is_valid():
		z = _heightfield.interpolated_height(wc3.x, wc3.y)
	var g := Wc3Coords.wc3_xy_to_godot(wc3.x, wc3.y, z)
	g.y += LINE_Y_BIAS
	return g


func _make_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 40
	return m


func _clear_meshes() -> void:
	if _line_mi:
		_line_mi.mesh = null
	if _dot_mi:
		_dot_mi.mesh = null
