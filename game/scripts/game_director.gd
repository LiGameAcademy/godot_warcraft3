class_name GameDirector
extends Node

const SceneDelay = preload("res://scripts/shared/infra/scene_delay.gd")

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
## 双方开局接入验证；电脑经营控制器尚未接入时默认关闭。
@export var spawn_opponent_base: bool = false
@export var enable_opponent_economy: bool = false
@export var enable_opponent_army: bool = false
## TODO(临时)：开局刷大法师便于测英雄技能，验收后删除。
@export var dev_spawn_archmage: bool = true
## TODO(临时)：开局刷牧师（含牧师大师训练 → 心灵之火），验收后删除。
@export var dev_spawn_priest: bool = true
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
var _command_router: CommandRouter = null
var _damage_pipeline: DamagePipeline = null
var _death_service: DeathService = null
var _item_service: ItemService
var _ground_items: Node3D
var _units: UnitsModule
var _build: BuildModule
var _combat: CombatModule
var _abilities: AbilitiesModule
var _items: ItemsModule
var _interaction: InteractionModule
var _smart_command: SmartCommandModule
var _command_card: CommandCardModule
var _selection_hud: SelectionHudModule
var _path_debug_mod: PathDebugModule
var _match_bootstrap: MatchBootstrapModule
var _match_lifecycle: MatchLifecycleModule
var _opponent_ai: OpponentAiModule
var _debug_tools: DebugToolsModule
var _projectile_service: ProjectileService = null
var _tree_registry: TreeRegistry = null
## 技能编排（由 AbilitiesModule 持有；此处保留别名便于旧入口）
var _ability_ctx_factory: AbilityCastContextFactory = null
var _ability_hud: AbilityHudFeedback = null
var _ability_runtime: AbilityRuntimeRegistry = null
var _ability_targeting_svc: AbilityTargetingService = null
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
## 英雄技能瞄准镜像（由 AbilityTargetingService 同步）
var _ability_targeting: bool = false
var _pending_ability_id: String = ""
## 选中可训建筑时显示的集结旗（长驻，复用）
var _rally_flag: RallyFlagFx = null
var _ability_preview_decal: BlizzardAreaDecal = null
## 瞄准期内被霜蓝染色的单位/建筑（Present）。
var _ability_preview_tinted: Array = []
var _ability_preview_tint_goal := Vector2.INF
var _ability_preview_tint_radius: float = 0.0

## F2-4：建造瞄准态（玩家按下建造按钮后进入）。
var _build_placement: BuildPlacementController = null
var _build_ghost: BuildPlacementGhost = null
## 确认落点后、开工前：工地半透明幽灵仍钉在地上（农民走动期间）。
var _site_ghost_pinned: bool = false
## 进入瞄准后须先移动鼠标再左键确认，避免点面板同一帧误提交。
var _build_confirm_armed: bool = false
## 鼠标 → godot 拾取（暴露给 Placement 控制器，避开循环引用）。
var _last_screen_pos: Vector2 = Vector2.ZERO
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
## 对局内生产功能及本地界面适配器；队列订阅由模块持有。
var _production: ProductionModule
var _production_panel: ProductionPanel


func _ready() -> void:
	_rng.randomize()
	AppLog.reload_config()
	_resolve_exports()
	if map_root == null:
		push_error("GameDirector: 未绑定 map_root")
		return
	_configure_map_root()
	var debug := _ensure_debug_tools_module()
	debug.ensure_gm_panel()
	debug.ensure_perf_overlay()
	_wire_hud()
	_load_camera_bounds()
	_configure_camera()
	if map_root.map_loaded.is_connected(_on_map_loaded) == false:
		map_root.map_loaded.connect(_on_map_loaded)
	if map_root.is_map_ready():
		_on_map_loaded()


func _toggle_gm_panel() -> void:
	_ensure_debug_tools_module().toggle_gm_panel()


func _apply_path_debug_visibility() -> void:
	if is_instance_valid(_path_debug_mod):
		_path_debug_mod.set_enabled(show_path_debug)


func get_session() -> GameSession:
	return _session


func is_session_ready() -> bool:
	return _bootstrapped


