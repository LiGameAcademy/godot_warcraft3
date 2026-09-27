## 场景根：负责子节点之间的依赖注入。
##
## **本类是 game_main.tscn 的根节点脚本**。GameMain 的唯一职责是按拓扑序
## 给所有子节点（MapRoot / RtsCamera / GameHud / HealthBarManager / UnitSelector
## / GameDirector / GameCursor / GameLoadingScreen）显式注入依赖。
##
## 设计文档：docs/design/game/SCENE_BOOTSTRAP.md（v1.3 强类型 setup 签名）。
##
## ---- 调用时机 ----
## [br]Godot _ready 是 bottom-up：子节点（GameDirector）先于父（GameMain）
## 执行 _ready。GameDirector._ready 因此 await 一帧 [code]get_tree().process_frame[/code]
## 等本节点 _ready 完成 setup() 注入后再触发 _boot_match()。
##
## ---- 编排顺序（不可调换） ----
## [br]1. [UnitSelector] → 2. [GameCursor] → 3. [HealthBarManager]
## [br]→ 4. [RtsCamera] → 5. [GameHud] → 6. [GameDirector] → 7. [GameLoadingScreen]
## [br]理由：每个 setup 节点的入参都依赖前置节点的产物（如
## [GameDirector.setup] 持有所有上游节点；[GameLoadingScreen.setup]
## 仅在 GameDirector 完成 setup 后再订阅 session_ready 信号）。
##
## ---- 强类型形参约定 ----
## [br]所有 _setup_* 函数以强类型形参逐字段赋值（不用 Dictionary），避免
## 编辑期/编译期丢失类型检查；每个子节点的 setup 接口契约见各自脚本顶部注释。
##
## ---- 失败语义 ----
## [br]任何子节点为 null 时 push_warning 但不中断其它子节点注入；运行时由
## 各自 setup() 内部按 null short-circuit 处理。
class_name GameMain
extends Node3D

## 全局环境（雾 / 太阳光 / 后处理）。
## [br]挂点：game_main.tscn 的 [code]WorldEnvironment[/code] 节点（unique_name_in_owner = true）。
@onready var world_environment: WorldEnvironment = %WorldEnvironment

## 主方向光（WC3 原作始终 sun 朝下 + 偏南 45°）。
## [br]挂点：game_main.tscn 的 [code]Sun[/code] 节点（unique_name_in_owner = true）。
@onready var sun: DirectionalLight3D = %Sun

## 地图根：管理 wc3mapMap 加载、地形 mesh、单位层、装饰层。
## [br]挂点：game_main.tscn 的 [code]MapRoot[/code] 节点（unique_name_in_owner = true）。
## [br]作为依赖传入 UnitSelector.setup / HealthBarManager.setup / RtsCamera.setup /
## GameDirector.setup / GameLoadingScreen.setup。
@onready var map_root: MapLoader = %MapRoot

## RTS 相机：俯仰/偏航/六档滚轮缩放/地形跟随/边界夹紧。
## [br]挂点：game_main.tscn 的 [code]RtsCamera[/code] 节点（unique_name_in_owner = true）。
## [br]在 _boot_scene() 中通过 setup(map_root) 注入；之后由 GameDirector._configure_camera
## 写入具体的 pan_speed / fov / zoom 参数。
@onready var rts_camera: RtsCamera = %RtsCamera

## 底栏 HUD：资源条 / 活动流 / 小地图 / 命令卡 / 选中详情 / 物品栏。
## [br]挂点：game_main.tscn 的 [code]GameHud[/code] 节点（unique_name_in_owner = true）。
## [br]setup() 仅缓存 selector / director / hpbar 引用，便于 UiSurface 调试查询。
@onready var game_hud: GameHud = %GameHud

## 全局头顶血条（Present）。
## [br]挂点：game_main.tscn 的 [code]HealthBarManager[/code] 节点（unique_name_in_owner = true）。
## [br]setup() 接收相机与 MapLoader，内部自行调 get_unit_layer() 取单位层。
@onready var health_bar_manager: HealthBarManager = %HealthBarManager

