class_name GameDirector
extends Node

## 游戏总管（对标 MapEditor）。
## 职责：配置 MapLoader、Melee 开局、Session/库存、选中、相机。

## 场景实例仍需 preload；脚本类一律用 class_name。
const MoveConfirmFxScene = preload("res://game/scenes/move_confirm_fx.tscn")

@export var map_root: MapLoader
@export var rts_camera: RtsCamera
@export var game_hud: GameHud
@export var unit_selector: Node
@export var game_cursor: Node
@export var map_dir: String = "res://assets/map-parsed/echoisles"
## 开发期：0 无 / 1 大黄 / 2 大+中 / 3 大+中+小灰(32)
@export_range(0, 3) var view_grid_level: int = 3
@export var show_pathing_ground: bool = true
@export var show_ramp_debug: bool = false

@export_group("Melee 开局")
## 预览种族：human / orc / undead / nightelf
@export var preview_race: String = "human"
## 本地玩家 owner（队伍色）
@export_range(0, 15) var local_player: int = 0
## true：在地图 sloc 中随机选一个；false：优先匹配 local_player 的 owner
@export var random_start_location: bool = true
@export var spawn_melee_base: bool = true
## 开发：F6 Birth / F7 Stand Work（训练烟）/ F8 Stand
@export var debug_building_fx_hotkeys: bool = true

@export_group("移动")
## 右键对选中单位下发网格寻路移动
@export var enable_move_command: bool = true
## 开发：显示选中单位当前路径折线（F9 切换）
@export var show_path_debug: bool = true

@export_group("相机")
## 对齐 WC3 CameraRates Forward≈3000 → ×WORLD_SCALE
@export var camera_pan_speed: float = 30.0
## 默认最远档 1650（MiscData）；滚轮六档联动 AOA，勿再拉到 50+
@export var camera_initial_distance: float = 16.5
@export var camera_min_distance: float = 11.0
@export var camera_max_distance: float = 16.5
@export var camera_initial_pitch_deg: float = -56.0
@export var camera_fov: float = 70.0
@export var use_wc3_zoom_curve: bool = true
@export var apply_camera_bounds: bool = true

## Echo Isles cameraBounds（WC3 XY）；小地图点击跳转用
var _cam_min := Vector2(-6912.0, -5376.0)
var _cam_max := Vector2(6912.0, 4864.0)
var _rng := RandomNumberGenerator.new()
var _bootstrapped: bool = false
var _session: GameSession = null
## 共享 PathQuery：所有 UnitNavigator 注入同一实例，避免每单位一份 A* 图。
var _path_query: PathQuery = null
var _heightfield: Wc3Heightfield = null
## 邻近单位查询（soft 分离）；与 PathQuery 一样地图就绪后绑定。
var _crowd_query: UnitCrowdQuery = null
var _cell_reservation: PathCellReservation = null
var _path_debug: PathDebugDraw = null


func _ready() -> void:
	_rng.randomize()
	_resolve_exports()
	if map_root == null:
		push_error("GameDirector: 未绑定 map_root")
		return
	_configure_map_root()
	_wire_hud()
	_load_camera_bounds()
	_configure_camera()
	if map_root.map_loaded.is_connected(_on_map_loaded) == false:
		map_root.map_loaded.connect(_on_map_loaded)
	if map_root.is_map_ready():
		_on_map_loaded()


func get_session() -> GameSession:
	return _session


## 按本地玩家种族切换光标图集（human/orc/undead/nightelf）。
func _apply_cursor_race(race_id: String) -> void:
	if game_cursor == null:
		_resolve_exports()
	if game_cursor == null:
		return
	if game_cursor.has_method("set_race"):
		game_cursor.call("set_race", race_id)