## 按本地玩家种族切换光标图集（human/orc/undead/nightelf）。
func _apply_cursor_race(race_id: String) -> void:
	if game_cursor == null:
		_resolve_exports()
	_ensure_interaction_module().set_cursor_race(race_id)


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
	AppLog.info(
		AppLog.Layer.GAME,
		"GameDirector",
		"bind map=%s cam=%s hud=%s sel=%s cursor=%s hpbar=%s"
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
	if game_hud != null:
		game_hud.item_use.connect(_on_item_use)
		game_hud.item_drop.connect(_on_item_drop)
		game_hud.item_swap.connect(_on_item_swap)
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
	if game_hud.has_signal("command_action_rclick") and not game_hud.command_action_rclick.is_connected(
		_on_command_action_rclick
	):
		game_hud.command_action_rclick.connect(_on_command_action_rclick)
	if game_hud.has_signal("multi_select_clicked") and not game_hud.multi_select_clicked.is_connected(_on_multi_select_clicked):
		game_hud.multi_select_clicked.connect(_on_multi_select_clicked)
	if game_hud.has_signal("train_queue_cancel") and not game_hud.train_queue_cancel.is_connected(_on_train_queue_cancel):
		game_hud.train_queue_cancel.connect(_on_train_queue_cancel)


func _setup_portrait_hud() -> void:
	_ensure_selection_hud_module().setup_portrait()


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
	# 点选：中立/敌方可点选观察；框选仅己方。下达指令另见「可控」过滤。
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
	# 背包点击交给 GUI，包括移动/技能瞄准期间，不把槽位当世界落点。
	if event is InputEventMouseButton and is_instance_valid(game_hud) and is_instance_valid(game_hud.inventory_panel):
		var panel := game_hud.inventory_panel
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(event.position):
			return
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
			else:
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
			else:
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
	# 技能瞄准：左键点地/点单位施法
	if _ability_targeting and event is InputEventMouseButton and _ability_targeting_svc != null:
		var mb_ab := event as InputEventMouseButton
		if mb_ab.pressed and mb_ab.button_index == MOUSE_BUTTON_LEFT:
			var abil_id := _ability_targeting_svc.pending_abil_id()
			var tk := AbilityCatalog.target_kind(abil_id)
			if tk == AbilityCatalog.TARGET_UNIT or tk == AbilityCatalog.TARGET_ALLY:
				_ability_targeting_svc.issue_at_unit_screen(mb_ab.position, UnitOrder.Source.TARGETING)
			else:
				_ability_targeting_svc.issue_at_screen(mb_ab.position, UnitOrder.Source.TARGETING)
			_ability_targeting_svc.cancel()
			get_viewport().set_input_as_handled()
			return
		if mb_ab.pressed and mb_ab.button_index == MOUSE_BUTTON_RIGHT:
			_ability_targeting_svc.cancel()
			get_viewport().set_input_as_handled()
			return
	# F2-4：建造瞄准 → 左键 commit / 右键 cancel / mousemove 跟手 ghost
	# 任何鼠标事件都记录最新位置，给 build_placement 跟手用
	if event is InputEventMouseMotion:
		_last_screen_pos = (event as InputEventMouseMotion).position
		_ensure_build_module()
		_build.update_last_screen_pos(_last_screen_pos)
		if _ability_targeting:
			_update_ability_preview(_last_screen_pos)
		if _build.is_build_targeting():
			_build.set_confirm_armed(true)
			_build.update_placement_screen(_last_screen_pos)
	if _build.is_build_targeting() and event is InputEventMouseButton:
		var mb_b := event as InputEventMouseButton
		if mb_b.pressed and mb_b.button_index == MOUSE_BUTTON_LEFT:
			# 点在 HUD/小地图上不提交；须先移动过鼠标再确认
			if not _build.is_confirm_armed() or _pointer_over_blocking_gui():
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
	_wire_all_gold_mines()
	_wire_all_unit_ai()
	if enable_opponent_economy:
		_setup_opponent_economy()
	if dev_spawn_archmage:
		call_deferred("_dev_spawn_archmage")
	if dev_spawn_priest:
		call_deferred("_dev_spawn_priest")
	# 地形材质已就绪后再刷调试栅格，避免 ready 阶段空材质警告
	if map_root != null:
		map_root.set_view_grid_level(view_grid_level)
	_setup_match_end()
	session_ready.emit()


func _setup_match_end() -> void:
	_ensure_match_lifecycle_module().setup_match_end(_session, spawn_opponent_base)


func _setup_opponent_economy() -> void:
	_ensure_opponent_ai_module().setup(local_player, enable_opponent_army)


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
	_ensure_combat_module()
	_ensure_abilities_module()
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
	if not _command_router.production_queue_ready.is_connected(_wire_train_queue):
		_command_router.production_queue_ready.connect(_wire_train_queue)
	_ensure_production_module()
	_setup_tree_registry()
	_ensure_path_debug()
	_ensure_items_module()
	_ensure_units_module()
	_ensure_interaction_module()
	_ensure_smart_command_module()
	_ensure_command_card_module()
	_ensure_selection_hud_module()


func _award_death_experience(victim: Node3D, killer: Node3D) -> void:
	# 兼容旧接线；实际由 CombatModule 处理。
	if is_instance_valid(_combat):
		_combat.call("_award_death_experience", victim, killer)


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
	_ensure_path_debug_module().ensure_draw()


func _process(delta: float) -> void:
	if _session != null and spawn_opponent_base and is_session_ready():
		var result := _session.evaluate_match(map_root.get_unit_layer())
		if bool(result.finished):
			return
	if is_instance_valid(_combat):
		_combat.tick(delta)
	if is_instance_valid(_abilities):
		_abilities.tick(delta)
	_refresh_move_executing_ui()
	_ensure_selection_hud_module().tick(delta)
	if is_instance_valid(_path_debug_mod):
		_path_debug_mod.tick(delta)
	_ensure_command_card_module().tick_cooldown_hud(delta)


## 技能 CD 进行中时低频刷命令卡，驱动扇形遮罩进度（否则只在施法瞬间刷一次会「卡住」）。
func _tick_command_card_cooldown_hud(delta: float) -> void:
	_ensure_command_card_module().tick_cooldown_hud(delta)


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
	var result := _ensure_match_bootstrap_module().bootstrap_melee({
		"preview_race": preview_race,
		"local_player": local_player,
		"random_start_location": random_start_location,
		"spawn_melee_base": spawn_melee_base,
		"spawn_opponent_base": spawn_opponent_base,
	})
	_session = result.get("session") as GameSession


## 兼容测试入口：重复刷对手基地应返回 false。
func _spawn_opponent_base(slocs: Array[Dictionary], local_sloc: Dictionary) -> bool:
	if _session == null:
		return false
	return _ensure_match_bootstrap_module().spawn_opponent_base(
		_session, slocs, local_sloc, local_player
	)


## TODO(临时)：开局在己方主城旁刷 Hamg，便于测技能/暴风雪；验收后整段删除。
func _dev_spawn_archmage() -> void:
	var hall := _find_local_town_hall()
	if hall == null:
		push_warning("GameDirector[dev]: 未找到己方主城，跳过大法师")
		return
	var node := _ensure_units_module().spawn_near(
		hall, "Hamg", local_player, Vector2(192.0, -192.0),
		{"ensure_hero": true, "charge_food": true}
	)
	if node == null:
		push_warning("GameDirector[dev]: 大法师刷出失败")
		return
	if unit_selector != null and unit_selector.has_method("select_node"):
		unit_selector.call("select_node", node)
	if game_hud:
		game_hud.set_status("开发：已刷大法师（dev_spawn_archmage）")


## TODO(临时)：开局在己方主城旁刷 hmpr，并授予牧师大师训练（Rhpt L2 → 心灵之火）。
func _dev_spawn_priest() -> void:
	var hall := _find_local_town_hall()
	if hall == null:
		push_warning("GameDirector[dev]: 未找到己方主城，跳过牧师")
		return
	var stock := _local_stock()
	if stock != null:
		stock.grant_upgrade("Rhpt", 2)
	var node := _ensure_units_module().spawn_near(
		hall, "hmpr", local_player, Vector2(64.0, -256.0),
		{"ensure_caster": true, "charge_food": true}
	)
	if node == null:
		push_warning("GameDirector[dev]: 牧师刷出失败")
		return
	if unit_selector != null and unit_selector.has_method("select_node"):
		unit_selector.call("select_node", node)
	if game_hud:
		game_hud.set_status("开发：已刷牧师（Rhpt 大师 · 心灵之火）")


func _find_local_town_hall() -> Node3D:
	return _ensure_units_module().find_owned_unit_by_types(
		local_player, PackedStringArray(["htow", "hkee", "hcas"])
	)


func _order_militia_move_to_hall(unit: Node3D, hall: Node3D) -> void:
	if unit == null or hall == null or _command_router == null:
		return
	if not is_instance_valid(unit) or not is_instance_valid(hall):
		return
	var goal := Wc3Coords.godot_to_wc3_xy(hall.global_position)
	_command_router.issue_move_to_wc3([unit], goal, UnitOrder.Source.PANEL)


func _unhandled_input(event: InputEvent) -> void:
	# 移动/采集/建造瞄准：Esc 取消（落点已在 _input 处理）
	if (
		(
			_move_targeting
			or _attack_targeting
			or _patrol_targeting
			or _harvest_targeting
			or _rally_targeting
			or _ability_targeting
			or _is_build_targeting()
		)
		and event is InputEventKey
		and event.pressed
		and not event.echo
	):
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_ensure_interaction_module().cancel_aim("escape")
			_sync_aim_flags_from_interaction()
			get_viewport().set_input_as_handled()
			return
	# 建造二级面板：Esc → 回主卡
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			if _ensure_command_card_module().handle_submenu_escape():
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
		if _ensure_command_card_module().try_hotkey(key):
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F9:
			show_path_debug = not show_path_debug
			_ensure_path_debug()
			_apply_path_debug_visibility()
			if game_hud:
				game_hud.set_status("路径调试：%s" % ("开" if show_path_debug else "关"))
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F3 or phys == KEY_F3:
			_ensure_debug_tools_module().toggle_perf_overlay()
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
	var selected: Array = _get_selected_safe()
	_interrupt_channels_for_units(selected)
	var n_stop := _command_router.issue_stop(selected, source)
	if n_stop > 0 and game_hud:
		game_hud.set_status("停止 · %d 单位" % n_stop)
	_refresh_command_card()
	return n_stop > 0


func _issue_hold(source: int = UnitOrder.Source.UNKNOWN) -> bool:
	if _command_router == null or unit_selector == null:
		return false
	var selected: Array = _get_selected_safe()
	_interrupt_channels_for_units(selected)
	var n := _command_router.issue_hold(selected, source)
	if n > 0 and game_hud:
		game_hud.set_status("保持原位 · %d 单位" % n)
	elif game_hud:
		game_hud.set_status("保持原位：无可用单位")
	_refresh_command_card()
	return n > 0


func _try_toggle_defend(_source: int = UnitOrder.Source.UNKNOWN) -> void:
	if _command_router == null:
		return
	var stock := _local_stock()
	if stock == null or not stock.has_upgrade(DefendController.UPGRADE_ID):
		if game_hud:
			game_hud.set_status("需要研究：%s" % TechPresence.display_name(DefendController.UPGRADE_ID))
		return
	var selected := _get_selected_safe()
	if selected.is_empty():
		return
	var primary: Node3D = null
	if unit_selector != null and unit_selector.has_method("get_primary"):
		primary = unit_selector.call("get_primary") as Node3D
	var want := not DefendController.is_defending(primary)
	var n := _command_router.issue_defend(selected, want)
	if game_hud:
		if n <= 0:
			game_hud.set_status("顶盾：无可用步兵")
		elif want:
			game_hud.set_status("顶盾开启 · %d 单位" % n)
		else:
			game_hud.set_status("停止顶盾 · %d 单位" % n)
	_refresh_command_card()


## 攻击瞄准落点：单位 → Attack（P0 追击）；地面 → Attack-Move。
func _issue_attack_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _command_router == null or unit_selector == null:
		return false
	var selected: Array = _get_selected_safe()
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
	var selected: Array = _get_selected_safe()
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
	var selected: Array = _get_selected_safe()
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
	if unit_selector == null:
		return false
	var selected: Array = _get_selected_safe()
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
const SMART_BUILDING_FOOT_PX := 40.0 ## 保留常量别名；实际阈值在 SmartCommandModule


func _resolve_smart_target(screen_pos: Vector2, selected: Array) -> SmartTarget:
	return _ensure_smart_command_module().resolve_smart_target(screen_pos, selected)


func _flash_tree_target(creation_number: int) -> void:
	_ensure_smart_command_module().flash_tree_target(creation_number)


func _format_smart_status(result: Dictionary) -> String:
	return _ensure_smart_command_module().format_smart_status(result)


## 对当前选中可移动单位下发移动（经 CommandRouter）。
func _issue_move_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _command_router == null or unit_selector == null or _path_query == null:
		return false
	var selected: Array = _get_selected_safe()
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
	if not unit_selector.has_method("get_primary"):
		return false
	var selected: Array = _get_selected_safe()
	if selected.is_empty():
		return false
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	if primary == null or not _is_controllable(primary) or not selected.has(primary):
		primary = selected[0] as Node3D
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
	var selected: Array = _get_selected_safe()
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
	var selected: Array = _get_selected_safe()
	var n := _command_router.issue_return_goods(selected, source)
	if n > 0 and game_hud:
		game_hud.set_status("送回资源 · %d 农民" % n)
	elif game_hud:
		game_hud.set_status("送回：无负重农民")
	_refresh_command_card()
	return n > 0


func _begin_move_targeting(source: int) -> void:
	var selected: Array = _get_selected_safe()
	if _command_router == null or _command_router.filter_movers(selected).is_empty():
		if game_hud:
			game_hud.set_status("移动：无可用单位")
		return
	_interrupt_channels_for_units(selected)
	_ensure_interaction_module().begin_aim(InteractionModule.Aim.MOVE)
	_sync_aim_flags_from_interaction()
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键 M"
		game_hud.set_status("移动瞄准（%s）· 左键指定地点 · Esc 取消" % src)


func _begin_attack_targeting(source: int) -> void:
	var selected: Array = _get_selected_safe()
	if _command_router == null or _command_router.filter_movers(selected).is_empty():
		if game_hud:
			game_hud.set_status("攻击：无可用单位")
		return
	_ensure_interaction_module().begin_aim(InteractionModule.Aim.ATTACK)
	_sync_aim_flags_from_interaction()
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键 A"
		game_hud.set_status("攻击瞄准（%s）· 左键单位/地面 · Esc 取消" % src)


func _begin_patrol_targeting(source: int) -> void:
	var selected: Array = _get_selected_safe()
	if _command_router == null or _command_router.filter_movers(selected).is_empty():
		if game_hud:
			game_hud.set_status("巡逻：无可用单位")
		return
	_ensure_interaction_module().begin_aim(InteractionModule.Aim.PATROL)
	_sync_aim_flags_from_interaction()
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键 P"
		game_hud.set_status("巡逻瞄准（%s）· 左键指定另一端 · Esc 取消" % src)


func _begin_harvest_targeting(source: int) -> void:
	var selected: Array = _get_selected_safe()
	if _command_router == null or _command_router.filter_peasants(selected).is_empty():
		if game_hud:
			game_hud.set_status("采集：无农民")
		return
	_ensure_interaction_module().begin_aim(InteractionModule.Aim.HARVEST)
	_sync_aim_flags_from_interaction()
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键 G"
		game_hud.set_status("采集瞄准（%s）· 左键点金矿 · Esc 取消" % src)


func _begin_rally_targeting(source: int) -> void:
	var selected: Array = _get_selected_safe()
	var any := false
	for n in selected:
		if n is Node3D and BuildingRally.can_set_rally(n as Node3D):
			any = true
			break
	if not any:
		if game_hud:
			game_hud.set_status("集结点：请选中可训练建筑")
		return
	_ensure_interaction_module().begin_aim(InteractionModule.Aim.RALLY)
	_sync_aim_flags_from_interaction()
	if game_hud:
		var src := "面板" if source == UnitOrder.Source.PANEL else "热键"
		game_hud.set_status("集结瞄准（%s）· 左键点地面/金矿/树 · Esc 取消" % src)


func _setup_ability_services() -> void:
	_ensure_abilities_module()


func _ability_set_status(text: String) -> void:
	if game_hud:
		game_hud.set_status(text)


func _ability_get_primary() -> Node3D:
	if unit_selector == null or not unit_selector.has_method("get_primary"):
		return null
	var primary := unit_selector.call("get_primary") as Node3D
	if not _is_controllable(primary):
		return null
	return primary


func _local_owner_id() -> int:
	if _session != null:
		return int(_session.local_player)
	return local_player


## 本地玩家是否可对该单位下达指令（点选仍可观察非己方）。
## 尸体 / 离场单位视为不可控（与野怪一样清空命令卡）。
func _is_controllable(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not CombatQuery.is_alive_in_world(node):
		return false
	return CombatQuery.is_controllable(node, _local_owner_id())


func _get_selected_safe() -> Array:
	if unit_selector == null or not unit_selector.has_method("get_selected"):
		return []
	var raw: Array = unit_selector.call("get_selected")
	if _command_router != null:
		return _command_router.filter_controllable(raw)
	var out: Array = []
	for n in raw:
		if n is Node3D and _is_controllable(n as Node3D):
			out.append(n)
	return out


func _ability_pick_at(screen_pos: Vector2) -> Node3D:
	if unit_selector == null or not unit_selector.has_method("pick_at"):
		return null
	return unit_selector.call("pick_at", screen_pos) as Node3D


func _clear_rival_targeting_for_ability() -> void:
	# begin_targeting 时 ability 尚未 adopt；清掉 move/attack/build 等互斥态
	if is_instance_valid(_interaction):
		var a := _interaction.current_aim()
		if a != InteractionModule.Aim.NONE and a != InteractionModule.Aim.ABILITY:
			_interaction.cancel_aim("rival_for_ability")
			_sync_aim_flags_from_interaction()
	else:
		_set_move_targeting(false)
		_set_attack_targeting(false)
		_set_patrol_targeting(false)
		_set_harvest_targeting(false)
		_set_rally_targeting(false)


func _ability_blizzard_preview_refresh() -> void:
	_update_ability_preview(_last_screen_pos)


func _on_ability_targeting_changed(active: bool, abil_id: String) -> void:
	_ability_targeting = active
	_pending_ability_id = abil_id.strip_edges() if active else ""
	if active:
		var kind := AbilityCatalog.target_kind(_pending_ability_id)
		_ensure_interaction_module().adopt_external_aim(
			InteractionModule.Aim.ABILITY, {"abil_id": _pending_ability_id, "target_kind": kind}
		)
		_sync_aim_flags_from_interaction()
		_ability_targeting = true
		_pending_ability_id = abil_id.strip_edges()
	else:
		if is_instance_valid(_interaction) and _interaction.is_ability():
			_interaction.cancel_aim("ability_end")
			_sync_aim_flags_from_interaction()
		_clear_ability_preview()
	_sync_selector_enabled_for_targeting()
	# 光标由 InteractionModule 统一设置（友方 → ALLY）


func _begin_ability_targeting(abil_id: String, source: int) -> void:
	_ensure_abilities_module().begin_targeting(abil_id, source)


## 自身技能（雷霆一击 / 天神下凡）：点按钮即施法。
func _issue_self_ability(abil_id: String, source: int) -> bool:
	return _ensure_abilities_module().issue_self(abil_id, source)


## 单位目标技能：瞄准态左键点单位。
func _issue_ability_at_unit_screen(screen_pos: Vector2, source: int) -> bool:
	return _ensure_abilities_module().issue_at_unit_screen(screen_pos, source)


## 技能瞄准落点：点地召唤 / 区域 DOT 等。
func _issue_ability_at_screen(screen_pos: Vector2, source: int) -> bool:
	return _ensure_abilities_module().issue_at_screen(screen_pos, source)


func _on_ability_cast_resolved(result: Dictionary, abil_id: String) -> void:
	# 兼容旧入口；实际由 AbilitiesModule 处理。
	if is_instance_valid(_abilities):
		_abilities.call("_on_cast_resolved", result, abil_id)


func _ability_cast_context() -> Dictionary:
	return _ensure_abilities_module().cast_context()


func _kill_unit(unit: Node3D) -> void:
	_ensure_combat_module().kill(unit)


## 引导开场清空命令队列（见 AbilityCastController._stop_caster_for_cast）。
func _clear_caster_orders(caster: Node3D) -> void:
	_ensure_abilities_module().clear_caster_orders(caster)


## 引导中 / 接近施法点：玩家新指令（非 AI）→ 打断暴风雪等。
func _ability_channel_interrupt_check(caster: Node3D) -> bool:
	return _ensure_abilities_module().channel_interrupt_check(caster)


func _ability_ui_state_for(primary: Node3D) -> Dictionary:
	return _ensure_abilities_module().ui_state_for(primary)


func _ensure_caster_runtime(unit: Node3D) -> void:
	_ensure_abilities_module().ensure_unit(unit)


func _ensure_hero_runtime(unit: Node3D) -> void:
	_ensure_units_module().ensure_hero(unit)


func _set_ability_targeting(active: bool, abil_id: String = "") -> void:
	_ensure_abilities_module().set_targeting(active, abil_id)


func _set_move_targeting(active: bool) -> void:
	if active:
		_ensure_interaction_module().begin_aim(InteractionModule.Aim.MOVE)
	elif is_instance_valid(_interaction) and _interaction.is_move():
		_interaction.cancel_aim()
	_sync_aim_flags_from_interaction()


func _set_attack_targeting(active: bool) -> void:
	if active:
		_ensure_interaction_module().begin_aim(InteractionModule.Aim.ATTACK)
	elif is_instance_valid(_interaction) and _interaction.is_attack():
		_interaction.cancel_aim()
	_sync_aim_flags_from_interaction()


func _set_patrol_targeting(active: bool) -> void:
	if active:
		_ensure_interaction_module().begin_aim(InteractionModule.Aim.PATROL)
	elif is_instance_valid(_interaction) and _interaction.is_patrol():
		_interaction.cancel_aim()
	_sync_aim_flags_from_interaction()


func _set_harvest_targeting(active: bool) -> void:
	if active:
		_ensure_interaction_module().begin_aim(InteractionModule.Aim.HARVEST)
	elif is_instance_valid(_interaction) and _interaction.is_harvest():
		_interaction.cancel_aim()
	_sync_aim_flags_from_interaction()


func _set_rally_targeting(active: bool) -> void:
	if active:
		_ensure_interaction_module().begin_aim(InteractionModule.Aim.RALLY)
	elif is_instance_valid(_interaction) and _interaction.is_rally():
		_interaction.cancel_aim()
	_sync_aim_flags_from_interaction()


func _sync_aim_flags_from_interaction() -> void:
	if not is_instance_valid(_interaction):
		return
	var a := _interaction.current_aim()
	_move_targeting = a == InteractionModule.Aim.MOVE
	_attack_targeting = a == InteractionModule.Aim.ATTACK
	_patrol_targeting = a == InteractionModule.Aim.PATROL
	_harvest_targeting = a == InteractionModule.Aim.HARVEST
	_rally_targeting = a == InteractionModule.Aim.RALLY
	_ability_targeting = a == InteractionModule.Aim.ABILITY
	_sync_selector_enabled_for_targeting()


func _sync_selector_enabled_for_targeting() -> void:
	if unit_selector == null:
		return
	unit_selector.enabled = not (
		_move_targeting
		or _attack_targeting
		or _patrol_targeting
		or _harvest_targeting
		or _rally_targeting
		or _ability_targeting
		or _is_build_targeting()
	)


func _flash_cursor_move() -> void:
	# 先退出瞄准再 flash，避免 set_move_targeting(false)→IDLE 掐死箭头动画
	if is_instance_valid(_interaction):
		_interaction.flash_move_confirm()
		_sync_aim_flags_from_interaction()
	elif game_cursor is Wc3GameCursor:
		(game_cursor as Wc3GameCursor).flash_move()
	elif game_cursor != null and game_cursor.has_method("flash_move"):
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
		and _is_controllable(primary)
		and BuildingRally.can_set_rally(primary)
		and BuildingRally.has_rally(primary)
	):
		return primary
	var selected: Array = _get_selected_safe()
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
			Callable(self, "_stock_for_unit").bind(unit),
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
		Callable(self, "_stock_for_unit").bind(unit),
		Callable(self, "_unit_host"),
		Callable(self, "_path_query_ref"),
		Callable(self, "_crowd_query_ref"),
		Callable(self, "_tree_registry_ref")
	)
	unit.add_child(hc)
	_wire_harvest_signals(hc)
	return hc


