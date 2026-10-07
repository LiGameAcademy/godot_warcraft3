class_name GameMain
extends Node3D

## 场景根：子节点依赖注入 + **对外窄外观（Facade）**。
##
## **对内**：按拓扑序给 MapRoot / RtsCamera / GameHud / HealthBarManager /
## UnitSelector / GameDirector / GameCursor 注入依赖（见 [method _boot_scene]）。
##
## **对外**（[code]boot.gd[/code] / 重启）：只通过下列 API，不直接 [code]get_node[/code]
## 子节点：
## [br]- [signal preparation_progress] / [signal session_ready]
## [br]- [method wire_external_hooks]（入树前）
## [br]- [method configure_match] / [method set_gameplay_ui_visible]
## [br]- [method is_session_ready] / [method has_playable_match]
##
## 设计文档：docs/design/game/SCENE_BOOTSTRAP.md（v1.4）。

## 进度分段（绝对 0..1；资源段由 boot 在 GameMain 实例化前使用）。
const RESOURCE_END := 0.30
const MAP_END := 0.85
const PREPARATION_END := 0.99

## 开局准备总进度（已映射到绝对 0..1）。编排方订此信号推给 Loading View。
signal preparation_progress(stage: String, progress: float)

## 对局 session 就绪。编排方订此信号以 [method GameLoadingScreen.finish]。
signal session_ready

## 全局环境（雾 / 太阳光 / 后处理）。
@onready var world_environment: WorldEnvironment = %WorldEnvironment

## 主方向光。
@onready var sun: DirectionalLight3D = %Sun

## 地图根（对内 DI；对外勿直接访问）。
@onready var map_root: MapLoader = %MapRoot

## RTS 相机。
@onready var rts_camera: RtsCamera = %RtsCamera

## 底栏 HUD。
@onready var game_hud: GameHud = %GameHud

## 全局头顶血条。
@onready var health_bar_manager: HealthBarManager = %HealthBarManager

## 点选/框选。
@onready var unit_selector: UnitSelector = %UnitSelector

## 游戏总管。
@onready var game_director: GameDirector = %GameDirector

## 对战鼠标光标。
@onready var game_cursor: Wc3GameCursor = %GameCursor

## 入树前解析的子节点缓存（[method wire_external_hooks] 用；@onready 此时仍为 null）。
var _facade_map: MapLoader
var _facade_director: GameDirector
var _facade_hud: CanvasLayer
var _facade_hpbar: CanvasLayer
var _external_hooks_wired: bool = false


## Godot 生命周期：bottom-up 下由 GameDirector 等一帧让本节点先完成 setup。
func _ready() -> void:
	_boot_scene()


#region ========== 对外 Facade ==========

## 入树前调用：解析子节点、转接进度/就绪信号、默认隐藏玩法 UI。
## [br]必须在 [code]add_child(self)[/code] **之前**调用，以免漏掉 MapRoot._ready 早期 emit。
func wire_external_hooks() -> void:
	_ensure_facade_children()
	if _external_hooks_wired:
		return
	_external_hooks_wired = true
	set_gameplay_ui_visible(false)
	if _facade_map != null:
		if not _facade_map.load_progress.is_connected(_on_map_load_progress):
			_facade_map.load_progress.connect(_on_map_load_progress)
	if _facade_director != null:
		if not _facade_director.session_preparation_progress.is_connected(_on_session_preparation_progress):
			_facade_director.session_preparation_progress.connect(_on_session_preparation_progress)
		if not _facade_director.session_ready.is_connected(_on_director_session_ready):
			_facade_director.session_ready.connect(_on_director_session_ready)
		if _facade_director.is_session_ready():
			_on_director_session_ready()
			return
	preparation_progress.emit("正在准备场景…", RESOURCE_END)


## 开局前写入 GameDirector 配置（如 [code]spawn_opponent_base[/code]）。
## [br]须在 [code]add_child[/code] 触发 [method _boot_scene] 之前调用。
func configure_match(settings: Dictionary) -> void:
	_ensure_facade_children()
	if _facade_director == null:
		push_warning("GameMain.configure_match: GameDirector 未挂载")
		return
	for key in settings:
		_facade_director.set(key, settings[key])


## 切换玩法 HUD / 血条可见性（loading 遮罩期间应隐藏）。
func set_gameplay_ui_visible(visible: bool) -> void:
	_ensure_facade_children()
	if _facade_hud != null:
		_facade_hud.visible = visible
	if _facade_hpbar != null:
		_facade_hpbar.visible = visible


## 对局 session 是否已就绪。
func is_session_ready() -> bool:
	_ensure_facade_children()
	if _facade_director == null:
		return false
	return _facade_director.is_session_ready()


## 冒烟验收：已有 session 且单位层达到可玩门槛。
func has_playable_match() -> bool:
	_ensure_facade_children()
	if _facade_director == null or _facade_director.get_session() == null:
		return false
	if _facade_map == null:
		return false
	var layer := _facade_map.get_unit_layer()
	return layer != null and layer.get_child_count() >= 12

#endregion


#region ========== Facade 内部转发 ==========

func _ensure_facade_children() -> void:
	# 入树后优先用 @onready；入树前用 get_node（仅场景根允许）。
	if _facade_map == null:
		_facade_map = map_root if map_root != null else get_node_or_null("MapRoot") as MapLoader
	if _facade_director == null:
		_facade_director = game_director if game_director != null else get_node_or_null("GameDirector") as GameDirector
	if _facade_hud == null:
		_facade_hud = game_hud if game_hud != null else get_node_or_null("GameHud") as CanvasLayer
	if _facade_hpbar == null:
		_facade_hpbar = health_bar_manager if health_bar_manager != null else get_node_or_null("HealthBarManager") as CanvasLayer


func _on_map_load_progress(stage: String, progress: float) -> void:
	preparation_progress.emit(stage, lerpf(RESOURCE_END, MAP_END, clampf(progress, 0.0, 1.0)))


func _on_session_preparation_progress(stage: String, progress: float) -> void:
	preparation_progress.emit(
		stage,
		lerpf(MAP_END, PREPARATION_END, clampf(progress, 0.0, 1.0)),
	)


func _on_director_session_ready() -> void:
	set_gameplay_ui_visible(true)
	session_ready.emit()

#endregion


#region ========== 对内 DI ==========

## 按拓扑序给所有子节点注入依赖。
func _boot_scene() -> void:
	_setup_unit_selector(rts_camera.get_camera() if rts_camera else null, map_root)
	_setup_game_cursor(unit_selector)
	_setup_health_bar_manager(
		rts_camera.get_camera() if rts_camera else null,
		map_root,
	)
	_setup_rts_camera(map_root)
	_setup_game_hud(unit_selector, game_director, health_bar_manager)
	_setup_game_director(
		map_root,
		rts_camera,
		game_hud,
		unit_selector,
		game_cursor,
		health_bar_manager,
	)
	if game_director == null:
		push_error("GameMain: 缺少 GameDirector，无法启动")
		get_tree().quit(1)
		return
	if not game_director.start_match():
		push_error("GameMain: 启动请求被拒绝")
		get_tree().quit(1)
		return


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
	p_unit_selector: UnitSelector,
	p_game_cursor: Node,
	p_health_bar_manager: HealthBarManager,
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
	)

#endregion