func _resolve_exports() -> void:
	var parent_n := get_parent()
	if map_root == null:
		map_root = get_node_or_null("../MapRoot") as MapLoader
		if map_root == null and parent_n != null:
			map_root = parent_n.get_node_or_null("MapRoot") as MapLoader
	if rts_camera == null:
		rts_camera = get_node_or_null("../RtsCamera") as RtsCamera
		if rts_camera == null and parent_n != null:
			rts_camera = parent_n.get_node_or_null("RtsCamera") as RtsCamera
	if game_hud == null:
		game_hud = get_node_or_null("../GameHud") as GameHud
		if game_hud == null and parent_n != null:
			game_hud = parent_n.get_node_or_null("GameHud") as GameHud
	if unit_selector == null:
		if parent_n != null:
			unit_selector = parent_n.get_node_or_null("UnitSelector")
			if unit_selector == null:
				unit_selector = parent_n.find_child("UnitSelector", true, false)
		if unit_selector == null:
			unit_selector = get_node_or_null("../UnitSelector")
	if game_cursor == null:
		game_cursor = get_node_or_null("../GameCursor")
		if game_cursor == null and parent_n != null:
			game_cursor = parent_n.get_node_or_null("GameCursor")
			if game_cursor == null:
				game_cursor = parent_n.get_node_or_null("HumanCursor")
	print(
		"[GameDirector] bind map=%s cam=%s hud=%s sel=%s cursor=%s"
		% [
			map_root != null,
			rts_camera != null,
			game_hud != null,
			unit_selector != null,
			game_cursor != null,
		]
	)


func _configure_map_root() -> void:
	if not map_dir.is_empty():
		map_root.map_dir = map_dir
	map_root.place_doodads = true
	map_root.place_units = true
	map_root.show_start_locations = false
	map_root.show_drop_rings = false
	map_root.show_pathing_debug_grid = true
	map_root.show_ramp_debug = show_ramp_debug
	map_root.show_pathing_ground = show_pathing_ground
	map_root.set_view_grid_level(view_grid_level)
	if show_pathing_ground and map_root.get_pathing_map() != null:
		map_root.set_show_pathing_ground(true)


func _configure_camera() -> void:
	if rts_camera == null:
		return
	rts_camera.pan_speed = camera_pan_speed
	rts_camera.use_wc3_zoom_curve = use_wc3_zoom_curve
	rts_camera.camera_fov = camera_fov
	rts_camera.min_distance = camera_min_distance
	rts_camera.max_distance = camera_max_distance
	rts_camera.initial_distance = camera_initial_distance
	rts_camera.initial_pitch_deg = camera_initial_pitch_deg
	rts_camera.apply_export_tuning()
	if apply_camera_bounds:
		_apply_camera_world_bounds()


func _apply_camera_world_bounds() -> void:
	if rts_camera == null:
		return
	# WC3 XY → Godot XZ：x'=x*s，z'=-y*s
	var s := Wc3Coords.WORLD_SCALE
	var min_xz := Vector2(_cam_min.x * s, -_cam_max.y * s)
	var max_xz := Vector2(_cam_max.x * s, -_cam_min.y * s)
	# 规范化（z 可能因取负翻转）
	var lo := Vector2(minf(min_xz.x, max_xz.x), minf(min_xz.y, max_xz.y))
	var hi := Vector2(maxf(min_xz.x, max_xz.x), maxf(min_xz.y, max_xz.y))
	rts_camera.set_boundaries(lo, hi)


func _wire_hud() -> void:
	if game_hud == null:
		return
	if not map_dir.is_empty():
		game_hud.map_dir = map_dir
	game_hud.set_status(_map_display_name())
	if not game_hud.minimap_clicked.is_connected(_on_minimap_clicked):
		game_hud.minimap_clicked.connect(_on_minimap_clicked)
	if not game_hud.command_pressed.is_connected(_on_command_pressed):
		game_hud.command_pressed.connect(_on_command_pressed)


