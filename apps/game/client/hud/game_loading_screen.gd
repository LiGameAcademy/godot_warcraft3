class_name GameLoadingScreen
extends CanvasLayer

## 进局全屏 Loading（表现层）。
##
## 职责：
## [br]- 遮罩地图装配过程，避免玩家看到渐进刷出的 wc3mapMap / 单位 / 装饰。
## [br]- 订阅 [code]MapRoot.load_progress[/code] / [code]GameDirector.session_preparation_progress[/code]
## 推进进度条。
## [br]- 监听 [code]GameDirector.session_ready[/code]（或兜底 [code]MapRoot.map_loaded[/code]），
## 最短展示 [code]min_visible_sec[/code] 秒后淡出。
##
## ---- 依赖注入 ----
## [br]两种装配模式：
## [br]1. **legacy 4 参 setup**：自检 / 嵌入场景时用；同步注入 map_root / director / hud / hpbar。
## [br]2. **独立 peer 模式（v1.4 默认）**：本场景与 [code]game_main.tscn[/code] 并列，
## 由 [code]boot.gd[/code] 先 [code]add_child[/code] 到 root，再
## [code]begin_async[/code] 启动显示；主场景实例化后、入树前调用 bind_map / bind_director，
## 订阅地图及对局准备进度，避免漏掉 _ready 中发出的事件。
## [br]本节点不再 [code]get_node_or_null[/code] 反查节点树。
##
## ---- 生命周期 ----
## [br][code]_enter_tree[/code] 设置 [code]layer = 100[/code]（顶层 HUD 层）。
## [br][method setup] 同步连线信号 + 启动 UI 样式；
## [code]call_deferred("_try_finish_if_already_ready")[/code] 处理「调用 setup 时
## session 已就绪」的早退路径。
## [br][method _finish] 进入淡出流程；fade_out_sec ≤ 0 时直接 queue_free。

# 阶段权重表示工作进度，不是剩余时间估计。
const RESOURCE_END := 0.30
const MAP_END := 0.85
const PREPARATION_END := 0.99
var _display_progress := 0.0
var _progress_phase := 0


## 地图标题（覆盖自动推导的 map_root.map_dir 文件名）。
## [br]为空时使用 map_root.map_dir 的 base name，再退化为 "Loading"。
@export var map_title: String = ""

## 淡出动画时长（秒）。≤ 0 时直接 [code]queue_free[/code]，跳过 tween。
@export var fade_out_sec: float = 0.35

## 最短展示时长（秒）。
## [br]用于避免快速对局（如纯 selftest）中 loading 屏一闪而过；elapsed > min 时立刻 fade。
@export var min_visible_sec: float = 0.4

## 全屏根 Control（含 title / progress / panel）；fade-out 透明度动画作用于它。
@onready var _root: Control = $Root

## 标题 Label（unique_name_in_owner = true；显示 map_title 或 map_dir 推导名）。
@onready var _title: Label = %TitleLabel

## 阶段文案 Label（unique_name_in_owner = true；显示当前阶段字符串）。
@onready var _stage: Label = %StageLabel

## 进度条（unique_name_in_owner = true；0–100）。
@onready var _bar: ProgressBar = %ProgressBar

## 百分比 Label（unique_name_in_owner = true；显示 [code]"NN%"[/code]）。
@onready var _pct: Label = %PercentLabel

## 地图根（setup 注入）。
## [br]用于订阅 [code]load_progress[/code] 与回退 [code]map_loaded[/code] 信号。
var map_root: MapLoader

## 游戏总管（setup 注入）。
## [br]用于订阅 [code]session_preparation_progress[/code] 与 [code]session_ready[/code]。
var game_director: GameDirector

## 底栏 HUD（setup 注入；loading 期间被隐藏，session_ready 后恢复）。
var game_hud: CanvasLayer

## 血条层（setup 注入；loading 期间被隐藏，session_ready 后恢复）。
var health_bar_manager: CanvasLayer

## 是否已完成淡出流程（防止重复触发 fade / queue_free）。
var _finished: bool = false

## [method setup] 调用时刻（msec）；用于计算与 [code]min_visible_sec[/code] 的差值。
var _shown_msec: int = 0

## [method _wire_signals] 是否已经执行过一次（幂等保护）。
var _signals_wired: bool = false


