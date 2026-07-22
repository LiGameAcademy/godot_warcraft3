extends Node
## 地表笔刷：左键拖拽，整格四角写 groundTextures；节流触发地形重建。


signal tile_hovered(tile: Vector2i)
signal painted
signal rebuild_requested

const REBUILD_INTERVAL_MS := 80

var document ## MapDocument（preload 实例）
var camera: Camera3D
var space: World3D

var _painting: bool = false
var _last_tile: Vector2i = Vector2i(-99999, -99999)
var _dirty_paint: bool = false
var _last_rebuild_ms: int = 0
var enabled: bool = true


func setup(doc, cam: Camera3D, world: World3D) -> void:
	document = doc
	camera = cam
	space = world


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
		var tile: Vector2i = _pick_tile(mm.position)
		if tile.x != -99999:
			tile_hovered.emit(tile)
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


func _paint_at_mouse(screen_pos: Vector2) -> void:
	var tile: Vector2i = _pick_tile(screen_pos)
	if tile.x == -99999:
		return
	if tile == _last_tile and _painting:
		return
	_last_tile = tile
	if bool(document.paint_tile(tile.x, tile.y)):
		_dirty_paint = true
		painted.emit()


func _request_rebuild(force: bool) -> void:
	if not _dirty_paint and not force:
		return
	_dirty_paint = false
	_last_rebuild_ms = Time.get_ticks_msec()
	rebuild_requested.emit()


func _pick_tile(screen_pos: Vector2) -> Vector2i:
	if document == null or bool(document.is_empty()) or camera == null:
		return Vector2i(-99999, -99999)
	var hit: Vector3 = _raycast_ground(screen_pos)
	if hit == Vector3.INF:
		hit = _ray_plane_fallback(screen_pos)
	if hit == Vector3.INF:
		return Vector2i(-99999, -99999)
	return document.world_godot_to_tile(hit) as Vector2i


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
	var tile: Vector2i = document.world_godot_to_tile(p) as Vector2i
	var h2: float = float(document.sample_height_at_tile(tile.x, tile.y)) * Wc3Coords.WORLD_SCALE
	t = (h2 - from.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	return from + dir * t
