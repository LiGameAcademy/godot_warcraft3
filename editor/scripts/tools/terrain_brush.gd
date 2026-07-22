extends Node3D
## 地表笔刷：吸附中级栅格顶点（tilepoint）；悬停绿框以该顶点为中心、边长=1 格（对齐经典 WE）。


signal tile_hovered(tile: Vector2i) ## 实为顶点坐标 (ix, iy)
signal painted
signal rebuild_requested

const REBUILD_INTERVAL_MS := 80
## 略抬高，避免与地面 z-fight（Godot 单位）
const HOVER_LIFT := 0.015
const HOVER_COLOR := Color(0.18, 0.92, 0.28, 0.42)
const HOVER_EDGE := Color(0.35, 1.0, 0.45, 0.85)
const INVALID_VERT := Vector2i(-99999, -99999)

var document ## MapDocument（preload 实例）
var camera: Camera3D
var space: World3D

var _painting: bool = false
var _last_vert: Vector2i = INVALID_VERT
var _hover_vert: Vector2i = INVALID_VERT
var _dirty_paint: bool = false
var _last_rebuild_ms: int = 0
var enabled: bool = true
## 笔刷半径档：1=单点，5=半径 4；形状 0 圆 / 1 方
var brush_size: int = 1
var brush_shape: int = 0 ## 0 circle, 1 square
var apply_texture: bool = true

var _hover_mesh: MeshInstance3D
var _hover_mat: StandardMaterial3D
var _edge_mesh: MeshInstance3D
var _edge_mat: StandardMaterial3D


func set_brush_settings(size: int, shape: int) -> void:
	brush_size = clampi(size, 1, 5)
	brush_shape = 0 if shape == 0 else 1
	if _hover_vert != INVALID_VERT:
		_update_hover_preview(_hover_vert)


func _ready() -> void:
	_ensure_hover_visuals()


func setup(doc, cam: Camera3D, world: World3D) -> void:
	document = doc
	camera = cam
	space = world
	_ensure_hover_visuals()
	_hide_hover_preview()


func _ensure_hover_visuals() -> void:
	if _hover_mesh != null:
		return
	_hover_mat = StandardMaterial3D.new()
	_hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hover_mat.albedo_color = HOVER_COLOR
	_hover_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_hover_mat.render_priority = 10

	_hover_mesh = MeshInstance3D.new()
	_hover_mesh.name = "HoverFill"
	_hover_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover_mesh.material_override = _hover_mat
	add_child(_hover_mesh)

	_edge_mat = StandardMaterial3D.new()
	_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_edge_mat.albedo_color = HOVER_EDGE
	_edge_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_edge_mat.render_priority = 11

	_edge_mesh = MeshInstance3D.new()
	_edge_mesh.name = "HoverEdge"
	_edge_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_edge_mesh.material_override = _edge_mat
	add_child(_edge_mesh)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or document == null or camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed
			if mb.pressed:
				_paint_at_mouse(mb.position)
				get_viewport().set_input_as_handled()
			elif _dirty_paint:
				_request_rebuild(true)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var vert: Vector2i = _pick_vertex(mm.position)
		_set_hover_vert(vert)
		if _painting:
			_paint_at_mouse(mm.position)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _dirty_paint and not _painting:
		_request_rebuild(false)
	elif _dirty_paint and _painting:
		var now: int = Time.get_ticks_msec()
		if now - _last_rebuild_ms >= REBUILD_INTERVAL_MS:
			_request_rebuild(false)


func _set_hover_vert(vert: Vector2i) -> void:
	if vert == _hover_vert:
		return
	_hover_vert = vert
	if vert == INVALID_VERT:
		_hide_hover_preview()
		return
	tile_hovered.emit(vert)
	_update_hover_preview(vert)


func _paint_at_mouse(screen_pos: Vector2) -> void:
	var vert: Vector2i = _pick_vertex(screen_pos)
	_set_hover_vert(vert)
	if vert == INVALID_VERT:
		return
	if vert == _last_vert and _painting:
		return
	_last_vert = vert
	if not apply_texture:
		return
	var painted_any := false
	for p in _brush_offsets():
		var ix: int = vert.x + p.x
		var iy: int = vert.y + p.y
		if bool(document.paint_corner(ix, iy)):
			painted_any = true
	if painted_any:
		_dirty_paint = true
		painted.emit()


func _request_rebuild(force: bool) -> void:
	if not _dirty_paint and not force:
		return
	_dirty_paint = false
	_last_rebuild_ms = Time.get_ticks_msec()
	rebuild_requested.emit()
	if _hover_vert != INVALID_VERT:
		_update_hover_preview(_hover_vert)