## 节点进入树时立刻把 layer 设到 100（在 HUD 之上、tooltip 之下）。
func _enter_tree() -> void:
	layer = 100


## 由 [GameMain] 在子节点装配最末端调用。
##
## 同步完成：
## [br]- 把 4 个依赖写入对应字段。
## [br]- [code]process_mode = PROCESS_MODE_ALWAYS[/code]（loading 期间即使游戏暂停也继续 tick）。
## [br]- 应用样式、设标题、显示 "正在进入战场…" 初始进度。
## [br]- 隐藏 game_hud / health_bar_manager。
## [br]- 调 [method _wire_signals] 连线（幂等）。
## [br]- [code]call_deferred("_try_finish_if_already_ready")[/code] 处理 setup 时 session 已就绪的早退路径。
##
## [param p_map_root] 地图根；用于订阅 [code]load_progress[/code] 与回退路径。
## [br]为 null 时本屏只能依赖 game_director；两者都为 null 则永远不结束（应避免）。
## [param p_game_director] 游戏总管；优先订阅 [code]session_preparation_progress[/code]
## 与 [code]session_ready[/code]。
## [param p_game_hud] 底栏 HUD；loading 期间被隐藏。
## [param p_health_bar_manager] 血条层；loading 期间被隐藏。
func setup(
	p_map_root: MapLoader,
	p_game_director: GameDirector,
	p_game_hud: CanvasLayer,
	p_health_bar_manager: CanvasLayer
) -> void:
	map_root = p_map_root
	game_director = p_game_director
	game_hud = p_game_hud
	health_bar_manager = p_health_bar_manager
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shown_msec = Time.get_ticks_msec()
	_apply_styles()
	_set_title_text()
	_set_progress("正在进入战场…", 0.0)
	_hide_game_ui(true)
	_wire_signals()
	call_deferred("_try_finish_if_already_ready")


