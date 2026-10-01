class_name GameLoadingScreen
extends CanvasLayer

## 进局全屏 Loading（纯表现 View）。
##
## 职责仅限：
## [br]- 显示标题 / 阶段文案 / 进度条。
## [br]- 最短展示 [code]min_visible_sec[/code] 后淡出并 [code]queue_free[/code]。
##
## **不持有** MapLoader / GameDirector / GameHud / HealthBarManager 引用。
## 进度与完成由编排方（[code]boot.gd[/code]）通过 [method begin] /
## [method set_progress] / [method finish] **推送**进来。
## 信号订阅、玩法 UI 显隐均由编排方负责。
##
## 设计：docs/design/game/SCENE_BOOTSTRAP.md §10。

## 地图标题；空则显示 "Loading"。
@export var map_title: String = ""

## 淡出动画时长（秒）。≤ 0 时直接 [code]queue_free[/code]，跳过 tween。
@export var fade_out_sec: float = 0.35

## 最短展示时长（秒）。避免快速对局中 loading 一闪而过。
@export var min_visible_sec: float = 0.4

## 全屏根 Control；fade-out 透明度动画作用于它。
@onready var _root: Control = $Root

## 标题 Label。
@onready var _title: Label = %TitleLabel

## 阶段文案 Label。
@onready var _stage: Label = %StageLabel

## 进度条（0–100）。
@onready var _bar: ProgressBar = %ProgressBar

## 百分比 Label。
@onready var _pct: Label = %PercentLabel

## 当前显示进度（0..1）；[method set_progress] 只升不降。
var _display_progress: float = 0.0

## 是否已进入 finish（防止重复淡出）。
var _finished: bool = false

## [method begin] 调用时刻（msec）；用于最短展示计时。
var _shown_msec: int = 0


## 节点进入树时立刻把 layer 设到 100（在 HUD 之上）。
func _enter_tree() -> void:
	layer = 100


## 启动显示。由编排方在 add_child 后立刻调用。
## [br][param p_title] 地图标题；空则显示 "Loading"。
func begin(p_title: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shown_msec = Time.get_ticks_msec()
	_finished = false
	_display_progress = 0.0
	if p_title.strip_edges() != "":
		map_title = p_title.strip_edges()
	_apply_title()
	set_progress("正在加载资源…", 0.0)


## 推送绝对进度（0..1）。只升不降；超出范围会被 clampf。
## [br][param stage] 阶段文案。
## [br][param progress] 总进度 0.0–1.0（分段映射由编排方完成）。
func set_progress(stage: String, progress: float) -> void:
	if _finished:
		return
	var p := maxf(_display_progress, clampf(progress, 0.0, 1.0))
	_display_progress = p
	if _stage:
		_stage.text = stage
	if _bar:
		_bar.value = p * 100.0
	if _pct:
		_pct.text = "%d%%" % int(round(p * 100.0))


## 完成入口（幂等）。满足最短展示后淡出并 queue_free。
func finish() -> void:
	if _finished:
		return
	set_progress("就绪", 1.0)
	_finished = true
	var elapsed_sec := (Time.get_ticks_msec() - _shown_msec) / 1000.0
	var wait := maxf(0.0, min_visible_sec - elapsed_sec)
	if wait > 0.0:
		preload("res://addons/rts_foundation/infra/scene_delay.gd").create_timer(self, wait).timeout.connect(_begin_fade)
	else:
		_begin_fade()


## 开始淡出动画（tween modulate.a → 0，再 queue_free）。
func _begin_fade() -> void:
	if fade_out_sec <= 0.0 or _root == null:
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, fade_out_sec)
	# 卸载时 Tween 会被取消，不保证发出 finished；用 callback 而不是 await。
	tw.tween_callback(queue_free)


## 写入标题文本。
func _apply_title() -> void:
	if _title == null:
		return
	var title := map_title.strip_edges()
	if title.is_empty():
		title = "Loading"
	_title.text = title
