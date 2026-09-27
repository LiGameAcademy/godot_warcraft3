class_name GameMain
extends Node3D

## 场景根：负责子节点之间的依赖注入。
## 装配顺序由 SCENE_BOOTSTRAP.md 锁定（拓扑序：上游依赖先 setup，下游依赖后 setup）。
##
## Godot _ready 是 bottom-up：子节点（GameDirector）先于父（GameMain）执行 _ready。
## GameDirector._ready 等一帧再 _boot_match（await process_frame），本节点 _ready 在此期间完成 setup() 注入。

@onready var world_environment: WorldEnvironment = %WorldEnvironment
@onready var sun: DirectionalLight3D = %Sun
@onready var map_root: MapLoader = %MapRoot
@onready var rts_camera: RtsCamera = %RtsCamera
@onready var game_hud: GameHud = %GameHud
@onready var health_bar_manager: HealthBarManager = %HealthBarManager
@onready var unit_selector: UnitSelector = %UnitSelector
@onready var game_director: GameDirector = %GameDirector
@onready var game_cursor: Wc3GameCursor = %GameCursor
@onready var game_loading_screen: GameLoadingScreen = %GameLoadingScreen


func _ready() -> void:
	_boot_scene()


## 拓扑序：上游依赖先 setup，下游依赖后 setup。任何 setup 失败都 push_warning 但不打断其它子节点。
func _boot_scene() -> void:
	# 上游：选择器只读相机 / 单位层
	_setup_unit_selector(rts_camera.get_camera() if rts_camera else null, map_root)
	# 鼠标光标：只读 selector（保留引用，详见 Wc3GameCursor.setup 注释）
	_setup_game_cursor(unit_selector)
	# 血条：读相机 / 单位层（selector 不参与血条渲染，故不传）
	_setup_health_bar_manager(
		rts_camera.get_camera() if rts_camera else null,
		map_root,
	)
	# 相机：读 map_root（地形跟随 + 边界）
	_setup_rts_camera(map_root)
	# HUD：缓存 selector / director / health_bar 引用（UiSurface 调试用）
	_setup_game_hud(unit_selector, game_director, health_bar_manager)
	# 主协调：依赖前面所有子节点
	_setup_game_director(
		map_root,
		rts_camera,
		game_hud,
		unit_selector,
		game_cursor,
		health_bar_manager,
		game_loading_screen,
	)
	# Loading 最后：订阅 session_ready / map_loaded
	_setup_game_loading_screen(map_root, game_director, game_hud, health_bar_manager)


func _setup_unit_selector(p_camera: Camera3D, p_map_root: MapLoader) -> void:
	if unit_selector == null:
		push_warning("GameMain: UnitSelector 未挂载")
		return
	var unit_host := p_map_root.get_unit_layer() if p_map_root != null else null
	unit_selector.setup(p_camera, unit_host)


func _setup_game_cursor(p_unit_selector: Node) -> void:
	if game_cursor == null:
		push_warning("GameMain: GameCursor 未挂载")
		return
	game_cursor.setup(p_unit_selector)


func _setup_health_bar_manager(p_camera: Camera3D, p_map_root: MapLoader) -> void:
	if health_bar_manager == null:
		push_warning("GameMain: HealthBarManager 未挂载")
		return
	health_bar_manager.setup(p_camera, p_map_root)


func _setup_rts_camera(p_map_root: MapLoader) -> void:
	if rts_camera == null:
		push_warning("GameMain: RtsCamera 未挂载")
		return
	rts_camera.setup(p_map_root)


func _setup_game_hud(
	p_unit_selector: Node,
	p_game_director: GameDirector,
	p_health_bar_manager: HealthBarManager
) -> void:
	if game_hud == null:
		push_warning("GameMain: GameHud 未挂载")
		return
	game_hud.setup(p_unit_selector, p_game_director, p_health_bar_manager)


func _setup_game_director(
	p_map_root: MapLoader,
	p_rts_camera: RtsCamera,
	p_game_hud: GameHud,
	p_unit_selector: Node,
	p_game_cursor: Node,
	p_health_bar_manager: HealthBarManager,
	p_game_loading_screen: Node,
) -> void:
	if game_director == null:
		push_warning("GameMain: GameDirector 未挂载")
		return
	game_director.setup(
		p_map_root,
		p_rts_camera,
		p_game_hud,
		p_unit_selector,
		p_game_cursor,
		p_health_bar_manager,
		p_game_loading_screen,
	)


func _setup_game_loading_screen(
	p_map_root: MapLoader,
	p_game_director: GameDirector,
	p_game_hud: CanvasLayer,
	p_health_bar_manager: CanvasLayer,
) -> void:
	if game_loading_screen == null:
		push_warning("GameMain: GameLoadingScreen 未挂载")
		return
	game_loading_screen.setup(
		p_map_root,
		p_game_director,
		p_game_hud,
		p_health_bar_manager,
	)