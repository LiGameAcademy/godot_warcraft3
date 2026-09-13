class_name MinimapView
extends Control
## Shared renderer/input surface. Callers supply textures and already-visible markers.
## No editor document, scene-unit lookup, ownership or fog decisions belong here.
signal clicked(uv: Vector2)
var background: TextureRect
var drag_navigation := true
var _dragging := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)
	resized.connect(queue_redraw)

func bind_background(rect: TextureRect) -> void:
	background = rect
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func set_texture(texture: Texture2D) -> void:
	if background != null:
		background.texture = texture
	queue_redraw()

func drawn_rect() -> Rect2:
	var dimensions := Vector2.ONE
	if background != null and background.texture != null:
		dimensions = background.texture.get_size()
	if dimensions.x <= 0 or dimensions.y <= 0:
		return Rect2()
	var extent := dimensions * minf(size.x / dimensions.x, size.y / dimensions.y)
	return Rect2((size - extent) * 0.5, extent)

func uv_to_position(uv: Vector2) -> Vector2:
	var rect := drawn_rect()
	return rect.position + uv * rect.size

func position_to_uv(point: Vector2) -> Vector2:
	var rect := drawn_rect()
	if rect.size.x <= 0 or rect.size.y <= 0 or point.x < rect.position.x or point.y < rect.position.y or point.x > rect.end.x or point.y > rect.end.y:
		return Vector2(-1, -1)
	return (point - rect.position) / rect.size

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_emit_at(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging and drag_navigation:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_dragging = false
			return
		_emit_at(event.position)
		accept_event()

func _emit_at(point: Vector2) -> void:
	var uv := position_to_uv(point)
	if uv.x >= 0:
		clicked.emit(uv)

## These draw helpers are called by the adapter's draw callback.
func draw_camera(polygon: PackedVector2Array, color := Color(1, 0.85, 0.2), width := 1.5) -> void:
	var clipped := MapMinimapUtils.clip_uv_polygon(polygon)
	if clipped.size() < 3:
		return
	var points := PackedVector2Array()
	for uv in clipped:
		points.append(uv_to_position(uv))
	points.append(points[0])
	draw_polyline(points, color, width, true)

func draw_marker(uv: Vector2, texture: Texture2D, color: Color, extent: Vector2, circle := false) -> void:
	if uv.x < 0 or uv.y < 0 or uv.x > 1 or uv.y > 1:
		return
	var point := uv_to_position(uv)
	if texture != null:
		draw_texture_rect(texture, Rect2(point - extent * 0.5, extent), false, color)
	elif circle:
		draw_circle(point, extent.x * 0.5 + 1.2, Color(0.1, 0.05, 0.02))
		draw_circle(point, extent.x * 0.5, color)
	else:
		draw_rect(Rect2(point - extent * 0.5, extent), color)
