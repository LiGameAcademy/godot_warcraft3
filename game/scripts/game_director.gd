class_name GameDirector
extends Node

## 游戏总管（对标 MapEditor）。
## 职责：配置 MapLoader、Melee 开局、Session/库存、选中、相机。

## 地图装配 + Melee/寻路/小地图 bootstrap 完成（Loading 屏可据此淡出）
signal session_ready

## 场景实例仍需 preload；脚本类一律用 class_name。
const MoveConfirmFxScene = preload("res://game/scenes/move_confirm_fx.tscn")

@export var map_root: MapLoader
@export var rts_camera: RtsCamera
@export var game_hud: GameHud
@export var unit_selector: Node
@export var game_cursor: Node
@export var health_bar_manager: HealthBarManager
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
var _pathing: Wc3PathingMap = null
var _heightfield: Wc3Heightfield = null
## 邻近单位查询（soft 分离）；与 PathQuery 一样地图就绪后绑定。
var _crowd_query: UnitCrowdQuery = null
var _cell_reservation: PathCellReservation = null
var _path_debug: PathDebugDraw = null
var _command_router: CommandRouter = null
var _damage_pipeline: DamagePipeline = null
var _death_service: DeathService = null
var _tree_registry: TreeRegistry = null
## 点了行动面板「移动」或热键 M 后，等待左键指定落点
var _move_targeting: bool = false
## 攻击瞄准：左键单位=Attack，地面=Attack-Move
var _attack_targeting: bool = false
## 巡逻瞄准：左键指定另一端点
var _patrol_targeting: bool = false
## 点了「采集」或热键 G 后，等待左键点金矿/树
var _harvest_targeting: bool = false
## 点了「集结点」后，等待左键指定地点/矿/树
var _rally_targeting: bool = false
## 选中可训建筑时显示的集结旗（长驻，复用）
var _rally_flag: RallyFlagFx = null
var _card_supports_move: bool = false
var _card_is_peasant: bool = false
var _last_move_executing: bool = false
var _last_harvest_ui: Dictionary = {}
## 当前命令卡：keycode → action_id（热键走 Catalog，不写死 M/G/R…）
var _card_hotkey_actions: Dictionary = {}
## 农民建造二级面板是否打开（主卡仅 AHbu 入口）。
var _build_menu_open: bool = false

## F2-4：建造瞄准态（玩家按下建造按钮后进入）。
var _build_placement: BuildPlacementController = null
var _build_ghost: BuildPlacementGhost = null
## 确认落点后、开工前：工地半透明幽灵仍钉在地上（农民走动期间）。
var _site_ghost_pinned: bool = false
## 进入瞄准后须先移动鼠标再左键确认，避免点面板同一帧误提交。
var _build_confirm_armed: bool = false
## 鼠标 → godot 拾取（暴露给 Placement 控制器，避开循环引用）。
var _last_screen_pos: Vector2 = Vector2.ZERO
## 运行时自增 creationNumber（建造半成品等）。
var _next_runtime_cn: int = 900000
## construction_key → { cn, node, building_id, site }
var _active_construction: Dictionary = {}
## 当前 HUD 绑定的工地 progress（避免重复 connect）。
var _hud_build_site: BuildSite = null
## 工地宿主（农民离开后 BuildSite 挂于此）
var _build_sites_host: Node = null
## building Node3D instance_id → BuildSite
var _build_site_by_building: Dictionary = {}
## "%s_x_y" → BuildSite
var _build_site_by_key: Dictionary = {}
## 已接线的 TrainQueue instance_id（避免重复 connect）
var _wired_train_queues: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	AppLog.reload_config()
	_resolve_exports()
	if map_root == null:
		push_error("GameDirector: 未绑定 map_root")
		return
	_configure_map_root()
	_ensure_gm_panel()
	_wire_hud()
	_load_camera_bounds()
	_configure_camera()
	if map_root.map_loaded.is_connected(_on_map_loaded) == false:
		map_root.map_loaded.connect(_on_map_loaded)
	if map_root.is_map_ready():
		_on_map_loaded()


var _gm_panel: CanvasLayer = null


func _ensure_gm_panel() -> void:
	var parent_n := get_parent()
	if parent_n == null:
		return
	if _gm_panel != null and is_instance_valid(_gm_panel):
		return
	var existing := parent_n.get_node_or_null("GmDebugPanel") as CanvasLayer
	if existing != null:
		_gm_panel = existing
		return
	var gm: CanvasLayer = GmDebugPanel.new()
	gm.name = "GmDebugPanel"
	_gm_panel = gm
	# _ready 期间父节点 blocked，必须延迟挂接
	parent_n.add_child.call_deferred(gm)


func _toggle_gm_panel() -> void:
	_ensure_gm_panel()
	if _gm_panel == null or not is_instance_valid(_gm_panel):
		return
	if not _gm_panel.is_inside_tree():
		# 仍在 deferred 队列：进树后再开
		_gm_panel.call_deferred("set_open", true)
	elif _gm_panel.has_method("toggle"):
		_gm_panel.call("toggle")
	if game_hud != null and _gm_panel.is_inside_tree():
		game_hud.set_status("GM 面板：%s（` / F4）" % ("开" if _gm_panel.visible else "关"))


func _apply_path_debug_visibility() -> void:
	if _path_debug != null:
		_path_debug.set_enabled(show_path_debug)


func get_session() -> GameSession:
	return _session


func is_session_ready() -> bool:
	return _bootstrapped


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
	if health_bar_manager == null:
		health_bar_manager = get_node_or_null("../HealthBarManager") as HealthBarManager
		if health_bar_manager == null and parent_n != null:
			health_bar_manager = parent_n.get_node_or_null("HealthBarManager") as HealthBarManager
	print(
		"[GameDirector] bind map=%s cam=%s hud=%s sel=%s cursor=%s hpbar=%s"
		% [
			map_root != null,
			rts_camera != null,
			game_hud != null,
			unit_selector != null,
			game_cursor != null,
			health_bar_manager != null,
		]
	)


func _configure_map_root() -> void:
	if not map_dir.is_empty():
		map_root.map_dir = map_dir
	map_root.place_doodads = true
	map_root.place_units = true
	map_root.show_start_locations = false
	map_root.show_drop_rings = false
	map_root.show_editor_helpers = false
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
	if game_hud.has_signal("multi_select_clicked") and not game_hud.multi_select_clicked.is_connected(_on_multi_select_clicked):
		game_hud.multi_select_clicked.connect(_on_multi_select_clicked)
	if game_hud.has_signal("train_queue_cancel") and not game_hud.train_queue_cancel.is_connected(_on_train_queue_cancel):
		game_hud.train_queue_cancel.connect(_on_train_queue_cancel)


func _setup_portrait_hud() -> void:
	if game_hud == null or map_root == null:
		return
	if not game_hud.has_method("configure_portrait"):
		return
	var cache = map_root.get_model_cache() if map_root.has_method("get_model_cache") else null
	var catalog = map_root.get_id_catalog() if map_root.has_method("get_id_catalog") else null
	game_hud.configure_portrait(cache, catalog)


func _on_multi_select_clicked(instance_id: int) -> void:
	if unit_selector == null or instance_id == 0:
		return
	var obj := instance_from_id(instance_id)
	if obj is Node3D:
		unit_selector.set_primary(obj as Node3D)


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
	if _attack_targeting and event is InputEventMouseButton:
		var mb_a := event as InputEventMouseButton
		if mb_a.pressed and mb_a.button_index == MOUSE_BUTTON_LEFT:
			_issue_attack_at_screen(mb_a.position, UnitOrder.Source.TARGETING)
			_set_attack_targeting(false)
			get_viewport().set_input_as_handled()
			return
		if mb_a.pressed and mb_a.button_index == MOUSE_BUTTON_RIGHT:
			_set_attack_targeting(false)
			get_viewport().set_input_as_handled()
			return
	if _patrol_targeting and event is InputEventMouseButton:
		var mb_p := event as InputEventMouseButton
		if mb_p.pressed and mb_p.button_index == MOUSE_BUTTON_LEFT:
			if _issue_patrol_at_screen(mb_p.position, UnitOrder.Source.TARGETING):
				_flash_cursor_move()
			_set_patrol_targeting(false)
			get_viewport().set_input_as_handled()
			return
		if mb_p.pressed and mb_p.button_index == MOUSE_BUTTON_RIGHT:
			_set_patrol_targeting(false)
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
	# 集结瞄准：左键设点（地面/金矿/树）
	if _rally_targeting and event is InputEventMouseButton:
		var mb_r := event as InputEventMouseButton
		if mb_r.pressed and mb_r.button_index == MOUSE_BUTTON_LEFT:
			_issue_set_rally_at_screen(mb_r.position, UnitOrder.Source.TARGETING)
			_set_rally_targeting(false)
			get_viewport().set_input_as_handled()
			return
		if mb_r.pressed and mb_r.button_index == MOUSE_BUTTON_RIGHT:
			_set_rally_targeting(false)
			get_viewport().set_input_as_handled()
			return
	# F2-4：建造瞄准 → 左键 commit / 右键 cancel / mousemove 跟手 ghost
	# 任何鼠标事件都记录最新位置，给 build_placement 跟手用
	if event is InputEventMouseMotion:
		_last_screen_pos = (event as InputEventMouseMotion).position
		if _build_placement != null and _build_placement.is_active():
			_build_confirm_armed = true
			_build_placement.update_screen(_last_screen_pos)
			_apply_ghost_to_screen()
	if _build_placement != null and _build_placement.is_active() and event is InputEventMouseButton:
		var mb_b := event as InputEventMouseButton
		if mb_b.pressed and mb_b.button_index == MOUSE_BUTTON_LEFT:
			# 点在 HUD/小地图上不提交；须先移动过鼠标再确认
			if not _build_confirm_armed or _pointer_over_blocking_gui():
				get_viewport().set_input_as_handled()
				return
			_commit_build_targeting(mb_b.position)
			get_viewport().set_input_as_handled()
			return
		if mb_b.pressed and mb_b.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_build_targeting()
			get_viewport().set_input_as_handled()
			return
	if unit_selector != null and unit_selector.has_method("handle_pointer_event"):
		if bool(unit_selector.call("handle_pointer_event", event)):
			get_viewport().set_input_as_handled()


func _map_display_name() -> String:
	var data := RuntimeAssets.read_json_dict(map_dir.path_join("info.json"))
	if not data.is_empty():
		var n := str(data.get("name", "")).strip_edges()
		if not n.is_empty():
			return n
	return map_dir.get_file()


func _load_camera_bounds() -> void:
	var data := RuntimeAssets.read_json_dict(map_dir.path_join("info.json"))
	if data.is_empty():
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
	_setup_portrait_hud()
	_setup_health_bars()
	# 地形材质已就绪后再刷调试栅格，避免 ready 阶段空材质警告
	if map_root != null:
		map_root.set_view_grid_level(view_grid_level)
	session_ready.emit()


func _setup_health_bars() -> void:
	if health_bar_manager == null:
		_resolve_exports()
	if health_bar_manager == null or map_root == null or rts_camera == null:
		return
	var cam := rts_camera.get_camera()
	health_bar_manager.configure(cam, map_root.get_unit_layer())
	health_bar_manager.resync()


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
	_pathing = map_root.get_pathing_map() if map_root != null else null
	_crowd_query = UnitCrowdQuery.new()
	_crowd_query.configure(
		map_root.get_unit_layer(),
		map_root.get_id_catalog()
	)
	_command_router = CommandRouter.new()
	_death_service = DeathService.new()
	_death_service.on_before_exit = Callable(self, "_on_unit_dying")
	_damage_pipeline = DamagePipeline.new()
	_damage_pipeline.death = _death_service
	_ensure_build_sites_host()
	_command_router.configure(
		_path_query,
		_crowd_query,
		Callable(self, "_ensure_navigator"),
		Callable(self, "_ensure_harvest_controller"),
		Callable(self, "_ensure_build_controller"),
		_session,
		Callable(self, "_find_build_site"),
		Callable(self, "_find_build_site_by_node"),
		Callable(self, "_ensure_attack_controller")
	)
	_setup_tree_registry()
	_ensure_path_debug()


