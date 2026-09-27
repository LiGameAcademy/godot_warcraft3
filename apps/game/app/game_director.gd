## 游戏总管（对标 MapEditor）。
##
## 职责：
## [br]- 场景配置：把 @export 配置（map_dir / 相机 / 寻路 / 移动 / GM 等）写入运行时状态。
## [br]- 对局启动：装配地图 / 寻路 / 战斗 / 单位 / 物品 / 交互等 12+ 子模块。
## [br]- 模块绑定：把 [GameMain.setup] 注入的 7 个依赖转发给各模块
## （CombatModule / BuildModule / UnitsModule / ItemsModule / InteractionModule 等）。
## [br]- HUD 协调：_wire_hud 留作空接线（M4 后走 UiManager.intent → UiGameplayBridge）。
##
## ---- 依赖注入 ----
## [br]运行时依赖由 [GameMain._setup_game_director] 在子节点装配第 6 步调
## [method setup] 注入；本节点不再 [code]get_node_or_null[/code] 反查节点树。
## 历史兜底 [code]_resolve_exports()[/code] 已删除（v1.3 SCENE_BOOTSTRAP）。
##
## ---- 生命周期 ----
## [br][code]_ready[/code] 首段：sealing AssetProvider / 随机种子 / 重载 AppLog。
## [br]若 [member map_root] 已就绪（被 setup 注入），立即触发 [method _boot_match]；
## 否则 await 一帧等 GameMain._ready 完成注入。
##
## ---- 信号 ----
## [br]- [signal session_ready]：地图装配 + Melee/寻路/小地图 bootstrap 完成
## （Loading 屏据此淡出）。
## [br]- [signal session_preparation_progress]：开局肖像预热阶段进度
## （Loading 屏同步推进度条）。
class_name GameDirector
extends Node

## 地图装配 + Melee/寻路/小地图 bootstrap 完成（Loading 屏可据此淡出）
signal session_ready
## 开局肖像预热阶段进度（stage 文本 + 0.0–1.0 进度）。
signal session_preparation_progress(stage: String, progress: float)

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
## Godot 垂直视野角；试验值，待原作同场景对拍校准。
@export var camera_fov: float = 50.0
@export var use_wc3_zoom_curve: bool = true
@export var apply_camera_bounds: bool = true

## Echo Isles cameraBounds（WC3 XY）；小地图点击跳转用
var _cam_min := Vector2(-6912.0, -5376.0)
var _cam_max := Vector2(6912.0, 4864.0)
var _rng := RandomNumberGenerator.new()
var _bootstrapped: bool = false
var _presentation_ready: bool = false
## Disabled only by diagnostic scenes comparing the cold selection path.
@export var prepare_starting_portraits: bool = true
var _session: GameSession = null
## 导航服务只读兼容入口；实例和生命周期统一归 NavigationModule。
var _path_query: PathQuery:
	get:
		return _navigation.path_query if is_instance_valid(_navigation) else null
var _pathing: Wc3PathingMap:
	get:
		return _navigation.pathing if is_instance_valid(_navigation) else null
var _heightfield: Wc3Heightfield:
	get:
		return _navigation.heightfield if is_instance_valid(_navigation) else null
## 邻近单位查询（soft 分离）；与 PathQuery 一样地图就绪后绑定。
var _crowd_query: UnitCrowdQuery:
	get:
		return _navigation.crowd_query if is_instance_valid(_navigation) else null
var _cell_reservation: PathCellReservation:
	get:
		return _navigation.cell_reservation if is_instance_valid(_navigation) else null
var _command_router: CommandRouter = null
var _damage_pipeline: DamagePipeline = null
var _death_service: DeathService = null
var _item_service: ItemService
var _ground_items: Node3D
var _navigation: NavigationModule
var _units: UnitsModule
var _entity_registry: EntityRegistry
var _behavior_registry: BehaviorRegistry
var _build: BuildModule
var _combat: CombatModule
var _abilities: AbilitiesModule
var _items: ItemsModule
var _interaction: InteractionModule
var _smart_command: SmartCommandModule
var _command_input: CommandInputModule
var _command_card: CommandCardModule
var _selection_hud: SelectionHudModule
var _path_debug_mod: PathDebugModule
var _match_bootstrap: MatchBootstrapModule
var _match_lifecycle: MatchLifecycleModule
var _opponent_ai: OpponentAiModule
var _debug_tools: DebugToolsModule
var _projectile_service: ProjectileService = null
var _harvest: HarvestModule
var _tree_registry: TreeRegistry:
	get:
		return _harvest.tree_registry if is_instance_valid(_harvest) else null
## 技能编排（由 AbilitiesModule 持有；此处保留别名便于旧入口）
var _ability_runtime: AbilityRuntimeRegistry = null
## 选中可训建筑时显示的集结旗（长驻，复用）
var _feedback: InteractionFeedback
var _world_picker: WorldPicker
var _match_input: MatchInputController
## 鼠标位置只读/写转发，状态由 MatchInputController 持有。
var _last_screen_pos: Vector2:
	get:
		return _match_input.last_screen_pos if is_instance_valid(_match_input) else Vector2.ZERO
	set(value):
		_ensure_match_input().last_screen_pos = value
## 对局内生产功能及本地界面适配器；队列订阅由模块持有。
var _production: ProductionModule
var _production_panel: ProductionPanel
## 配置阶段递增；仅缓存绑定代次，不保存业务状态或服务定位表。
var _binding_epoch := 0
var _bound_modules: Dictionary = {}
var _binding_counts: Dictionary = {}
var _wired_hud: GameHud
var _wired_selector: Node
var _ui_bridge: Node


## 由 [GameMain] 在子节点装配第 6 步调 [method setup] 注入。
##
## 6 个依赖写入对应 @export 字段；引用就绪后立刻触发 [method _boot_match]
## （仅触发一次，[member _bootstrapped] 守卫防止重复）。
##
## 形参顺序固定：map_root → rts_camera → game_hud → unit_selector → game_cursor
## → health_bar_manager，与 GameMain._setup_game_director 一致。
##
## [param p_map_root] 地图根（装配 MapLoader.configure_unit_runtime）。
## [param p_rts_camera] RTS 相机（_configure_camera 写入 zoom/fov）。
## [param p_game_hud] 底栏 HUD（_wire_hud 留作空接线；走 UiManager.intent）。
## [param p_unit_selector] UnitSelector（_setup_selector 挂 selection_changed）。
## [param p_game_cursor] 鼠标光标（InteractionModule 注入 cursor）。
## [param p_health_bar_manager] 血条（BuildModule / CombatModule 同步 resync）。
## [br]v1.4 起不再注入 game_loading_screen：Loading 已独立为 peer scene，由 [code]boot.gd[/code]
## 直接持有并订阅本节点的 [signal session_ready]。
func setup(
	p_map_root: MapLoader,
	p_rts_camera: RtsCamera,
	p_game_hud: GameHud,
	p_unit_selector: Node,
	p_game_cursor: Node,
	p_health_bar_manager: HealthBarManager,
) -> void:
	map_root = p_map_root
	rts_camera = p_rts_camera
	game_hud = p_game_hud
	unit_selector = p_unit_selector
	game_cursor = p_game_cursor
	health_bar_manager = p_health_bar_manager
	if _bootstrapped:
		return
	_boot_match()


