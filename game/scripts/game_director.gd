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
var _command_router: CommandRouter = null
var _tree_registry: TreeRegistry = null
## 点了行动面板「移动」或热键 M 后，等待左键指定落点
var _move_targeting: bool = false
## 点了「采集」或热键 G 后，等待左键点金矿/树
var _harvest_targeting: bool = false
var _card_supports_move: bool = false
var _card_is_peasant: bool = false
var _last_move_executing: bool = false
var _last_harvest_ui: Dictionary = {}


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
	if game_hud.has_signal("command_action") and not game_hud.command_action.is_connected(_on_command_action):
		game_hud.command_action.connect(_on_command_action)


func _setup_selector() -> void:
	if unit_selector == null or rts_camera == null or map_root == null:
		push_warning("GameDirector: UnitSelector 绑定失败（selector/camera/map 为空）")
		return
	var cam := rts_camera.get_camera()
	var layer := map_root.get_unit_layer()
	if cam == null or layer == null:
		push_warning("GameDirector: UnitSelector.setup 跳过（camera=%s layer=%s）" % [cam, layer])
		return
	# 点选：中立金矿等仍可选；框选：仅己方（不可多选敌对/中立）
	unit_selector.set("owner_filter", -1)
	unit_selector.set("marquee_owner", local_player)
	if unit_selector.has_method("setup"):
		unit_selector.call("setup", cam, layer, null)
	# 原作：树不可左键选中；伐木只走右键智能命令
	unit_selector.pick_extra = Callable()
	if unit_selector.has_signal("selection_changed"):
		var sel_sig: Signal = unit_selector.selection_changed
		if not sel_sig.is_connected(_on_selection_changed):
			sel_sig.connect(_on_selection_changed)
	if game_hud:
		game_hud.set_status("点选就绪 · LMB 单位/金矿 · RMB 矿/树/移动")


func _input(event: InputEvent) -> void:
	# 运行时再解析一次：防止 ready 时序导致 selector 引用为空。
	if unit_selector == null:
		_resolve_exports()
	# 移动瞄准：左键必须在 _input 里下发并 marked handled。
	# UnitSelector 自带 _input / 全屏 gui 层，若不在此拦截，落点永远进不了 _unhandled_input。
	if _move_targeting and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# 瞄准态左键：必须在此下发（UnitSelector 会吃掉 _unhandled）。点完即退出瞄准。
			if _issue_move_at_screen(mb.position, UnitOrder.Source.TARGETING):
				_flash_cursor_move()
			_set_move_targeting(false)
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			# 瞄准态右键：取消瞄准（不另下智能指令，避免与「点一下取消」预期冲突）
			_set_move_targeting(false)
			get_viewport().set_input_as_handled()
			return
	# 采集瞄准：左键点金矿
	if _harvest_targeting and event is InputEventMouseButton:
		var mb_h := event as InputEventMouseButton
		if mb_h.pressed and mb_h.button_index == MOUSE_BUTTON_LEFT:
			_issue_harvest_at_screen(mb_h.position, UnitOrder.Source.TARGETING)
			_set_harvest_targeting(false)
			get_viewport().set_input_as_handled()
			return
		if mb_h.pressed and mb_h.button_index == MOUSE_BUTTON_RIGHT:
			_set_harvest_targeting(false)
			get_viewport().set_input_as_handled()
			return
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
	_setup_minimap()
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
	_command_router = CommandRouter.new()
	_command_router.configure(
		_path_query,
		_crowd_query,
		Callable(self, "_ensure_navigator"),
		Callable(self, "_ensure_harvest_controller")
	)
	_setup_tree_registry()
	_ensure_path_debug()


func _setup_minimap() -> void:
	if game_hud == null or map_root == null or rts_camera == null:
		return
	if not game_hud.has_method("configure_minimap"):
		return
	var cam := rts_camera.get_camera()
	game_hud.configure_minimap(
		map_dir,
		_heightfield,
		map_root.get_unit_layer(),
		cam,
		rts_camera,
		local_player
	)


