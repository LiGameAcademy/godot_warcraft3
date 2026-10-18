extends Node3D

## M2 黑盒验收入口：真实地图和模型，单位状态只由 C# 内核推进。
const UNIT_VIEW: PackedScene = preload("res://scenes/kernel_movement/movement_unit_view.tscn")
const MAX_SELECTION: int = 24
const COUNTS: Array[int] = [12, 24, 64, 65, 300, 500]
const PROFILES: Array[String] = ["hfoo", "Hamg", "ogru", "earc", "eaoe"]
const FORMATIONS: Array[String] = ["紧凑", "矩形", "楔形", "圆形"]

@onready var _map: MapLoader = $MapRoot
@onready var _camera: RtsCamera = $RtsCamera
@onready var _bridge: Node = $RtsKernelBridge
@onready var _units: Node3D = $Units
@onready var _status: Label = $UI/Panel/Rows/Status
@onready var _profiles: OptionButton = $UI/Panel/Rows/Presets/Profile
@onready var _buttons: HBoxContainer = $UI/Panel/Rows/Presets
@onready var _selection_view: Control = $UI/MovementSelectionView
@onready var _route_view: MovementRouteView = $MovementRouteView
@onready var _route_toggle: CheckButton = $UI/Panel/Rows/ShowRoutes

var _sources: Array[String] = []
var _footprints: PackedByteArray = PackedByteArray()
var _views: Dictionary[int, RtsMovementUnitView] = {}
var _selected: Dictionary[int, bool] = {}
var _frame: Dictionary = {}
var _active: bool = false
var _paused: bool = false
var _spawning: bool = false
var _accumulator: float = 0.0
var _sequence: int = 1
var _formation: int = 0
var _failures: int = 0
var _last_step_ms: float = 0.0
var _peak_step_ms: float = 0.0
var _status_elapsed: float = 0.0
var _message: String = "正在加载真实地图…"
var _snapshot: String = ""
var _snapshot_sequence: int = 0
var _snapshot_selection: Dictionary[int, bool] = {}
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	DisplayServer.window_set_title("RTS 移动验收 · 24 单位落点与动画修复 · v13")
	AssetProvider.seal_runtime_content()
	_route_toggle.toggled.connect(_on_routes_toggled)
	for profile: String in PROFILES:
		_profiles.add_item(profile)
	for index: int in range(COUNTS.size()):
		var button: Button = _buttons.get_node("Count%d" % COUNTS[index]) as Button
		button.pressed.connect(_spawn_preset.bind(COUNTS[index]))
	_bridge.connect("MatchEventRaised", _on_match_event)
	if not _map.is_map_ready():
		await _map.map_loaded
	_camera.setup(_map)
	_camera.set_heightfield(Wc3Heightfield.from_dict(_map.get_heightfield_dict()))
	var pathing: Wc3PathingMap = _map.get_pathing_map()
	if pathing == null or not pathing.is_valid():
		_fail("地图未生成有效寻路面")
		return
	_footprints = pathing.cells_dynamic.duplicate()
	var data_root: String = AssetProvider.get_data_root()
	for path: String in [_map.map_dir.path_join("pathing.json"), _map.map_dir.path_join("terrain-heightfield.json"),
			data_root.path_join("Units/UnitData.json"), data_root.path_join("Units/UnitBalance.json"), _map.map_dir.path_join("units.json")]:
		if not FileAccess.file_exists(path):
			_fail("缺少内容：" + path)
			return
		_sources.append(FileAccess.get_file_as_string(path))
	var initial_count: int = 24
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--kernel-count="):
			var count_text: String = argument.trim_prefix("--kernel-count=")
			if not count_text.is_valid_int() or not int(count_text) in COUNTS:
				_fail("验收规模必须为 12、24、64、65、300 或 500")
				return
			initial_count = int(count_text)
	await _spawn_preset(initial_count)
	if _active:
		var blocked_cells: int = 0
		for flag: int in _footprints:
			if (flag & Wc3PathingMap.FLAG_NO_WALK) != 0:
				blocked_cells += 1
		print("KERNEL_MOVEMENT_READY entities=", _views.size(), " runtime_no_walk_cells=", blocked_cells)
		if "--smoke-test" in OS.get_cmdline_user_args():
			print("APP startup PASS: kernel_movement")
			get_tree().quit()