## Godot 生命周期钩子。
##
## [br]首段（AssetProvider seal / RNG / AppLog）无条件执行。
## [br]若 [member map_root] 已就绪（[method setup] 在 _ready 之前被 GameMain 调用），
## 立即触发 [method _boot_match]。
## [br]否则 await 一帧 [code]get_tree().process_frame[/code]（GameMain._ready 在
## 子节点 _ready 之后），等 setup 注入完成后再触发 [method _boot_match]。
## 仍未注入则 push_warning 早退。
func _ready() -> void:
	var assets := get_node_or_null("/root/AssetProvider")
	if assets != null:
		assets.seal_runtime_content()
	_rng.randomize()
	AppLog.reload_config()
	# GameMain 的 _ready 在本节点之后（Godot bottom-up _ready 顺序）；
	# 等一帧让 GameMain._ready 把 setup() 跑完，再触发 _boot_match。
	if map_root == null:
		await get_tree().process_frame
		if map_root == null:
			push_warning(
				"GameDirector: setup() 未在首帧后注入；GameMain._ready 必须调 setup(...)"
			)
			return
	_boot_match()


## 对局启动入口（仅触发一次，由 [member _bootstrapped] 守卫）。
##
## 把原 _ready 后半段 / [method _configure_map_root] / [method _wire_hud] /
## [method _load_camera_bounds] / [method _configure_camera] 集中到此；
## selftest 可手动 [code]GameDirector.new() + setup() + _boot_match()[/code]
## 全链路跑通而无需挂入 GameMain.tscn。
func _boot_match() -> void:
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


func _apply_path_debug_visibility() -> void:
	if is_instance_valid(_path_debug_mod):
		_path_debug_mod.set_enabled(show_path_debug)


func get_session() -> GameSession:
	return _session


func is_session_ready() -> bool:
	return _bootstrapped and _presentation_ready


## 按本地玩家种族切换光标图集（human/orc/undead/nightelf）。
## game_cursor 由 GameMain.setup() 注入；运行时无需二次解析。
func _apply_cursor_race(race_id: String) -> void:
	_ensure_interaction_module().set_cursor_race(race_id)


func _configure_map_root() -> void:
	map_dir = ContentPaths.resolve(map_dir)
	map_root.configure_unit_runtime(func() -> Node3D: return Unit.new(), UnitLife.ensure)
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
	# M2 完成后，HUD 事件统一经 UiManager.intent → UiGameplayBridge 分发。
	# Director 不再直连 HUD signal；保留此处仅做轻量配置（map_dir / set_status）+ 触发桥绑定。
	_wired_hud = game_hud
	if game_hud == null:
		return
	if not map_dir.is_empty():
		game_hud.map_dir = map_dir
	game_hud.set_status(_map_display_name())
	_bind_ui_bridge()


func _setup_portrait_hud() -> void:
	_ensure_selection_hud_module().setup_portrait()


## 把对局作用域的依赖注入 UiGameplayBridge：UiManager intent → 玩法分发。
## 重复调用安全：仅替换字段、不重复订阅 UiManager.intent。
## 依赖以 Callable 注入，与 CommandCardModule / BuildModule 同款；
## bridge 不再需要拿到 director / selector / camera 等具体 Node 引用。
func _bind_ui_bridge() -> void:
	if not is_instance_valid(_ui_bridge):
		_ui_bridge = UiGameplayBridge.new()
		_ui_bridge.name = "UiGameplayBridge"
		add_child(_ui_bridge)
	# production_panel / items_module / command_router 必须已存在；未初始化则跳过。
	if not is_instance_valid(_production_panel):
		_ensure_production_module()
	if not is_instance_valid(_items):
		_ensure_items_module()
	# M3：presenter 挂在 bridge 子节点（bridge 释放即随之释放；不堆在 Autoload）。
	_ensure_resource_presenter().attach(_session.local_stock() if _session != null else null)
	_ensure_selection_presenter().attach(unit_selector)
	_ui_bridge.bind({
		UiGameplayBridge.DEP_DISPATCH_COMMAND: Callable(_ensure_command_card_module(), "dispatch_action"),
		UiGameplayBridge.DEP_DISPATCH_COMMAND_RCLICK: Callable(_ensure_command_card_module(), "dispatch_action_rclick"),
		UiGameplayBridge.DEP_CANCEL_TRAIN_SLOT: Callable(_production_panel, "cancel_selected"),
		UiGameplayBridge.DEP_USE_ITEM: Callable(_items, "use_slot"),
		UiGameplayBridge.DEP_DROP_ITEM: Callable(_items, "drop_slot"),
		UiGameplayBridge.DEP_SWAP_ITEMS: Callable(_items, "swap_slots"),
		UiGameplayBridge.DEP_SET_PRIMARY: Callable(unit_selector, "set_primary"),
		UiGameplayBridge.DEP_FOCUS_CAMERA: Callable(rts_camera, "focus_on_position"),
		UiGameplayBridge.DEP_UV_TO_WORLD_FALLBACK: _make_uv_to_world_callable(),
	})


func _ensure_resource_presenter() -> ResourcePresenter:
	if not is_instance_valid(_ui_bridge):
		_bind_ui_bridge()
	var child := _ui_bridge.get_node_or_null("ResourcePresenter")
	if child != null:
		return child as ResourcePresenter
	var p := ResourcePresenter.new()
	p.name = "ResourcePresenter"
	_ui_bridge.add_child(p)
	return p


func _ensure_selection_presenter() -> SelectionPresenter:
	if not is_instance_valid(_ui_bridge):
		_bind_ui_bridge()
	var child := _ui_bridge.get_node_or_null("SelectionPresenter")
	if child != null:
		return child as SelectionPresenter
	var p := SelectionPresenter.new()
	p.name = "SelectionPresenter"
	_ui_bridge.add_child(p)
	return p