func _ensure_attack_controller(unit: Node3D) -> AttackController:
	return _ensure_combat_module().ensure_attack_controller(unit)


## U0-2：可战斗非建筑单位挂 UnitAI + AttackController；中立 → CAMP_CREEP。
func _ensure_unit_ai(unit: Node3D) -> UnitAI:
	return _ensure_units_module().ensure_combat_ai(unit)


## 地图已有单位 + 开局刷兵：pathing/战斗服务就绪后批量挂 AI。
func _wire_all_unit_ai() -> void:
	_ensure_units_module().wire_existing()


func _ensure_militia_controller(unit: Node3D) -> MilitiaController:
	if unit == null or not is_instance_valid(unit):
		return null
	if not MilitiaController.unit_has_abil(unit):
		return null
	var existing := MilitiaController.of(unit)
	if existing != null:
		existing.configure(
			Callable(self, "_apply_unit_form"),
			Callable(self, "_find_local_town_hall"),
			Callable(self, "_order_militia_move_to_hall")
		)
		return existing
	var mc := MilitiaController.new()
	mc.name = MilitiaController.NODE_NAME
	mc.configure(
		Callable(self, "_apply_unit_form"),
		Callable(self, "_find_local_town_hall"),
		Callable(self, "_order_militia_move_to_hall")
	)
	unit.add_child(mc)
	return mc