func _ensure_build_sites_host() -> void:
	if _build_sites_host != null and is_instance_valid(_build_sites_host):
		return
	var host := Node.new()
	host.name = "BuildSitesHost"
	host.add_to_group("build_sites_host")
	add_child(host)
	_build_sites_host = host


func _find_build_site(site_wc3: Vector2, building_id: String) -> BuildSite:
	var key := _site_lookup_key(building_id, site_wc3)
	var site: BuildSite = _build_site_by_key.get(key) as BuildSite
	if site != null and is_instance_valid(site) and site.is_active():
		return site
	return null


func _find_build_site_by_node(building_node: Node3D) -> BuildSite:
	if building_node == null or not is_instance_valid(building_node):
		return null
	var site: BuildSite = _build_site_by_building.get(building_node.get_instance_id()) as BuildSite
	if site != null and is_instance_valid(site) and site.is_active():
		return site
	# 回退：用 unit_data 坐标查
	var d: Dictionary = building_node.get_meta("unit_data", {})
	var bid := str(d.get("typeId", ""))
	var pos: Dictionary = d.get("position", {})
	return _find_build_site(Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0))), bid)


func _site_lookup_key(building_id: String, site_wc3: Vector2) -> String:
	return "%s_%.0f_%.0f" % [building_id, site_wc3.x, site_wc3.y]


func _register_build_site(site: BuildSite, building_node: Node3D, order: BuildOrder) -> void:
	if site == null or order == null:
		return
	var key := _site_lookup_key(order.building_id, order.site_wc3)
	_build_site_by_key[key] = site
	if building_node != null and is_instance_valid(building_node):
		_build_site_by_building[building_node.get_instance_id()] = site
	if not site.build_completed.is_connected(_on_registered_site_completed):
		site.build_completed.connect(_on_registered_site_completed)


func _unregister_build_site(order: BuildOrder, building_node: Node3D = null) -> void:
	if order == null:
		return
	var key := _site_lookup_key(order.building_id, order.site_wc3)
	var site: BuildSite = _build_site_by_key.get(key) as BuildSite
	_build_site_by_key.erase(key)
	if building_node != null and is_instance_valid(building_node):
		_build_site_by_building.erase(building_node.get_instance_id())
	if site != null and is_instance_valid(site):
		if site.build_completed.is_connected(_on_registered_site_completed):
			site.build_completed.disconnect(_on_registered_site_completed)
		# 已 reparent 到 host 的工地需释放；仍挂在农民下的由 BuildController 释放
		if _build_sites_host != null and site.get_parent() == _build_sites_host:
			site.queue_free()


func _on_registered_site_completed(order: BuildOrder, site_wc3: Vector2, player_owner: int) -> void:
	# 农民已离开时由 Director 收尾；若 BuildController 仍会 emit，二次调用安全
	_on_build_completed(order, site_wc3, player_owner)

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
		local_player,
		map_root.get_id_catalog()
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

	# 开局刷兵后立刻同步动态 pathing（与叠层一致），避免瞄准时漏检脚印
	_pathing = map_root.get_pathing_map() if map_root != null else null
	_refresh_dynamic_pathing()


func _find_sloc_for_owner(slocs: Array[Dictionary], owner_id: int) -> Dictionary:
	for s in slocs:
		if int(s.get("owner", -1)) == owner_id:
			return s
	return {}


func _unhandled_input(event: InputEvent) -> void:
	# 移动/采集/建造瞄准：Esc 取消（落点已在 _input 处理）
	if (
		(
			_move_targeting
			or _attack_targeting
			or _patrol_targeting
			or _harvest_targeting
			or _rally_targeting
			or _is_build_targeting()
		)
		and event is InputEventKey
		and event.pressed
		and not event.echo
	):
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_set_move_targeting(false)
			_set_attack_targeting(false)
			_set_patrol_targeting(false)
			_set_harvest_targeting(false)
			_set_rally_targeting(false)
			if _is_build_targeting():
				_cancel_build_targeting()
			get_viewport().set_input_as_handled()
			return
	# 建造二级面板：Esc → 回主卡
	if (
		_build_menu_open
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and (event as InputEventKey).keycode == KEY_ESCAPE
	):
		_set_build_menu_open(false)
		get_viewport().set_input_as_handled()
		return
	# 右键智能：解析目标 → CommandRouter.issue_smart（能力优先级：采集/送回/建造 → 集结 → 移动）。
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mb.shift_pressed and enable_move_command:
				if _issue_group_move_command(mb.position, FormationFollow.FORMATION_RECT):
					get_viewport().set_input_as_handled()
					return
			if _issue_smart_at_screen(mb.position, UnitOrder.Source.SMART_RMB):
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and event.pressed and not event.echo:
		var ek := event as InputEventKey
		var key := ek.keycode
		var phys := ek.physical_keycode
		# 多选：Tab / Shift+Tab 切换当前选中（肖像 + 命令卡）
		if key == KEY_TAB or phys == KEY_TAB:
			if unit_selector != null and unit_selector.has_method("cycle_primary"):
				var step := -1 if ek.shift_pressed else 1
				if unit_selector.cycle_primary(step):
					get_viewport().set_input_as_handled()
					return
		# GM 面板：`（反引号）或 F4。F10 常被编辑器占用。
		if (
			key == KEY_QUOTELEFT
			or phys == KEY_QUOTELEFT
			or key == KEY_F4
			or phys == KEY_F4
		):
			_toggle_gm_panel()
			get_viewport().set_input_as_handled()
			return
		# 命令卡热键（Catalog Tip/Hotkey；交回官方为 E）
		if _card_hotkey_actions.has(key):
			_on_command_action(str(_card_hotkey_actions[key]), UnitOrder.Source.HOTKEY)
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


func _issue_hold(source: int = UnitOrder.Source.UNKNOWN) -> bool:
	if _command_router == null or unit_selector == null:
		return false
	if not unit_selector.has_method("get_selected"):
		return false
	var selected: Array = unit_selector.call("get_selected")
	var n := _command_router.issue_hold(selected, source)
	if n > 0 and game_hud:
		game_hud.set_status("保持原位 · %d 单位" % n)
	elif game_hud:
		game_hud.set_status("保持原位：无可用单位")
	_refresh_command_card()
	return n > 0


## 攻击瞄准落点：单位 → Attack（P0 追击）；地面 → Attack-Move。
func _issue_attack_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _command_router == null or unit_selector == null:
		return false
	if not unit_selector.has_method("get_selected"):
		return false
	var selected: Array = unit_selector.call("get_selected")
	if selected.is_empty():
		return false
	var picked: Node3D = null
	if unit_selector.has_method("pick_at"):
		picked = unit_selector.call("pick_at", screen_pos) as Node3D
	if picked != null and CombatQuery.any_can_attack(selected, picked):
		var n := _command_router.issue_attack_target(selected, picked, source)
		if game_hud:
			if n > 0:
				game_hud.set_status("攻击 · %d 单位" % n)
			else:
				game_hud.set_status("攻击：无合法目标")
		_refresh_command_card()
		return n > 0
	var hit := _ground_at_screen(screen_pos)
	if hit == Vector3.INF:
		if game_hud:
			game_hud.set_status("攻击：未点到地面或目标")
		return false
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var goal_center := Vector2(hit.x * inv, -hit.z * inv)
	var result := _command_router.issue_attack_move(selected, goal_center, source)
	var moved: int = int(result.get("moved", 0))
	if moved > 0:
		_spawn_move_confirm(goal_center, MoveConfirmFx.Kind.ATTACK)
	if game_hud:
		if moved > 0:
			game_hud.set_status(
				"攻击移动 → (%.0f, %.0f) · %d 单位" % [goal_center.x, goal_center.y, moved]
			)
		else:
			game_hud.set_status("攻击移动：无法到达")
	_refresh_command_card()
	return moved > 0


func _issue_patrol_at_screen(screen_pos: Vector2, source: int) -> bool:
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
			game_hud.set_status("巡逻：未点到地面")
		return false
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var goal_center := Vector2(hit.x * inv, -hit.z * inv)
	var result := _command_router.issue_patrol(selected, goal_center, source)
	var moved: int = int(result.get("moved", 0))
	if moved > 0:
		_spawn_move_confirm(goal_center)
	if game_hud:
		if moved > 0:
			game_hud.set_status(
				"巡逻 ↔ (%.0f, %.0f) · %d 单位" % [goal_center.x, goal_center.y, moved]
			)
		else:
			game_hud.set_status("巡逻：无法开始")
	_refresh_command_card()
	return moved > 0


## 右键智能：屏幕点 → SmartTarget → CommandRouter.issue_smart。
## 能力优先级在 Router 内：特殊交互 → 移动 → 集结（可并行）。
func _issue_smart_at_screen(screen_pos: Vector2, source: int) -> bool:
	if unit_selector == null or _command_router == null:
		return false
	if not unit_selector.has_method("get_selected"):
		return false
	var selected: Array = unit_selector.call("get_selected")
	if selected.is_empty():
		return false
	var target := _resolve_smart_target(screen_pos, selected)
	if target == null or target.goal_wc3 == Vector2.INF:
		if game_hud:
			game_hud.set_status("命令：未点到有效目标")
		return false
	var result := _command_router.issue_smart(selected, target, source)
	if not bool(result.get("ok", false)):
		# 仅选可训建筑却未写出集结时给明确提示（避免「右键无反应」）
		if _command_router != null and not _command_router.filter_rally_buildings(selected).is_empty():
			if game_hud:
				game_hud.set_status("集结点：未能设置（目标无效？）")
		return false
	var goal: Vector2 = result.get("goal_wc3", Vector2.INF)
	var moved := int(result.get("moved", 0))
	var rallied := int(result.get("rallied", 0))
	# 移动反馈与集结反馈分离：纯集结只出旗，不播移动确认箭/光标
	if moved > 0:
		_flash_cursor_move()
		if goal != Vector2.INF:
			_spawn_move_confirm(goal)
	if rallied > 0:
		_sync_rally_flag_for_selection()
	if game_hud:
		game_hud.set_status(_format_smart_status(result))
	_refresh_command_card()
	return true


## 对当前选中的可训建筑写入集结点。
func _issue_set_rally_at_screen(screen_pos: Vector2, source: int) -> bool:
	if unit_selector == null or not unit_selector.has_method("get_selected"):
		return false
	var selected: Array = unit_selector.call("get_selected")
	var buildings: Array[Node3D] = []
	for n in selected:
		if n is Node3D and BuildingRally.can_set_rally(n as Node3D):
			buildings.append(n as Node3D)
	if buildings.is_empty():
		return false
	var target := _resolve_smart_target(screen_pos, selected)
	if target == null or target.goal_wc3 == Vector2.INF:
		if game_hud:
			game_hud.set_status("集结点：未点到有效地点")
		return false
	for b in buildings:
		_apply_rally_from_smart(b, target)
	_sync_rally_flag_for_selection()
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL or source == UnitOrder.Source.TARGETING else "右键"
		match target.kind:
			SmartTarget.Kind.GOLD_MINE:
				game_hud.set_status("集结点 → 金矿（%s）" % src)
			SmartTarget.Kind.TREE:
				game_hud.set_status("集结点 → 树木（%s）" % src)
			_:
				game_hud.set_status(
					"集结点 → (%.0f, %.0f)（%s）" % [target.goal_wc3.x, target.goal_wc3.y, src]
				)
	return true


func _apply_rally_from_smart(building: Node3D, target: SmartTarget) -> void:
	if building == null or target == null:
		return
	match target.kind:
		SmartTarget.Kind.GOLD_MINE:
			BuildingRally.set_gold_mine(building, target.node, target.goal_wc3)
		SmartTarget.Kind.TREE:
			BuildingRally.set_tree(building, target.tree_cn, target.goal_wc3)
		_:
			BuildingRally.set_ground(building, target.goal_wc3)