## 独立 peer 模式入口（v1.4）：由 [code]boot.gd[/code] 在 add_child 后立即调用。
##
## 同步完成：
## [br]- 设 process_mode 为 ALWAYS。
## [br]- 应用样式、设标题（[param p_title] 非空时优先；否则回退 "Loading"）。
## [br]- 进度推到 0、文案为「正在加载资源…」。
## [br]- 不订阅任何信号（game_main 尚未加载）。
##
## 后续步骤由 [code]boot.gd[/code] 调用 [method set_async_progress] 推进进度，
## 在 [code]game_main.tscn[/code] instantiate 之后调 [method bind_director] 补订
## [code]session_ready[/code]。
##
## [param p_title] 地图标题（如 "Echo Isles"）；为空时使用 "Loading"。
func begin_async(p_title: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shown_msec = Time.get_ticks_msec()
	_apply_styles()
	if p_title.strip_edges() != "":
		map_title = p_title.strip_edges()
	_set_title_text()
	_set_progress("正在加载资源…", 0.0)


## 独立 peer 模式：每帧由 [code]boot.gd[/code] 把 [code]ResourceLoader.load_threaded_get_status[/code]
## 返回的 0.0–1.0 进度推到这里（保留前 30% 给资源加载，避免与 session 阶段重叠）。
##
## [param p_progress] 0.0–1.0；超出范围被 clampf。
func set_async_progress(p_progress: float) -> void:
	if _finished or _progress_phase > 0:
		return
	_set_progress("正在加载资源…", clampf(p_progress, 0.0, 1.0) * RESOURCE_END)


## 在主场景入树之前连接，避免漏掉 MapRoot._ready 发出的早期进度。
func bind_map(p_map: MapLoader) -> void:
	map_root = p_map
	if map_root != null and not map_root.load_progress.is_connected(_on_map_progress):
		map_root.load_progress.connect(_on_map_progress)


func _on_map_progress(stage: String, progress: float) -> void:
	if _finished or _progress_phase > 1:
		return
	_progress_phase = 1
	_set_progress(stage, lerpf(RESOURCE_END, MAP_END, clampf(progress, 0.0, 1.0)))


## 独立 peer 模式：game_main 实例化后、add_child 之前连接；也兼容已就绪的对象。
##
## 缓存 director / game_hud / health_bar_manager 引用，
## 并订阅 [code]session_preparation_progress[/code] / [code]session_ready[/code]。
## 当 director 已经 is_session_ready() 时立即走 finish。
##
## [param p_director] GameDirector（或 duck-type 兼容 stub：需有
## session_preparation_progress / session_ready 信号与 is_session_ready()）。
## [param p_hud] game_main.tscn 的 %GameHud（用于 loading 期间隐藏）。
## [param p_health_bar] game_main.tscn 的 %HealthBarManager（用于 loading 期间隐藏）。
func bind_director(
	p_director: Node,
	p_hud: CanvasLayer,
	p_health_bar: CanvasLayer
) -> void:
	if p_director == null:
		return
	game_director = p_director as GameDirector
	game_hud = p_hud
	health_bar_manager = p_health_bar
	_hide_game_ui(true)
	# 不重复连信号；bind_director 是 boot 阶段的唯一补订点。
	if p_director.has_signal("session_preparation_progress") \
			and not p_director.is_connected("session_preparation_progress", _on_load_progress):
		p_director.connect("session_preparation_progress", _on_load_progress)
	if p_director.has_signal("session_ready") \
			and not p_director.is_connected("session_ready", _on_session_ready):
		p_director.connect("session_ready", _on_session_ready)
	if p_director.has_method("is_session_ready") and p_director.is_session_ready():
		_on_session_ready()
		return
	# 尚未收到阶段事件时仅标记场景资源已加载，不虚构地图完成进度。
	if _progress_phase == 0:
		_set_progress("正在准备场景…", RESOURCE_END)


## 连线订阅（幂等：重复调用不会重复挂信号）。
## [br]订阅顺序：
## [br]- [code]map_root.load_progress[/code] → [method _on_map_progress]（优先）。
## [br]- 若 game_director 非空：[code]session_preparation_progress[/code] → [method _on_load_progress]，
## [code]session_ready[/code] → [method _on_session_ready]。
## [br]- 若 game_director 为空但 map_root 非空：兜底订阅 [code]map_root.map_loaded[/code] →
## [method _on_map_loaded_fallback]。
func _wire_signals() -> void:
	if map_root != null and not map_root.load_progress.is_connected(_on_map_progress):
		map_root.load_progress.connect(_on_map_progress)
	if game_director != null:
		if not game_director.session_preparation_progress.is_connected(_on_load_progress):
			game_director.session_preparation_progress.connect(_on_load_progress)
		if not game_director.session_ready.is_connected(_on_session_ready):
			game_director.session_ready.connect(_on_session_ready)
	elif map_root != null and not map_root.map_loaded.is_connected(_on_map_loaded_fallback):
		map_root.map_loaded.connect(_on_map_loaded_fallback)
	_signals_wired = true


## 兜底：若 setup 调用时 session 已经就绪（selftest / 快速重启），立即触发 finish 流程。
func _try_finish_if_already_ready() -> void:
	if _finished:
		return
	_hide_game_ui(true)
	if game_director != null and game_director.is_session_ready():
		_on_session_ready()
		return
	if game_director == null and map_root != null and map_root.is_map_ready():
		_on_map_loaded_fallback()


## 对局准备局部进度（0–1）映射到总进度 85%–99%。
## [br][param stage] 阶段文案（"正在加载资源…"、"准备单位显示…" 等）。
## [br][param progress] 进度 0.0–1.0（超出范围会被 clampf）。
func _on_load_progress(stage: String, progress: float) -> void:
	if _finished:
		return
	_progress_phase = 2
	_set_progress(stage, lerpf(MAP_END, PREPARATION_END, clampf(progress, 0.0, 1.0)))


## 兜底回调（game_director 为空时，仅 map_loaded 触发）。
## [br]把进度推至 0.98 进入 finish。
func _on_map_loaded_fallback() -> void:
	_set_progress("准备开局…", 0.98)
	_finish()


## session_ready 信号回调：把进度推到 1.0 并进入 finish 流程。
func _on_session_ready() -> void:
	_set_progress("就绪", 1.0)
	_finish()


## 完成入口（幂等）。
## [br]计算与 [code]min_visible_sec[/code] 的差值，必要时 delay 一下再 fade，
## 避免 loading 屏一闪而过。
func _finish() -> void:
	if _finished:
		return
	_finished = true
	var elapsed_sec := (Time.get_ticks_msec() - _shown_msec) / 1000.0
	var wait := maxf(0.0, min_visible_sec - elapsed_sec)
	if wait > 0.0:
		preload("res://addons/rts_foundation/infra/scene_delay.gd").create_timer(self, wait).timeout.connect(_begin_fade)
	else:
		_begin_fade()


## 开始淡出动画（恢复 game_hud / health_bar_manager，tween modulate.a → 0，再 queue_free）。
func _begin_fade() -> void:
	_hide_game_ui(false)
	if fade_out_sec <= 0.0 or _root == null:
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, fade_out_sec)
	# 卸载时 Tween 会被取消，不保证发出 finished；避免协程持有它等待永远不会到来的信号。
	tw.tween_callback(queue_free)