func _setup_tree_registry() -> void:
	if map_root == null:
		return
	if _tree_registry == null or not is_instance_valid(_tree_registry):
		_tree_registry = TreeRegistry.new()
		_tree_registry.name = "TreeRegistry"
		add_child(_tree_registry)
	var cam: Camera3D = null
	if rts_camera != null:
		cam = rts_camera.get_camera()
	_tree_registry.configure(map_root, map_root.get_id_catalog(), cam)
	_tree_registry.rebuild_from_map()


func _tree_registry_ref() -> TreeRegistry:
	return _tree_registry


func _ensure_path_debug() -> void:
	if map_root == null:
		return
	if _path_debug != null and is_instance_valid(_path_debug):
		_path_debug.setup(_heightfield)
		_path_debug.set_enabled(show_path_debug)
		return
	_path_debug = PathDebugDraw.new()
	_path_debug.name = "PathDebugDraw"
	map_root.add_child(_path_debug)
	_path_debug.setup(_heightfield)
	_path_debug.set_enabled(show_path_debug)


func _process(_delta: float) -> void:
	_refresh_move_executing_ui()
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
	# 移动/采集瞄准：Esc 取消（落点已在 _input 处理）
	if (_move_targeting or _harvest_targeting) and event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_set_move_targeting(false)
			_set_harvest_targeting(false)
			get_viewport().set_input_as_handled()
			return
	# 右键智能命令优先于调试热键：金矿→采集，空地→移动。
	if enable_move_command and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _issue_smart_at_screen(mb.position, UnitOrder.Source.SMART_RMB):
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_S and enable_move_command:
			if _issue_stop(UnitOrder.Source.HOTKEY):
				get_viewport().set_input_as_handled()
				return
		if key == KEY_M and enable_move_command and _card_supports_move:
			_begin_move_targeting(UnitOrder.Source.HOTKEY)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_G and _card_is_peasant:
			_begin_harvest_targeting(UnitOrder.Source.HOTKEY)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_R and _card_is_peasant:
			if _issue_return_goods(UnitOrder.Source.HOTKEY):
				get_viewport().set_input_as_handled()
				return
		if key == KEY_F9:
			show_path_debug = not show_path_debug
			_ensure_path_debug()
			if _path_debug != null:
				_path_debug.set_enabled(show_path_debug)
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


## 选中单位立即停步并回 Stand。
func _issue_stop(source: int = UnitOrder.Source.UNKNOWN) -> bool:
	if _command_router == null or unit_selector == null:
		return false
	if not unit_selector.has_method("get_selected"):
		return false
	var selected: Array = unit_selector.call("get_selected")
	var n_stop := _command_router.issue_stop(selected, source)
	if n_stop > 0 and game_hud:
		game_hud.set_status("停止 · %d 单位" % n_stop)
	_refresh_command_card()
	return n_stop > 0


## 右键智能：识别 SmartTarget → CommandRouter.issue_smart（按单位能力匹配）。
func _issue_smart_at_screen(screen_pos: Vector2, source: int) -> bool:
	if unit_selector == null or _command_router == null:
		return false
	if not unit_selector.has_method("get_selected"):
		return false
	var selected: Array = unit_selector.call("get_selected")
	if selected.is_empty():
		return false
	var target := _resolve_smart_target(screen_pos, selected)
	if target == null:
		if game_hud:
			game_hud.set_status("命令：未点到有效目标")
		return false
	var result := _command_router.issue_smart(selected, target, source)
	if not bool(result.get("ok", false)):
		return false
	_flash_cursor_move()
	var goal: Vector2 = result.get("goal_wc3", Vector2.INF)
	if int(result.get("moved", 0)) > 0 and goal != Vector2.INF:
		_spawn_move_confirm(goal)
	if game_hud:
		game_hud.set_status(_format_smart_status(result))
	_refresh_command_card()
	return true