## Present/输入：屏幕点 → SmartTarget；不在此按兵种分支下令。
## 拾取走 UnitSelector 脚底 2D 圆；送回点 / 工地另加脚底像素近距门槛。
const SMART_BUILDING_FOOT_PX := 40.0


func _resolve_smart_target(screen_pos: Vector2, selected: Array) -> SmartTarget:
	var ground_goal := _screen_to_goal_wc3(screen_pos)
	var best: SmartTarget = null
	var best_score := INF

	var picked: Node3D = null
	if unit_selector != null and unit_selector.has_method("pick_at"):
		picked = unit_selector.call("pick_at", screen_pos) as Node3D

	if picked != null and _is_gold_mine(picked):
		var s := _screen_score_node(picked, screen_pos)
		if s < best_score:
			best_score = s
			best = SmartTarget.gold_mine(picked, _node_goal_wc3(picked, ground_goal))

	if _tree_registry != null:
		var cn := _tree_registry.pick_cn_at_screen(screen_pos)
		if cn >= 0:
			var tree_goal := _tree_registry.get_pos_wc3(cn)
			if tree_goal == Vector2.INF:
				tree_goal = ground_goal
			var s2 := _screen_score_tree(cn, screen_pos)
			if s2 < best_score:
				best_score = s2
				best = SmartTarget.tree(cn, tree_goal)

	if (
		picked != null
		and _is_own_dropoff_building(picked, selected)
		and _selection_any_carrying(selected)
	):
		var foot_drop := _screen_score_node(picked, screen_pos)
		# 须点得够近，避免主城大胶囊抢走「点附近地面移动」
		if foot_drop <= SMART_BUILDING_FOOT_PX:
			var s3 := foot_drop + 18.0
			if s3 < best_score:
				best_score = s3
				best = SmartTarget.dropoff(picked, _node_goal_wc3(picked, ground_goal))

	# 未完工建筑 → 增派建造（也须脚底够近）
	if picked != null and UnitLife.is_under_construction(picked):
		var foot_site := _screen_score_node(picked, screen_pos)
		if foot_site <= SMART_BUILDING_FOOT_PX:
			var s4 := foot_site - 8.0
			if s4 < best_score:
				best_score = s4
				best = SmartTarget.build_site(picked, _node_goal_wc3(picked, ground_goal))

	# 敌对单位 → Attack（优先于纯地面，低于矿/树/交货/工地）；友军不走智能攻击
	if picked != null and CombatQuery.any_can_auto_attack(selected, picked):
		var s5 := _screen_score_node(picked, screen_pos)
		if s5 < best_score:
			best_score = s5
			best = SmartTarget.enemy_unit(picked, _node_goal_wc3(picked, ground_goal))

	if best != null:
		_flash_smart_interact_target(best)
		return best
	if ground_goal == Vector2.INF:
		return null
	return SmartTarget.ground(ground_goal)


## 右键交互反馈：金矿 / 建筑 / 树木统一闪选中环（不改左键选中集合）。
func _flash_smart_interact_target(target: SmartTarget) -> void:
	if target == null:
		return
	match target.kind:
		SmartTarget.Kind.TREE:
			_flash_tree_target(target.tree_cn)
		SmartTarget.Kind.GOLD_MINE:
			_flash_unit_interact_ring(target.node, InteractableComponent.SmartKind.GOLD_MINE, false)
		SmartTarget.Kind.DROPOFF:
			_flash_unit_interact_ring(target.node, InteractableComponent.SmartKind.DROPOFF, false)
		SmartTarget.Kind.BUILD_SITE:
			_flash_unit_interact_ring(target.node, InteractableComponent.SmartKind.BUILD_SITE, false)
		_:
			pass