func _process(delta: float) -> void:
	if not _active:
		_status.text = _message
		return
	if not _paused:
		_accumulator += delta
		var tick: float = 1.0 / float(_bridge.call("GetTickRate"))
		var advanced: int = 0
		while _accumulator >= tick and advanced < 4:
			var started: int = Time.get_ticks_usec()
			_bridge.call("Step", 1)
			_last_step_ms = float(Time.get_ticks_usec() - started) / 1000.0
			_peak_step_ms = maxf(_peak_step_ms, _last_step_ms)
			_apply_frame(false)
			_accumulator -= tick
			advanced += 1
	var alpha: float = 1.0 if _paused else minf(_accumulator * float(_bridge.call("GetTickRate")), 1.0)
	for id: int in _views:
		_views[id].display(alpha, _selected.has(id), delta)
	if _dragging:
		_selection_view.call("show_region", Rect2(_drag_start, get_viewport().get_mouse_position() - _drag_start).abs(), true)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_dragging = false
			_selection_view.call("show_region", Rect2(), false)
	_status_elapsed += delta
	if _status_elapsed >= 0.2:
		_status_elapsed = 0.0
		_refresh_routes()
		var moving: PackedByteArray = _frame.get("moving", PackedByteArray())
		_status.text = "帧 %d | 单位 %d / 选中 %d / 移动 %d | %s | 失败 %d | Step %.2f / 峰值 %.2f ms%s\n%s" % [
			int(_bridge.call("GetFrame")), _views.size(), _selected.size(), moving.count(1), FORMATIONS[_formation],
			_failures, _last_step_ms, _peak_step_ms, " | 已暂停" if _paused else "", _message]


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_drag_start = mouse.position
				_dragging = true
			elif _dragging:
				_select_region(Rect2(_drag_start, mouse.position - _drag_start).abs(), mouse.shift_pressed)
				_dragging = false
				_selection_view.call("show_region", Rect2(), false)
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			_move_to_mouse(mouse.position, mouse.shift_pressed)
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_F2:
				_route_toggle.button_pressed = not _route_toggle.button_pressed
			KEY_1, KEY_2, KEY_3, KEY_4:
				_formation = int(key.keycode - KEY_1)
			KEY_A:
				_select_all()
			KEY_SPACE:
				for id: int in _selected:
					_bridge.call("SubmitStop", int(_bridge.call("GetFrame")) + 1, 0, _sequence, id)
					_sequence += 1
			KEY_P:
				_paused = not _paused
			KEY_F:
				_focus_selection()
			KEY_F5:
				_snapshot = str(_bridge.call("CaptureSnapshotJson"))
				_snapshot_sequence = _sequence
				_snapshot_selection = _selected.duplicate()
				_message = "已保存当前帧"
			KEY_F9:
				_restore_snapshot()


func _spawn_preset(count: int) -> void:
	if _sources.size() != 5 or _spawning:
		return
	_spawning = true
	_active = false
	_message = "正在创建 %d 个单位…" % count
	_set_buttons_disabled(true)
	await get_tree().process_frame
	var initialized: bool = bool(_bridge.call("ResetContentMatch", _sources[0], _sources[1], _sources[2], _sources[3], _sources[4], _footprints, 30, 7))
	if not initialized:
		_fail(str(_bridge.call("GetLastError")))
		_finish_spawning()
		return
	var result: Dictionary = _bridge.call("SpawnPreset", PROFILES[_profiles.selected], count, 0)
	if not bool(result.accepted):
		_fail(str(result.error))
		_finish_spawning()
		return
	for view: RtsMovementUnitView in _views.values():
		view.queue_free()
	_views.clear()
	_selected.clear()
	_frame = _bridge.call("ReadMovementFrame")
	var ids: PackedInt64Array = _frame.ids
	for index: int in range(ids.size()):
		if not _create_view(ids[index], int(_frame.definitions[index])):
			_finish_spawning()
			return
		if index % 16 == 15:
			await get_tree().process_frame
	_sequence = count + 1
	_accumulator = 0.0
	_failures = 0
	_peak_step_ms = 0.0
	_snapshot = ""
	_apply_frame(true)
	_select_all()
	_focus_selection()
	_message = "右键移动；Shift+右键追加；新预设会重置本局"
	_active = true
	_finish_spawning()