## Present/输入：屏幕点 → SmartTarget；不在此按兵种分支下令。
func _resolve_smart_target(screen_pos: Vector2, selected: Array) -> SmartTarget:
	var ground_goal := _screen_to_goal_wc3(screen_pos)
	if unit_selector != null and unit_selector.has_method("pick_at"):
		var picked: Node3D = unit_selector.call("pick_at", screen_pos) as Node3D
		if picked != null and _is_gold_mine(picked):
			return SmartTarget.gold_mine(picked, _node_goal_wc3(picked, ground_goal))
		if picked != null and _is_own_dropoff_building(picked, selected):
			return SmartTarget.dropoff(picked, _node_goal_wc3(picked, ground_goal))
	if _tree_registry != null:
		var cn := _tree_registry.pick_cn_at_screen(screen_pos)
		if cn >= 0:
			var tree_goal := _tree_registry.get_pos_wc3(cn)
			if tree_goal == Vector2.INF:
				tree_goal = ground_goal
			return SmartTarget.tree(cn, tree_goal)
	if ground_goal == Vector2.INF:
		return null
	return SmartTarget.ground(ground_goal)


func _screen_to_goal_wc3(screen_pos: Vector2) -> Vector2:
	var hit := _ground_at_screen(screen_pos)
	if hit == Vector3.INF:
		return Vector2.INF
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	return Vector2(hit.x * inv, -hit.z * inv)


func _node_goal_wc3(node: Node3D, fallback: Vector2) -> Vector2:
	if node == null or not is_instance_valid(node):
		return fallback
	return Wc3Coords.godot_to_wc3_xy(node.global_position)


func _is_own_dropoff_building(building: Node3D, selected: Array) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	var bd: Dictionary = building.get_meta("unit_data", {})
	var tid := str(bd.get("typeId", "")).strip_edges()
	if ReceiveResources.capability_for_type(tid) == int(ReceiveResources.Kind.NONE):
		return false
	var b_owner := int(bd.get("owner", -1))
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var ud: Dictionary = (n as Node).get_meta("unit_data", {})
		if int(ud.get("owner", -2)) == b_owner:
			return true
	return false


func _format_smart_status(result: Dictionary) -> String:
	var harvested := int(result.get("harvested", 0))
	var returned := int(result.get("returned", 0))
	var moved := int(result.get("moved", 0))
	var kind := str(result.get("kind", ""))
	match kind:
		"GoldMine":
			if harvested > 0 and moved > 0:
				return "智能 · 采金 %d · 移动 %d" % [harvested, moved]
			if harvested > 0:
				return "采集金币 · %d 单位" % harvested
		"Tree":
			if harvested > 0 and moved > 0:
				return "智能 · 伐木 %d · 移动 %d" % [harvested, moved]
			if harvested > 0:
				return "采集木材 · %d 单位" % harvested
		"Dropoff":
			if returned > 0 and moved > 0:
				return "智能 · 送回 %d · 移动 %d" % [returned, moved]
			if returned > 0:
				return "送回资源 · %d 单位" % returned
	var goal: Vector2 = result.get("goal_wc3", Vector2.INF)
	if moved > 0 and goal != Vector2.INF:
		return "移动 → (%.0f, %.0f) · %d 单位" % [goal.x, goal.y, moved]
	if int(result.get("failed", 0)) > 0 and goal != Vector2.INF:
		return "无法到达 (%.0f, %.0f)" % [goal.x, goal.y]
	return "智能 · %s" % kind