## 就地换 typeId + 模型（农民↔民兵）。保持同一 Unit 节点与 creationNumber。
func _apply_unit_form(unit: Node3D, new_type_id: String) -> bool:
	if unit == null or not is_instance_valid(unit) or new_type_id.is_empty():
		return false
	var d: Dictionary = unit.get_meta("unit_data", {}).duplicate(true)
	var old_tid := str(d.get("typeId", "")).strip_edges()
	if old_tid == new_type_id:
		return true
	var hc := unit.get_node_or_null("HarvestController") as HarvestController
	if hc != null:
		hc.abort()
	var ac := unit.get_node_or_null("AttackController") as AttackController
	if ac != null:
		ac.cancel()
	var uai := UnitAI.of(unit)
	if uai != null:
		uai.yield_to_player()
	var life_ratio := UnitLife.ratio(unit)
	d["typeId"] = new_type_id
	unit.set_meta("unit_data", d)
	if unit.has_meta(UnitLife.META_LIFE):
		unit.remove_meta(UnitLife.META_LIFE)
	if unit.has_meta(UnitLife.META_MAX_LIFE):
		unit.remove_meta(UnitLife.META_MAX_LIFE)
	UnitLife.ensure(unit)
	UnitLife.set_ratio(unit, life_ratio)
	if not _swap_unit_model(unit, new_type_id, int(d.get("owner", 0)), int(d.get("variation", 0))):
		AppLog.warn(AppLog.Layer.LOGIC, "GameDirector", "morph 模型失败 %s→%s" % [old_tid, new_type_id])
	var nav := unit.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		_apply_move_stats(unit, nav)
	if CombatQuery.has_weapon(unit):
		_ensure_attack_controller(unit)
		_ensure_unit_ai(unit)
	else:
		# 收回农民：卸掉战斗 AI 空转（可选保留 PASSIVE）
		var ai2 := UnitAI.of(unit)
		if ai2 != null:
			ai2.set_profile(UnitAI.Profile.PASSIVE)
	_refresh_command_card()
	_sync_selection_info_panel()
	if health_bar_manager != null:
		health_bar_manager.resync()
	return true


func _swap_unit_model(unit: Node3D, type_id: String, owner_id: int, variation: int) -> bool:
	if map_root == null:
		return false
	var cache: MapModelCache = null
	var catalog = null
	if map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	if map_root.has_method("get_id_catalog"):
		catalog = map_root.get_id_catalog()
	if cache == null or catalog == null:
		return false
	var glb: String = catalog.converted_glb_path(type_id, variation)
	if glb.is_empty():
		return false
	var unit_soft := not BuildingVisual.is_building(type_id)
	var inst: Node3D = cache.instance_glb(glb, unit_soft) as Node3D
	if inst == null:
		return false
	var color_i := MapUnitLayer.resolve_team_color_index(type_id, owner_id)
	cache.apply_team_color(inst, color_i, false)
	inst.name = Unit.MODEL_NODE_NAME
	var u: Unit = Unit.of(unit)
	var old: Node3D = null
	if u != null:
		old = u.model_node()
	else:
		old = unit.get_node_or_null(Unit.MODEL_NODE_NAME) as Node3D
	if old != null:
		old.name = "Model_Old"
		old.queue_free()
	unit.remove_meta(AnimPlayback.META_ANIM_PLAYER)
	unit.add_child(inst)
	# 新 Model 置顶（旧节点可能延后释放）
	unit.move_child(inst, 0)
	var vis := _ensure_unit_visual(unit)
	var ap := AnimPlayback.find_animation_player(inst)
	if ap == null:
		ap = AnimPlayback.find_animation_player(unit)
	if vis != null:
		vis.bind_cache(cache)
		vis.bind_animation_player(ap)
	var u2 := Unit.of(unit)
	if u2 != null and ap != null:
		u2.bind_animation_player(ap)
	if ap != null:
		AnimPlayback.bind_animation_player(unit, ap)
	cache.autoplay_stand(unit)
	if cache.has_method("snap_stand_geoset_visibility"):
		cache.call("snap_stand_geoset_visibility", unit)
	if Wc3Pe2Particles.has_emitters(glb):
		Wc3Pe2Particles.attach_to(unit, glb)
		Wc3Pe2Particles.apply_sequence(unit, "Stand")
	return true


func _issue_call_to_arms(source: int = UnitOrder.Source.PANEL) -> int:
	if unit_selector == null:
		return 0
	var selected: Array = _get_selected_safe()
	var bells: Array[Node3D] = []
	var direct: Array[Node3D] = []
	for n in selected:
		if not (n is Node3D):
			continue
		var unit := n as Node3D
		var tid := CombatQuery.type_id_of(unit)
		if BuildingVisual.is_building(tid) and _building_has_town_bell(tid):
			bells.append(unit)
		elif MilitiaController.unit_has_abil(unit):
			direct.append(unit)
	var n_ok := 0
	if not bells.is_empty():
		n_ok += _issue_town_bell_near_peasants(bells, source)
	for unit in direct:
		if _command_router != null:
			_command_router.issue_stop([unit], source)
		var mc := _ensure_militia_controller(unit)
		if mc != null and mc.toggle_call_to_arms():
			n_ok += 1
	if game_hud != null and n_ok > 0:
		game_hud.set_status("战斗号召：已转换 %d 人" % n_ok)
	elif game_hud != null:
		game_hud.set_status("战斗号召：无可用农民/民兵")
	_refresh_command_card()
	return n_ok


const TOWN_BELL_RADIUS_WC3 := 2800.0


func _building_has_town_bell(type_id: String) -> bool:
	var cat := CommandButtonCatalog.get_shared()
	for abil_id in cat.get_all_abil_list(type_id):
		if cat.get_ability_order(str(abil_id)) == "townbellon":
			return true
	return false


func _issue_town_bell_near_peasants(bells: Array[Node3D], source: int) -> int:
	var host := _unit_host()
	if host == null:
		return 0
	var n_ok := 0
	var touched: Dictionary = {}
	for bell in bells:
		if bell == null or not is_instance_valid(bell):
			continue
		var owner := int(bell.get_meta("unit_data", {}).get("owner", 0))
		var bell_xy := Wc3Coords.godot_to_wc3_xy(bell.global_position)
		for c in host.get_children():
			if not (c is Node3D):
				continue
			var unit := c as Node3D
			if not is_instance_valid(unit):
				continue
			if int(unit.get_meta("unit_data", {}).get("owner", -1)) != owner:
				continue
			var tid := CombatQuery.type_id_of(unit)
			if tid != "hpea" and tid != "hmil":
				continue
			var uid := unit.get_instance_id()
			if touched.has(uid):
				continue
			var uxy := Wc3Coords.godot_to_wc3_xy(unit.global_position)
			if uxy.distance_to(bell_xy) > TOWN_BELL_RADIUS_WC3:
				continue
			touched[uid] = true
			if _command_router != null:
				_command_router.issue_stop([unit], source)
			var mc := _ensure_militia_controller(unit)
			if mc != null and mc.toggle_call_to_arms():
				n_ok += 1
	return n_ok


func _on_combat_projectile_launched(info: Dictionary) -> void:
	# 兼容旧信号名；实际由 CombatModule 订阅 ProjectileService。
	if is_instance_valid(_combat):
		_combat.call("_on_projectile_launched", info)


func _on_combat_projectile_resolved(result: Dictionary) -> void:
	if is_instance_valid(_combat):
		_combat.call("_on_projectile_resolved", result)