func _setup_selector() -> void:
	if unit_selector == null or rts_camera == null or map_root == null:
		push_warning("GameDirector: UnitSelector 绑定失败（selector/camera/map 为空）")
		return
	var cam := rts_camera.get_camera()
	var layer := map_root.get_unit_layer()
	if cam == null or layer == null:
		push_warning("GameDirector: UnitSelector.setup 跳过（camera=%s layer=%s）" % [cam, layer])
		return
	unit_selector.set("owner_filter", -1)
	if unit_selector.has_method("setup"):
		unit_selector.call("setup", cam, layer, null)
	if unit_selector.has_signal("selection_changed"):
		var sel_sig: Signal = unit_selector.selection_changed
		if not sel_sig.is_connected(_on_selection_changed):
			sel_sig.connect(_on_selection_changed)
	if game_hud:
		game_hud.set_status("点选就绪 · LMB 点选/框选 · RMB 移动")


func _input(event: InputEvent) -> void:
	# 运行时再解析一次：防止 ready 时序导致 selector 引用为空。
	if unit_selector == null:
		_resolve_exports()
	if unit_selector != null and unit_selector.has_method("handle_pointer_event"):
		if bool(unit_selector.call("handle_pointer_event", event)):
			get_viewport().set_input_as_handled()


func _map_display_name() -> String:
	var path := map_dir.path_join("info.json")
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			if typeof(data) == TYPE_DICTIONARY:
				var n := str((data as Dictionary).get("name", "")).strip_edges()
				if not n.is_empty():
					return n
	return map_dir.get_file()


func _load_camera_bounds() -> void:
	var path := map_dir.path_join("info.json")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var b: Variant = data.get("cameraBounds", null)
	if b is Array and (b as Array).size() >= 4:
		var a: Array = b
		_cam_min = Vector2(float(a[0]), float(a[1]))
		_cam_max = Vector2(float(a[2]), float(a[3]))


func _on_map_loaded() -> void:
	if _bootstrapped:
		return
	_bootstrapped = true
	_hide_start_locations()
	_bootstrap_melee()
	_setup_selector()
	_setup_pathing()
	# 地形材质已就绪后再刷调试栅格，避免 ready 阶段空材质警告
	if map_root != null:
		map_root.set_view_grid_level(view_grid_level)


## 地图就绪后再绑 PathQuery：WPM/合成图此时才保证有效。
func _setup_pathing() -> void:
	if map_root == null:
		return
	_path_query = PathQuery.new()
	_path_query.bind_pathing(map_root.get_pathing_map())
	_cell_reservation = PathCellReservation.new()
	_path_query.bind_reservation(_cell_reservation)
	var hf_dict := map_root.get_heightfield_dict()
	if not hf_dict.is_empty():
		_heightfield = Wc3Heightfield.from_dict(hf_dict, true)
	else:
		_heightfield = null
	_crowd_query = UnitCrowdQuery.new()
	_crowd_query.configure(
		map_root.get_unit_layer(),
		map_root.get_id_catalog()
	)
	_ensure_path_debug()


func _ensure_path_debug() -> void:
	if map_root == null:
		return
	if _path_debug != null and is_instance_valid(_path_debug):
		if _path_debug.has_method("setup"):
			_path_debug.call("setup", _heightfield)
		if _path_debug.has_method("set_enabled"):
			_path_debug.call("set_enabled", show_path_debug)
		return
	_path_debug = PathDebugDraw.new()
	_path_debug.name = "PathDebugDraw"
	map_root.add_child(_path_debug)
	if _path_debug.has_method("setup"):
		_path_debug.call("setup", _heightfield)
	if _path_debug.has_method("set_enabled"):
		_path_debug.call("set_enabled", show_path_debug)


func _process(_delta: float) -> void:
	_refresh_path_debug()