## 对当前选中可移动单位下发移动（经 CommandRouter）。
func _issue_move_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _command_router == null or unit_selector == null or _path_query == null:
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
	var result := _command_router.issue_move_to_wc3(selected, goal_center, source)
	var moved: int = int(result.get("moved", 0))
	var failed: int = int(result.get("failed", 0))
	if moved > 0:
		_spawn_move_confirm(goal_center)
	if game_hud:
		if moved > 0:
			game_hud.set_status(
				"移动 → (%.0f, %.0f) · %d 单位（已散开落点）" % [goal_center.x, goal_center.y, moved]
			)
		elif failed > 0:
			game_hud.set_status("无法到达 (%.0f, %.0f)" % [goal_center.x, goal_center.y])
		elif _command_router.filter_movers(selected).is_empty():
			game_hud.set_status("选中无可用移动单位（建筑？）")
	_refresh_command_card()
	return moved > 0 or failed > 0


func _issue_harvest_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _command_router == null or unit_selector == null:
		return false
	if not unit_selector.has_method("get_selected"):
		return false
	var selected: Array = unit_selector.call("get_selected")
	var peasants := _command_router.filter_peasants(selected)
	if peasants.is_empty():
		if game_hud:
			game_hud.set_status("采集：无农民")
		return false
	if unit_selector.has_method("pick_at"):
		var picked: Node3D = unit_selector.call("pick_at", screen_pos) as Node3D
		if picked != null and _is_gold_mine(picked):
			var n := _command_router.issue_harvest_gold(peasants, picked, source)
			if n > 0 and game_hud:
				game_hud.set_status("采集金币 · %d 农民" % n)
			_refresh_command_card()
			return n > 0
		if picked != null and _is_harvestable_tree_node(picked):
			var cn := _tree_cn_of(picked)
			if cn >= 0:
				var nl := _command_router.issue_harvest_lumber(peasants, cn, source)
				if nl > 0 and game_hud:
					game_hud.set_status("采集木材 · %d 农民" % nl)
				_refresh_command_card()
				return nl > 0
	if _tree_registry != null:
		var cn2 := _tree_registry.pick_cn_at_screen(screen_pos)
		if cn2 >= 0:
			var nl2 := _command_router.issue_harvest_lumber(peasants, cn2, source)
			if nl2 > 0 and game_hud:
				game_hud.set_status("采集木材 · %d 农民" % nl2)
			_refresh_command_card()
			return nl2 > 0
	if game_hud:
		game_hud.set_status("采集：请点金矿或树木")
	return false


func _issue_return_goods(source: int = UnitOrder.Source.UNKNOWN) -> bool:
	if _command_router == null or unit_selector == null:
		return false
	if not unit_selector.has_method("get_selected"):
		return false
	var selected: Array = unit_selector.call("get_selected")
	var n := _command_router.issue_return_goods(selected, source)
	if n > 0 and game_hud:
		game_hud.set_status("送回资源 · %d 农民" % n)
	elif game_hud:
		game_hud.set_status("送回：无负重农民")
	_refresh_command_card()
	return n > 0


func _begin_move_targeting(source: int) -> void:
	if unit_selector == null or not unit_selector.has_method("get_selected"):
		return
	var selected: Array = unit_selector.call("get_selected")
	if _command_router == null or _command_router.filter_movers(selected).is_empty():
		if game_hud:
			game_hud.set_status("移动：无可用单位")
		return
	_set_harvest_targeting(false)
	_set_move_targeting(true)
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键 M"
		game_hud.set_status("移动瞄准（%s）· 左键指定地点 · Esc 取消" % src)


func _begin_harvest_targeting(source: int) -> void:
	if unit_selector == null or not unit_selector.has_method("get_selected"):
		return
	var selected: Array = unit_selector.call("get_selected")
	if _command_router == null or _command_router.filter_peasants(selected).is_empty():
		if game_hud:
			game_hud.set_status("采集：无农民")
		return
	# 已有负金：面板若显示交回则不会进此；若空手瞄准
	_set_move_targeting(false)
	_set_harvest_targeting(true)
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键 G"
		game_hud.set_status("采集瞄准（%s）· 左键点金矿 · Esc 取消" % src)