func _on_damage_applied_present(result: Dictionary) -> void:
	if is_instance_valid(_combat):
		_combat.call("_on_damage_applied_present", result)


func _on_unit_dying(unit: Node3D) -> void:
	_ensure_combat_module().on_unit_dying(unit)


func _on_corpse_expired(unit: Node3D) -> void:
	_ensure_combat_module().on_corpse_expired(unit)


func _wire_all_gold_mines() -> void:
	var host := _unit_host()
	if host == null:
		return
	for c in host.get_children():
		if not (c is Node3D) or not GoldMineRuntime.is_gold_mine(c):
			continue
		_wire_gold_mine(c as Node3D)


func _wire_gold_mine(mine: Node3D) -> void:
	if mine == null or not is_instance_valid(mine):
		return
	var rt := GoldMineRuntime.ensure(mine)
	if rt == null:
		return
	if rt.depleted.is_connected(_on_gold_mine_depleted):
		return
	rt.depleted.connect(_on_gold_mine_depleted.bind(mine))


func _on_gold_mine_depleted(mine: Node3D) -> void:
	if mine == null or not is_instance_valid(mine):
		return
	if bool(mine.get_meta("gold_mine_collapsing", false)):
		return
	mine.set_meta("gold_mine_collapsing", true)
	if unit_selector != null and unit_selector.has_method("deselect_unit"):
		unit_selector.call("deselect_unit", mine)
	WorldMembership.exit(mine)
	if is_instance_valid(mine):
		mine.visible = true
	var cache: MapModelCache = null
	if map_root != null and map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	var tid := str(mine.get_meta("unit_data", {}).get("typeId", "ngol"))
	var played: Dictionary = BuildingVisual.play_death(cache, mine, tid)
	var wait := float(played.get("duration", 0.0))
	if wait < 0.35:
		wait = 1.6
	var tree := get_tree()
	if tree != null:
		SceneDelay.create_timer(self, wait).timeout.connect(_on_gold_mine_collapse_finished.bind(mine))
	else:
		_on_gold_mine_collapse_finished(mine)


func _on_gold_mine_collapse_finished(mine: Node3D) -> void:
	_on_corpse_expired(mine)


func _terminate_unit_production(unit: Node3D) -> void:
	_ensure_production_module().terminate(unit)


func _release_unit_food(unit: Node3D) -> void:
	if unit == null or bool(unit.get_meta("food_released", false)):
		return
	var d: Dictionary = unit.get_meta("unit_data", {})
	var owner := int(d.get("owner", -1))
	var tid := str(d.get("typeId", "")).strip_edges()
	var food := BuildingCatalog.get_food_used(tid)
	var capacity := BuildingCatalog.get_food_made(tid) if not UnitLife.is_under_construction(unit) else 0
	if food <= 0 and capacity <= 0:
		return
	var stock := _stock_for_owner(owner)
	if stock == null:
		return
	if food > 0:
		stock.add_food_used(-food)
	if capacity > 0:
		stock.add_food_cap(-capacity)
	unit.set_meta("food_released", true)


func _is_build_targeting() -> bool:
	return _build.is_build_targeting() if is_instance_valid(_build) else false


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
	# 选建筑后收起二级面板，进入瞄准（begin_aim 互斥清掉 ability/move 等）
	_ensure_command_card_module().close_submenus()
	_ensure_interaction_module().begin_aim(InteractionModule.Aim.BUILD, {"building_id": building_id})
	_sync_aim_flags_from_interaction()
	var vp := get_viewport()
	if vp != null:
		_last_screen_pos = vp.get_mouse_position()
	var module := _ensure_build_module()
	if not module.begin_placement(building_id, _last_screen_pos, not _pointer_over_blocking_gui()):
		_ensure_interaction_module().cancel_aim("build_fail")
		_sync_aim_flags_from_interaction()
		return
	_refresh_command_card()
	if game_hud:
		var display_name := CommandCard._building_display_name(building_id)
		game_hud.set_status("建造瞄准：%s · 左键指定地点 · 右键/Esc 取消" % display_name)


func _cancel_build_targeting() -> void:
	if not is_instance_valid(_build):
		return
	_build.cancel_placement()
	if is_instance_valid(_interaction) and _interaction.is_build():
		_interaction.cancel_aim("build_cancel")
		_sync_aim_flags_from_interaction()
	else:
		_sync_selector_enabled_for_targeting()
	if game_hud:
		game_hud.set_status("建造取消")


func _set_build_menu_open(open: bool) -> void:
	_ensure_command_card_module().set_build_menu_open(open)


func _set_hero_skill_menu_open(open: bool) -> void:
	_ensure_command_card_module().set_hero_skill_menu_open(open)


func _try_learn_hero_skill(abil_id: String) -> void:
	_ensure_command_card_module().try_learn_hero_skill(abil_id)


## —— GM：英雄等级 / 技能（转发 DebugToolsModule）——


func gm_hero_level_up() -> void:
	_ensure_debug_tools_module().hero_level_up()


func gm_hero_max_level() -> void:
	_ensure_debug_tools_module().hero_max_level()


## 用 1 点自动学第一个可学技能（或升级已有）。
func gm_hero_learn_one_point() -> void:
	_ensure_debug_tools_module().hero_learn_one_point()


## 满级 + 该英雄全部技能升到最高。
func gm_hero_unlock_all_skills() -> void:
	_ensure_debug_tools_module().hero_unlock_all_skills()


func _clear_ability_preview() -> void:
	if is_instance_valid(_abilities):
		_abilities.clear_preview()


func _clear_ability_preview_tints() -> void:
	if is_instance_valid(_abilities):
		_abilities.call("_clear_preview_tints")


func _update_ability_preview(screen_pos: Vector2) -> void:
	_ensure_abilities_module().update_preview(screen_pos)


func _refresh_ability_preview_tints(caster: Node3D, goal: Vector2, radius: float) -> void:
	if is_instance_valid(_abilities):
		_abilities.call("_refresh_preview_tints", caster, goal, radius)


func _interrupt_channels_for_units(units: Array) -> void:
	_ensure_abilities_module().interrupt_channels(units)


func _commit_build_targeting(screen_pos: Vector2) -> void:
	if not is_instance_valid(_build):
		return
	_last_screen_pos = screen_pos
	var module := _build
	var bid := module.current_placement_building_id()
	if not module.is_build_targeting() or not module.is_placement_valid():
		if game_hud:
			game_hud.set_status("无法在此处建造（合法位置？）")
		return
	# 资源复检（资源可能在瞄准中被花掉）
	if not _can_afford(bid):
		_notify_cannot_afford_build(bid)
		_cancel_build_targeting()
		return
	var n := module.commit_placement(
		screen_pos,
		Callable(self, "_get_selected_safe"),
		[],
		true
	)
	if n > 0:
		# placement 已在 commit 中结束；勿再 cancel_placement（会清掉钉住幽灵）
		if is_instance_valid(_interaction) and _interaction.is_build():
			_interaction.acknowledge_external_end()
			_sync_aim_flags_from_interaction()
		else:
			_sync_selector_enabled_for_targeting()
		_refresh_command_card()
		if game_hud:
			game_hud.set_status("建造：农民前往工地")
		return
	# 失败：若 placement 已结束（扣费失败 / issue 失败等）同步清瞄准；仍在瞄准则保留
	if not module.is_build_targeting():
		if is_instance_valid(_interaction) and _interaction.is_build():
			_interaction.acknowledge_external_end()
			_sync_aim_flags_from_interaction()
		else:
			_sync_selector_enabled_for_targeting()
		module.clear_pinned_ghost()
	else:
		_sync_selector_enabled_for_targeting()
	_refresh_command_card()
	if game_hud:
		game_hud.set_status("建造下令失败（需选中空闲农民）")


func _pin_site_ghost(building_id: String, site_wc3: Vector2) -> void:
	if is_instance_valid(_build):
		_build.pin_site_ghost(building_id, site_wc3)


func _clear_pinned_site_ghost() -> void:
	if is_instance_valid(_build):
		_build.clear_pinned_ghost()


func _apply_ghost_to_screen() -> void:
	# BuildModule 内部信号回调会刷新；此处保留以兼容旧调用方（无副作用）。
	pass


func _on_build_placement_changed(_bid: String, _site: Vector2, _valid: bool) -> void:
	pass


func _on_build_placement_cancelled() -> void:
	_sync_selector_enabled_for_targeting()


func _on_build_placement_committed(_bid: String, _site: Vector2) -> void:
	pass


func _ensure_build_placement_objects() -> void:
	_ensure_build_module()


func _ensure_ghost_node(_building_id: String) -> void:
	_ensure_build_module()


## HUD / 小地图等吃鼠标的 Control：建造确认与地面采样应避开。
## 不用底栏粗条带兜底（见 UnitSelector._hud_blocks_screen include_edge_bands=false），
## 否则屏幕下缘地图落点左键会被静默吞掉，表现为「建造点了没反应」。
func _pointer_over_blocking_gui() -> bool:
	if unit_selector != null and unit_selector.has_method("_hud_blocks_screen"):
		return bool(unit_selector.call("_hud_blocks_screen", _last_screen_pos, false))
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
	# 协助农民轮询「首工到位后」登记的工地（BuildModule 反查）
	_ensure_build_module()
	bc.find_site_at = Callable(_build, "find_site")


## 增派工人到位（半成品应已存在；此信号仅作进度/动画旁路，不再提前刷建筑）。
func _on_build_joined(_site: BuildSite, _builder: Node3D) -> void:
	pass