func _setup_selector() -> void:
	if is_instance_valid(_wired_selector) and _wired_selector != unit_selector:
		if _wired_selector.is_connected("selection_changed", _on_selection_changed):
			_wired_selector.disconnect("selection_changed", _on_selection_changed)
	_wired_selector = unit_selector
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
	_ensure_match_input().handle_input(event)


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
	_ensure_navigation_module().initialize(map_root, Callable(_unit_presenter(), "ensure_visual"))
	if rts_camera != null:
		rts_camera.set_heightfield(_heightfield)
	_bootstrap_melee()
	_setup_selector()
	_bind_match_modules()
	_setup_minimap()
	_setup_portrait_hud()
	_setup_health_bars()
	_wire_all_gold_mines()
	_wire_all_unit_ai()
	if enable_opponent_economy:
		_setup_opponent_economy()
	# 地形材质已就绪后再刷调试栅格，避免 ready 阶段空材质警告
	if map_root != null:
		map_root.set_view_grid_level(view_grid_level)
	_setup_match_end()
	if prepare_starting_portraits and DisplayServer.get_name() != "headless":
		var game_root: Node = get_parent()
		var previous_mode: ProcessMode = game_root.process_mode
		game_root.process_mode = Node.PROCESS_MODE_DISABLED
		session_preparation_progress.emit("准备单位显示…", 0.98)
		var started: int = Time.get_ticks_usec()
		await _ensure_selection_hud_module().prepare_starting_portraits(local_player)
		if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(game_root) or game_root.is_queued_for_deletion():
			return
		game_root.process_mode = previous_mode
		AppLog.info(AppLog.Layer.LOAD, "Portrait", "Starting portraits prepared in %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	_presentation_ready = true
	session_ready.emit()


func _setup_match_end() -> void:
	_ensure_match_lifecycle_module().setup_match_end(_session, spawn_opponent_base)


func _setup_opponent_economy() -> void:
	_ensure_opponent_ai_module().setup(local_player, enable_opponent_army)


func _setup_health_bars() -> void:
	if health_bar_manager == null or map_root == null or rts_camera == null:
		return
	var cam := rts_camera.get_camera()
	health_bar_manager.configure(cam, map_root.get_unit_layer())
	health_bar_manager.resync()


func _bind_match_modules() -> void:
	if map_root == null:
		return
	_command_router = CommandRouter.new()
	_binding_epoch += 1
	_ensure_combat_module()
	_ensure_abilities_module()
	_ensure_build_module()
	_command_router.configure(
		_path_query,
		_crowd_query,
		Callable(_ensure_navigation_module(), "ensure_navigator"),
		Callable(_ensure_harvest_module(), "ensure_controller"),
		Callable(self, "_ensure_build_controller"),
		_session,
		Callable(_build, "find_site"),
		Callable(_build, "find_site_for_node"),
		Callable(_ensure_combat_module(), "ensure_attack_controller")
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
	_ensure_command_input_module()
	_ensure_command_card_module()
	_ensure_selection_hud_module()
	_ensure_debug_tools_module()
	_ensure_interaction_feedback()
	_ensure_match_input()


func _award_death_experience(victim: Node3D, killer: Node3D) -> void:
	# 兼容旧接线；实际由 CombatModule 处理。
	if is_instance_valid(_combat):
		_combat.call("_award_death_experience", victim, killer)


func _find_build_site(site_wc3: Vector2, building_id: String) -> BuildSite:
	return _ensure_build_module().find_site(site_wc3, building_id)


func _find_build_site_by_node(building_node: Node3D) -> BuildSite:
	return _ensure_build_module().find_site_for_node(building_node)


func _site_lookup_key(building_id: String, site_wc3: Vector2) -> String:
	return _ensure_build_module().site_lookup_key(building_id, site_wc3)


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
	_ensure_harvest_module().setup_trees()


func _tree_registry_ref() -> TreeRegistry:
	return _tree_registry


func _ensure_path_debug() -> void:
	_ensure_path_debug_module().ensure_draw()


func _process(delta: float) -> void:
	if _session != null and spawn_opponent_base and is_session_ready():
		var match_started := MatchHotpathMetrics.begin()
		var result := _session.evaluate_match(map_root.get_unit_layer())
		MatchHotpathMetrics.finish(&"match_evaluate", match_started)
		if bool(result.finished):
			return
	if is_instance_valid(_combat):
		var combat_started := MatchHotpathMetrics.begin()
		_combat.tick(delta)
		MatchHotpathMetrics.finish(&"combat_tick", combat_started)
	if is_instance_valid(_abilities):
		var abilities_started := MatchHotpathMetrics.begin()
		_abilities.tick(delta)
		MatchHotpathMetrics.finish(&"abilities_tick", abilities_started)
	_refresh_move_executing_ui()
	_ensure_selection_hud_module().tick(delta)
	if is_instance_valid(_path_debug_mod):
		_path_debug_mod.tick(delta)
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


func _unhandled_input(event: InputEvent) -> void:
	_ensure_match_input().handle_unhandled(event, enable_move_command, debug_building_fx_hotkeys)


## —— 命令输入：薄转发至 CommandInputModule ——

## 选中单位立即停步并回 Stand。
func _issue_stop(source: int = UnitOrder.Source.UNKNOWN) -> bool:
	return _ensure_command_input_module().issue_stop(source)


func _issue_hold(source: int = UnitOrder.Source.UNKNOWN) -> bool:
	return _ensure_command_input_module().issue_hold(source)


func _try_toggle_defend(source: int = UnitOrder.Source.UNKNOWN) -> void:
	_ensure_command_input_module().try_toggle_defend(source)


## Present/输入：屏幕点 → SmartTarget；不在此按兵种分支下令。
## 拾取走 UnitSelector 脚底 2D 圆；送回点 / 工地另加脚底像素近距门槛。
const SMART_BUILDING_FOOT_PX := 40.0 ## 保留常量别名；实际阈值在 SmartCommandModule


## F3-2: Shift+RMB 队形排开群体移动（FormationFollow）。
func _issue_group_move_command(
	screen_pos: Vector2,
	formation: String,
	spacing: float = 64.0
) -> bool:
	return _ensure_command_input_module().issue_group_move_command(screen_pos, formation, spacing)


func _issue_return_goods(source: int = UnitOrder.Source.UNKNOWN) -> bool:
	return _ensure_command_input_module().issue_return_goods(source)


func _begin_move_targeting(source: int) -> void:
	_ensure_command_input_module().begin_move_targeting(source)


func _begin_attack_targeting(source: int) -> void:
	_ensure_command_input_module().begin_attack_targeting(source)


func _begin_patrol_targeting(source: int) -> void:
	_ensure_command_input_module().begin_patrol_targeting(source)


func _begin_harvest_targeting(source: int) -> void:
	_ensure_command_input_module().begin_harvest_targeting(source)


func _begin_rally_targeting(source: int) -> void:
	_ensure_command_input_module().begin_rally_targeting(source)


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
	if is_instance_valid(_interaction) and not _interaction.is_ability():
		_interaction.cancel_aim("rival_for_ability")


func _ability_blizzard_preview_refresh() -> void:
	_update_ability_preview(_last_screen_pos)


func _on_ability_targeting_changed(active: bool, abil_id: String) -> void:
	if active:
		_ensure_interaction_module().adopt_external_aim(
			InteractionModule.Aim.ABILITY,
			{"abil_id": abil_id.strip_edges(), "target_kind": AbilityCatalog.target_kind(abil_id.strip_edges())}
		)
	else:
		if is_instance_valid(_interaction) and _interaction.is_ability():
			_interaction.acknowledge_external_end()
		_clear_ability_preview()


func _begin_ability_targeting(abil_id: String, source: int) -> void:
	_ensure_abilities_module().begin_targeting(abil_id, source)


## 自身技能（雷霆一击 / 天神下凡）：点按钮即施法。
func _issue_self_ability(abil_id: String, source: int) -> bool:
	return _ensure_abilities_module().issue_self(abil_id, source)


func _on_ability_cast_resolved(result: Dictionary, abil_id: String) -> void:
	# 兼容旧入口；实际由 AbilitiesModule 处理。
	if is_instance_valid(_abilities):
		_abilities.call("_on_cast_resolved", result, abil_id)


func _kill_unit(unit: Node3D) -> void:
	_ensure_combat_module().kill(unit)


## 引导开场清空命令队列（见 AbilityCastController._stop_caster_for_cast）。
func _clear_caster_orders(caster: Node3D) -> void:
	_ensure_abilities_module().clear_caster_orders(caster)


func _ability_ui_state_for(primary: Node3D) -> Dictionary:
	return _ensure_abilities_module().ui_state_for(primary)


func _ensure_caster_runtime(unit: Node3D) -> void:
	_ensure_abilities_module().ensure_unit(unit)


func _ensure_hero_runtime(unit: Node3D) -> void:
	_ensure_units_module().ensure_hero(unit)


func _sync_selector_enabled_for_targeting() -> void:
	if is_instance_valid(_interaction):
		_interaction.refresh_selector()


func _flash_cursor_move() -> void:
	# 先退出瞄准再 flash，避免 取消瞄准→IDLE 掐死箭头动画
	if is_instance_valid(_interaction):
		_interaction.flash_move_confirm()
	elif game_cursor is Wc3GameCursor:
		(game_cursor as Wc3GameCursor).flash_move()
	elif game_cursor != null and game_cursor.has_method("flash_move"):
		game_cursor.call("flash_move")


func _spawn_move_confirm(goal_wc3: Vector2, kind: int = MoveConfirmFx.Kind.MOVE) -> void:
	_ensure_interaction_feedback().spawn_move_confirm(goal_wc3, kind)


func _ensure_rally_flag() -> RallyFlagFx:
	return _ensure_interaction_feedback().ensure_rally_flag()


## 选中集合里：优先主选可训建筑；否则任一已设集结的可训建筑 → 显示种族旗。
func _sync_rally_flag_for_selection() -> void:
	_ensure_interaction_feedback().sync_rally_flag()


func _ensure_navigator(unit: Node3D) -> UnitNavigator:
	return _ensure_navigation_module().ensure_navigator(unit)

func _ensure_harvest_controller(unit: Node3D) -> HarvestController:
	return _ensure_harvest_module().ensure_controller(unit)


func _ensure_attack_controller(unit: Node3D) -> AttackController:
	return _ensure_combat_module().ensure_attack_controller(unit)


## U0-2：可战斗非建筑单位挂 UnitAI + AttackController；中立 → CAMP_CREEP。
func _ensure_unit_ai(unit: Node3D) -> UnitAI:
	return _ensure_units_module().ensure_combat_ai(unit)


## 地图已有单位 + 开局刷兵：pathing/战斗服务就绪后批量挂 AI。
func _wire_all_unit_ai() -> void:
	_ensure_units_module().wire_existing()


func _ensure_militia_controller(unit: Node3D) -> MilitiaController:
	return _ensure_units_module().forms.ensure_militia(unit)


func _issue_call_to_arms(source: int = UnitOrder.Source.PANEL) -> int:
	var n_ok := _ensure_units_module().issue_call_to_arms(_get_selected_safe(), source)
	if game_hud != null:
		game_hud.set_status("战斗号召：已转换 %d 人" % n_ok if n_ok > 0 else "战斗号召：无可用农民/民兵")
	_refresh_command_card()
	return n_ok


func _building_has_town_bell(type_id: String) -> bool:
	return _ensure_units_module().forms._building_has_town_bell(type_id)


func _issue_town_bell_near_peasants(bells: Array[Node3D], source: int) -> int:
	return _ensure_units_module().forms._issue_town_bell_near_peasants(bells, source)


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


func _wire_all_gold_mines() -> void:
	_ensure_harvest_module().wire_mines()


func _on_gold_mine_depleted(mine: Node3D) -> void:
	_ensure_harvest_module()._on_gold_mine_depleted(mine)


func _on_gold_mine_collapse_finished(mine: Node3D) -> void:
	_ensure_harvest_module()._on_gold_mine_collapse_finished(mine)


func _terminate_unit_production(unit: Node3D) -> void:
	_ensure_production_module().terminate(unit)


func _release_unit_food(unit: Node3D) -> void:
	if unit == null or bool(unit.get_meta("food_released", false)):
		return
	var d: Dictionary = unit.get_meta("unit_data", {})
	var unit_owner := int(d.get("owner", -1))
	var tid := str(d.get("typeId", "")).strip_edges()
	var food := BuildingCatalog.get_food_used(tid)
	var capacity := BuildingCatalog.get_food_made(tid) if not UnitLife.is_under_construction(unit) else 0
	if food <= 0 and capacity <= 0:
		return
	var stock := _stock_for_owner(unit_owner)
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

	var vp := get_viewport()
	if vp != null:
		_last_screen_pos = vp.get_mouse_position()
	var module := _ensure_build_module()
	if not module.begin_placement(building_id, _last_screen_pos, not _pointer_over_blocking_gui()):
		_ensure_interaction_module().cancel_aim("build_fail")

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

	else:
		_sync_selector_enabled_for_targeting()
	if game_hud:
		game_hud.set_status("建造取消")


## —— GM：英雄等级 / 技能（转发 DebugToolsModule）——


func gm_hero_level_up() -> void:
	_ensure_debug_tools_module().hero_level_up()


func gm_hero_max_level() -> void:
	_ensure_debug_tools_module().hero_max_level()


## 构造 uv → world 的 Callable：heightfield 可用时走其 minimap_uv_to_world，
## 否则按 _cam_min / _cam_max 线性映射。Bridge 不直接持有 Heightfield / Camera。
func _make_uv_to_world_callable() -> Callable:
	return func(uv: Vector2) -> Vector3:
		var hf := _heightfield
		if hf != null and is_instance_valid(hf) and hf.is_valid():
			return MapMinimapUtils.minimap_uv_to_world(uv, hf, 0.0)
		var wx := lerpf(_cam_min.x, _cam_max.x, uv.x)
		var wy := lerpf(_cam_max.y, _cam_min.y, uv.y)
		return Wc3Coords.wc3_xy_to_godot(wx, wy, 0.0)


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
	return _ensure_interaction_feedback().pointer_over_blocking_gui(_last_screen_pos)


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
	# 协助农民轮询「首工到位后」登记的工地（BuildModule 反查）
	_ensure_build_module()
	bc.find_site_at = Callable(_build, "find_site")


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


func _on_build_completed(order: BuildOrder, site_wc3: Vector2, player_owner: int) -> void:
	var building: Node3D = _ensure_build_module().on_construction_completed(
		order, site_wc3, player_owner
	)
	## 守卫塔等有武器建筑：完工后 HOLD 站桩开火。
	if building != null:
		_ensure_units_module().ensure_combat_ai(building)
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
	_ensure_navigation_module().refresh_dynamic_pathing()

func _build_entry_for(building_id: String, site_wc3: Vector2, player_owner: int, creation_number: int = -1) -> Dictionary:
	return _ensure_units_module().build_building_entry(building_id, site_wc3, player_owner, creation_number)


## 主城/兵营等可训建筑：命令卡带 training_unit 高亮 + Requires 置灰。
## 建造中：隐藏训兵按钮，保留集结点。
func _apply_building_train_card(building: Node3D, tid: String) -> void:
	_ensure_command_card_module().apply_building_train_card(building, tid)


func _owned_buildings_for_local() -> Dictionary:
	return _ensure_command_card_module().owned_buildings_for_local()


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


func _try_issue_building_upgrade(target_id: String) -> void:
	_ensure_production_module()
	_production_panel.request_building_upgrade(target_id)


## 商店购入：ItemsModule 扣费入包，刷状态栏与命令卡库存。
func _try_issue_buy(item_id: String) -> void:
	var result := _ensure_items_module().try_buy_item(item_id)
	var reason := str(result.get("reason", "")).strip_edges()
	if not reason.is_empty() and game_hud != null:
		if bool(result.get("ok", false)):
			game_hud.set_status(reason)
		elif game_hud.has_method("show_command_tip"):
			game_hud.show_command_tip(reason)
		else:
			game_hud.set_status(reason)
	if is_instance_valid(_command_card):
		_command_card.refresh()


## 主城升本完工：改 typeId、按比例保留生命、切 TownHall 档位姿态（同模型）。
func _apply_building_upgrade(building: Node3D, new_type_id: String) -> bool:
	return _ensure_units_module().forms.apply_building_upgrade(building, new_type_id)


func _wire_train_queue(queue: TrainQueue) -> void:
	_ensure_production_module().watch(queue)


## 训练中切 Stand Work（门开 + 门光）；队列空回 Stand。


func _apply_revived_hero_state(unit: Node3D, completed: Dictionary) -> void:
	_ensure_production_module().apply_revived_hero_state(unit, completed)


## 训练完工刷单位：脚印四角（集结最近 / 默认左下）→ 重叠则自建筑中心挤位 → 再跟集结。
func _spawn_trained_unit(
	unit_id: String, site_wc3: Vector2, owner_id: int, from_building: Node3D = null
) -> Node3D:
	return _ensure_units_module().spawn_trained(unit_id, site_wc3, owner_id, from_building)


## 训练刷兵后改坐标（挤位）；同步 unit_data 与贴地。
func _teleport_unit_wc3(unit: Node3D, wc3_xy: Vector2) -> void:
	_ensure_units_module().teleport_wc3(unit, wc3_xy)


## 只结算已加入会话的玩家；中立或无效 owner 不创建隐式库存。
func _stock_for_unit(unit: Node3D) -> PlayerStock:
	if not is_instance_valid(unit):
		return null
	var data: Dictionary = unit.get_meta("unit_data", {})
	return _stock_for_owner(int(data.get("owner", -1)))


func _stock_for_owner(owner_id: int) -> PlayerStock:
	if _session == null:
		return null
	return _session.stocks.get(owner_id) as PlayerStock


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


func _tree_cn_of(node: Node) -> int:
	return _ensure_harvest_module().tree_cn_of(node)


static func _is_gold_mine(node: Node) -> bool:
	return HarvestModule.is_gold_mine(node)


func _on_unit_locomotion_changed(_moving: bool) -> void:
	_refresh_move_executing_ui()


func _ensure_unit_visual(unit: Node3D) -> Unit:
	return _ensure_units_module().presenter.ensure_visual(unit)


## 刷单位时挂选框场景 + Selectable / Interactable，并注入依赖。
func _ensure_interaction_components(unit: Node3D) -> void:
	_ensure_units_module().presenter.ensure_interaction(unit)


func _ground_at_screen(screen_pos: Vector2) -> Vector3:
	return _ensure_world_picker().ground_at_screen(screen_pos)


func _on_selection_changed(primary: Node3D, selected: Array) -> void:
	var started: int = MatchHotpathMetrics.begin()
	_measured_on_selection_changed(primary, selected)
	MatchHotpathMetrics.finish(&"selection_event", started)


func _measured_on_selection_changed(primary: Node3D, selected: Array) -> void:
	_ensure_selection_hud_module().bind_inventory_for(primary)
	_ensure_interaction_module().on_selection_changed(primary, selected)

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


func _on_ground_item_spawned(ground: GroundItem) -> void:
	if is_instance_valid(_items):
		_items.call("_on_ground_spawned", ground)


func _on_inventory_changed() -> void:
	_ensure_items_module().on_inventory_changed()


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
		_bound_modules.erase(&"debug_tools")
		_debug_tools.name = "DebugToolsModule"
		add_child(_debug_tools)
	if _bound_modules.get(&"debug_tools", -1) == _binding_epoch:
		return _debug_tools
	if game_hud == null or unit_selector == null:
		push_warning("GameDirector: DebugToolsModule 绑定跳过（hud/selector 未注入）")
		return _debug_tools
	_debug_tools.configure({
		"map_root": map_root,
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
	_bound_modules[&"debug_tools"] = _binding_epoch
	_binding_counts[&"debug_tools"] = int(_binding_counts.get(&"debug_tools", 0)) + 1
	return _debug_tools


## 装配对手电脑：经营 / 军队 AI 挂接。
func _ensure_opponent_ai_module() -> OpponentAiModule:
	if not is_instance_valid(_opponent_ai):
		_opponent_ai = OpponentAiModule.new()
		_bound_modules.erase(&"opponent_ai")
		_opponent_ai.name = "OpponentAiModule"
		add_child(_opponent_ai)
	if _bound_modules.get(&"opponent_ai", -1) == _binding_epoch:
		return _opponent_ai
	_opponent_ai.configure({
		"host_parent": self,
		"map_root": map_root,
		"session": _session,
		"path_query": _path_query,
		"crowd_query": _crowd_query,
		"pathing": _pathing,
		"tree_registry": _tree_registry,
		"item_service": _ensure_items_module().item_service,
		"ensure_navigator": Callable(_ensure_navigation_module(), "ensure_navigator"),
		"ensure_harvest": Callable(_ensure_harvest_module(), "ensure_controller"),
		"ensure_build": Callable(self, "_ensure_build_controller"),
		"ensure_attack": Callable(_ensure_combat_module(), "ensure_attack_controller"),
		"find_build_site": Callable(_build, "find_site"),
		"find_build_site_by_node": Callable(_build, "find_site_for_node"),
		"wire_train_queue": Callable(self, "_wire_train_queue"),
		"stock_for_owner": Callable(self, "_stock_for_owner"),
	})
	_bound_modules[&"opponent_ai"] = _binding_epoch
	_binding_counts[&"opponent_ai"] = int(_binding_counts.get(&"opponent_ai", 0)) + 1
	return _opponent_ai


## 装配对局生命周期：胜负接线、结算屏、重开。
func _ensure_match_lifecycle_module() -> MatchLifecycleModule:
	if not is_instance_valid(_match_lifecycle):
		_match_lifecycle = MatchLifecycleModule.new()
		_bound_modules.erase(&"match_lifecycle")
		_match_lifecycle.name = "MatchLifecycleModule"
		add_child(_match_lifecycle)
	if _bound_modules.get(&"match_lifecycle", -1) == _binding_epoch:
		return _match_lifecycle
	_match_lifecycle.configure({
		"game_root": get_parent(),
		"settings_source": self,
	})
	_bound_modules[&"match_lifecycle"] = _binding_epoch
	_binding_counts[&"match_lifecycle"] = int(_binding_counts.get(&"match_lifecycle", 0)) + 1
	return _match_lifecycle


## 装配对局开局：会话、本地/对手基地、镜头落点。
func _ensure_match_bootstrap_module() -> MatchBootstrapModule:
	if not is_instance_valid(_match_bootstrap):
		_match_bootstrap = MatchBootstrapModule.new()
		_bound_modules.erase(&"match_bootstrap")
		_match_bootstrap.name = "MatchBootstrapModule"
		add_child(_match_bootstrap)
	if _bound_modules.get(&"match_bootstrap", -1) == _binding_epoch:
		return _match_bootstrap
	if game_hud == null or rts_camera == null:
		push_warning("GameDirector: MatchBootstrapModule 绑定跳过（hud/camera 未注入）")
		return _match_bootstrap
	_match_bootstrap.configure({
		"map_root": map_root,
		"map_dir": map_dir,
		"game_hud": game_hud,
		"rts_camera": rts_camera,
		"rng": _rng,
		"apply_cursor_race": Callable(self, "_apply_cursor_race"),
		"refresh_pathing": Callable(_ensure_navigation_module(), "refresh_dynamic_pathing"),
		"map_display_name": Callable(self, "_map_display_name"),
		"on_pathing_map": Callable(_ensure_navigation_module(), "bind_pathing"),
	})
	_bound_modules[&"match_bootstrap"] = _binding_epoch
	_binding_counts[&"match_bootstrap"] = int(_binding_counts.get(&"match_bootstrap", 0)) + 1
	return _match_bootstrap


## 装配路径调试：选中单位寻路折线。
func _ensure_path_debug_module() -> PathDebugModule:
	if not is_instance_valid(_path_debug_mod):
		_path_debug_mod = PathDebugModule.new()
		_bound_modules.erase(&"path_debug_mod")
		_path_debug_mod.name = "PathDebugModule"
		add_child(_path_debug_mod)
	if _bound_modules.get(&"path_debug_mod", -1) == _binding_epoch:
		return _path_debug_mod
	if unit_selector == null:
		push_warning("GameDirector: PathDebugModule 绑定跳过（selector 未注入）")
		return _path_debug_mod
	_path_debug_mod.configure({
		"map_root": map_root,
		"heightfield": _heightfield,
		"unit_selector": unit_selector,
		"enabled": show_path_debug,
	})
	_bound_modules[&"path_debug_mod"] = _binding_epoch
	_binding_counts[&"path_debug_mod"] = int(_binding_counts.get(&"path_debug_mod", 0)) + 1
	return _path_debug_mod


## 装配选中 HUD：肖像 vitals / buff / 选中详情。
func _ensure_selection_hud_module() -> SelectionHudModule:
	if not is_instance_valid(_selection_hud):
		_selection_hud = SelectionHudModule.new()
		_selection_hud.name = "SelectionHudModule"
		add_child(_selection_hud)
	if game_hud == null or unit_selector == null:
		push_warning("GameDirector: SelectionHudModule 绑定跳过（hud/selector 未注入）")
		return _selection_hud
	if _selection_hud.matches_dependencies(game_hud, unit_selector, map_root):
		return _selection_hud
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
		push_warning("GameDirector: CommandCardModule 绑定跳过（hud/selector 未注入）")
		return _command_card
	if _command_card.matches_dependencies(game_hud, unit_selector, _command_router, _session, enable_move_command):
		return _command_card
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
			_ensure_interaction_module().cancel_aim("submenu"),
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
		"try_building_upgrade": Callable(self, "_try_issue_building_upgrade"),
		"try_buy": Callable(self, "_try_issue_buy"),
	})
	return _command_card


## 装配交互模块：互斥瞄准状态机 + 光标同步。
func _ensure_interaction_module() -> InteractionModule:
	if not is_instance_valid(_interaction):
		_interaction = InteractionModule.new()
		_bound_modules.erase(&"interaction")
		_interaction.name = "InteractionModule"
		add_child(_interaction)
	if _bound_modules.get(&"interaction", -1) == _binding_epoch:
		return _interaction
	if game_cursor == null:
		push_warning("GameDirector: InteractionModule 绑定跳过（cursor 未注入）")
		return _interaction
	_interaction.configure({
		"cursor": game_cursor as Wc3GameCursor,
		"unit_selector": unit_selector,
		"set_status": Callable(self, "_ability_set_status"),
		"cancel_ability": func() -> void:
			if is_instance_valid(_abilities):
				_abilities.cancel_targeting(),
		"cancel_build": Callable(self, "_cancel_build_targeting"),
		"ability_target_kind": func() -> int:
			return AbilityCatalog.target_kind(_abilities.pending_abil_id()) if is_instance_valid(_abilities) else 0,
		"is_ability_targeting": func() -> bool:
			return is_instance_valid(_abilities) and _abilities.is_targeting(),
		"is_build_targeting": Callable(self, "_is_build_targeting"),
	})
	_bound_modules[&"interaction"] = _binding_epoch
	_binding_counts[&"interaction"] = int(_binding_counts.get(&"interaction", 0)) + 1
	return _interaction


## 装配智能右键：目标解析、闪选、状态文案。
func _ensure_smart_command_module() -> SmartCommandModule:
	if not is_instance_valid(_smart_command):
		_smart_command = SmartCommandModule.new()
		_bound_modules.erase(&"smart_command")
		_smart_command.name = "SmartCommandModule"
		add_child(_smart_command)
	if _bound_modules.get(&"smart_command", -1) == _binding_epoch:
		return _smart_command
	if unit_selector == null or rts_camera == null:
		push_warning("GameDirector: SmartCommandModule 绑定跳过（selector/camera 未注入）")
		return _smart_command
	# ground_items 可能在 ItemsModule 之后才就绪
	if _ground_items == null and is_instance_valid(_items):
		_ground_items = _items.ground_host()
	_smart_command.configure({
		"unit_selector": unit_selector,
		"rts_camera": rts_camera,
		"tree_registry": _tree_registry,
		"ground_items": _ground_items,
		"ground_at_screen": Callable(_ensure_world_picker(), "ground_at_screen"),
		"is_gold_mine": Callable(self, "_is_gold_mine"),
	})
	_bound_modules[&"smart_command"] = _binding_epoch
	_binding_counts[&"smart_command"] = int(_binding_counts.get(&"smart_command", 0)) + 1
	return _smart_command


## 装配命令输入：issue_*/begin_*、瞄准点击与智能右键。
## InteractionModule 持瞄准态；SmartCommandModule 解析 SmartTarget；本模块只下发。
func _ensure_command_input_module() -> CommandInputModule:
	if not is_instance_valid(_command_input):
		_command_input = CommandInputModule.new()
		_bound_modules.erase(&"command_input")
		_command_input.name = "CommandInputModule"
		add_child(_command_input)
	if _bound_modules.get(&"command_input", -1) == _binding_epoch:
		return _command_input
	if unit_selector == null or rts_camera == null:
		push_warning("GameDirector: CommandInputModule 绑定跳过（selector/camera 未注入）")
		return _command_input
	_command_input.configure({
		"command_router": _command_router,
		"unit_selector": unit_selector,
		"path_query": _path_query,
		"tree_registry": _tree_registry,
		"interaction": _ensure_interaction_module(),
		"smart_command": _ensure_smart_command_module(),
		"game_hud": game_hud,
		"ground_at_screen": Callable(_ensure_world_picker(), "ground_at_screen"),
		"get_selected": Callable(self, "_get_selected_safe"),
		"interrupt_channels": Callable(self, "_interrupt_channels_for_units"),
		"refresh_command_card": Callable(self, "_refresh_command_card"),
		"spawn_move_confirm": Callable(_ensure_interaction_feedback(), "spawn_move_confirm"),
		"flash_cursor_move": Callable(self, "_flash_cursor_move"),
		"sync_rally_flag": Callable(_ensure_interaction_feedback(), "sync_rally_flag"),
		"ensure_navigator": Callable(_ensure_navigation_module(), "ensure_navigator"),
		"is_gold_mine": Callable(self, "_is_gold_mine"),
		"is_harvestable_tree": Callable(_ensure_harvest_module(), "is_harvestable_tree"),
		"tree_cn_of": Callable(_ensure_harvest_module(), "tree_cn_of"),
		"local_stock": Callable(self, "_local_stock"),
		"is_controllable": Callable(self, "_is_controllable"),
	})
	_bound_modules[&"command_input"] = _binding_epoch
	_binding_counts[&"command_input"] = int(_binding_counts.get(&"command_input", 0)) + 1
	return _command_input


## 装配战斗模块：伤害管线、投射物、死亡/尸体、AttackController。
## 食物释放 / 生产终止 / 物品死亡准备 / 选中清理经 Callable 注入。
func _ensure_combat_module() -> CombatModule:
	if not is_instance_valid(_combat):
		_combat = CombatModule.new()
		_bound_modules.erase(&"combat")
		_combat.name = "CombatModule"
		add_child(_combat)
		_combat.tree_exiting.connect(_on_combat_module_exiting)
	if _bound_modules.get(&"combat", -1) == _binding_epoch:
		return _combat
	_combat.configure({
		"map_root": map_root,
		"health_bar_manager": health_bar_manager,
		"ensure_navigator": Callable(_ensure_navigation_module(), "ensure_navigator"),
		"ensure_unit_visual": Callable(_unit_presenter(), "ensure_visual"),
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
	_bound_modules[&"combat"] = _binding_epoch
	_binding_counts[&"combat"] = int(_binding_counts.get(&"combat", 0)) + 1
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
		_bound_modules.erase(&"build")
		_build.name = "BuildModule"
		add_child(_build)
	if _bound_modules.get(&"build", -1) == _binding_epoch:
		return _build
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
		"alloc_creation_number": Callable(self, "_alloc_runtime_cn"),
		"build_entry_for": Callable(self, "_build_entry_for"),
		"find_anim_player": Callable(self, "_find_anim_player"),
		"issue_move": Callable(self, "_command_router_issue_move"),
		"ensure_navigator": Callable(_ensure_navigation_module(), "ensure_navigator"),
		"ensure_unit_visual": Callable(_unit_presenter(), "ensure_visual"),
		"resync_health_bars": Callable(self, "_resync_health_bars"),
		"ground_at_screen": Callable(_ensure_world_picker(), "ground_at_screen"),
		"refresh_pathing": Callable(_ensure_navigation_module(), "refresh_dynamic_pathing"),
	})
	_bound_modules[&"build"] = _binding_epoch
	_binding_counts[&"build"] = int(_binding_counts.get(&"build", 0)) + 1
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
		_bound_modules.erase(&"units")
		_units.name = "UnitsModule"
		_units.form_changed.connect(_on_unit_form_changed)
		add_child(_units)
	if _entity_registry == null:
		_entity_registry = EntityRegistry.new()
	if _bound_modules.get(&"units", -1) == _binding_epoch:
		return _units
	_units.configure({
		"navigation": _ensure_navigation_module(),
		"session": _session,
		"map_root": map_root,
		"heightfield": _heightfield,
		"path_query": _path_query,
		"crowd_query": _crowd_query,
		"command_router": _command_router,
		"health_bar_manager": health_bar_manager,
		"registry_host": self,
		"entity_registry": _entity_registry,
		"ensure_navigator": Callable(_ensure_navigation_module(), "ensure_navigator"),
		"ensure_attack_controller": Callable(_ensure_combat_module(), "ensure_attack_controller"),
		"unit_host": Callable(self, "_unit_host"),
		"refresh_pathing": Callable(_ensure_navigation_module(), "refresh_dynamic_pathing"),
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
	_bound_modules[&"units"] = _binding_epoch
	_binding_counts[&"units"] = int(_binding_counts.get(&"units", 0)) + 1
	return _units


## D5：技能行为工厂（对局内冻结后只读）。
func _ensure_behavior_registry() -> BehaviorRegistry:
	if _behavior_registry == null:
		_behavior_registry = BehaviorRegistry.new()
	return _behavior_registry


## 装配技能模块：cast ctx / runtime / 瞄准 / 预览。
func _ensure_abilities_module() -> AbilitiesModule:
	if not is_instance_valid(_abilities):
		_abilities = AbilitiesModule.new()
		_bound_modules.erase(&"abilities")
		_abilities.name = "AbilitiesModule"
		add_child(_abilities)
	if _bound_modules.get(&"abilities", -1) == _binding_epoch:
		return _abilities
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
		"ground_at_screen": Callable(_ensure_world_picker(), "ground_at_screen"),
		"clear_rival_targeting": Callable(self, "_clear_rival_targeting_for_ability"),
		"on_targeting_changed": Callable(self, "_on_ability_targeting_changed"),
		"set_status": Callable(self, "_ability_set_status"),
		"refresh_command_card": Callable(self, "_refresh_command_card"),
		"refresh_pathing": Callable(_ensure_navigation_module(), "refresh_dynamic_pathing"),
		"resync_health_bars": func() -> void:
			if health_bar_manager != null:
				health_bar_manager.resync(),
		"sync_selection_info": Callable(self, "_sync_selection_info_panel"),
		"last_screen_pos": func() -> Vector2: return _last_screen_pos,
	})
	_ability_runtime = _abilities.runtime
	_bound_modules[&"abilities"] = _binding_epoch
	_binding_counts[&"abilities"] = int(_binding_counts.get(&"abilities", 0)) + 1
	return _abilities


## 装配物品模块：地面物、背包操作、死亡掉落订阅。
func _ensure_items_module() -> ItemsModule:
	if not is_instance_valid(_items):
		_items = ItemsModule.new()
		_bound_modules.erase(&"items")
		_items.name = "ItemsModule"
		add_child(_items)
	if _bound_modules.get(&"items", -1) == _binding_epoch:
		return _items
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
		"local_stock": Callable(self, "_local_stock"),
		"unit_host": Callable(self, "_unit_host"),
		"get_selected": Callable(self, "_get_selected_safe"),
	})
	_item_service = _items.item_service
	_ground_items = _items.ground_host()
	_bound_modules[&"items"] = _binding_epoch
	_binding_counts[&"items"] = int(_binding_counts.get(&"items", 0)) + 1
	return _items


