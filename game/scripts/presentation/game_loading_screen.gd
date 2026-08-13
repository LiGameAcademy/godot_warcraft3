class_name GameLoadingScreen
extends CanvasLayer

## 进局全屏 Loading（表现层）。遮罩地图装配过程，session_ready 后淡出。

@export var map_root: MapLoader
@export var game_director: GameDirector
@export var game_hud: CanvasLayer
@export var health_bar_manager: CanvasLayer
@export var map_title: String = ""
@export var fade_out_sec: float = 0.35
@export var min_visible_sec: float = 0.4

@onready var _root: Control = $Root
@onready var _title: Label = %TitleLabel
@onready var _stage: Label = %StageLabel
@onready var _bar: ProgressBar = %ProgressBar
@onready var _pct: Label = %PercentLabel

var _finished: bool = false
var _shown_msec: int = 0


func _enter_tree() -> void:
	layer = 100


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shown_msec = Time.get_ticks_msec()
	_resolve_refs()
	_apply_styles()
	_set_title_text()
	_set_progress("正在进入战场…", 0.0)
	_hide_game_ui(true)
	_wire_signals()
	call_deferred("_try_finish_if_already_ready")


func _resolve_refs() -> void:
	var parent_n := get_parent()
	if map_root == null and parent_n != null:
		map_root = parent_n.get_node_or_null("MapRoot") as MapLoader
	if game_director == null and parent_n != null:
		game_director = parent_n.get_node_or_null("GameDirector") as GameDirector
	if game_hud == null and parent_n != null:
		game_hud = parent_n.get_node_or_null("GameHud") as CanvasLayer
	if health_bar_manager == null and parent_n != null:
		health_bar_manager = parent_n.get_node_or_null("HealthBarManager") as CanvasLayer


func _wire_signals() -> void:
	if map_root != null and not map_root.load_progress.is_connected(_on_load_progress):
		map_root.load_progress.connect(_on_load_progress)
	if game_director != null:
		if not game_director.session_ready.is_connected(_on_session_ready):
			game_director.session_ready.connect(_on_session_ready)
	elif map_root != null and not map_root.map_loaded.is_connected(_on_map_loaded_fallback):
		map_root.map_loaded.connect(_on_map_loaded_fallback)


func _try_finish_if_already_ready() -> void:
	if _finished:
		return
	_hide_game_ui(true)
	if game_director != null and game_director.is_session_ready():
		_on_session_ready()
		return
	if game_director == null and map_root != null and map_root.is_map_ready():
		_on_map_loaded_fallback()


func _on_load_progress(stage: String, progress: float) -> void:
	if _finished:
		return
	_set_progress(stage, progress)


func _on_map_loaded_fallback() -> void:
	_set_progress("准备开局…", 0.98)
	_finish()


func _on_session_ready() -> void:
	_set_progress("就绪", 1.0)
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var elapsed_sec := (Time.get_ticks_msec() - _shown_msec) / 1000.0
	var wait := maxf(0.0, min_visible_sec - elapsed_sec)
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	_hide_game_ui(false)
	if fade_out_sec <= 0.0 or _root == null:
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, fade_out_sec)
	await tw.finished
	queue_free()


func _hide_game_ui(should_hide: bool) -> void:
	if game_hud != null:
		game_hud.visible = not should_hide
	if health_bar_manager != null:
		health_bar_manager.visible = not should_hide


func _set_title_text() -> void:
	if _title == null:
		return
	var title := map_title.strip_edges()
	if title.is_empty() and map_root != null:
		title = _pretty_map_name(map_root.map_dir)
	if title.is_empty():
		title = "Loading"
	_title.text = title


func _pretty_map_name(dir: String) -> String:
	var base := dir.get_file()
	if base.is_empty():
		base = dir.trim_suffix("/").get_file()
	if base.is_empty():
		return "Battlefield"
	return base.capitalize()


func _set_progress(stage: String, progress: float) -> void:
	var p := clampf(progress, 0.0, 1.0)
	if _stage:
		_stage.text = stage
	if _bar:
		_bar.value = p * 100.0
	if _pct:
		_pct.text = "%d%%" % int(round(p * 100.0))


func _apply_styles() -> void:
	var panel := $Root/Center/Panel as PanelContainer
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