func _flash_unit_interact_ring(node: Node3D, kind: int, flash_model: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	InteractionSetup.attach(node, kind)
	var ic := InteractionSetup.get_interactable(node)
	if ic != null:
		ic.flash(0.65, flash_model)


func _flash_tree_target(creation_number: int) -> void:
	if _tree_registry == null or creation_number < 0:
		return
	var node := _tree_registry.ensure_promoted(creation_number)
	if node != null:
		_flash_unit_interact_ring(node, InteractableComponent.SmartKind.TREE, true)


func _screen_score_node(node: Node3D, screen_pos: Vector2) -> float:
	if unit_selector != null and unit_selector.has_method("screen_foot_distance"):
		return float(unit_selector.call("screen_foot_distance", node, screen_pos))
	if rts_camera == null:
		return INF
	var cam := rts_camera.get_camera() if rts_camera.has_method("get_camera") else null
	if cam == null or node == null:
		return INF
	if cam.is_position_behind(node.global_position):
		return INF
	return cam.unproject_position(node.global_position).distance_to(screen_pos)


func _screen_score_tree(creation_number: int, screen_pos: Vector2) -> float:
	if _tree_registry == null:
		return INF
	var pos_wc3 := _tree_registry.get_pos_wc3(creation_number)
	if pos_wc3 == Vector2.INF:
		return INF
	var gpos := Wc3Coords.wc3_xy_to_godot(pos_wc3.x, pos_wc3.y, 0.0)
	# 尽量用条目高度
	var entry: Dictionary = _tree_registry.get_entry(creation_number)
	var p: Dictionary = entry.get("position", {})
	if not p.is_empty():
		gpos = Wc3Coords.wc3_xy_to_godot(
			float(p.get("x", pos_wc3.x)),
			float(p.get("y", pos_wc3.y)),
			float(p.get("z", 0.0))
		)
	var cam: Camera3D = null
	if unit_selector != null and unit_selector.get("camera") != null:
		cam = unit_selector.get("camera") as Camera3D
	elif rts_camera != null and rts_camera.has_method("get_camera"):
		cam = rts_camera.call("get_camera") as Camera3D
	if cam == null:
		return INF
	if cam.is_position_behind(gpos):
		return INF
	return cam.unproject_position(gpos).distance_to(screen_pos)


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


## 选中单位里是否有人负重（空闲农民点主城不当送回）。
func _selection_any_carrying(selected: Array) -> bool:
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var hc := (n as Node).get_node_or_null("HarvestController") as HarvestController
		if hc != null and hc.is_carrying():
			return true
	return false


func _format_smart_status(result: Dictionary) -> String:
	var harvested := int(result.get("harvested", 0))
	var returned := int(result.get("returned", 0))
	var moved := int(result.get("moved", 0))
	var rallied := int(result.get("rallied", 0))
	var kind := str(result.get("kind", ""))
	var goal: Vector2 = result.get("goal_wc3", Vector2.INF)
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
		"BuildSite":
			var built := int(result.get("built", 0))
			if built > 0:
				return "加入建造 · %d 单位" % built
	if rallied > 0 and moved > 0 and goal != Vector2.INF:
		return "智能 · 集结 %d · 移动 %d → (%.0f, %.0f)" % [rallied, moved, goal.x, goal.y]
	if rallied > 0 and goal != Vector2.INF:
		match kind:
			"GoldMine":
				return "集结点 → 金矿 · %d 建筑" % rallied
			"Tree":
				return "集结点 → 树木 · %d 建筑" % rallied
			_:
				return "集结点 → (%.0f, %.0f) · %d 建筑" % [goal.x, goal.y, rallied]
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


## F3-2: Shift+RMB 队形排开群体移动（FormationFollow）。
## 行为：leader = primary selected；follower = selected[1:]；
## 头一回算 slot（leader_heading=0 硬编码），各 follower 各自 A* 到 slot 目标。
## WC3 复刻：不做 leader 边走 follower 边跟（见 docs/game/GROUP_MOVE.md §3.5）。
func _issue_group_move_command(
	screen_pos: Vector2,
	formation: String,
	spacing: float = 64.0
) -> bool:
	if unit_selector == null or _path_query == null:
		return false
	if not unit_selector.has_method("get_primary") or not unit_selector.has_method("get_selected"):
		return false
	var primary: Node3D = unit_selector.call("get_primary")
	var selected: Array = unit_selector.call("get_selected")
	if primary == null or selected.is_empty():
		return false
	var hit := _ground_at_screen(screen_pos)
	if hit == Vector3.INF:
		if game_hud:
			game_hud.set_status("队形移动：未点到地面")
		return true
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var goal_center := Vector2(hit.x * inv, -hit.z * inv)
	# 过滤建筑（不可移动）
	var movers: Array = []
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node := n as Node3D
		var d: Dictionary = node.get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if BuildingVisual.is_building(tid):
			continue
		movers.append(node)
	if movers.is_empty():
		if game_hud:
			game_hud.set_status("选中无可用移动单位（建筑？）")
		return true
	# leader 位置（WC3 XY）
	var leader: Node3D = primary
	var leader_pos := Vector2(
		leader.global_position.x * inv, -leader.global_position.z * inv
	)
	# 算 slot（F3 硬编码 heading=0，future 接 leader facing）
	var slots: PackedVector2Array = FormationFollow.slot_positions(
		leader_pos, 0.0, movers.size(), formation, spacing
	)
	# leader 走 goal_center（slot[0] = leader_pos + (0,0) = leader_pos，但要走到 goal）
	# followers 走 slot[1..]
	var moved := 0
	var failed := 0
	for i in range(movers.size()):
		var node: Node3D = movers[i]
		var nav := _ensure_navigator(node)
		if nav == null:
			continue
		var goal: Vector2
		if node == leader:
			goal = goal_center  # leader 直接走落点
		else:
			# follower 走 slot 偏移（相对 leader 当前位置，offset 到 goal_center）
			var offset: Vector2 = slots[i] - slots[0]  # slot 0 = leader_pos
			goal = goal_center + offset
		if nav.go_to_wc3(goal):
			moved += 1
		else:
			failed += 1
	if moved > 0:
		_spawn_move_confirm(goal_center)
	if game_hud:
		if moved > 0:
			game_hud.set_status(
				"队形移动 [%s] → (%.0f, %.0f) · %d 单位" % [formation, goal_center.x, goal_center.y, moved]
			)
		elif failed > 0:
			game_hud.set_status("队形移动：无法到达 (%.0f, %.0f)" % [goal_center.x, goal_center.y])
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
				_flash_tree_target(cn)
				var nl := _command_router.issue_harvest_lumber(peasants, cn, source)
				if nl > 0 and game_hud:
					game_hud.set_status("采集木材 · %d 农民" % nl)
				_refresh_command_card()
				return nl > 0
	if _tree_registry != null:
		var cn2 := _tree_registry.pick_cn_at_screen(screen_pos)
		if cn2 >= 0:
			_flash_tree_target(cn2)
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
	_set_attack_targeting(false)
	_set_patrol_targeting(false)
	_set_harvest_targeting(false)
	_set_rally_targeting(false)
	_set_move_targeting(true)
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键 M"
		game_hud.set_status("移动瞄准（%s）· 左键指定地点 · Esc 取消" % src)


func _begin_attack_targeting(source: int) -> void:
	if unit_selector == null or not unit_selector.has_method("get_selected"):
		return
	var selected: Array = unit_selector.call("get_selected")
	if _command_router == null or _command_router.filter_movers(selected).is_empty():
		if game_hud:
			game_hud.set_status("攻击：无可用单位")
		return
	_set_move_targeting(false)
	_set_patrol_targeting(false)
	_set_harvest_targeting(false)
	_set_rally_targeting(false)
	_set_attack_targeting(true)
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键 A"
		game_hud.set_status("攻击瞄准（%s）· 左键单位/地面 · Esc 取消" % src)


func _begin_patrol_targeting(source: int) -> void:
	if unit_selector == null or not unit_selector.has_method("get_selected"):
		return
	var selected: Array = unit_selector.call("get_selected")
	if _command_router == null or _command_router.filter_movers(selected).is_empty():
		if game_hud:
			game_hud.set_status("巡逻：无可用单位")
		return
	_set_move_targeting(false)
	_set_attack_targeting(false)
	_set_harvest_targeting(false)
	_set_rally_targeting(false)
	_set_patrol_targeting(true)
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键 P"
		game_hud.set_status("巡逻瞄准（%s）· 左键指定另一端 · Esc 取消" % src)


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
	_set_attack_targeting(false)
	_set_patrol_targeting(false)
	_set_rally_targeting(false)
	_set_harvest_targeting(true)
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键 G"
		game_hud.set_status("采集瞄准（%s）· 左键点金矿 · Esc 取消" % src)


func _begin_rally_targeting(source: int) -> void:
	if unit_selector == null or not unit_selector.has_method("get_selected"):
		return
	var selected: Array = unit_selector.call("get_selected")
	var any := false
	for n in selected:
		if n is Node3D and BuildingRally.can_set_rally(n as Node3D):
			any = true
			break
	if not any:
		if game_hud:
			game_hud.set_status("集结点：请选中可训练建筑")
		return
	_set_move_targeting(false)
	_set_attack_targeting(false)
	_set_patrol_targeting(false)
	_set_harvest_targeting(false)
	_set_rally_targeting(true)
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键"
		game_hud.set_status("集结瞄准（%s）· 左键点地面/金矿/树 · Esc 取消" % src)


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


func _set_attack_targeting(active: bool) -> void:
	_attack_targeting = active
	_sync_selector_enabled_for_targeting()
	if game_cursor != null and game_cursor.has_method("set_attack_targeting"):
		game_cursor.call("set_attack_targeting", active)
	elif game_cursor != null and game_cursor.has_method("set_mode"):
		game_cursor.call(
			"set_mode",
			Wc3GameCursor.Mode.TARGET if active else Wc3GameCursor.Mode.IDLE
		)


func _set_patrol_targeting(active: bool) -> void:
	_patrol_targeting = active
	_sync_selector_enabled_for_targeting()
	if game_cursor != null and game_cursor.has_method("set_move_targeting"):
		game_cursor.call("set_move_targeting", active)


func _set_harvest_targeting(active: bool) -> void:
	_harvest_targeting = active
	_sync_selector_enabled_for_targeting()
	if game_cursor != null and game_cursor.has_method("set_move_targeting"):
		# 暂复用移动瞄准光标；后续可换采集专用
		game_cursor.call("set_move_targeting", active)


func _set_rally_targeting(active: bool) -> void:
	_rally_targeting = active
	_sync_selector_enabled_for_targeting()
	# 不用移动瞄准光标，避免「集结=移动」观感；仅靠状态栏提示
	if game_cursor != null and game_cursor.has_method("set_move_targeting"):
		game_cursor.call("set_move_targeting", false)
	elif game_cursor != null and game_cursor.has_method("set_mode"):
		game_cursor.call("set_mode", Wc3GameCursor.Mode.IDLE)


func _sync_selector_enabled_for_targeting() -> void:
	if unit_selector == null:
		return
	# 任一瞄准态都关掉点选，避免抢左键
	unit_selector.enabled = not (
		_move_targeting
		or _attack_targeting
		or _patrol_targeting
		or _harvest_targeting
		or _rally_targeting
		or _is_build_targeting()
	)

func _flash_cursor_move() -> void:
	if game_cursor != null and game_cursor.has_method("flash_move"):
		game_cursor.call("flash_move")


func _spawn_move_confirm(goal_wc3: Vector2, kind: int = MoveConfirmFx.Kind.MOVE) -> void:
	if map_root == null:
		return
	var fx := MoveConfirmFxScene.instantiate() as MoveConfirmFx
	map_root.add_child(fx)
	var cache: MapModelCache = null
	if map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	fx.setup(cache)
	fx.play_at_wc3(goal_wc3, _heightfield, kind)


func _ensure_rally_flag() -> RallyFlagFx:
	if _rally_flag != null and is_instance_valid(_rally_flag):
		return _rally_flag
	if map_root == null:
		return null
	var fx := RallyFlagFx.new()
	fx.name = "RallyFlagFx"
	map_root.add_child(fx)
	var cache: MapModelCache = null
	if map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	fx.setup(cache)
	_rally_flag = fx
	return fx


## 选中集合里：优先主选可训建筑；否则任一已设集结的可训建筑 → 显示种族旗。
func _sync_rally_flag_for_selection() -> void:
	var building := _rally_flag_source_building()
	if building == null:
		if _rally_flag != null and is_instance_valid(_rally_flag):
			_rally_flag.hide_flag()
		return
	var fx := _ensure_rally_flag()
	if fx == null:
		return
	var d: Dictionary = building.get_meta("unit_data", {})
	var race := str(d.get("race", "")).strip_edges().to_lower()
	if race.is_empty() and _session != null:
		race = str(_session.local_race).to_lower()
	if race.is_empty():
		race = preview_race.strip_edges().to_lower()
	var owner_id := int(d.get("owner", local_player))
	var tid := str(d.get("typeId", ""))
	var color_i := MapUnitLayer.resolve_team_color_index(tid, owner_id)
	fx.show_at_wc3(BuildingRally.goal_wc3(building), race, color_i, _heightfield)


## 集结旗数据源：主选可训且已设 → 主选；否则选中里第一个已设集结的可训建筑。
func _rally_flag_source_building() -> Node3D:
	if unit_selector == null:
		return null
	var primary: Node3D = null
	if unit_selector.has_method("get_primary"):
		primary = unit_selector.call("get_primary") as Node3D
	if (
		primary != null
		and BuildingRally.can_set_rally(primary)
		and BuildingRally.has_rally(primary)
	):
		return primary
	if not unit_selector.has_method("get_selected"):
		return null
	var selected: Array = unit_selector.call("get_selected")
	for n in selected:
		if not (n is Node3D):
			continue
		var b := n as Node3D
		if BuildingRally.can_set_rally(b) and BuildingRally.has_rally(b):
			return b
	return null


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


func _ensure_attack_controller(unit: Node3D) -> AttackController:
	_ensure_unit_visual(unit)
	UnitLife.ensure(unit)
	var existing := unit.get_node_or_null("AttackController") as AttackController
	if existing != null:
		existing.configure(
			Callable(self, "_ensure_navigator"),
			Callable(self, "_unit_host"),
			_damage_pipeline
		)
		return existing
	var ac := AttackController.new()
	ac.name = "AttackController"
	ac.configure(
		Callable(self, "_ensure_navigator"),
		Callable(self, "_unit_host"),
		_damage_pipeline
	)
	unit.add_child(ac)
	return ac


func _on_unit_dying(unit: Node3D) -> void:
	if unit == null:
		return
	if unit_selector != null and unit_selector.has_method("deselect_unit"):
		unit_selector.call("deselect_unit", unit)
	var hc := unit.get_node_or_null("HarvestController") as HarvestController
	if hc != null:
		hc.abort()
	var ac := unit.get_node_or_null("AttackController") as AttackController
	if ac != null:
		ac.cancel()
	var pc := unit.get_node_or_null("PatrolController") as PatrolController
	if pc != null:
		pc.cancel()


func _is_build_targeting() -> bool:
	return _build_placement != null and _build_placement.is_active()


## F2-4：玩家按下"建造 <something>"按钮 → 进入瞄准态，显示跟手预览。
func _begin_build_targeting(building_id: String, _source: int) -> void:
	if not BuildingCatalog.is_building(building_id):
		if game_hud:
			game_hud.set_status("未知建筑 %s" % building_id)
		return
	if _command_router == null:
		return
	var peasants: Array = _command_router.filter_peasants(_get_selected_safe())
	if peasants.is_empty():
		if game_hud:
			game_hud.set_status("建造：无农民")
		return
	var missing := TechPresence.missing_requires(
		_owned_buildings_for_local(),
		UnitRequiresCatalog.get_shared().get_requires(building_id)
	)
	if not missing.is_empty():
		if game_hud:
			game_hud.set_status(TechPresence.requires_tip(missing))
		return
	# 资源检查：不置灰，点下提示
	if not _can_afford(building_id):
		_notify_cannot_afford_build(building_id)
		return
	# 选建筑后收起二级面板，进入瞄准
	_build_menu_open = false
	# 中断其他瞄准态
	_set_move_targeting(false)
	_set_attack_targeting(false)
	_set_patrol_targeting(false)
	_set_harvest_targeting(false)
	_set_rally_targeting(false)
	_clear_pinned_site_ghost()
	_ensure_build_placement_objects()
	_build_placement.begin(building_id)
	_ensure_ghost_node(building_id)
	# 面板点击：先禁止确认；热键且光标已在地图上可立刻确认
	_build_confirm_armed = not _pointer_over_blocking_gui()
	_build_ghost.set_visible_preview(true)
	_sync_selector_enabled_for_targeting()
	# 用当前鼠标位置立刻刷新预览（面板点击处若打不中地面，等移出 HUD 后再显示）
	var vp := get_viewport()
	if vp != null:
		_last_screen_pos = vp.get_mouse_position()
	_build_placement.update_screen(_last_screen_pos)
	_apply_ghost_to_screen()
	_refresh_command_card()
	if game_hud:
		var display_name := CommandCard._building_display_name(building_id)
		game_hud.set_status("建造瞄准：%s · 左键指定地点 · 右键/Esc 取消" % display_name)


func _cancel_build_targeting() -> void:
	if _build_placement == null:
		return
	_build_placement.cancel()
	_build_confirm_armed = false
	_clear_pinned_site_ghost()
	_sync_selector_enabled_for_targeting()
	if game_hud:
		game_hud.set_status("建造取消")


func _set_build_menu_open(open: bool) -> void:
	if _build_menu_open == open:
		if open:
			_refresh_command_card()
		return
	_build_menu_open = open
	if open:
		_set_move_targeting(false)
		_set_attack_targeting(false)
		_set_patrol_targeting(false)
		_set_harvest_targeting(false)
		if _is_build_targeting():
			_cancel_build_targeting()
	_refresh_command_card()
	if game_hud:
		if open:
			game_hud.set_status("建造：选择建筑 · Esc/取消 返回")
		elif _card_is_peasant:
			game_hud.set_status("已选农民 · 建造见命令卡")


func _commit_build_targeting(screen_pos: Vector2) -> void:
	if _build_placement == null or not _build_placement.is_active():
		return
	_last_screen_pos = screen_pos
	_build_placement.update_screen(screen_pos)
	if not _build_placement.is_valid():
		if game_hud:
			game_hud.set_status("无法在此处建造（合法位置？）")
		return
	var bid := _build_placement.current_building_id()
	var site := _build_placement.current_site_wc3()
	# 资源复检（资源可能在瞄准中被花掉）
	if not _can_afford(bid):
		_notify_cannot_afford_build(bid)
		_cancel_build_targeting()
		return
	if not _build_placement.commit():
		return
	_build_confirm_armed = false
	# 接 peasant 列表后下 issue_build
	var peasants: Array = _command_router.filter_peasants(_get_selected_safe())
	var n := _command_router.issue_build(peasants, bid, site, UnitOrder.Source.TARGETING)
	_sync_selector_enabled_for_targeting()
	_refresh_command_card()
	if n <= 0:
		_clear_pinned_site_ghost()
		if game_hud:
			game_hud.set_status("建造下令失败（需选中空闲农民）")
		return
	# 农民走动期间：工地保留半透明建筑幽灵（开工刷半成品时再撤）
	_pin_site_ghost(bid, site)
	if game_hud:
		game_hud.set_status("建造：农民前往工地")


func _pin_site_ghost(building_id: String, site_wc3: Vector2) -> void:
	_ensure_ghost_node(building_id)
	if _build_ghost == null:
		return
	_site_ghost_pinned = true
	var sample := PlacementRules.sample_footprint(building_id, site_wc3, _pathing)
	_build_ghost.update_from_sample(sample, _pathing, _heightfield, site_wc3)
	_build_ghost.set_valid(true)
	_build_ghost.set_pinned_style(true)
	_build_ghost.set_visible_preview(true)


func _clear_pinned_site_ghost() -> void:
	_site_ghost_pinned = false
	if _build_ghost != null:
		_build_ghost.set_pinned_style(false)
		_build_ghost.set_visible_preview(false)


func _apply_ghost_to_screen() -> void:
	if _build_placement == null or _build_ghost == null:
		return
	# 已钉在工地的幽灵：不要被 HUD 挡鼠标逻辑关掉
	if _site_ghost_pinned and not _build_placement.is_active():
		return
	if not _build_placement.is_active():
		return
	# 光标在命令面板上：已有落点则保持；尚无落点则先不画
	if _pointer_over_blocking_gui():
		var site := _build_placement.current_site_wc3()
		if site == Vector2.INF:
			_build_ghost.set_visible_preview(false)
		else:
			_build_ghost.set_visible_preview(true)
		return
	var site2 := _build_placement.current_site_wc3()
	if site2 == Vector2.INF:
		return
	_build_ghost.set_visible_preview(true)
	_build_ghost.update_from_sample(
		_build_placement.current_footprint_sample(),
		_pathing,
		_heightfield,
		site2
	)


func _on_build_placement_changed(_bid: String, _site: Vector2, _valid: bool) -> void:
	if _build_ghost != null and _build_placement != null and _build_placement.is_active():
		_apply_ghost_to_screen()


func _on_build_placement_cancelled() -> void:
	_build_confirm_armed = false
	# 仅瞄准取消时藏幽灵；已钉工地的幽灵由 pin/开工/取消令 管理
	if not _site_ghost_pinned and _build_ghost != null:
		_build_ghost.set_visible_preview(false)
	_sync_selector_enabled_for_targeting()


func _on_build_placement_committed(_bid: String, _site: Vector2) -> void:
	_build_confirm_armed = false


func _ensure_build_placement_objects() -> void:
	if _build_placement == null:
		_build_placement = BuildPlacementController.new()
		_build_placement.configure(
			Callable(self, "_ground_at_screen"),
			Callable(self, "_heightfield_ref"),
			Callable(self, "_pathing_ref"),
			Callable(self, "_cell_reservation_ref")
		)
		_build_placement.placement_changed.connect(_on_build_placement_changed)
		_build_placement.placement_cancelled.connect(_on_build_placement_cancelled)
		_build_placement.placement_committed.connect(_on_build_placement_committed)


func _ensure_ghost_node(building_id: String) -> void:
	if _build_ghost == null:
		_build_ghost = BuildPlacementGhost.new()
		_build_ghost.name = "BuildPlacementGhost"
		if map_root != null:
			map_root.add_child(_build_ghost)
		else:
			add_child(_build_ghost)
	if map_root != null:
		_build_ghost.configure(map_root.get_model_cache(), map_root.get_id_catalog())
	_build_ghost.set_building(building_id)


## HUD / 小地图等吃鼠标的 Control：建造确认与地面采样应避开。
func _pointer_over_blocking_gui() -> bool:
	if unit_selector != null and unit_selector.has_method("_hud_blocks_screen"):
		return bool(unit_selector.call("_hud_blocks_screen", _last_screen_pos))
	var vp := get_viewport()
	if vp == null:
		return false
	var hovered := vp.gui_get_hovered_control()
	if hovered == null:
		return false
	return hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _heightfield_ref() -> Wc3Heightfield:
	return _heightfield


func _pathing_ref() -> Wc3PathingMap:
	return _pathing


func _cell_reservation_ref() -> PathCellReservation:
	return _cell_reservation


func _can_afford(building_id: String) -> bool:
	if _session == null:
		return false
	var stock: PlayerStock = _session.local_stock()
	if stock == null:
		return false
	var g: int = BuildingCatalog.get_gold_cost(building_id)
	var l: int = BuildingCatalog.get_lumber_cost(building_id)
	return stock.gold >= g and stock.lumber >= l


func _notify_cannot_afford_build(building_id: String) -> void:
	if game_hud == null:
		return
	var g := BuildingCatalog.get_gold_cost(building_id)
	var l := BuildingCatalog.get_lumber_cost(building_id)
	var msg := "资源不够"
	if g > 0 or l > 0:
		msg = "资源不够（需 %d金" % g
		if l > 0:
			msg += " %d木" % l
		msg += "）"
	if game_hud.has_method("show_command_tip"):
		game_hud.show_command_tip(msg)
	else:
		game_hud.set_status(msg)


func _get_selected_safe() -> Array:
	if unit_selector == null or not unit_selector.has_method("get_selected"):
		return []
	return unit_selector.call("get_selected")


## F2-4：每个 peasant 挂一个 BuildController；首次创建时连 build_completed 信号。
func _ensure_build_controller(unit: Node3D) -> BuildController:
	_ensure_unit_visual(unit)
	var existing := unit.get_node_or_null("BuildController") as BuildController
	if existing != null:
		existing.configure(_session, _pathing, _cell_reservation)
		_wire_build_signals(existing)
		return existing
	var bc := BuildController.new()
	bc.name = "BuildController"
	bc.configure(_session, _pathing, _cell_reservation)
	unit.add_child(bc)
	_wire_build_signals(bc)
	return bc


func _wire_build_signals(bc: BuildController) -> void:
	if bc == null:
		return
	if not bc.build_started.is_connected(_on_build_started):
		bc.build_started.connect(_on_build_started)
	if not bc.build_completed.is_connected(_on_build_completed):
		bc.build_completed.connect(_on_build_completed)
	if not bc.build_cancelled.is_connected(_on_build_cancelled):
		bc.build_cancelled.connect(_on_build_cancelled)
	if not bc.build_joined.is_connected(_on_build_joined):
		bc.build_joined.connect(_on_build_joined)
	# 协助农民轮询「首工到位后」登记的工地
	bc.find_site_at = Callable(self, "_find_build_site")


## 增派工人到位（半成品应已存在；此信号仅作进度/动画旁路，不再提前刷建筑）。
func _on_build_joined(_site: BuildSite, _builder: Node3D) -> void:
	pass


## 0 工人：冻结 Birth/粒子；有人回来继续。
func _on_construction_paused(paused: bool, key: String) -> void:
	if not _active_construction.has(key):
		return
	var rec: Dictionary = _active_construction[key]
	var node: Node3D = rec.get("node") as Node3D
	if node == null or not is_instance_valid(node):
		return
	_set_construction_present_paused(node, str(rec.get("building_id", "")), paused)


func _set_construction_present_paused(building: Node3D, building_id: String, paused: bool) -> void:
	if building == null:
		return
	var ap := _find_anim_player(building)
	if ap != null:
		ap.speed_scale = 0.0 if paused else 1.0
	for n in building.find_children("*", "GPUParticles3D", true, false):
		(n as GPUParticles3D).emitting = not paused
	for n2 in building.find_children("*", "CPUParticles3D", true, false):
		(n2 as CPUParticles3D).emitting = not paused
	if not paused and not building_id.is_empty():
		var cache = map_root.get_model_cache() if map_root != null and map_root.has_method("get_model_cache") else null
		if cache != null:
			BuildingVisual.apply_phase(cache, building, building_id, BuildingVisual.Phase.BIRTH)


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := _find_anim_player(c)
		if f:
			return f
	return null


## 农民到位开工：立刻刷半成品建筑（低血 + under_construction），进度驱动血条/HUD。
func _on_build_started(order: BuildOrder) -> void:
	if order == null or map_root == null or _heightfield == null:
		return
	var key := _construction_key(order)
	if _active_construction.has(key):
		return
	# 半成品已刷出：撤掉落点幽灵
	_clear_pinned_site_ghost()
	var player_owner := 0
	if order.builder != null:
		var d: Dictionary = order.builder.get_meta("unit_data", {})
		player_owner = int(d.get("owner", local_player))
		# 仅当该农民已在工地施工时播锤子（join 先到时不要让还在路上的首工进入 Stand Work）
		var bc0 := order.builder.get_node_or_null("BuildController") as BuildController
		if bc0 != null and bc0.is_building():
			var vis := _ensure_unit_visual(order.builder)
			vis.set_building_work(true)
	var cn := _alloc_runtime_cn()
	var entry := _build_entry_for(order.building_id, order.site_wc3, player_owner, cn)
	entry["hitPoints"] = 5.0
	entry["under_construction"] = true
	var node := map_root.add_unit_instance(entry, _heightfield.as_dict_view())
	if node == null:
		push_warning("GameDirector: 半成品建筑刷出失败 %s" % order.building_id)
		return
	UnitLife.ensure(node)
	UnitLife.set_under_construction(node, true)
	UnitLife.set_ratio(node, 0.05)
	# Birth 建造动画（add 时若已按 under_construction 播过则再确保一次）
	var cache = map_root.get_model_cache() if map_root.has_method("get_model_cache") else null
	if cache != null:
		BuildingVisual.apply_phase(cache, node, order.building_id, BuildingVisual.Phase.BIRTH)
	var bc: BuildController = null
	if order.builder != null:
		bc = order.builder.get_node_or_null("BuildController") as BuildController
	var site: BuildSite = bc.current_site() if bc != null else null
	if site == null:
		site = _find_build_site(order.site_wc3, order.building_id)
	_active_construction[key] = {
		"cn": cn,
		"node": node,
		"building_id": order.building_id,
		"site": site,
	}
	_register_build_site(site, node, order)
	if site != null and not bool(site.get_meta("pause_wired", false)):
		site.set_meta("pause_wired", true)
		site.paused_changed.connect(_on_construction_paused.bind(key))
	# 若开工时已有工人则确保非暂停表现；0 人不应发生
	if site != null:
		_set_construction_present_paused(node, order.building_id, site.is_paused())
	if site != null:
		var cb := _on_construction_progress.bind(key)
		if not site.progress_changed.is_connected(cb):
			site.progress_changed.connect(cb)
	_refresh_dynamic_pathing()
	# 半成品已占 pathing：把脚印内闲散单位推到外沿（施工工人除外）
	_make_way_for_construction(order, node, site)
	if health_bar_manager:
		health_bar_manager.resync()
	_sync_build_hud_for_selection()
	if game_hud:
		game_hud.set_status("开工：%s" % order.building_id)


## 开工让位：脚印内可移动单位走开，避免卡在半成品 pathTex 上。
func _make_way_for_construction(order: BuildOrder, building_node: Node3D, site: BuildSite) -> void:
	if order == null or map_root == null or _pathing == null:
		return
	var layer := map_root.get_unit_layer()
	if layer == null:
		return
	var exclude: Array = []
	if building_node != null:
		exclude.append(building_node)
	if order.builder != null:
		exclude.append(order.builder)
	if site != null:
		for b in site.active_builders():
			exclude.append(b)
	var blockers: Array[Node3D] = BuildFootprintClearance.collect_blockers(
		layer, order.building_id, order.site_wc3, _pathing, _crowd_query, exclude
	)
	if blockers.is_empty():
		return
	var aabb: Rect2 = BuildFootprintClearance.footprint_aabb_wc3(
		order.building_id, order.site_wc3, _pathing
	)
	for unit in blockers:
		if unit == null or not is_instance_valid(unit):
			continue
		var tid := str(unit.get_meta("unit_data", {}).get("typeId", ""))
		var pos := Wc3Coords.godot_to_wc3_xy(unit.global_position)
		var goal: Vector2 = BuildFootprintClearance.resolve_outside(
			unit, tid, pos, order.site_wc3, aabb, _path_query, _crowd_query
		)
		if goal == Vector2.INF:
			continue
		if _command_router != null:
			_command_router.issue_move_to_wc3([unit], goal, UnitOrder.Source.UNKNOWN)
		else:
			var nav := _ensure_navigator(unit)
			if nav != null:
				nav.go_to_wc3(goal)


func _on_construction_progress(elapsed: float, total: float, ratio: float, key: String) -> void:
	if not _active_construction.has(key):
		return
	var rec: Dictionary = _active_construction[key]
	var node: Node3D = rec.get("node") as Node3D
	if node == null or not is_instance_valid(node):
		return
	UnitLife.set_ratio(node, maxf(ratio, 0.05))
	_update_build_hud_if_relevant(key, ratio, elapsed, total)


## F2-5：工地 timer 跑完 → 半成品转正（满血）；若无半成品则兜底刷建筑。
func _on_build_completed(order: BuildOrder, site_wc3: Vector2, player_owner: int) -> void:
	if order == null:
		return
	var key := _construction_key(order)
	# BuildController 与 site 可能双重回调；只处理一次
	if not _active_construction.has(key):
		return
	var rec: Dictionary = _active_construction[key]
	var building_node: Node3D = rec.get("node") as Node3D
	_active_construction.erase(key)
	if building_node != null and is_instance_valid(building_node):
		UnitLife.set_under_construction(building_node, false)
		UnitLife.set_ratio(building_node, 1.0)
		var cache = map_root.get_model_cache() if map_root != null and map_root.has_method("get_model_cache") else null
		if cache != null:
			BuildingVisual.apply_phase(cache, building_node, order.building_id, BuildingVisual.Phase.IDLE)
	elif map_root != null and _heightfield != null:
		var entry := _build_entry_for(order.building_id, site_wc3, player_owner, _alloc_runtime_cn())
		map_root.add_unit_instance(entry, _heightfield.as_dict_view())
		_refresh_dynamic_pathing()
	# 人口上限（首工已离开时 BuildController 不会加）
	if _session != null:
		var stock: PlayerStock = _session.local_stock()
		if stock != null:
			var fmade: int = BuildingCatalog.get_food_made(order.building_id)
			if fmade > 0:
				stock.add_food_cap(fmade)
	_unbind_hud_build_site()
	_unregister_build_site(order, building_node)
	if game_hud != null:
		game_hud.clear_build_progress()
		game_hud.set_status("完工：%s @ (%.0f, %.0f)" % [order.building_id, site_wc3.x, site_wc3.y])
	_refresh_command_card()
	_sync_selection_info_panel()
	if health_bar_manager:
		health_bar_manager.resync()


func _on_build_cancelled(order: BuildOrder) -> void:
	_clear_pinned_site_ghost()
	if order != null:
		var key := _construction_key(order)
		if _active_construction.has(key):
			var rec: Dictionary = _active_construction[key]
			var cn := int(rec.get("cn", -1))
			var building_node: Node3D = rec.get("node") as Node3D
			if cn >= 0 and map_root != null:
				map_root.remove_unit_instance(cn)
				_refresh_dynamic_pathing()
			_active_construction.erase(key)
			_unregister_build_site(order, building_node)
	_unbind_hud_build_site()
	if game_hud != null:
		game_hud.clear_build_progress()
	_refresh_command_card()
	if health_bar_manager:
		health_bar_manager.resync()


func _alloc_runtime_cn() -> int:
	var cn := _next_runtime_cn
	_next_runtime_cn += 1
	return cn


func _construction_key(order: BuildOrder) -> String:
	if order == null:
		return ""
	return _site_lookup_key(order.building_id, order.site_wc3)

func _refresh_dynamic_pathing() -> void:
	if map_root == null:
		return
	# 动态脚印变更后：数据与叠层必须同源，否则会出现「蓝格可摆」或「叠层过期」
	if bool(map_root.get("show_pathing_ground")) and map_root.has_method("_rebuild_pathing_overlay"):
		map_root.call("_rebuild_pathing_overlay")
	elif map_root.has_method("_apply_dynamic_pathing"):
		map_root.call("_apply_dynamic_pathing")
	elif map_root.has_method("set_pathing_map") and _pathing != null:
		map_root.set_pathing_map(_pathing)


## 完工后入图的 unit entry dict（MapUnitLayer 期望的字段）。
func _build_entry_for(building_id: String, site_wc3: Vector2, player_owner: int, creation_number: int = -1) -> Dictionary:
	return {
		"typeId": building_id,
		"position": {"x": site_wc3.x, "y": site_wc3.y},
		# 与 Melee 开局一致：默认朝南（bj_UNIT_FACING）；缺省 0 会让建筑「横着」
		"angle": MeleeBootstrap.UNIT_FACING_RAD,
		"owner": player_owner,
		"creationNumber": creation_number,
		"variation": 0,
		"isBuilding": true,
	}


## 主城/兵营等可训建筑：命令卡带 training_unit 高亮 + Requires 置灰。
## 建造中：隐藏训兵按钮，保留集结点。
func _apply_building_train_card(building: Node3D, tid: String) -> void:
	var owner_id := 0
	if _session != null:
		owner_id = int(_session.local_player)
	var under := building != null and UnitLife.is_under_construction(building)
	var state := {
		"include_locomotion": false,
		"owned_buildings": _owned_buildings_for_local(),
		"hero_slots_full": (
			TechPresence.count_heroes_with_queues(_unit_host(), owner_id)
			>= TechPresence.MAX_HEROES_PER_PLAYER
		),
		"hide_trains": under,
	}
	if building != null and not under:
		var q := building.get_node_or_null("TrainQueue") as TrainQueue
		if q != null and q.is_training():
			state["training_unit"] = q.current_unit()
			state["train_queue"] = q.snapshot()
	_apply_command_card(CommandCard.for_unit(tid, state))


func _owned_buildings_for_local() -> Dictionary:
	var owner_id := 0
	if _session != null:
		owner_id = int(_session.local_player)
	return TechPresence.collect_owned_buildings(_unit_host(), owner_id)


func _try_issue_train(unit_id: String) -> void:
	if _command_router == null or unit_selector == null or not unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	if primary == null or not is_instance_valid(primary):
		if game_hud:
			game_hud.set_status("请先选中可训练建筑")
		return
	var d: Dictionary = primary.get_meta("unit_data", {})
	var building_id := str(d.get("typeId", "")).strip_edges()
	if building_id.is_empty() or not BuildingCatalog.is_building(building_id):
		if game_hud:
			game_hud.set_status("当前选中无法训练")
		return
	if UnitLife.is_under_construction(primary):
		if game_hud:
			game_hud.set_status("建造中，无法训练")
		return
	var uid := unit_id.strip_edges()
	var trains := TechPresence.filter_vertical_trains(
		building_id, CommandButtonCatalog.get_shared().get_trains(building_id)
	)
	if trains.find(uid) < 0:
		if game_hud:
			game_hud.set_status("%s 不能训练 %s" % [building_id, uid])
		return
	var owned := _owned_buildings_for_local()
	var missing := TechPresence.missing_requires(
		owned, UnitRequiresCatalog.get_shared().get_requires(uid)
	)
	if not missing.is_empty():
		if game_hud:
			game_hud.set_status(TechPresence.requires_tip(missing))
		return
	if TechPresence.is_hero_id(uid):
		var owner_id := int(d.get("owner", 0))
		if (
			TechPresence.count_heroes_with_queues(_unit_host(), owner_id)
			>= TechPresence.MAX_HEROES_PER_PLAYER
		):
			if game_hud:
				game_hud.set_status("每位玩家同时只能拥有 %d 名英雄" % TechPresence.MAX_HEROES_PER_PLAYER)
			return
	var stock := _local_stock()
	var gold := BuildingCatalog.get_gold_cost(uid)
	var lumber := BuildingCatalog.get_lumber_cost(uid)
	var food := BuildingCatalog.get_food_used(uid)
	if stock != null:
		if food > 0 and not stock.can_afford_food(food):
			if game_hud:
				game_hud.set_status("人口不足（%d/%d）" % [stock.food_used, stock.food_cap])
			return
		if stock.gold < gold or stock.lumber < lumber:
			_notify_cannot_afford_build(uid)
			return
	var existing := primary.get_node_or_null("TrainQueue") as TrainQueue
	if existing != null and existing.is_full():
		if game_hud:
			game_hud.set_status("训练队列已满（%d/%d）" % [existing.queue_count(), TrainQueue.MAX_QUEUE])
		return
	if not _command_router.issue_train(primary, uid):
		if game_hud:
			game_hud.set_status("无法训练 %s" % uid)
		return
	var queue := primary.get_node_or_null("TrainQueue") as TrainQueue
	_wire_train_queue(queue)
	_apply_building_train_card(primary, building_id)
	_sync_build_hud_for_selection()
	if game_hud:
		var n := queue.queue_count() if queue != null else 1
		game_hud.set_status("已加入训练队列：%s（%d/%d）" % [uid, n, TrainQueue.MAX_QUEUE])


func _wire_train_queue(queue: TrainQueue) -> void:
	if queue == null or not is_instance_valid(queue):
		return
	var id := queue.get_instance_id()
	if _wired_train_queues.has(id):
		return
	_wired_train_queues[id] = true
	queue.training_completed.connect(_on_training_completed.bind(queue))
	queue.training_cancelled.connect(_on_training_cancelled)
	if not queue.queue_changed.is_connected(_on_train_queue_changed):
		queue.queue_changed.connect(_on_train_queue_changed.bind(queue))
	if not queue.progress_changed.is_connected(_on_train_progress_changed):
		queue.progress_changed.connect(_on_train_progress_changed.bind(queue))
	if not queue.training_started.is_connected(_on_train_started_visual):
		queue.training_started.connect(_on_train_started_visual.bind(queue))
	_sync_building_train_visual(queue.get_parent() as Node3D)


func _on_train_started_visual(_unit_id: String, _time_sec: float, queue: TrainQueue) -> void:
	if queue == null or not is_instance_valid(queue):
		return
	_sync_building_train_visual(queue.get_parent() as Node3D)


## 训练中切 Stand Work（门开 + 门光）；队列空回 Stand。
func _sync_building_train_visual(building: Node3D) -> void:
	if building == null or not is_instance_valid(building) or map_root == null:
		return
	var tid := str(building.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	if tid.is_empty() or not BuildingCatalog.is_building(tid):
		return
	if UnitLife.is_under_construction(building):
		return
	var cache = map_root.get_model_cache() if map_root.has_method("get_model_cache") else null
	if cache == null:
		return
	var q := building.get_node_or_null("TrainQueue") as TrainQueue
	var phase := (
		BuildingVisual.Phase.WORK if q != null and q.is_training() else BuildingVisual.Phase.IDLE
	)
	BuildingVisual.apply_phase(cache, building, tid, phase)


func _on_train_progress_changed(_progress: float, _remaining_sec: float, queue: TrainQueue) -> void:
	# 仅当该队列所属建筑是当前主选时刷 HUD（事件驱动，非 Director 轮询）
	if queue == null or not is_instance_valid(queue):
		return
	if not _is_primary_train_queue(queue):
		return
	_push_train_queue_hud(queue)


func _is_primary_train_queue(queue: TrainQueue) -> bool:
	if game_hud == null or unit_selector == null or not unit_selector.has_method("get_primary"):
		return false
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	if primary == null or not is_instance_valid(primary):
		return false
	return queue.get_parent() == primary


func _on_train_queue_cancel(slot_index: int) -> void:
	if unit_selector == null or not unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	if primary == null:
		return
	var tq := primary.get_node_or_null("TrainQueue") as TrainQueue
	if tq == null:
		return
	_wire_train_queue(tq)
	if not tq.cancel_at(slot_index):
		return
	_sync_building_train_visual(primary)
	var tid := str(primary.get_meta("unit_data", {}).get("typeId", ""))
	if not tid.is_empty():
		_apply_building_train_card(primary, tid)
	_sync_build_hud_for_selection()


func _on_train_queue_changed(queue: TrainQueue = null) -> void:
	if queue != null and is_instance_valid(queue):
		_sync_building_train_visual(queue.get_parent() as Node3D)
	_sync_build_hud_for_selection()
	if unit_selector != null and unit_selector.has_method("get_primary"):
		var primary: Node3D = unit_selector.call("get_primary") as Node3D
		if primary != null:
			var tid := str(primary.get_meta("unit_data", {}).get("typeId", ""))
			if not tid.is_empty() and not CommandButtonCatalog.get_shared().get_trains(tid).is_empty():
				_apply_building_train_card(primary, tid)


func _on_training_completed(unit_id: String, site_wc3: Vector2, owner: int, queue: TrainQueue) -> void:
	var building: Node3D = null
	if queue != null and is_instance_valid(queue):
		building = queue.get_parent() as Node3D
	_sync_building_train_visual(building)
	var node := _spawn_trained_unit(unit_id, site_wc3, owner, building)
	if node == null:
		push_warning("GameDirector: 训练完成但刷单位失败 %s" % unit_id)
		# 刷失败：释回人口（开训时已预占）
		var stock := _local_stock()
		if stock != null:
			var food := BuildingCatalog.get_food_used(unit_id)
			if food > 0:
				stock.add_food_used(-food)
		if game_hud:
			game_hud.set_status("训练完成但刷出失败：%s" % unit_id)
		return
	if unit_selector != null and unit_selector.has_method("get_primary"):
		var primary: Node3D = unit_selector.call("get_primary") as Node3D
		if primary != null and building != null and primary == building:
			var tid := str(building.get_meta("unit_data", {}).get("typeId", ""))
			if not tid.is_empty():
				_apply_building_train_card(building, tid)
			_sync_build_hud_for_selection()
	if game_hud:
		game_hud.set_status("训练完成：%s" % unit_id)


func _on_training_cancelled(unit_id: String, refund_g: int, refund_l: int, food: int = -1) -> void:
	var stock := _local_stock()
	if stock != null:
		if refund_g > 0:
			stock.add_gold(refund_g)
		if refund_l > 0:
			stock.add_lumber(refund_l)
		var food_n := food if food >= 0 else BuildingCatalog.get_food_used(unit_id)
		if food_n > 0:
			stock.add_food_used(-food_n)
	if game_hud:
		game_hud.set_status("取消训练：%s（退 %d金 %d木）" % [unit_id, refund_g, refund_l])
	_sync_build_hud_for_selection()
	if unit_selector != null and unit_selector.has_method("get_primary"):
		var primary: Node3D = unit_selector.call("get_primary") as Node3D
		if primary != null:
			var tid := str(primary.get_meta("unit_data", {}).get("typeId", ""))
			if not tid.is_empty() and not CommandButtonCatalog.get_shared().get_trains(tid).is_empty():
				_apply_building_train_card(primary, tid)
	if unit_selector != null and unit_selector.has_method("get_primary"):
		var primary: Node3D = unit_selector.call("get_primary") as Node3D
		if primary != null:
			var tid := str(primary.get_meta("unit_data", {}).get("typeId", ""))
			if BuildingCatalog.is_building(tid):
				_apply_building_train_card(primary, tid)
			_sync_build_hud_for_selection()


## 训练完工刷单位：脚印四角（集结最近 / 默认左下）→ 重叠则自建筑中心挤位 → 再跟集结。
func _spawn_trained_unit(
	unit_id: String, site_wc3: Vector2, owner: int, from_building: Node3D = null
) -> Node3D:
	if map_root == null or _heightfield == null:
		return null
	var corner_xy := TrainSpawn.exit_xy_for_building(from_building, site_wc3)
	var entry := {
		"typeId": unit_id,
		"position": {"x": corner_xy.x, "y": corner_xy.y, "z": 0.0},
		"angle": MeleeBootstrap.UNIT_FACING_RAD,
		"scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"owner": owner,
		"flags": 2,
		"creationNumber": _alloc_runtime_cn(),
		"variation": 0,
	}
	var node := map_root.add_unit_instance(entry, _heightfield.as_dict_view())
	if node == null:
		return null
	UnitLife.ensure(node)
	var final_xy := TrainSpawn.resolve_with_displace(
		corner_xy, site_wc3, node, unit_id, _path_query, _crowd_query
	)
	if final_xy != corner_xy:
		_teleport_unit_wc3(node, final_xy)
	_refresh_dynamic_pathing()
	if health_bar_manager:
		health_bar_manager.resync()
	_dispatch_trained_rally(from_building, node)
	return node


## 新兵出门后跟集结点：地面→移动；金矿/树→采集（人族农民）。
func _dispatch_trained_rally(building: Node3D, unit: Node3D) -> void:
	if building == null or unit == null or _command_router == null:
		return
	if not BuildingRally.has_rally(building):
		return
	match BuildingRally.kind(building):
		BuildingRally.KIND_GOLD_MINE:
			var mine := BuildingRally.mine_node(building)
			if mine != null:
				_command_router.issue_harvest_gold([unit], mine, UnitOrder.Source.UNKNOWN)
				return
		BuildingRally.KIND_TREE:
			var cn := BuildingRally.tree_cn(building)
			if cn >= 0:
				_command_router.issue_harvest_lumber([unit], cn, UnitOrder.Source.UNKNOWN)
				return
	var goal := BuildingRally.goal_wc3(building)
	if goal != Vector2.INF:
		_command_router.issue_move_to_wc3([unit], goal, UnitOrder.Source.UNKNOWN)


## 训练刷兵后改坐标（挤位）；同步 unit_data 与贴地。
func _teleport_unit_wc3(unit: Node3D, wc3_xy: Vector2) -> void:
	if unit == null or not is_instance_valid(unit) or wc3_xy == Vector2.INF:
		return
	var z := 0.0
	if _heightfield != null and _heightfield.is_valid():
		z = _heightfield.interpolated_height(wc3_xy.x, wc3_xy.y)
	unit.global_position = Wc3Coords.wc3_xy_to_godot(wc3_xy.x, wc3_xy.y, z)
	if unit.has_meta("unit_data"):
		var d: Dictionary = unit.get_meta("unit_data", {}).duplicate(true)
		var pos: Dictionary = d.get("position", {})
		if typeof(pos) != TYPE_DICTIONARY:
			pos = {}
		pos["x"] = wc3_xy.x
		pos["y"] = wc3_xy.y
		pos["z"] = z
		d["position"] = pos
		unit.set_meta("unit_data", d)


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
	var cache: MapModelCache = null
	if map_root != null and map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	var existing := unit.get_node_or_null("UnitVisual") as UnitVisual
	if existing != null:
		existing.bind_cache(cache)
		existing.bind_animation_player(AnimPlayback.find_animation_player(unit))
		_ensure_interaction_components(unit)
		return existing
	var vis := UnitVisual.new()
	vis.name = "UnitVisual"
	vis.bind_cache(cache)
	vis.bind_animation_player(AnimPlayback.find_animation_player(unit))
	unit.add_child(vis)
	_ensure_interaction_components(unit)
	return vis


## 刷单位时挂选框场景 + Selectable / Interactable，并注入依赖。
func _ensure_interaction_components(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var d: Dictionary = unit.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	var kind := InteractableComponent.SmartKind.NONE
	if tid == "ngol":
		kind = InteractableComponent.SmartKind.GOLD_MINE
	InteractionSetup.attach(unit, kind)


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


func _on_command_pressed(_slot: int) -> void:
	# 有 action_id 时由 _on_command_action 处理；纯文字占位格仍提示
	if game_hud != null and game_hud.has_method("set_status"):
		pass


func _on_command_action(
	action_id: String, source: int = UnitOrder.Source.PANEL
) -> void:
	match action_id:
		CommandCard.ACTION_MOVE:
			if enable_move_command:
				_begin_move_targeting(source)
		CommandCard.ACTION_STOP:
			if enable_move_command:
				_issue_stop(source)
		CommandCard.ACTION_HOLD:
			if enable_move_command:
				_issue_hold(source)
		CommandCard.ACTION_ATTACK:
			if enable_move_command:
				_begin_attack_targeting(source)
		CommandCard.ACTION_PATROL:
			if enable_move_command:
				_begin_patrol_targeting(source)
		CommandCard.ACTION_HARVEST_GOLD:
			_begin_harvest_targeting(source)
		CommandCard.ACTION_RETURN_GOODS:
			_issue_return_goods(source)
		CommandCard.ACTION_OPEN_BUILD:
			if _card_is_peasant:
				_set_build_menu_open(true)
		CommandCard.ACTION_CLOSE_BUILD:
			_set_build_menu_open(false)
		CommandCard.ACTION_CALL_TO_ARMS:
			if game_hud:
				game_hud.set_status("战斗号召：逻辑待接（F3+）")
		CommandCard.ACTION_SET_RALLY:
			_begin_rally_targeting(source)
		_:
			if action_id.begins_with(CommandCard.ACTION_BUILD_PREFIX):
				var bid := action_id.substr(CommandCard.ACTION_BUILD_PREFIX.length())
				_begin_build_targeting(bid, source)
				return
			if action_id.begins_with(CommandCard.ACTION_TRAIN_PREFIX):
				var uid := action_id.substr(CommandCard.ACTION_TRAIN_PREFIX.length())
				_try_issue_train(uid)
				return
			if game_hud:
				game_hud.set_status("指令：%s（未实现）" % action_id)


func _apply_command_card(card: Array) -> void:
	if game_hud != null:
		game_hud.set_command_card(card)
	_card_hotkey_actions.clear()
	for e in card:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d := e as Dictionary
		var id := str(d.get("id", "")).strip_edges()
		var hk := int(d.get("hotkey", 0))
		if id.is_empty() or hk == 0:
			continue
		if not bool(d.get("enabled", true)):
			continue
		_card_hotkey_actions[hk] = id


func _clear_command_card_hotkeys() -> void:
	_card_hotkey_actions.clear()


func _on_selection_changed(primary: Node3D, selected: Array) -> void:
	_set_move_targeting(false)
	_set_attack_targeting(false)
	_set_patrol_targeting(false)
	_set_harvest_targeting(false)
	_set_rally_targeting(false)
	_build_menu_open = false
	if _is_build_targeting():
		_cancel_build_targeting()
	if health_bar_manager:
		health_bar_manager.set_selection(selected)
	if game_hud == null:
		_sync_rally_flag_for_selection()
		return
	if primary == null or selected.is_empty():
		_card_supports_move = false
		_card_is_peasant = false
		_clear_command_card_hotkeys()
		_unbind_hud_build_site()
		game_hud.set_selection_info(SelectionInfoBuilder.build_empty())
		game_hud.clear_build_progress()
		if game_hud.has_method("clear_train_queue"):
			game_hud.clear_train_queue()
		game_hud.clear_command_labels()
		game_hud.set_status("未选中")
		_sync_rally_flag_for_selection()
		return
	_apply_selection_info_to_hud(primary, selected)
	var d: Dictionary = primary.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "?"))
	# 中立金矿：黄环；命令卡清空；详情里已有储量
	if tid == "ngol" or _is_gold_mine(primary):
		_card_supports_move = false
		_card_is_peasant = false
		_unbind_hud_build_site()
		game_hud.clear_build_progress()
		if game_hud.has_method("clear_train_queue"):
			game_hud.clear_train_queue()
		game_hud.clear_command_labels()
		var gold_left := int(d.get("goldAmount", -1))
		var rt := GoldMineRuntime.ensure(primary)
		if rt != null:
			gold_left = rt.remaining_gold
		elif gold_left < 0:
			gold_left = 12500
		game_hud.set_status("金矿 · 剩余 %d 金" % gold_left)
		_sync_rally_flag_for_selection()
		return
	# 可训建筑（主城/兵营/祭坛等）：训练命令卡
	if not CommandButtonCatalog.get_shared().get_trains(tid).is_empty():
		_card_supports_move = false
		_card_is_peasant = false
		_apply_building_train_card(primary, tid)
		if UnitLife.is_under_construction(primary):
			game_hud.set_status("建造中：%s · 可设集结点" % tid)
		else:
			game_hud.set_status("已选 %s · 训练见命令卡" % tid)
	elif _command_router != null and not _command_router.filter_movers(selected).is_empty():
		_card_supports_move = true
		_refresh_command_card()
		if _card_is_peasant:
			game_hud.set_status("已选 %s · 农民命令卡（采集/交回/建造热键见按钮）" % tid)
		else:
			game_hud.set_status("已选 %s · 移动/停止见命令卡" % tid)
	else:
		_card_supports_move = false
		_card_is_peasant = false
		_clear_command_card_hotkeys()
		game_hud.clear_command_labels()
		if UnitLife.is_under_construction(primary):
			game_hud.set_status("建造中：%s" % tid)
		else:
			game_hud.set_status("已选 %s" % tid)
	_sync_build_hud_for_selection()
	_sync_rally_flag_for_selection()


func _apply_selection_info_to_hud(primary: Node3D, selected: Array) -> void:
	if game_hud == null:
		return
	if not game_hud.has_method("set_selection_info"):
		_apply_unit_info_to_hud(primary, "")
		return
	game_hud.set_selection_info(SelectionInfoBuilder.build(primary, selected))


func _apply_unit_info_to_hud(unit: Node3D, label: String) -> void:
	if game_hud == null or unit == null:
		return
	UnitLife.ensure(unit)
	var hp := int(round(UnitLife.get_life(unit)))
	var hp_max := int(round(UnitLife.get_max_life(unit)))
	var name_s := label
	if name_s.is_empty():
		var d: Dictionary = unit.get_meta("unit_data", {})
		name_s = str(d.get("typeId", "—"))
	game_hud.set_unit_info(name_s, hp, hp_max)


func _sync_selection_info_panel() -> void:
	if unit_selector == null or not unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	var selected: Array = []
	if unit_selector.has_method("get_selected"):
		selected = unit_selector.call("get_selected")
	if primary == null or game_hud == null:
		return
	_apply_selection_info_to_hud(primary, selected)
	_sync_build_hud_for_selection()


func _sync_build_hud_for_selection() -> void:
	if game_hud == null or unit_selector == null or not unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	if primary == null:
		_unbind_hud_build_site()
		game_hud.clear_build_progress()
		return
	# 选中半成品建筑
	if UnitLife.is_under_construction(primary):
		var r := UnitLife.ratio(primary)
		var d: Dictionary = primary.get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if game_hud.has_method("clear_train_queue"):
			game_hud.clear_train_queue()
		game_hud.set_build_progress(true, r, "建造 %s %d%%" % [tid, int(round(r * 100.0))])
		_unbind_hud_build_site()
		return
	# 选中正在施工的农民
	var bc := primary.get_node_or_null("BuildController") as BuildController
	var site: BuildSite = bc.current_site() if bc != null else null
	if site != null and site.is_active():
		if game_hud.has_method("clear_train_queue"):
			game_hud.clear_train_queue()
		_bind_hud_build_site(site)
		var total := site.total()
		var ratio := 0.0 if total <= 0.0 else clampf(site.elapsed() / total, 0.0, 1.0)
		var order := site.current_order()
		var bid := order.building_id if order != null else ""
		game_hud.set_build_progress(true, ratio, "建造 %s %d%%" % [bid, int(round(ratio * 100.0))])
		return
	# 选中正在训练的建筑 → 独立生产队列 HUD（不用建造进度条）
	var tq := primary.get_node_or_null("TrainQueue") as TrainQueue
	if tq != null and tq.is_training():
		_unbind_hud_build_site()
		game_hud.clear_build_progress()
		_wire_train_queue(tq)
		_push_train_queue_hud(tq)
		return
	_unbind_hud_build_site()
	game_hud.clear_build_progress()
	if game_hud.has_method("clear_train_queue"):
		game_hud.clear_train_queue()


func _push_train_queue_hud(tq: TrainQueue) -> void:
	if game_hud == null or tq == null:
		return
	if not game_hud.has_method("set_train_queue"):
		return
	var slots: Array = []
	var cat := CommandButtonCatalog.get_shared()
	for e in tq.snapshot():
		var uid := str(e.get("unit_id", ""))
		var entry := cat.unit_hud_entry(uid, "train:" + uid, {})
		slots.append({
			"unit_id": uid,
			"name": str(entry.get("name", uid)),
			"icon": str(entry.get("icon", "")),
			"progress": float(e.get("progress", 0.0)),
			"active": bool(e.get("active", false)),
			"remaining_sec": float(e.get("remaining_sec", 0.0)),
			"tooltip": "%s · 点击取消" % str(entry.get("name", uid)),
		})
	game_hud.set_train_queue(slots, tq.queue_count(), TrainQueue.MAX_QUEUE)


func _bind_hud_build_site(site: BuildSite) -> void:
	if site == null or site == _hud_build_site:
		return
	_unbind_hud_build_site()
	_hud_build_site = site
	if not site.progress_changed.is_connected(_on_hud_build_site_progress):
		site.progress_changed.connect(_on_hud_build_site_progress)


func _unbind_hud_build_site() -> void:
	if _hud_build_site != null and is_instance_valid(_hud_build_site):
		if _hud_build_site.progress_changed.is_connected(_on_hud_build_site_progress):
			_hud_build_site.progress_changed.disconnect(_on_hud_build_site_progress)
	_hud_build_site = null


func _on_hud_build_site_progress(elapsed: float, total: float, ratio: float) -> void:
	if game_hud == null:
		return
	var bid := ""
	if _hud_build_site != null:
		var order := _hud_build_site.current_order()
		if order != null:
			bid = order.building_id
	var caption := "建造 %s %d%%" % [bid, int(round(ratio * 100.0))]
	if total > 0.0:
		caption += " · %.0f/%.0fs" % [elapsed, total]
	game_hud.set_build_progress(true, ratio, caption)
	_sync_selection_info_panel_hp_only()


func _sync_selection_info_panel_hp_only() -> void:
	if unit_selector == null or game_hud == null or not unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	if primary == null:
		return
	var selected: Array = []
	if unit_selector.has_method("get_selected"):
		selected = unit_selector.call("get_selected")
	_apply_selection_info_to_hud(primary, selected)


func _update_build_hud_if_relevant(key: String, ratio: float, elapsed: float, total: float) -> void:
	if game_hud == null or unit_selector == null or not unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	if primary == null:
		return
	var rec: Dictionary = _active_construction.get(key, {})
	var node: Node3D = rec.get("node") as Node3D
	var bid := str(rec.get("building_id", ""))
	var watching := false
	if node != null and primary == node:
		watching = true
	elif primary.get_node_or_null("BuildController") != null:
		var bc := primary.get_node_or_null("BuildController") as BuildController
		if bc != null and _construction_key(bc.current_order()) == key:
			watching = true
	if not watching:
		return
	var caption := "建造 %s %d%%" % [bid, int(round(ratio * 100.0))]
	if total > 0.0:
		caption += " · %.0f/%.0fs" % [elapsed, total]
	game_hud.set_build_progress(true, ratio, caption)
	if primary == node:
		_apply_unit_info_to_hud(primary, bid)


## 竖切可造列表 = UnitFunc Builds ∩ VERTICAL_BUILDING_IDS。
func _build_building_ids(worker_type_id: String = "hpea") -> PackedStringArray:
	var allow := PackedStringArray()
	for bid in BuildingCatalog.VERTICAL_BUILDING_IDS:
		allow.append(str(bid))
	return CommandButtonCatalog.get_shared().filter_builds(worker_type_id, allow)


## 建造按钮启用：仅 Requires 解锁；资源不足不置灰，点下再提示。
func _build_unlocked_flags(building_ids: PackedStringArray) -> PackedInt32Array:
	var owned := _owned_buildings_for_local()
	var req_cat := UnitRequiresCatalog.get_shared()
	var arr := PackedInt32Array()
	for bid in building_ids:
		var missing := TechPresence.missing_requires(owned, req_cat.get_requires(str(bid)))
		arr.append(0 if not missing.is_empty() else 1)
	return arr


## 置灰原因：仅未解锁（Requires）；资源不足不走这里。
func _build_disabled_reasons(building_ids: PackedStringArray) -> PackedStringArray:
	var owned := _owned_buildings_for_local()
	var req_cat := UnitRequiresCatalog.get_shared()
	var arr := PackedStringArray()
	for bid in building_ids:
		var missing := TechPresence.missing_requires(owned, req_cat.get_requires(str(bid)))
		arr.append(TechPresence.requires_tip(missing) if not missing.is_empty() else "")
	return arr


func _build_executing_flags(building_ids: PackedStringArray) -> PackedInt32Array:
	var arr := PackedInt32Array()
	for _bid in building_ids:
		arr.append(0) ## F2-4 简化：未来接 _is_any_peasant_building(_bid) 再开
	return arr


func _refresh_command_card() -> void:
	if game_hud == null or not _card_supports_move or unit_selector == null:
		return
	if not unit_selector.has_method("get_selected"):
		return
	var selected: Array = unit_selector.call("get_selected")
	var primary: Node3D = null
	if unit_selector.has_method("get_primary"):
		primary = unit_selector.call("get_primary") as Node3D
	var moving := false
	var carrying := false
	var harvesting := false
	var returning := false
	if _command_router != null:
		moving = _command_router.any_moving(selected)
		# 命令卡跟当前选中：仅 primary 是农民时显示农民卡
		var primary_peasants: Array = []
		if primary != null:
			primary_peasants = _command_router.filter_peasants([primary])
		_card_is_peasant = not primary_peasants.is_empty()
		if _card_is_peasant:
			var peasants := _command_router.filter_peasants(selected)
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
		_apply_peasant_command_card(selected, moving, carrying, harvesting, returning)
	else:
		_build_menu_open = false
		var tid := _primary_type_id(selected)
		if tid.is_empty():
			_apply_command_card(CommandCard.basic_locomotion(moving))
		elif BuildingCatalog.is_building(tid) and not CommandButtonCatalog.get_shared().get_trains(tid).is_empty():
			var primary_b: Node3D = null
			if unit_selector != null and unit_selector.has_method("get_primary"):
				primary_b = unit_selector.call("get_primary") as Node3D
			_apply_building_train_card(primary_b, tid)
		else:
			_apply_command_card(
				CommandCard.for_unit(
					tid,
					{
						"move_executing": moving,
						"include_locomotion": true,
						"owned_buildings": _owned_buildings_for_local(),
					}
				)
			)


func _apply_peasant_command_card(
	selected: Array,
	moving: bool,
	carrying: bool,
	harvesting: bool,
	returning: bool
) -> void:
	var worker_tid := _primary_type_id(selected)
	if worker_tid.is_empty():
		worker_tid = "hpea"
	var build_ids := _build_building_ids(worker_tid)
	_apply_command_card(
		CommandCard.for_unit(
			worker_tid,
			{
				"move_executing": moving,
				"carrying": carrying,
				"harvest_executing": harvesting and not carrying,
				"return_executing": returning,
				"building_ids": build_ids,
				"can_afford": _build_unlocked_flags(build_ids),
				"build_disabled_reasons": _build_disabled_reasons(build_ids),
				"building_executing": _build_executing_flags(build_ids),
				"build_menu_open": _build_menu_open,
				"worker_race": "human",
			}
		)
	)


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
	var is_peasant := false
	if _command_router != null and unit_selector != null and unit_selector.has_method("get_primary"):
		var primary: Node3D = unit_selector.call("get_primary") as Node3D
		if primary != null:
			is_peasant = not _command_router.filter_peasants([primary]).is_empty()
	_card_is_peasant = is_peasant
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
	# 互斥格可能从采集切到交回，需整卡刷新（保留建造二级面板）
	if is_peasant:
		_apply_peasant_command_card(selected, moving, carrying, harvesting, returning)
	else:
		game_hud.set_command_executing(CommandCard.ACTION_MOVE, moving)


func _primary_type_id(_selected: Array = []) -> String:
	if unit_selector != null and unit_selector.has_method("get_primary"):
		var p: Node3D = unit_selector.call("get_primary") as Node3D
		if p != null and is_instance_valid(p):
			var d: Dictionary = p.get_meta("unit_data", {})
			return str(d.get("typeId", "")).strip_edges()
	if not _selected.is_empty() and _selected[0] is Node3D:
		var d2: Dictionary = (_selected[0] as Node3D).get_meta("unit_data", {})
		return str(d2.get("typeId", "")).strip_edges()
	return ""
