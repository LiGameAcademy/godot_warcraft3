extends Window
## Isolated running view of an in-memory snapshot; never saves or edits the document.
signal preview_built
const MapScene := preload("res://scenes/map/map_root.tscn")
const CameraScene := preload("res://editor/scenes/editor_camera.tscn")
var snapshot: Dictionary = {}
var map: MapLoader
var camera_rig: Node3D
var built := false
var _closing := false
var _hint: Label


func _ready() -> void:
	title = "当前地图运行预览"
	size = Vector2i(1100, 720)
	own_world_3d = true
	close_requested.connect(_close)
	window_input.connect(_input_preview)
	var world := Node3D.new()
	add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = preload("res://editor/resources/editor_environment.tres").duplicate(true)
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.1
	world.add_child(sun)
	map = MapScene.instantiate()
	map.auto_load_on_ready = false
	map.place_units = false
	map.place_doodads = false
	map.show_pathing_debug_grid = false
	map.show_editor_helpers = false
	map.show_start_locations = false
	map.show_drop_rings = false
	map.status_path = NodePath("")
	world.add_child(map)
	camera_rig = CameraScene.instantiate()
	world.add_child(camera_rig)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 12)
	canvas.add_child(bar)
	var back := Button.new()
	back.text = "返回编辑器"
	back.pressed.connect(_close)
	bar.add_child(back)
	_hint = Label.new()
	_hint.text = "正在加载当前编辑内容…"
	bar.add_child(_hint)
	await get_tree().process_frame
	await map.reload_from_hf(snapshot.terrain.duplicate(true), snapshot.info.duplicate(true), "res://")
	if not _closing:
		map.rebuild_doodads_from_list(snapshot.terrain, snapshot.doodads.doodads)
		map.rebuild_units_from_list(snapshot.terrain, snapshot.units.units)
		camera_rig.focus_map_extent(Vector2i(int(snapshot.terrain.mapWidth), int(snapshot.terrain.mapHeight)))
		_hint.text = "右键平移 · Ctrl+右键旋转 · 滚轮缩放 · Esc 返回（视觉预览）"
		var missing: int = map.get_unit_layer().last_placeholder + map.get_doodad_layer().last_placeholder
		if missing > 0:
			_hint.text += "\n警告：%d 个对象缺少可用模型，当前显示占位模型。" % missing
	built = true
	preview_built.emit()
	if _closing:
		queue_free()


func _close() -> void:
	_closing = true
	hide()
	# Let the asynchronous map build finish before freeing its nodes.
	if built:
		queue_free()


func _input_preview(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
	if not built or _closing:
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		if event.ctrl_pressed:
			camera_rig.apply_orbit(event.relative)
		else:
			camera_rig.apply_pan_screen(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_rig.apply_zoom(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.apply_zoom(1)