## 0 工人：冻结 Birth/粒子；有人回来继续 → 由 BuildModule 内部处理。
func _on_construction_paused(_paused: bool, _key: String) -> void:
	pass


func _set_construction_present_paused(_building: Node3D, _building_id: String, _paused: bool) -> void:
	pass


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
	_ensure_build_module().on_construction_started(order)


## 开工让位：脚印内可移动单位走开，避免卡在半成品 pathTex 上。
func _make_way_for_construction(_order: BuildOrder, _building_node: Node3D, _site: BuildSite) -> void:
	# 由 BuildModule.on_construction_started 内部完成
	pass


func _on_construction_progress(_elapsed: float, _total: float, _ratio: float, _key: String) -> void:
	# BuildModule 内部负责：UnitLife.set_ratio + HUD 刷新
	pass


## F2-5：工地 timer 跑完 → 半成品转正（满血）；若无半成品则兜底刷建筑。
func _on_build_completed(order: BuildOrder, site_wc3: Vector2, player_owner: int) -> void:
	_ensure_build_module().on_construction_completed(order, site_wc3, player_owner)
	_refresh_command_card()
	_sync_selection_info_panel()


func _on_build_cancelled(order: BuildOrder) -> void:
	_ensure_build_module().on_construction_cancelled(order)
	_refresh_command_card()


func _alloc_runtime_cn() -> int:
	return _ensure_units_module().alloc_creation_number()


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
	return _ensure_units_module().build_building_entry(building_id, site_wc3, player_owner, creation_number)


## 主城/兵营等可训建筑：命令卡带 training_unit 高亮 + Requires 置灰。
## 建造中：隐藏训兵按钮，保留集结点。
func _apply_building_train_card(building: Node3D, tid: String) -> void:
	_ensure_command_card_module().apply_building_train_card(building, tid)


func _owned_buildings_for_local() -> Dictionary:
	return _ensure_command_card_module().owned_buildings_for_local()


func _researched_for_local() -> Dictionary:
	return _ensure_command_card_module().researched_for_local()


func _try_issue_train(unit_id: String) -> void:
	_ensure_production_module()
	_production_panel.request_train(unit_id)


## 祭坛复活阵亡英雄：费用/时间随等级；入 TrainQueue，完工刷回同等级。
func _try_issue_revive(unit_id: String) -> void:
	_ensure_production_module()
	_production_panel.request_revive(unit_id)


func _try_issue_research(upgrade_id: String) -> void:
	_ensure_production_module()
	_production_panel.request_research(upgrade_id)


func _wire_train_queue(queue: TrainQueue) -> void:
	_ensure_production_module().watch(queue)


## 训练中切 Stand Work（门开 + 门光）；队列空回 Stand。


func _on_train_queue_cancel(slot_index: int) -> void:
	_ensure_production_module()
	_production_panel.cancel_selected(slot_index)


func _apply_revived_hero_state(unit: Node3D, completed: Dictionary) -> void:
	_ensure_production_module().apply_revived_hero_state(unit, completed)


## 训练完工刷单位：脚印四角（集结最近 / 默认左下）→ 重叠则自建筑中心挤位 → 再跟集结。
func _spawn_trained_unit(
	unit_id: String, site_wc3: Vector2, owner: int, from_building: Node3D = null
) -> Node3D:
	return _ensure_units_module().spawn_trained(unit_id, site_wc3, owner, from_building)


## 训练刷兵后改坐标（挤位）；同步 unit_data 与贴地。
func _teleport_unit_wc3(unit: Node3D, wc3_xy: Vector2) -> void:
	_ensure_units_module().teleport_wc3(unit, wc3_xy)


## 只结算已加入会话的玩家；中立或无效 owner 不创建隐式库存。
func _stock_for_unit(unit: Node3D) -> PlayerStock:
	if not is_instance_valid(unit):
		return null
	var data: Dictionary = unit.get_meta("unit_data", {})
	return _stock_for_owner(int(data.get("owner", -1)))


func _stock_for_owner(owner: int) -> PlayerStock:
	if _session == null:
		return null
	return _session.stocks.get(owner) as PlayerStock


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


func _ensure_unit_visual(unit: Node3D) -> Unit:
	var cache: MapModelCache = null
	if map_root != null and map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	var u: Unit = Unit.of(unit)
	if u == null:
		# 旧存档/非 Unit 根：不应再挂 UnitVisual 子节点；尽量当实体用
		AppLog.warn(AppLog.Layer.PRESENT, "GameDirector", "ensure_unit: 非 Unit 根 %s" % unit)
		_ensure_interaction_components(unit)
		return null
	u.bind_cache(cache)
	u.bind_animation_player(AnimPlayback.find_animation_player(u))
	_ensure_interaction_components(u)
	return u


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
	var dc := DefendController.of(unit)
	nav.speed_mul = dc.speed_mul() if dc != null else 1.0
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


func _on_command_action_rclick(action_id: String) -> void:
	_ensure_command_card_module().dispatch_action_rclick(action_id)


func _on_command_action(
	action_id: String, source: int = UnitOrder.Source.PANEL
) -> void:
	_ensure_command_card_module().dispatch_action(action_id, source)


func _clear_command_card_hotkeys() -> void:
	_ensure_command_card_module().clear_hotkeys()


func _on_selection_changed(primary: Node3D, selected: Array) -> void:
	_ensure_selection_hud_module().bind_inventory_for(primary)
	_ensure_interaction_module().on_selection_changed(primary, selected)
	_sync_aim_flags_from_interaction()
	if health_bar_manager:
		health_bar_manager.set_selection(selected)
	if game_hud == null:
		_sync_rally_flag_for_selection()
		return
	if primary != null and not selected.is_empty():
		_ensure_selection_hud_module().apply_selection_info(primary, selected)
	_ensure_command_card_module().on_selection_changed(primary, selected)
	if (
		primary != null
		and not selected.is_empty()
		and _is_controllable(primary)
		and not _is_gold_mine(primary)
		and str(primary.get_meta("unit_data", {}).get("typeId", "")) != "ngol"
	):
		_sync_build_hud_for_selection()
	_sync_rally_flag_for_selection()


func _apply_selection_info_to_hud(primary: Node3D, selected: Array) -> void:
	_ensure_selection_hud_module().apply_selection_info(primary, selected)


func _sync_selection_info_panel() -> void:
	_ensure_selection_hud_module().sync_panel()


func _sync_build_hud_for_selection() -> void:
	if unit_selector == null or not unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	# 半成品或施工中农民：BuildModule 负责更新；TrainQueue 走 ProductionPanel。
	if primary != null and primary.get_node_or_null("TrainQueue") != null and (primary.get_node_or_null("TrainQueue") as TrainQueue).is_training():
		_ensure_build_module().unbind_hud_site()
		if game_hud != null:
			game_hud.clear_build_progress()
		_wire_train_queue(primary.get_node_or_null("TrainQueue") as TrainQueue)
		_push_train_queue_hud(primary.get_node_or_null("TrainQueue") as TrainQueue)
		return
	_ensure_build_module().sync_hud_for_selection(Callable(unit_selector, "get_primary"))


func _push_train_queue_hud(queue: TrainQueue) -> void:
	_ensure_production_module()
	_production_panel.show_queue(queue)


func _bind_hud_build_site(site: BuildSite) -> void:
	if not is_instance_valid(_build):
		return
	_build.bind_hud_site(site)


func _unbind_hud_build_site() -> void:
	if not is_instance_valid(_build):
		return
	_build.unbind_hud_site()


func _refresh_command_card() -> void:
	_ensure_command_card_module().refresh()


func _refresh_move_executing_ui() -> void:
	_ensure_command_card_module().refresh_move_executing_ui()


func _primary_type_id(_selected: Array = []) -> String:
	return _ensure_command_card_module().primary_type_id(_selected)


func _setup_item_system() -> void:
	_ensure_items_module()


func _on_ground_item_spawned(ground: GroundItem) -> void:
	if is_instance_valid(_items):
		_items.call("_on_ground_spawned", ground)


func _on_inventory_changed() -> void:
	_ensure_items_module().on_inventory_changed()


func _on_item_use(slot: int) -> void:
	_ensure_items_module().use_slot(slot)


func _on_item_drop(slot: int) -> void:
	_ensure_items_module().drop_slot(slot)


func _on_item_swap(a: int, b: int) -> void:
	_ensure_items_module().swap_slots(a, b)


## GM：只生成测试物品，不修改地图掉落或普通开局。
func gm_item_test_kit() -> void:
	_ensure_debug_tools_module().item_test_kit()


func gm_item_test_vitals() -> void:
	_ensure_debug_tools_module().item_test_vitals()


func gm_item_test_death() -> void:
	_ensure_debug_tools_module().item_test_death()


func gm_item_test_creep() -> void:
	_ensure_debug_tools_module().item_test_creep()