func _refresh_path_debug() -> void:
	if _path_debug == null or not show_path_debug:
		return
	if unit_selector == null or not unit_selector.has_method("get_selected"):
		return
	if not _path_debug.has_method("redraw"):
		return
	var paths: Array = []
	var selected: Array = unit_selector.call("get_selected")
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var nav := (n as Node3D).get_node_or_null("UnitNavigator")
		if nav == null or not nav.has_method("get_remaining_waypoints_wc3"):
			continue
		if not bool(nav.call("is_moving")):
			continue
		var pts: Array = nav.call("get_remaining_waypoints_wc3")
		if pts.is_empty():
			continue
		# 加上当前位置，线从脚下出发
		var inv := 1.0 / Wc3Coords.WORLD_SCALE
		var body := n as Node3D
		var cur := Vector2(body.global_position.x * inv, -body.global_position.z * inv)
		var full: Array = [cur]
		for p in pts:
			full.append(p)
		paths.append({"points": full})
	_path_debug.call("redraw", paths)


## 游戏内移除已放置的 sloc（防 MapRoot 早于 Director 配置时漏网）。
func _hide_start_locations() -> void:
	if map_root == null:
		return
	var layer := map_root.get_unit_layer()
	if layer == null:
		return
	for c in layer.get_children():
		var d: Dictionary = c.get_meta("unit_data", {})
		if str(d.get("typeId", "")) == "sloc" or str(c.name).begins_with("sloc_"):
			c.queue_free()


func _bootstrap_melee() -> void:
	var race := MeleeRacePreview.race_from_string(preview_race)
	var preview := MeleeRacePreview.preview_dict(race)
	var worker_n: int = int(preview.get("worker_count", 5))
	_session = GameSession.from_melee_bootstrap(
		map_dir,
		local_player,
		str(preview.get("race", "human")),
		worker_n,
		PlayerStock.MELEE_TOWN_HALL_FOOD
	)
	_apply_cursor_race(str(preview.get("race", "human")))
	if game_hud:
		game_hud.bind_stock(_session.local_stock())

	var slocs := MeleeBootstrap.collect_slocs(map_dir)
	if slocs.is_empty():
		if game_hud:
			game_hud.set_status("%s · 无 sloc，跳过开局刷兵" % str(preview.get("display_name", "")))
		return

	var sloc: Dictionary
	if random_start_location:
		sloc = MeleeBootstrap.pick_random_sloc(slocs, _rng)
	else:
		sloc = _find_sloc_for_owner(slocs, local_player)
		if sloc.is_empty():
			sloc = MeleeBootstrap.pick_random_sloc(slocs, _rng)

	var hall_world := Vector3.ZERO
	if spawn_melee_base:
		var hf := map_root.get_heightfield_dict()
		var result := MeleeBootstrap.spawn_at_sloc(map_root, sloc, race, local_player, hf)
		if result.get("ok", false):
			hall_world = result.get("hall_world", Vector3.ZERO) as Vector3
			if game_hud:
				game_hud.set_status(
					"%s · %s @ sloc owner=%s · 刷 %d · 金%d 木%d"
					% [
						_map_display_name(),
						str(preview.get("display_name", "")),
						str(sloc.get("owner", "?")),
						int(result.get("spawned", 0)),
						_session.local_stock().gold,
						_session.local_stock().lumber,
					]
				)
		else:
			if game_hud:
				game_hud.set_status("%s · 开局刷兵失败" % str(preview.get("display_name", "")))
	else:
		var pos: Dictionary = sloc.get("position", {})
		hall_world = Wc3Coords.wc3_xy_to_godot(
			float(pos.get("x", 0.0)),
			float(pos.get("y", 0.0)),
			float(pos.get("z", 0.0))
		)

	if rts_camera and hall_world != Vector3.ZERO:
		rts_camera.snap_to(hall_world)
		rts_camera.focus_on_position(hall_world, 0.35)


func _find_sloc_for_owner(slocs: Array[Dictionary], owner_id: int) -> Dictionary:
	for s in slocs:
		if int(s.get("owner", -1)) == owner_id:
			return s
	return {}