func _set_move_targeting(active: bool) -> void:
	_move_targeting = active
	_sync_selector_enabled_for_targeting()
	if game_cursor != null and game_cursor.has_method("set_move_targeting"):
		game_cursor.call("set_move_targeting", active)
	elif game_cursor != null and game_cursor.has_method("set_mode"):
		game_cursor.call(
			"set_mode",
			Wc3GameCursor.Mode.MOVE if active else Wc3GameCursor.Mode.IDLE
		)


func _set_harvest_targeting(active: bool) -> void:
	_harvest_targeting = active
	_sync_selector_enabled_for_targeting()
	if game_cursor != null and game_cursor.has_method("set_move_targeting"):
		# 暂复用移动瞄准光标；后续可换采集专用
		game_cursor.call("set_move_targeting", active)


func _sync_selector_enabled_for_targeting() -> void:
	if unit_selector == null:
		return
	# 任一瞄准态都关掉点选，避免抢左键
	unit_selector.enabled = not (_move_targeting or _harvest_targeting)


func _flash_cursor_move() -> void:
	if game_cursor != null and game_cursor.has_method("flash_move"):
		game_cursor.call("flash_move")


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
		_wire_navigator_signals(existing)
		return existing
	var nav := UnitNavigator.new()
	nav.name = "UnitNavigator"
	# 先 configure 再进树：即使 _ready 延后，query 也已就绪。
	nav.configure(_path_query, _heightfield, _crowd_query, _cell_reservation)
	nav.set_visual(visual)
	_apply_move_stats(unit, nav)
	unit.add_child(nav)
	_wire_navigator_signals(nav)
	return nav


func _ensure_harvest_controller(unit: Node3D) -> HarvestController:
	_ensure_unit_visual(unit)
	var existing := unit.get_node_or_null("HarvestController") as HarvestController
	if existing != null:
		existing.configure(
			Callable(self, "_ensure_navigator"),
			Callable(self, "_local_stock"),
			Callable(self, "_unit_host"),
			Callable(self, "_path_query_ref"),
			Callable(self, "_crowd_query_ref"),
			Callable(self, "_tree_registry_ref")
		)
		_wire_harvest_signals(existing)
		return existing
	var hc := HarvestController.new()
	hc.name = "HarvestController"
	hc.configure(
		Callable(self, "_ensure_navigator"),
		Callable(self, "_local_stock"),
		Callable(self, "_unit_host"),
		Callable(self, "_path_query_ref"),
		Callable(self, "_crowd_query_ref"),
		Callable(self, "_tree_registry_ref")
	)
	unit.add_child(hc)
	_wire_harvest_signals(hc)
	return hc


func _local_stock() -> PlayerStock:
	if _session == null:
		return null
	return _session.local_stock()


func _unit_host() -> Node:
	if map_root == null:
		return null
	return map_root.get_unit_layer()


func _path_query_ref() -> PathQuery:
	return _path_query


func _crowd_query_ref() -> UnitCrowdQuery:
	return _crowd_query


func _wire_harvest_signals(hc: HarvestController) -> void:
	if hc == null:
		return
	if not hc.carry_changed.is_connected(_on_harvest_carry_changed):
		hc.carry_changed.connect(_on_harvest_carry_changed)
	if not hc.deposited.is_connected(_on_harvest_deposited):
		hc.deposited.connect(_on_harvest_deposited)
	if not hc.state_changed.is_connected(_on_harvest_state_changed):
		hc.state_changed.connect(_on_harvest_state_changed)
	if hc.has_signal("entered_unselectable") and not hc.entered_unselectable.is_connected(
		_on_harvest_entered_unselectable
	):
		hc.entered_unselectable.connect(_on_harvest_entered_unselectable)


func _on_harvest_carry_changed(_resource_id: String, _amount: int) -> void:
	_refresh_command_card()