## 装配调试工具：GM 面板 / 性能叠层 / GM 动作。
func _ensure_debug_tools_module() -> DebugToolsModule:
	if not is_instance_valid(_debug_tools):
		_debug_tools = DebugToolsModule.new()
		_debug_tools.name = "DebugToolsModule"
		add_child(_debug_tools)
	if game_hud == null or unit_selector == null:
		_resolve_exports()
	_debug_tools.configure({
		"host_parent": get_parent(),
		"game_hud": game_hud,
		"unit_selector": unit_selector,
		"ensure_caster": Callable(self, "_ensure_caster_runtime"),
		"refresh_command_card": Callable(self, "_refresh_command_card"),
		"sync_selection_info": Callable(self, "_sync_selection_info_panel"),
		"get_primary": Callable(self, "_ability_get_primary"),
		"is_controllable": Callable(self, "_is_controllable"),
		"set_status": Callable(self, "_ability_set_status"),
		"spawn_test_kit": func() -> void:
			_ensure_items_module().spawn_test_kit_around_primary(),
		"on_inventory_changed": Callable(self, "_on_inventory_changed"),
		"kill_unit": Callable(self, "_kill_unit"),
		"spawn_near": func(
			near: Node3D, type_id: String, owner_id: int, offset: Vector2, opts: Dictionary
		) -> Node3D:
			return _ensure_units_module().spawn_near(near, type_id, owner_id, offset, opts),
	})
	return _debug_tools


## 装配对手电脑：经营 / 军队 AI 挂接。
func _ensure_opponent_ai_module() -> OpponentAiModule:
	if not is_instance_valid(_opponent_ai):
		_opponent_ai = OpponentAiModule.new()
		_opponent_ai.name = "OpponentAiModule"
		add_child(_opponent_ai)
	_opponent_ai.configure({
		"host_parent": self,
		"map_root": map_root,
		"session": _session,
		"path_query": _path_query,
		"crowd_query": _crowd_query,
		"pathing": _pathing,
		"tree_registry": _tree_registry,
		"item_service": _ensure_items_module().item_service,
		"ensure_navigator": Callable(self, "_ensure_navigator"),
		"ensure_harvest": Callable(self, "_ensure_harvest_controller"),
		"ensure_build": Callable(self, "_ensure_build_controller"),
		"ensure_attack": Callable(self, "_ensure_attack_controller"),
		"find_build_site": Callable(self, "_find_build_site"),
		"find_build_site_by_node": Callable(self, "_find_build_site_by_node"),
		"wire_train_queue": Callable(self, "_wire_train_queue"),
		"stock_for_owner": Callable(self, "_stock_for_owner"),
	})
	return _opponent_ai


## 装配对局生命周期：胜负接线、结算屏、重开。
func _ensure_match_lifecycle_module() -> MatchLifecycleModule:
	if not is_instance_valid(_match_lifecycle):
		_match_lifecycle = MatchLifecycleModule.new()
		_match_lifecycle.name = "MatchLifecycleModule"
		add_child(_match_lifecycle)
	_match_lifecycle.configure({
		"game_root": get_parent(),
		"settings_source": self,
	})
	return _match_lifecycle


## 装配对局开局：会话、本地/对手基地、镜头落点。
func _ensure_match_bootstrap_module() -> MatchBootstrapModule:
	if not is_instance_valid(_match_bootstrap):
		_match_bootstrap = MatchBootstrapModule.new()
		_match_bootstrap.name = "MatchBootstrapModule"
		add_child(_match_bootstrap)
	if game_hud == null or rts_camera == null:
		_resolve_exports()
	_match_bootstrap.configure({
		"map_root": map_root,
		"map_dir": map_dir,
		"game_hud": game_hud,
		"rts_camera": rts_camera,
		"rng": _rng,
		"apply_cursor_race": Callable(self, "_apply_cursor_race"),
		"refresh_pathing": Callable(self, "_refresh_dynamic_pathing"),
		"map_display_name": Callable(self, "_map_display_name"),
		"on_pathing_map": func(pm) -> void:
			_pathing = pm,
	})
	return _match_bootstrap


## 装配路径调试：选中单位寻路折线。
func _ensure_path_debug_module() -> PathDebugModule:
	if not is_instance_valid(_path_debug_mod):
		_path_debug_mod = PathDebugModule.new()
		_path_debug_mod.name = "PathDebugModule"
		add_child(_path_debug_mod)
	if unit_selector == null:
		_resolve_exports()
	_path_debug_mod.configure({
		"map_root": map_root,
		"heightfield": _heightfield,
		"unit_selector": unit_selector,
		"enabled": show_path_debug,
	})
	return _path_debug_mod


## 装配选中 HUD：肖像 vitals / buff / 选中详情。
func _ensure_selection_hud_module() -> SelectionHudModule:
	if not is_instance_valid(_selection_hud):
		_selection_hud = SelectionHudModule.new()
		_selection_hud.name = "SelectionHudModule"
		add_child(_selection_hud)
	if game_hud == null or unit_selector == null:
		_resolve_exports()
	_selection_hud.configure({
		"game_hud": game_hud,
		"unit_selector": unit_selector,
		"map_root": map_root,
		"sync_build_hud": Callable(self, "_sync_build_hud_for_selection"),
		"is_controllable": Callable(self, "_is_controllable"),
	})
	return _selection_hud


## 装配命令卡模块：刷卡、热键、二级菜单、action 分发。
func _ensure_command_card_module() -> CommandCardModule:
	if not is_instance_valid(_command_card):
		_command_card = CommandCardModule.new()
		_command_card.name = "CommandCardModule"
		add_child(_command_card)
	if game_hud == null or unit_selector == null:
		_resolve_exports()
	_command_card.configure({
		"game_hud": game_hud,
		"unit_selector": unit_selector,
		"command_router": _command_router,
		"session": _session,
		"enable_move_command": enable_move_command,
		"unit_host": Callable(self, "_unit_host"),
		"local_stock": Callable(self, "_local_stock"),
		"is_controllable": Callable(self, "_is_controllable"),
		"is_gold_mine": Callable(self, "_is_gold_mine"),
		"ability_ui_state_for": Callable(self, "_ability_ui_state_for"),
		"get_selected": Callable(self, "_get_selected_safe"),
		"unbind_hud_build_site": Callable(self, "_unbind_hud_build_site"),
		"cancel_aim_rivals": func() -> void:
			_ensure_interaction_module().cancel_aim("submenu")
			_sync_aim_flags_from_interaction(),
		"ensure_caster": Callable(self, "_ensure_caster_runtime"),
		"begin_move": Callable(self, "_begin_move_targeting"),
		"issue_stop": Callable(self, "_issue_stop"),
		"issue_hold": Callable(self, "_issue_hold"),
		"begin_attack": Callable(self, "_begin_attack_targeting"),
		"begin_patrol": Callable(self, "_begin_patrol_targeting"),
		"begin_harvest": Callable(self, "_begin_harvest_targeting"),
		"issue_return_goods": Callable(self, "_issue_return_goods"),
		"issue_call_to_arms": Callable(self, "_issue_call_to_arms"),
		"begin_rally": Callable(self, "_begin_rally_targeting"),
		"try_toggle_defend": Callable(self, "_try_toggle_defend"),
		"begin_ability": Callable(self, "_begin_ability_targeting"),
		"issue_self_ability": Callable(self, "_issue_self_ability"),
		"begin_build": Callable(self, "_begin_build_targeting"),
		"try_train": Callable(self, "_try_issue_train"),
		"try_revive": Callable(self, "_try_issue_revive"),
		"try_research": Callable(self, "_try_issue_research"),
	})
	return _command_card


## 装配交互模块：互斥瞄准状态机 + 光标同步。
func _ensure_interaction_module() -> InteractionModule:
	if not is_instance_valid(_interaction):
		_interaction = InteractionModule.new()
		_interaction.name = "InteractionModule"
		add_child(_interaction)
	if game_cursor == null:
		_resolve_exports()
	_interaction.configure({
		"cursor": game_cursor as Wc3GameCursor,
		"unit_selector": unit_selector,
		"set_status": Callable(self, "_ability_set_status"),
		"cancel_ability": func() -> void:
			if is_instance_valid(_abilities):
				_abilities.cancel_targeting(),
		"cancel_build": Callable(self, "_cancel_build_targeting"),
		"ability_target_kind": func() -> int:
			var id := _pending_ability_id
			if id.is_empty() and is_instance_valid(_abilities):
				id = _abilities.pending_abil_id()
			return AbilityCatalog.target_kind(id),
		"is_ability_targeting": func() -> bool:
			return _ability_targeting or (
				is_instance_valid(_abilities) and _abilities.is_targeting()
			),
		"is_build_targeting": Callable(self, "_is_build_targeting"),
	})
	return _interaction


## 装配智能右键：目标解析、闪选、状态文案。
func _ensure_smart_command_module() -> SmartCommandModule:
	if not is_instance_valid(_smart_command):
		_smart_command = SmartCommandModule.new()
		_smart_command.name = "SmartCommandModule"
		add_child(_smart_command)
	if unit_selector == null or rts_camera == null:
		_resolve_exports()
	# ground_items 可能在 ItemsModule 之后才就绪
	if _ground_items == null and is_instance_valid(_items):
		_ground_items = _items.ground_host()
	_smart_command.configure({
		"unit_selector": unit_selector,
		"rts_camera": rts_camera,
		"tree_registry": _tree_registry,
		"ground_items": _ground_items,
		"ground_at_screen": Callable(self, "_ground_at_screen"),
		"is_gold_mine": Callable(self, "_is_gold_mine"),
	})
	return _smart_command