## 切换 HUD / 血条可见性（loading 期间应被隐藏，session_ready 后恢复）。
## [br][param should_hide] true 表示隐藏；false 表示恢复可见。
func _hide_game_ui(should_hide: bool) -> void:
	if game_hud != null:
		game_hud.visible = not should_hide
	if health_bar_manager != null:
		health_bar_manager.visible = not should_hide


## 更新进度条 / 阶段文案 / 百分比 Label。
## [br][param stage] 阶段文案。
## [br][param progress] 0.0–1.0；超出范围会被 clampf 到 [0, 1]。
func _set_progress(stage: String, progress: float) -> void:
	_ensure_ui_refs()
	var p := maxf(_display_progress, clampf(progress, 0.0, 1.0))
	_display_progress = p
	if _stage:
		_stage.text = stage
	if _bar:
		_bar.value = p * 100.0
	if _pct:
		_pct.text = "%d%%" % int(round(p * 100.0))


## 写入标题文本（按 [code]map_title[/code] → map_root.map_dir → "Loading" 顺序回退）。
func _set_title_text() -> void:
	_ensure_ui_refs()
	if _title == null:
		return
	var title := map_title.strip_edges()
	if title.is_empty() and map_root != null:
		title = _pretty_map_name(map_root.map_dir)
	if title.is_empty():
		title = "Loading"
	_title.text = title


## 从目录路径推导显示标题（去扩展名 + capitalize）。
## [br][param dir] 目录路径（通常为 map_root.map_dir）。
## [br][return] 推导出的标题字符串；目录为空时回退 "Battlefield"。
func _pretty_map_name(dir: String) -> String:
	var base := dir.get_file()
	if base.is_empty():
		base = dir.trim_suffix("/").get_file()
	if base.is_empty():
		return "Battlefield"
	return base.capitalize()


## 懒解析 UI 引用（@onready / %UniqueName 在独立 peer 实例化时偶发未就绪）。
func _ensure_ui_refs() -> void:
	if _root == null:
		_root = get_node_or_null("Root") as Control
	if _title == null:
		_title = get_node_or_null("Root/Center/Panel/VBox/TitleLabel") as Label
	if _stage == null:
		_stage = get_node_or_null("Root/Center/Panel/VBox/StageLabel") as Label
	if _bar == null:
		_bar = get_node_or_null("Root/Center/Panel/VBox/BarRow/ProgressBar") as ProgressBar
	if _pct == null:
		_pct = get_node_or_null("Root/Center/Panel/VBox/BarRow/PercentLabel") as Label


## 应用样式（panel 边框 + 进度条 fill/background 颜色）。
## [br]每次 setup / begin_async 调用时执行一次（运行期样式覆盖不会持久化）。
func _apply_styles() -> void:
	_ensure_ui_refs()
	var panel := get_node_or_null("Root/Center/Panel") as PanelContainer
	if panel != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.1, 0.96)
		sb.border_color = Color(0.62, 0.48, 0.2, 0.95)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		sb.content_margin_top = 22
		sb.content_margin_bottom = 22
		panel.add_theme_stylebox_override("panel", sb)
	if _bar != null:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.72, 0.55, 0.22, 1.0)
		fill.set_corner_radius_all(3)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.12, 0.13, 0.16, 1.0)
		bg.set_corner_radius_all(3)
		_bar.add_theme_stylebox_override("fill", fill)
		_bar.add_theme_stylebox_override("background", bg)