## 点选/框选中央裁决（依赖相机 + 单位层）。
## [br]挂点：game_main.tscn 的 [code]UnitSelector[/code] 节点（unique_name_in_owner = true）。
@onready var unit_selector: UnitSelector = %UnitSelector

## 游戏总管（MapEditor 对标）：场景配置、对局启动、模块绑定。
## [br]挂点：game_main.tscn 的 [code]GameDirector[/code] 节点（unique_name_in_owner = true）。
## [br]接收 7 参 setup()：map_root / rts_camera / game_hud / unit_selector / game_cursor
## / health_bar_manager / game_loading_screen。
@onready var game_director: GameDirector = %GameDirector

## 对战鼠标光标（按种族切换图集）。
## [br]挂点：game_main.tscn 的 [code]GameCursor[/code] 节点（unique_name_in_owner = true）。
@onready var game_cursor: Wc3GameCursor = %GameCursor

## 进局全屏 Loading（遮罩地图装配过程，session_ready 后淡出）。
## [br]挂点：game_main.tscn 的 [code]GameLoadingScreen[/code] 节点（unique_name_in_owner = true）。
@onready var game_loading_screen: GameLoadingScreen = %GameLoadingScreen


## Godot 生命周期钩子：bottom-up 时序下由 GameDirector._ready 等一帧让本节点先完成 setup 注入。
func _ready() -> void:
	_boot_scene()


## 按 [SCENE_BOOTSTRAP.md] 锁定的拓扑序给所有子节点注入依赖。
## [br]任何子节点为 null 时 push_warning 但不打断其它子节点注入。
## [br]幂等性：本函数当前不重复防护（GameMain 仅 add_child(scene) 时调用一次）。
## [br]调用顺序固定为 1→7，详情见类级注释。
func _boot_scene() -> void:
	# 1. 上游：选择器只读相机 / 单位层
	_setup_unit_selector(rts_camera.get_camera() if rts_camera else null, map_root)
	# 2. 鼠标光标：只读 selector（保留引用，详见 Wc3GameCursor.setup 注释）
	_setup_game_cursor(unit_selector)
	# 3. 血条：读相机 / 单位层（selector 不参与血条渲染，故不传）
	_setup_health_bar_manager(
		rts_camera.get_camera() if rts_camera else null,
		map_root,
	)
	# 4. 相机：读 map_root（地形跟随 + 边界）
	_setup_rts_camera(map_root)
	# 5. HUD：缓存 selector / director / health_bar 引用（UiSurface 调试用）
	_setup_game_hud(unit_selector, game_director, health_bar_manager)
	# 6. 主协调：依赖前面所有子节点
	_setup_game_director(
		map_root,
		rts_camera,
		game_hud,
		unit_selector,
		game_cursor,
		health_bar_manager,
		game_loading_screen,
	)
	# 7. Loading 最后：订阅 session_ready / map_loaded
	_setup_game_loading_screen(map_root, game_director, game_hud, health_bar_manager)


## 步骤 1：UnitSelector 注入。
## [br]把相机 + MapRoot.get_unit_layer() 传给 UnitSelector.setup；
## unit_host 在 MapRoot 未就绪时为 null（UnitSelector.setup 内部 short-circuit）。
## [br][param p_camera] 相机（来自 RtsCamera 子节点）。
## [br][param p_map_root] 地图根（来自 MapRoot 子节点；用于 get_unit_layer）。
func _setup_unit_selector(p_camera: Camera3D, p_map_root: MapLoader) -> void:
	if unit_selector == null:
		push_warning("GameMain: UnitSelector 未挂载")
		return
	var unit_host := p_map_root.get_unit_layer() if p_map_root != null else null
	unit_selector.setup(p_camera, unit_host)