## 装配战斗模块：伤害管线、投射物、死亡/尸体、AttackController。
## 食物释放 / 生产终止 / 物品死亡准备 / 选中清理经 Callable 注入。
func _ensure_combat_module() -> CombatModule:
	if not is_instance_valid(_combat):
		_combat = CombatModule.new()
		_combat.name = "CombatModule"
		add_child(_combat)
		_combat.tree_exiting.connect(_on_combat_module_exiting)
	_combat.configure({
		"map_root": map_root,
		"health_bar_manager": health_bar_manager,
		"ensure_navigator": Callable(self, "_ensure_navigator"),
		"ensure_unit_visual": Callable(self, "_ensure_unit_visual"),
		"unit_host": Callable(self, "_unit_host"),
		"release_food": Callable(self, "_release_unit_food"),
		"terminate_production": Callable(self, "_terminate_unit_production"),
		"prepare_hero_death": func(unit: Node3D) -> void:
			_ensure_items_module().prepare_hero_death(unit),
		"deselect_unit": Callable(self, "_deselect_unit_on_death"),
		"get_primary": Callable(self, "_ability_get_primary"),
		"get_selected": Callable(self, "_get_selected_safe"),
		"apply_selection_info": Callable(self, "_apply_selection_info_to_hud"),
		"refresh_command_card": Callable(self, "_refresh_command_card"),
	})
	_damage_pipeline = _combat.damage_pipeline
	_death_service = _combat.death_service
	_projectile_service = _combat.projectile_service
	return _combat


func _on_combat_module_exiting() -> void:
	_damage_pipeline = null
	_death_service = null
	_projectile_service = null
	_combat = null


func _deselect_unit_on_death(unit: Node3D) -> void:
	if unit_selector != null and unit_selector.has_method("deselect_unit"):
		unit_selector.call("deselect_unit", unit)
	elif unit_selector != null and unit_selector.has_method("clear_selection"):
		var pri: Node3D = null
		if unit_selector.has_method("get_primary"):
			pri = unit_selector.call("get_primary") as Node3D
		if pri == unit:
			unit_selector.call("clear_selection")


## 装配建造调度模块：工地注册表、放置视觉、开工/完工/取消、HUD 工地绑定。
## 通过 Callable 注入查找动画玩家、UnitVisual 与导航；不直接持有 GameDirector 类型。
func _ensure_build_module() -> BuildModule:
	if not is_instance_valid(_build):
		_build = BuildModule.new()
		_build.name = "BuildModule"
		add_child(_build)
	_build.configure({
		"map_root": map_root,
		"heightfield": _heightfield,
		"pathing": _pathing,
		"path_query": _path_query,
		"crowd_query": _crowd_query,
		"command_router": _command_router,
		"session": _session,
		"health_bar_manager": health_bar_manager,
		"game_hud": game_hud,
		"sites_registry_host": self,
		"alloc_creation_number": Callable(self, "_alloc_runtime_cn"),
		"build_entry_for": Callable(self, "_build_entry_for"),
		"find_anim_player": Callable(self, "_find_anim_player"),
		"issue_move": Callable(self, "_command_router_issue_move"),
		"ensure_navigator": Callable(self, "_ensure_navigator"),
		"ensure_unit_visual": Callable(self, "_ensure_unit_visual"),
		"resync_health_bars": Callable(self, "_resync_health_bars"),
		"ground_at_screen": Callable(self, "_ground_at_screen"),
	})
	return _build


func _command_router_issue_move(units: Array, goal: Vector2) -> void:
	if _command_router != null:
		_command_router.issue_move_to_wc3(units, goal, UnitOrder.Source.UNKNOWN)


func _resync_health_bars() -> void:
	if health_bar_manager != null:
		health_bar_manager.resync()


## 装配单位出生 / AI / 英雄运行时模块；生产与技能通过其公开接口接入。
func _ensure_units_module() -> UnitsModule:
	if not is_instance_valid(_units):
		_units = UnitsModule.new()
		_units.name = "UnitsModule"
		add_child(_units)
	_units.configure({
		"map_root": map_root,
		"heightfield": _heightfield,
		"path_query": _path_query,
		"crowd_query": _crowd_query,
		"command_router": _command_router,
		"health_bar_manager": health_bar_manager,
		"registry_host": self,
		"ensure_navigator": Callable(self, "_ensure_navigator"),
		"ensure_attack_controller": Callable(self, "_ensure_attack_controller"),
		"unit_host": Callable(self, "_unit_host"),
		"refresh_pathing": Callable(self, "_refresh_dynamic_pathing"),
		"on_inventory_changed": Callable(self, "_on_inventory_changed"),
		"ensure_hero_passives": func(unit: Node3D) -> void:
			_ensure_abilities_module().ensure_hero_passives(unit),
		"ensure_caster": Callable(self, "_ensure_caster_runtime"),
		"add_food_used": func(owner_id: int, food: int) -> void:
			if _session == null or food == 0:
				return
			var stock: PlayerStock = _session.stocks.get(owner_id) as PlayerStock
			if stock != null:
				stock.add_food_used(food),
	})
	return _units


## 装配技能模块：cast ctx / runtime / 瞄准 / 预览。
func _ensure_abilities_module() -> AbilitiesModule:
	if not is_instance_valid(_abilities):
		_abilities = AbilitiesModule.new()
		_abilities.name = "AbilitiesModule"
		add_child(_abilities)
	_ensure_combat_module()
	_abilities.configure({
		"map_root": map_root,
		"heightfield": _heightfield,
		"path_query": _path_query,
		"crowd_query": _crowd_query,
		"command_router": _command_router,
		"damage_pipeline": _damage_pipeline,
		"projectile_service": _projectile_service,
		"alloc_creation_number": Callable(self, "_alloc_runtime_cn"),
		"ensure_unit_ai": Callable(self, "_ensure_unit_ai"),
		"spawn_summon": func(
			entry: Dictionary, duration: float, kill_cb: Callable, caster: Node3D
		) -> Node3D:
			return _ensure_units_module().spawn_summon(entry, duration, kill_cb, caster),
		"unit_host": Callable(self, "_unit_host"),
		"teleport_unit_wc3": Callable(self, "_teleport_unit_wc3"),
		"kill_unit": Callable(self, "_kill_unit"),
		"get_primary": Callable(self, "_ability_get_primary"),
		"pick_at": Callable(self, "_ability_pick_at"),
		"ground_at_screen": Callable(self, "_ground_at_screen"),
		"clear_rival_targeting": Callable(self, "_clear_rival_targeting_for_ability"),
		"on_targeting_changed": Callable(self, "_on_ability_targeting_changed"),
		"set_status": Callable(self, "_ability_set_status"),
		"refresh_command_card": Callable(self, "_refresh_command_card"),
		"refresh_pathing": Callable(self, "_refresh_dynamic_pathing"),
		"resync_health_bars": func() -> void:
			if health_bar_manager != null:
				health_bar_manager.resync(),
		"sync_selection_info": Callable(self, "_sync_selection_info_panel"),
		"last_screen_pos": func() -> Vector2: return _last_screen_pos,
	})
	_ability_ctx_factory = _abilities.ctx_factory
	_ability_hud = _abilities.hud
	_ability_runtime = _abilities.runtime
	_ability_targeting_svc = _abilities.targeting
	return _abilities


## 装配物品模块：地面物、背包操作、死亡掉落订阅。
func _ensure_items_module() -> ItemsModule:
	if not is_instance_valid(_items):
		_items = ItemsModule.new()
		_items.name = "ItemsModule"
		add_child(_items)
	_items.configure({
		"map_root": map_root,
		"heightfield": _heightfield,
		"map_dir": map_dir,
		"ground_parent": get_parent(),
		"combat": _ensure_combat_module(),
		"command_router": _command_router,
		"set_status": Callable(self, "_ability_set_status"),
		"get_primary": Callable(self, "_ability_get_primary"),
		"is_controllable": Callable(self, "_is_controllable"),
		"on_inventory_ui_refresh": func() -> void:
			var primary := _ability_get_primary()
			if primary != null and game_hud != null:
				_apply_selection_info_to_hud(primary, _get_selected_safe()),
		"get_model_cache": func() -> MapModelCache:
			if map_root != null and map_root.has_method("get_model_cache"):
				return map_root.get_model_cache() as MapModelCache
			return null,
	})
	_item_service = _items.item_service
	_ground_items = _items.ground_host()
	return _items


## 只负责装配对局生产模块及其界面适配器。
## 单位创建经 UnitsModule 显式接口注入。
func _ensure_production_module() -> ProductionModule:
	if not is_instance_valid(_production):
		_production = ProductionModule.new()
		_production.name = "ProductionModule"
		add_child(_production)
		_production_panel = ProductionPanel.new()
		_production_panel.name = "ProductionPanel"
		add_child(_production_panel)
		_production_panel.production = _production
		_production.queue_changed.connect(_production_panel.on_queue_changed)
		_production.progress_changed.connect(_production_panel.on_progress)
		_production.feedback.connect(_production_panel.show_feedback)
		_production.research_completed.connect(_production_panel.on_research_completed)
		_production.queue_changed.connect(_on_production_activity_changed)
		_production.progress_changed.connect(_on_production_activity_changed)
		_production_panel.command_card_requested.connect(_apply_building_train_card)
		_production_panel.selection_refresh_requested.connect(_sync_build_hud_for_selection)
		_production_panel.command_refresh_requested.connect(_refresh_command_card)
	var units := _ensure_units_module()
	_production.configure(_session, units.spawn_trained, units.ensure_hero)
	_production_panel.configure(_session, _command_router, unit_selector, game_hud,
		_unit_host(), map_root.get_model_cache() if map_root != null else null)
	return _production


func _on_production_activity_changed(_queue: TrainQueue = null) -> void:
	if game_hud == null or not is_instance_valid(_production) or _session == null:
		return
	if not game_hud.has_method("set_activity_feed"):
		return
	game_hud.set_activity_feed(_production.collect_owner_activities(_session.local_player))