func _create_view(id: int, definition: int) -> bool:
	var code: String = ""
	for shift: int in [24, 16, 8, 0]:
		code += String.chr((definition >> shift) & 255)
	var path: String = _map.get_id_catalog().converted_glb_path(code)
	var model: Node3D = _map.get_model_cache().instance_glb(path, true)
	if not model is Wc3ModelScene:
		if model != null:
			model.free()
		_fail("未加载有效单位模型：" + code)
		return false
	var view: RtsMovementUnitView = UNIT_VIEW.instantiate() as RtsMovementUnitView
	_units.add_child(view)
	view.configure(code, model as Wc3ModelScene)
	_views[id] = view
	return true


func _apply_frame(snap: bool) -> void:
	_frame = _bridge.call("ReadMovementFrame")
	var ids: PackedInt64Array = _frame.ids
	var positions: PackedVector3Array = _frame.positions
	var facing: PackedFloat64Array = _frame.facing
	var radii: PackedFloat64Array = _frame.radii
	for index: int in range(ids.size()):
		_views[ids[index]].accept_frame(positions[index], facing[index], radii[index], snap)


func _selected_ids() -> PackedInt64Array:
	var ids: Array[int] = _selected.keys()
	ids.sort()
	return PackedInt64Array(ids)


func _select_all() -> void:
	_selected.clear()
	for id: int in _views:
		if _selected.size() >= MAX_SELECTION:
			break
		_selected[id] = true


func _select_region(region: Rect2, append: bool) -> void:
	if not append:
		_selected.clear()
	var camera: Camera3D = _camera.get_camera()
	var nearest: int = 0
	var best: float = 32.0 * 32.0
	for id: int in _views:
		var point: Vector3 = _views[id].position
		if camera.is_position_behind(point):
			continue
		var screen: Vector2 = camera.unproject_position(point)
		if region.size.length_squared() > 36.0:
			if region.has_point(screen) and _selected.size() < MAX_SELECTION:
				_selected[id] = true
		else:
			var distance: float = screen.distance_squared_to(region.get_center())
			if distance < best:
				best = distance
				nearest = id
	if nearest != 0 and (_selected.has(nearest) or _selected.size() < MAX_SELECTION):
		_selected[nearest] = true


func _move_to_mouse(screen: Vector2, append: bool) -> void:
	if _selected.is_empty():
		return
	var camera: Camera3D = _camera.get_camera()
	var origin: Vector3 = camera.project_ray_origin(screen)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 2000.0, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_message = "未命中地形"
		return
	var goal: Vector2 = Wc3Coords.godot_to_wc3_xy(hit.position as Vector3)
	var result: Dictionary = _bridge.call("SubmitGroupMove", int(_bridge.call("GetFrame")) + 1, 0, _sequence, _selected_ids(), goal, _formation, append)
	_sequence += 1
	_message = "已追加移动" if append else "已提交移动"
	if not bool(result.accepted):
		_message = str(result.error)


func _focus_selection() -> void:
	if _selected.is_empty():
		return
	var center: Vector3 = Vector3.ZERO
	for id: int in _selected:
		center += _views[id].position
	_camera.snap_to(center / float(_selected.size()))


func _restore_snapshot() -> void:
	if _snapshot.is_empty():
		_message = "尚未保存快照"
		return
	if not bool(_bridge.call("RestoreSnapshotJson", _snapshot)):
		_message = str(_bridge.call("GetLastError"))
		return
	_sequence = _snapshot_sequence
	_selected = _snapshot_selection.duplicate()
	_accumulator = 0.0
	_apply_frame(true)
	_message = "已恢复当前帧、待执行命令与输入序号"


func _on_match_event(_frame_id: int, _event_sequence: int, kind: int, entity_id: int, detail: String) -> void:
	if kind == 2 or kind == 4:
		_failures += 1
		_message = "单位 %d：%s" % [entity_id, detail]


func _set_buttons_disabled(disabled: bool) -> void:
	_profiles.disabled = disabled
	for count: int in COUNTS:
		(_buttons.get_node("Count%d" % count) as Button).disabled = disabled


func _finish_spawning() -> void:
	_spawning = false
	_set_buttons_disabled(false)
	_route_view.clear_routes()


func _on_routes_toggled(enabled: bool) -> void:
	_route_view.visible = enabled
	if enabled:
		_refresh_routes()
	else:
		_route_view.clear_routes()


func _refresh_routes() -> void:
	if not _route_toggle.button_pressed:
		return
	var routes: Array[Dictionary] = _bridge.call("ReadMovementRoutes", _selected_ids())
	_route_view.show_routes(routes)


func _fail(message: String) -> void:
	_active = false
	_message = message
	push_error("Kernel movement acceptance: " + message)