## 只负责装配对局生产模块及其界面适配器。
## 单位创建经 UnitsModule 显式接口注入。
func _ensure_production_module() -> ProductionModule:
	if not is_instance_valid(_production):
		_production = ProductionModule.new()
		_bound_modules.erase(&"production")
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
	if (_bound_modules.get(&"production", -1) == _binding_epoch
			and _production_panel.matches_dependencies(_session, _command_router, unit_selector, game_hud)):
		return _production
	var units := _ensure_units_module()
	_production.configure(
		_session,
		units.spawn_trained,
		units.ensure_hero,
		Callable(units, "apply_building_upgrade")
	)
	_production_panel.configure(_session, _command_router, unit_selector, game_hud,
		_unit_host(), map_root.get_model_cache() if map_root != null else null)
	_bound_modules[&"production"] = _binding_epoch
	_binding_counts[&"production"] = int(_binding_counts.get(&"production", 0)) + 1
	return _production


func _on_production_activity_changed(_queue: TrainQueue = null) -> void:
	if game_hud == null or not is_instance_valid(_production) or _session == null:
		return
	if not game_hud.has_method("set_activity_feed"):
		return
	game_hud.set_activity_feed(_production.collect_owner_activities(_session.local_player))


func _ensure_navigation_module() -> NavigationModule:
	if not is_instance_valid(_navigation):
		_navigation = NavigationModule.new()
		_navigation.name = "NavigationModule"
		add_child(_navigation)
		_navigation.locomotion_changed.connect(_on_unit_locomotion_changed)
	return _navigation