func _unhandled_input(event: InputEvent) -> void:
	# 右键移动优先于调试热键：RTS 主操作不应被 F 键分支挡住。
	if enable_move_command and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _issue_move_command(mb.position):
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		# S = Stop：对齐原作停止命令（寻路分支导航指令，不是采集）
		if key == KEY_S and enable_move_command:
			if _issue_stop_command():
				get_viewport().set_input_as_handled()
				return
		if key == KEY_F9:
			show_path_debug = not show_path_debug
			_ensure_path_debug()
			if _path_debug != null and _path_debug.has_method("set_enabled"):
				_path_debug.call("set_enabled", show_path_debug)
			if game_hud:
				game_hud.set_status("路径调试：%s" % ("开" if show_path_debug else "关"))
			get_viewport().set_input_as_handled()
			return
		if not debug_building_fx_hotkeys:
			return
		var phase := -1
		var label := ""
		match key:
			KEY_F6:
				phase = BuildingVisual.Phase.BIRTH
				label = "Birth（建造尘）"
			KEY_F7:
				phase = BuildingVisual.Phase.WORK
				label = "Stand Work（训练烟）"
			KEY_F8:
				phase = BuildingVisual.Phase.IDLE
				label = "Stand"
			_:
				return
		if _debug_apply_hall_phase(phase):
			if game_hud:
				game_hud.set_status("主城 FX → %s" % label)
			get_viewport().set_input_as_handled()


## 选中单位立即停步并回 Stand（不推动静止单位）。
func _issue_stop_command() -> bool:
	if unit_selector == null or not unit_selector.has_method("get_selected"):
		return false
	var selected: Array = unit_selector.call("get_selected")
	if selected.is_empty():
		return false
	var n_stop := 0
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node := n as Node3D
		var d: Dictionary = node.get_meta("unit_data", {})
		if BuildingVisual.is_building(str(d.get("typeId", ""))):
			continue
		var nav := node.get_node_or_null("UnitNavigator")
		if nav != null and nav.has_method("stop"):
			nav.call("stop")
			n_stop += 1
	if n_stop > 0 and game_hud:
		game_hud.set_status("停止 · %d 单位" % n_stop)
	return n_stop > 0


## 对当前选中可移动单位下发 go_to。建筑跳过（主城不能走）。
## 多单位：黄金角螺旋分配错开终点（对齐原作群体落点），再各自 A*；途中 soft push 防途中叠模。
func _issue_move_command(screen_pos: Vector2) -> bool:
	if unit_selector == null or _path_query == null:
		return false
	if not unit_selector.has_method("get_selected"):
		return false
	var selected: Array = unit_selector.call("get_selected")
	if selected.is_empty():
		return false
	var hit := _ground_at_screen(screen_pos)
	if hit == Vector3.INF:
		if game_hud:
			game_hud.set_status("移动：未点到地面")
		return true
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var goal_center := Vector2(hit.x * inv, -hit.z * inv)
	var movers: Array = []
	var radii := PackedFloat32Array()
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node := n as Node3D
		var d: Dictionary = node.get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if BuildingVisual.is_building(tid):
			continue
		movers.append(node)
		var r := 16.0
		if _crowd_query != null and _crowd_query.has_method("radius_for_unit"):
			r = float(_crowd_query.call("radius_for_unit", node))
		radii.append(r)
	if movers.is_empty():
		if game_hud:
			game_hud.set_status("选中无可用移动单位（建筑？）")
		return true
	var goals: PackedVector2Array = UnitMoveSlots.assign_goals(
		movers, radii, goal_center, _path_query
	)
	var moved := 0
	var failed := 0
	for i in range(movers.size()):
		var node: Node3D = movers[i]
		var nav := _ensure_navigator(node)
		if nav == null:
			continue
		var slot: Vector2 = goals[i] if i < goals.size() else goal_center
		if nav.go_to_wc3(slot):
			moved += 1
		else:
			failed += 1
	if moved > 0:
		_spawn_move_confirm(goal_center)
	if game_hud:
		if moved > 0:
			game_hud.set_status(
				"移动 → (%.0f, %.0f) · %d 单位（已散开落点）" % [goal_center.x, goal_center.y, moved]
			)
		elif failed > 0:
			game_hud.set_status("无法到达 (%.0f, %.0f)" % [goal_center.x, goal_center.y])
	return moved > 0 or failed > 0


