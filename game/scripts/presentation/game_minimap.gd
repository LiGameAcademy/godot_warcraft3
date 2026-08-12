class_name GameMinimap
extends Control
## 游戏小地图：war3mapMap 底图 + 视口黄框 + 单位/建筑色点；点击跳转相机。
## 坐标与编辑器共用 MapMinimapUtils（heightfield UV）。

const BuildingVisualScr = preload("res://scripts/map/presentation/building_visual.gd")

signal clicked(uv: Vector2)

const NEUTRAL_OWNER_MIN := 12
const DOT_UNIT := 2.5
const DOT_BLDG := 4.0
const DOT_MINE := 5.0

var _tex: TextureRect
var _overlay: Control
var _image: Image = null
var _hf: Wc3Heightfield = null
var _unit_host: Node = null
var _camera: Camera3D = null
var _camera_rig: Node3D = null
var _local_player: int = 0
var _viewport_quad: PackedVector2Array = PackedVector2Array()
var _drag_pressed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(136, 136)
	_ensure_children()
	gui_input.connect(_on_gui_input)
	set_process(true)


func configure(
	heightfield: Wc3Heightfield,
	unit_host: Node,
	camera: Camera3D,
	camera_rig: Node3D,
	local_player: int = 0
) -> void:
	_hf = heightfield
	_unit_host = unit_host
	_camera = camera
	_camera_rig = camera_rig
	_local_player = local_player
	if _overlay != null:
		_overlay.queue_redraw()


func load_from_map_dir(map_dir: String) -> bool:
	_ensure_children()
	var img := _try_load_war3map(map_dir)
	if img == null:
		return false
	_image = img
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex.texture = ImageTexture.create_from_image(img)
	_overlay.queue_redraw()
	return true


func set_background_texture(tex: Texture2D) -> void:
	_ensure_children()
	_tex.texture = tex
	_image = tex.get_image() if tex != null else null
	_overlay.queue_redraw()


func _process(_delta: float) -> void:
	if _camera == null or _hf == null or not _hf.is_valid():
		return
	_viewport_quad = MapMinimapUtils.compute_camera_minimap_uv_quad(
		_camera, _camera_rig if _camera_rig != null else _camera, _hf
	)
	if _overlay != null:
		_overlay.queue_redraw()


func _ensure_children() -> void:
	if _tex != null and is_instance_valid(_tex):
		return
	_tex = TextureRect.new()
	_tex.name = "Background"
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_tex)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_on_overlay_draw)
	_overlay.resized.connect(func() -> void: _overlay.queue_redraw())
	add_child(_overlay)


func _try_load_war3map(map_dir: String) -> Image:
	if map_dir.is_empty():
		return null
	for name in ["war3mapMap.png", "war3mapMap.tga", "war3mapMap.blp"]:
		var path := map_dir.path_join(name)
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			continue
		var img := Image.new()
		if img.load(path) == OK:
			return img
		var tex := load(path) as Texture2D
		if tex != null:
			return tex.get_image()
	return null


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_drag_pressed = mb.pressed
		if mb.pressed:
			_emit_click_at(mb.position)
			accept_event()
	elif event is InputEventMouseMotion and _drag_pressed:
		var mm := event as InputEventMouseMotion
		_emit_click_at(mm.position)
		accept_event()


func _emit_click_at(local_pos: Vector2) -> void:
	var uv := _control_to_uv(local_pos)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return
	clicked.emit(uv)


func _control_to_uv(pos: Vector2) -> Vector2:
	var drawn := _drawn_rect()
	if drawn.size.x < 1.0 or drawn.size.y < 1.0:
		return Vector2(-1, -1)
	return Vector2(
		(pos.x - drawn.position.x) / drawn.size.x,
		(pos.y - drawn.position.y) / drawn.size.y
	)


func _uv_to_overlay(uv: Vector2) -> Vector2:
	var drawn := _drawn_rect()
	return Vector2(
		drawn.position.x + uv.x * drawn.size.x,
		drawn.position.y + uv.y * drawn.size.y
	)


func _drawn_rect() -> Rect2:
	var cs := size
	if cs.x <= 1.0 or cs.y <= 1.0:
		return Rect2(Vector2.ZERO, cs)
	if _image == null:
		return Rect2(Vector2.ZERO, cs)
	var ts := Vector2(float(_image.get_width()), float(_image.get_height()))
	var sc := minf(cs.x / ts.x, cs.y / ts.y)
	var drawn := ts * sc
	return Rect2((cs - drawn) * 0.5, drawn)


func _on_overlay_draw() -> void:
	_draw_unit_dots()
	if _viewport_quad.size() >= 4:
		var pts := PackedVector2Array()
		for i in range(4):
			pts.append(_uv_to_overlay(_viewport_quad[i]))
		pts.append(pts[0])
		_overlay.draw_polyline(pts, Color(1.0, 0.85, 0.2, 1.0), 1.5, true)


func _draw_unit_dots() -> void:
	if _unit_host == null or _hf == null or not _hf.is_valid():
		return
	for c in _unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var n := c as Node3D
		if not WorldMembership.is_in_world(n):
			continue
		if not n.has_meta("unit_data"):
			continue
		var d: Dictionary = n.get_meta("unit_data", {})
		var tid := str(d.get("typeId", "")).strip_edges()
		if tid.is_empty() or tid == "sloc":
			continue
		var uv := MapMinimapUtils.world_to_minimap_uv(n.global_position, _hf)
		if uv.x < -0.02 or uv.y < -0.02 or uv.x > 1.02 or uv.y > 1.02:
			continue
		var pos := _uv_to_overlay(uv)
		var owner_id := int(d.get("owner", -1))
		var is_bldg := BuildingVisualScr.is_building(tid)
		var col := _dot_color(tid, owner_id, is_bldg)
		var half := DOT_UNIT
		if tid == "ngol":
			half = DOT_MINE
		elif is_bldg:
			half = DOT_BLDG
		_overlay.draw_rect(Rect2(pos - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), col)


func _dot_color(type_id: String, owner_id: int, is_building: bool) -> Color:
	if type_id == "ngol":
		return Color(1.0, 0.82, 0.12, 1.0)
	if owner_id == _local_player:
		return Color(0.25, 0.55, 1.0, 1.0) if not is_building else Color(0.35, 0.7, 1.0, 1.0)
	if owner_id >= NEUTRAL_OWNER_MIN or owner_id < 0:
		# 中立建筑偏金；野怪/小动物偏琥珀
		return Color(0.95, 0.78, 0.2, 1.0) if is_building else Color(1.0, 0.65, 0.15, 1.0)
	# 敌对
	return Color(1.0, 0.12, 0.1, 1.0)