func _on_harvest_deposited(gold: int, lumber: int) -> void:
	if game_hud:
		if gold > 0:
			game_hud.set_status("交货 +%d 金" % gold)
		elif lumber > 0:
			game_hud.set_status("交货 +%d 木" % lumber)
	_refresh_command_card()


func _on_harvest_state_changed(_state: int) -> void:
	_refresh_command_card()


func _on_harvest_entered_unselectable(unit: Node3D) -> void:
	if unit == null or unit_selector == null:
		return
	if unit_selector.has_method("deselect_unit"):
		unit_selector.call("deselect_unit", unit)


func _is_harvestable_tree_node(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var dd: Dictionary = node.get_meta("doodad_data", {})
	if dd.is_empty():
		return false
	var cn := int(dd.get("creationNumber", -1))
	if cn < 0 or _tree_registry == null:
		return false
	return _tree_registry.is_alive(cn)


func _tree_cn_of(node: Node) -> int:
	if node == null:
		return -1
	var dd: Dictionary = node.get_meta("doodad_data", {})
	return int(dd.get("creationNumber", -1))


static func _is_gold_mine(node: Node) -> bool:
	if node == null:
		return false
	var d: Dictionary = node.get_meta("unit_data", {})
	return str(d.get("typeId", "")).strip_edges() == HarvestController.GOLD_MINE_TYPE


func _wire_navigator_signals(nav: UnitNavigator) -> void:
	if nav == null:
		return
	if not nav.locomotion_changed.is_connected(_on_unit_locomotion_changed):
		nav.locomotion_changed.connect(_on_unit_locomotion_changed)


func _on_unit_locomotion_changed(_moving: bool) -> void:
	_refresh_move_executing_ui()


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
	# 农民 soft 分离略放大，减轻采金/伐木叠人（不改 UnitBalance.collision 权威值）
	if tid == HarvestController.WORKER_PEASANT:
		nav.separation_radius_mul = 1.45

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
	var world: Vector3
	if _heightfield != null and _heightfield.is_valid():
		world = MapMinimapUtils.minimap_uv_to_world(uv, _heightfield, 0.0)
	else:
		var wx := lerpf(_cam_min.x, _cam_max.x, uv.x)
		var wy := lerpf(_cam_max.y, _cam_min.y, uv.y)
		world = Wc3Coords.wc3_xy_to_godot(wx, wy, 0.0)
	rts_camera.focus_on_position(world)
	if game_hud:
		var inv := 1.0 / Wc3Coords.WORLD_SCALE
		game_hud.set_status(
			"镜头 → (%.0f, %.0f)" % [world.x * inv, -world.z * inv]
		)


func _on_command_pressed(slot: int) -> void:
	# 有 action_id 时由 _on_command_action 处理；纯文字占位格仍提示
	if game_hud != null and game_hud.has_method("set_status"):
		pass


func _on_command_action(action_id: String) -> void:
	match action_id:
		CommandCard.ACTION_MOVE:
			_begin_move_targeting(UnitOrder.Source.PANEL)
		CommandCard.ACTION_STOP:
			_issue_stop(UnitOrder.Source.PANEL)
		CommandCard.ACTION_HARVEST_GOLD:
			_begin_harvest_targeting(UnitOrder.Source.PANEL)
		CommandCard.ACTION_RETURN_GOODS:
			_issue_return_goods(UnitOrder.Source.PANEL)
		_:
			if game_hud:
				game_hud.set_status("指令：%s（未实现）" % action_id)


func _on_selection_changed(primary: Node3D, selected: Array) -> void:
	_set_move_targeting(false)
	_set_harvest_targeting(false)
	if game_hud == null:
		return
	if primary == null or selected.is_empty():
		_card_supports_move = false
		_card_is_peasant = false
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
	# 中立金矿：黄环 + 储量状态（树不可左键选中）
	if tid == "ngol" or _is_gold_mine(primary):
		_card_supports_move = false
		_card_is_peasant = false
		game_hud.clear_command_labels()
		var gold_left := int(d.get("goldAmount", -1))
		var rt := GoldMineRuntime.ensure(primary)
		if rt != null:
			gold_left = rt.remaining_gold
		elif gold_left < 0:
			gold_left = 12500
		# Info 区无 HP 槽时只显示名称；储量走 status
		game_hud.set_unit_info("金矿", 0, 0)
		game_hud.set_status("金矿 · 剩余 %d 金" % gold_left)
		return
	if BuildingVisual.is_building(tid) and (tid == "htow" or tid == "hkee" or tid == "hcas"):
		_card_supports_move = false
		_card_is_peasant = false
		game_hud.set_command_labels(
			PackedStringArray(["训练", "号召", "交资源", "", "", "", "", "", "", "", "", ""])
		)
		game_hud.set_status("主城已选 · 具备接收资源能力")
	elif _command_router != null and not _command_router.filter_movers(selected).is_empty():
		_card_supports_move = true
		_refresh_command_card()
		if _card_is_peasant:
			game_hud.set_status("已选 %s · M移动 · S停止 · G采集 / R交回" % tid)
		else:
			game_hud.set_status("已选 %s · M 移动 · S 停止" % tid)
	else:
		_card_supports_move = false
		_card_is_peasant = false
		game_hud.clear_command_labels()
		game_hud.set_status("已选 %s" % tid)


func _refresh_command_card() -> void:
	if game_hud == null or not _card_supports_move or unit_selector == null:
		return
	if not unit_selector.has_method("get_selected"):
		return
	var selected: Array = unit_selector.call("get_selected")
	var moving := false
	var carrying := false
	var harvesting := false
	var returning := false
	if _command_router != null:
		moving = _command_router.any_moving(selected)
		var peasants := _command_router.filter_peasants(selected)
		var movers := _command_router.filter_movers(selected)
		_card_is_peasant = (
			not peasants.is_empty() and peasants.size() == movers.size()
		)
		if _card_is_peasant:
			carrying = _command_router.any_carrying(peasants)
			harvesting = _command_router.any_harvesting(peasants)
			returning = _command_router.any_returning(peasants)
	else:
		_card_is_peasant = false
	_last_move_executing = moving
	_last_harvest_ui = {
		"peasant": _card_is_peasant,
		"carrying": carrying,
		"harvesting": harvesting,
		"returning": returning,
		"moving": moving,
	}
	if _card_is_peasant:
		game_hud.set_command_card(
			CommandCard.peasant(moving, carrying, harvesting and not carrying, returning)
		)
	else:
		game_hud.set_command_card(CommandCard.basic_locomotion(moving))


func _refresh_move_executing_ui() -> void:
	if not _card_supports_move or game_hud == null or unit_selector == null:
		return
	if not unit_selector.has_method("get_selected"):
		return
	var selected: Array = unit_selector.call("get_selected")
	var moving := false
	var carrying := false
	var harvesting := false
	var returning := false
	var is_peasant := _card_is_peasant
	if _command_router != null:
		moving = _command_router.any_moving(selected)
		if is_peasant:
			var peasants := _command_router.filter_peasants(selected)
			carrying = _command_router.any_carrying(peasants)
			harvesting = _command_router.any_harvesting(peasants)
			returning = _command_router.any_returning(peasants)
	var snap := {
		"peasant": is_peasant,
		"carrying": carrying,
		"harvesting": harvesting,
		"returning": returning,
		"moving": moving,
	}
	if snap == _last_harvest_ui and moving == _last_move_executing:
		return
	_last_move_executing = moving
	_last_harvest_ui = snap
	# 互斥格可能从采集切到交回，需整卡刷新
	if is_peasant:
		game_hud.set_command_card(
			CommandCard.peasant(moving, carrying, harvesting and not carrying, returning)
		)
	else:
		game_hud.set_command_executing(CommandCard.ACTION_MOVE, moving)