func _spawn_move_confirm(goal_wc3: Vector2) -> void:
	if map_root == null:
		return
	var fx := MoveConfirmFxScene.instantiate() as MoveConfirmFx
	map_root.add_child(fx)
	var cache: MapModelCache = null
	if map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	fx.setup(cache)
	# 当前只有移动命令；攻击移动接上后改传 MoveConfirmFx.Kind.ATTACK
	fx.play_at_wc3(goal_wc3, _heightfield, MoveConfirmFx.Kind.MOVE)


func _ensure_navigator(unit: Node3D) -> UnitNavigator:
	var visual := _ensure_unit_visual(unit)
	var existing := unit.get_node_or_null("UnitNavigator") as UnitNavigator
	if existing != null:
		existing.configure(_path_query, _heightfield, _crowd_query, _cell_reservation)
		existing.set_visual(visual)
		_apply_move_stats(unit, existing)
		return existing
	var nav := UnitNavigator.new()
	nav.name = "UnitNavigator"
	# 先 configure 再进树：即使 _ready 延后，query 也已就绪。
	nav.configure(_path_query, _heightfield, _crowd_query, _cell_reservation)
	nav.set_visual(visual)
	_apply_move_stats(unit, nav)
	unit.add_child(nav)
	return nav


func _ensure_unit_visual(unit: Node3D) -> UnitVisual:
	var existing := unit.get_node_or_null("UnitVisual") as UnitVisual
	if existing != null:
		return existing
	var vis := UnitVisual.new()
	vis.name = "UnitVisual"
	var cache: MapModelCache = null
	if map_root != null and map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	vis.bind_cache(cache)
	unit.add_child(vis)
	return vis


## 从 UnitBalance.spd / UnitData.turnRate / Balance.collision 写入 Navigator。
## 注意：UnitUI.walk 是动画侧速率，不是对象编辑器「移动速度」。
func _apply_move_stats(unit: Node3D, nav: UnitNavigator) -> void:
	if unit == null or nav == null:
		return
	var d: Dictionary = unit.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	if tid.is_empty():
		return
	var spd := 0.0
	var turn := 0.0
	var radius := 0.0
	Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
	Wc3DefStore.ensure_table(UnitDataDef.TABLE_NAME)
	var bal := Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef
	if bal != null and bal.spd > 0.0:
		spd = bal.spd
	var data := Wc3DefStore.get_row(UnitDataDef.TABLE_NAME, tid) as UnitDataDef
	if data != null and data.turn_rate > 0.0:
		turn = data.turn_rate
	if _crowd_query != null:
		radius = _crowd_query.radius_for_unit(unit)
	nav.apply_unit_stats(spd, turn, radius)


## 地面拾取：沿相机射线对 Heightfield 求交，而不是 PhysicsRay。
## 为何不用物理射线：会先打到单位网格/选中环，目标变成「自己脚下」→ 表现为不移动。
func _ground_at_screen(screen_pos: Vector2) -> Vector3:
	if rts_camera == null:
		return Vector3.INF
	var cam := rts_camera.get_camera()
	if cam == null:
		return Vector3.INF
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if dir.length_squared() < 1e-8:
		return Vector3.INF
	dir = dir.normalized()
	if _heightfield != null and _heightfield.is_valid():
		var hit := _ray_heightfield(from, dir)
		if hit != Vector3.INF:
			return hit
	# 回退：物理射线（排除无 heightfield 时）
	var space := cam.get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 20000.0)
		q.collision_mask = 0xFFFFFFFF
		var hit2 := space.intersect_ray(q)
		if not hit2.is_empty():
			return hit2.get("position", Vector3.INF)
	if absf(dir.y) < 1e-5:
		return Vector3.INF
	var t := -from.y / dir.y
	if t < 0.0:
		return Vector3.INF
	return from + dir * t