func _pick_vertex(screen_pos: Vector2) -> Vector2i:
	if document == null or bool(document.is_empty()) or camera == null:
		return INVALID_VERT
	var hit: Vector3 = _raycast_ground(screen_pos)
	if hit == Vector3.INF:
		hit = _ray_plane_fallback(screen_pos)
	if hit == Vector3.INF:
		return INVALID_VERT
	var vert: Vector2i = document.world_godot_to_tilepoint(hit) as Vector2i
	var tp: Vector2i = document.tilepoint_size()
	if vert.x < 0 or vert.y < 0 or vert.x >= tp.x or vert.y >= tp.y:
		return INVALID_VERT
	return vert


func _hide_hover_preview() -> void:
	if _hover_mesh:
		_hover_mesh.visible = false
		_hover_mesh.mesh = null
	if _edge_mesh:
		_edge_mesh.visible = false
		_edge_mesh.mesh = null


func _update_hover_preview(vert: Vector2i) -> void:
	_ensure_hover_visuals()
	if document == null or bool(document.is_empty()):
		_hide_hover_preview()
		return
	# 以顶点为中心、边长=1 中级格：四角在半格偏移处（栅格线穿过绿框中心）
	var corners: Array = _vertex_centered_quad_godot(vert.x, vert.y)
	if corners.is_empty():
		_hide_hover_preview()
		return
	var bl: Vector3 = corners[0]
	var br: Vector3 = corners[1]
	var tl: Vector3 = corners[2]
	var tr: Vector3 = corners[3]
	var lift := Vector3(0.0, HOVER_LIFT, 0.0)
	bl += lift
	br += lift
	tl += lift
	tr += lift

	_hover_mesh.mesh = _make_fill_mesh(bl, br, tl, tr)
	_hover_mesh.visible = true
	_edge_mesh.mesh = _make_edge_mesh(bl, br, tl, tr)
	_edge_mesh.visible = true


## 顶点 (ix,iy) 为中心的笔刷预选框四角 [bl, br, tl, tr]（覆盖整个笔刷外接方框）。
func _vertex_centered_quad_godot(ix: int, iy: int) -> Array:
	var center: Vector2 = document.center_offset()
	var ts: float = document.tile_size()
	var radius: float = float(maxi(brush_size - 1, 0)) + 0.5
	var out: Array = []
	for c in [
		Vector2(float(ix) - radius, float(iy) - radius),
		Vector2(float(ix) + radius, float(iy) - radius),
		Vector2(float(ix) - radius, float(iy) + radius),
		Vector2(float(ix) + radius, float(iy) + radius),
	]:
		var h: float = float(document.sample_height_at_xy(c.x, c.y))
		var xy := Vector2(center.x + c.x * ts, center.y + c.y * ts)
		out.append(Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, h))
	return out


## 笔刷覆盖的相对偏移（tilepoint）。size=1 → 仅 (0,0)。
func _brush_offsets() -> Array:
	var out: Array = []
	var r: int = maxi(brush_size - 1, 0)
	var r2: int = r * r
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if brush_shape == 0 and (dx * dx + dy * dy) > r2:
				continue
			out.append(Vector2i(dx, dy))
	if out.is_empty():
		out.append(Vector2i.ZERO)
	return out


func _make_fill_mesh(bl: Vector3, br: Vector3, tl: Vector3, tr: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_tri(st, bl, br, tr)
	_add_tri(st, bl, tr, tl)
	return st.commit()


func _make_edge_mesh(bl: Vector3, br: Vector3, tl: Vector3, tr: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	_add_line(st, bl, br)
	_add_line(st, br, tr)
	_add_line(st, tr, tl)
	_add_line(st, tl, bl)
	return st.commit()


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _add_line(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	if space == null:
		return Vector3.INF
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 5000.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result: Dictionary = space.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return Vector3.INF
	return result.position as Vector3


func _ray_plane_fallback(screen_pos: Vector2) -> Vector3:
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var h_guess: float = 0.0
	if not bool(document.is_empty()):
		h_guess = float(document.sample_height_at_tile(0, 0)) * Wc3Coords.WORLD_SCALE
	var t: float = (h_guess - from.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	var p: Vector3 = from + dir * t
	var vert: Vector2i = document.world_godot_to_tilepoint(p) as Vector2i
	var h2: float = float(document.sample_height_at_xy(float(vert.x), float(vert.y))) * Wc3Coords.WORLD_SCALE
	t = (h2 - from.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	return from + dir * t