func _ensure_harvest_module() -> HarvestModule:
	if not is_instance_valid(_harvest):
		_harvest = HarvestModule.new()
		_bound_modules.erase(&"harvest")
		_harvest.name = "HarvestModule"
		add_child(_harvest)
		_harvest.carry_changed.connect(_on_harvest_carry_changed)
		_harvest.deposited.connect(_on_harvest_deposited)
		_harvest.state_changed.connect(_on_harvest_state_changed)
		_harvest.mine_depleted.connect(_deselect_unit_on_death)

	if _bound_modules.get(&"harvest", -1) == _binding_epoch:
		return _harvest
	_harvest.configure(map_root, _ensure_navigation_module(), _session,
		rts_camera.get_camera() if rts_camera != null else null,
		Callable(_unit_presenter(), "ensure_visual"), Callable(_ensure_combat_module(), "on_corpse_expired"))
	_bound_modules[&"harvest"] = _binding_epoch
	_binding_counts[&"harvest"] = int(_binding_counts.get(&"harvest", 0)) + 1
	return _harvest


func _unit_presenter() -> UnitModelPresenter:
	# 表现绑定在地图加载前也可用，不触发其余玩法模块装配。
	if not is_instance_valid(_units):
		_units = UnitsModule.new()
		_bound_modules.erase(&"units")
		_units.name = "UnitsModule"
		_units.form_changed.connect(_on_unit_form_changed)
		add_child(_units)
	if _units.presenter.map_root != map_root:
		_units.presenter.configure(map_root)
	return _units.presenter