## 沿射线步进，找「射线高度穿过地形高度」的交点（RTS 常用、不依赖碰撞层）。
func _ray_heightfield(from: Vector3, dir: Vector3) -> Vector3:
	var step := 0.35
	var max_dist := 400.0
	var prev_above := true
	var d := step
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	while d <= max_dist:
		var p: Vector3 = from + dir * d
		var wx := p.x * inv
		var wy := -p.z * inv
		var gz := _heightfield.interpolated_height(wx, wy)
		var ground := Wc3Coords.wc3_xy_to_godot(wx, wy, gz)
		var above := p.y >= ground.y
		if prev_above and not above:
			# 二分细化交点，减少步进粒度带来的落点偏差。
			var lo := d - step
			var hi := d
			for _i in range(6):
				var mid := (lo + hi) * 0.5
				var pm: Vector3 = from + dir * mid
				var w2x := pm.x * inv
				var w2y := -pm.z * inv
				var gz2 := _heightfield.interpolated_height(w2x, w2y)
				var g2 := Wc3Coords.wc3_xy_to_godot(w2x, w2y, gz2)
				if pm.y >= g2.y:
					lo = mid
				else:
					hi = mid
			var final_d := (lo + hi) * 0.5
			var pf: Vector3 = from + dir * final_d
			var wfx := pf.x * inv
			var wfy := -pf.z * inv
			var gzf := _heightfield.interpolated_height(wfx, wfy)
			return Wc3Coords.wc3_xy_to_godot(wfx, wfy, gzf)
		prev_above = above
		d += step
	return Vector3.INF


func _debug_apply_hall_phase(phase: int) -> bool:
	if map_root == null:
		return false
	var layer := map_root.get_unit_layer()
	if layer == null:
		return false
	var cache: MapModelCache = null
	if map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	for c in layer.get_children():
		if not (c is Node3D):
			continue
		var d: Dictionary = (c as Node).get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if tid != "htow" and tid != "hkee" and tid != "hcas":
			continue
		if cache != null:
			BuildingVisual.apply_phase(cache, c, tid, phase)
		return true
	return false


func _on_minimap_clicked(uv: Vector2) -> void:
	if rts_camera == null:
		return
	var wx := lerpf(_cam_min.x, _cam_max.x, uv.x)
	# 小地图顶 = 北 = 较大 WC3.Y
	var wy := lerpf(_cam_max.y, _cam_min.y, uv.y)
	var world := Wc3Coords.wc3_xy_to_godot(wx, wy, 0.0)
	rts_camera.focus_on_position(world)
	if game_hud:
		game_hud.set_status("镜头 → (%.0f, %.0f)" % [wx, wy])


func _on_command_pressed(slot: int) -> void:
	if game_hud:
		game_hud.set_status("指令格 [%d]（训练/号召稍后接 Order）" % slot)


func _on_selection_changed(primary: Node3D, selected: Array) -> void:
	if game_hud == null:
		return
	if primary == null or selected.is_empty():
		game_hud.set_unit_info("—", 0, 0)
		game_hud.clear_command_labels()
		game_hud.set_status("未选中")
		return
	var d: Dictionary = primary.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "?"))
	var label := tid
	if selected.size() > 1:
		label = "%s ×%d" % [tid, selected.size()]
	game_hud.set_unit_info(label, 0, 0)
	if BuildingVisual.is_building(tid) and (tid == "htow" or tid == "hkee" or tid == "hcas"):
		game_hud.set_command_labels(
			PackedStringArray(["训练", "号召", "交资源", "", "", "", "", "", "", "", "", ""])
		)
		game_hud.set_status("主城已选 · 指令格为占位")
	else:
		game_hud.clear_command_labels()
		game_hud.set_status("已选 %s" % tid)