## 步骤 2：Wc3GameCursor 注入。
## [br]仅缓存 UnitSelector 引用（Wc3GameCursor.setup 不消费 selector，仅占位便于未来闪选联动）。
## [br][param p_unit_selector] UnitSelector 节点（保留引用，详见 Wc3GameCursor.setup 注释）。
func _setup_game_cursor(p_unit_selector: Node) -> void:
	if game_cursor == null:
		push_warning("GameMain: GameCursor 未挂载")
		return
	game_cursor.setup(p_unit_selector)


## 步骤 3：HealthBarManager 注入。
## [br]传相机 + MapRoot（HealthBarManager.setup 内部自行取 unit_layer）。
## [br][param p_camera] 相机（来自 RtsCamera 子节点）。
## [br][param p_map_root] 地图根（HealthBarManager 内部 get_unit_layer()）。
func _setup_health_bar_manager(p_camera: Camera3D, p_map_root: MapLoader) -> void:
	if health_bar_manager == null:
		push_warning("GameMain: HealthBarManager 未挂载")
		return
	health_bar_manager.setup(p_camera, p_map_root)


## 步骤 4：RtsCamera 注入。
## [br]RtsCamera.setup 仅缓存 MapLoader 引用，相机调参由 GameDirector._configure_camera
## 在 _boot_match() 中按 @export 值写入。
## [br][param p_map_root] 地图根（用于地形跟随与边界夹紧）。
func _setup_rts_camera(p_map_root: MapLoader) -> void:
	if rts_camera == null:
		push_warning("GameMain: RtsCamera 未挂载")
		return
	rts_camera.setup(p_map_root)


## 步骤 5：GameHud 注入（仅缓存引用）。
## [br]GameHud.setup 不消费参数，仅把它们存到 _unit_selector / _game_director /
## _health_bar_manager 字段，便于 UiSurface 调试查询；原有 _ready 自动装配不变。
## [br][param p_unit_selector] UnitSelector 节点。
## [br][param p_game_director] GameDirector 节点（强类型，便于类型查询）。
## [br][param p_health_bar_manager] HealthBarManager 节点（强类型）。
func _setup_game_hud(
	p_unit_selector: Node,
	p_game_director: GameDirector,
	p_health_bar_manager: HealthBarManager
) -> void:
	if game_hud == null:
		push_warning("GameMain: GameHud 未挂载")
		return
	game_hud.setup(p_unit_selector, p_game_director, p_health_bar_manager)


## 步骤 6：GameDirector 7 参 setup 注入。
## [br]顺序固定：map_root → rts_camera → game_hud → unit_selector → game_cursor
## → health_bar_manager → game_loading_screen。
## [br][param p_map_root] 地图根（GameDirector 内部装配 MapLoader.configure_unit_runtime）。
## [br][param p_rts_camera] RTS 相机（GameDirector._configure_camera 写入 zoom/fov 等）。
## [br][param p_game_hud] HUD（GameDirector._wire_hud 订阅 signal）。
## [br][param p_unit_selector] 选择器（GameDirector._setup_selector 挂 selection_changed）。
## [br][param p_game_cursor] 鼠标光标（InteractionModule 注入 cursor）。
## [br][param p_health_bar_manager] 血条（BuildModule / CombatModule 同步 resync）。
## [br][param p_game_loading_screen] Loading（历史用 duck-type 注入；当前 GameMain
## 直接走 GameLoadingScreen.setup()，本参数保留仅用于 GameDirector 内部 compat）。
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


## 步骤 7：GameLoadingScreen 4 参 setup 注入（最后一步）。
## [br]必须在 GameDirector 完成 setup 之后再调用，因为 GameLoadingScreen.setup
## 会订阅 game_director.session_ready / session_preparation_progress 信号。
## [br][param p_map_root] 地图根（订阅 map_root.load_progress）。
## [br][param p_game_director] 游戏总管（订阅 session_ready）。
## [br][param p_game_hud] HUD（loading 期间隐藏，session_ready 后恢复）。
## [br][param p_health_bar_manager] 血条（loading 期间隐藏，session_ready 后恢复）。
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