func _on_unit_form_changed(_unit: Node3D) -> void:
	_refresh_command_card()
	_sync_selection_info_panel()
	_resync_health_bars()


func _ensure_world_picker() -> WorldPicker:
	if _world_picker == null:
		_world_picker = WorldPicker.new()
		_bound_modules.erase(&"world_picker")
	if _bound_modules.get(&"world_picker", -1) == _binding_epoch:
		return _world_picker
	_world_picker.configure(rts_camera, _ensure_navigation_module())
	_bound_modules[&"world_picker"] = _binding_epoch
	_binding_counts[&"world_picker"] = int(_binding_counts.get(&"world_picker", 0)) + 1
	return _world_picker

func _ensure_interaction_feedback() -> InteractionFeedback:
	if not is_instance_valid(_feedback):
		_feedback = InteractionFeedback.new()
		_bound_modules.erase(&"feedback")
		_feedback.name = "InteractionFeedback"
		add_child(_feedback)
	if _bound_modules.get(&"feedback", -1) == _binding_epoch:
		return _feedback
	_feedback.configure(map_root, unit_selector, _session, _ensure_navigation_module(),
		preview_race, local_player, Callable(self, "_get_selected_safe"), Callable(self, "_is_controllable"))
	_bound_modules[&"feedback"] = _binding_epoch
	_binding_counts[&"feedback"] = int(_binding_counts.get(&"feedback", 0)) + 1
	return _feedback

func _ensure_match_input() -> MatchInputController:
	if not is_instance_valid(_match_input):
		_match_input = MatchInputController.new()
		_bound_modules.erase(&"match_input")
		_match_input.name = "MatchInput"
		add_child(_match_input)
		_match_input.path_debug_toggle_requested.connect(_toggle_path_debug)
	if _bound_modules.get(&"match_input", -1) == _binding_epoch:
		return _match_input
	_match_input.configure({
		"commands": _ensure_command_input_module(),
		"interaction": _ensure_interaction_module(),
		"abilities": _ensure_abilities_module(),
		"build": _ensure_build_module(),
		"card": _ensure_command_card_module(),
		"debug": _ensure_debug_tools_module(),
		"feedback": _ensure_interaction_feedback(),
		"selector": unit_selector,
		"hud": game_hud,
		"commit_build": Callable(self, "_commit_build_targeting"),
		"cancel_build": Callable(self, "_cancel_build_targeting"),
	})
	_bound_modules[&"match_input"] = _binding_epoch
	_binding_counts[&"match_input"] = int(_binding_counts.get(&"match_input", 0)) + 1
	# 等到所有可能注入的模块就绪后，再把 UiBridge 字段刷新一次
	_bind_ui_bridge()
	return _match_input

func _toggle_path_debug() -> void:
	show_path_debug = not show_path_debug
	_ensure_path_debug()
	_apply_path_debug_visibility()
	if game_hud:
		game_hud.set_status("路径调试：%s" % ("开" if show_path_debug else "关"))


## 替换场景依赖后显式调用；保留运行中的查询、预约、队列和瞄准状态。
## 切换整张地图/对局应走 MatchLifecycle 的重开流程。
func rebind_modules() -> void:
	_binding_epoch += 1
	_wire_hud()
	_setup_selector()
	_ensure_combat_module()
	_ensure_units_module()
	_ensure_harvest_module()
	_ensure_build_module()
	_ensure_interaction_module()
	_ensure_abilities_module()
	_ensure_items_module()
	_ensure_production_module()
	_ensure_smart_command_module()
	_ensure_command_input_module()
	_ensure_command_card_module()
	_ensure_selection_hud_module()
	_ensure_path_debug_module()
	_ensure_debug_tools_module()
	_ensure_interaction_feedback()
	_ensure_match_input()
	_ensure_match_bootstrap_module()
	_ensure_match_lifecycle_module()
	_ensure_opponent_ai_module()
	_interaction.refresh_selector()
	if _behavior_registry != null and not _behavior_registry.is_frozen():
		_behavior_registry.freeze()

func module_binding_counts() -> Dictionary:
	return _binding_counts.duplicate()
