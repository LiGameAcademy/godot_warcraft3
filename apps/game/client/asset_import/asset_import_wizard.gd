extends Control

signal ready_to_play()

const Guard: GDScript = preload("res://app/asset_import_guard.gd")
const Job: GDScript = preload("res://app/asset_import_job.gd")
const Index: GDScript = preload("res://app/asset_import_index.gd")
const TaskImport: GDScript = preload("res://app/game_asset_import.gd")

@export var request_resource: String = "res://config/development_asset_request.source"
@export var auto_resume: bool = true
@export var cache_root: String = "user://wc3-cache/source-import"
@onready var directory: LineEdit = %Directory
@onready var browse: Button = %Browse
@onready var start_button: Button = %Start
@onready var cancel_button: Button = %Cancel
@onready var play_button: Button = %Play
@onready var status: Label = %Status
@onready var progress: ProgressBar = %Progress
@onready var dialog: FileDialog = %DirectoryDialog
var _cache_thread: Thread
var _cache_importer: RefCounted
var checking_cache: bool = false
var job: RefCounted

func _ready() -> void:
	job = Job.new()
	job.request_resource = request_resource
	job.progress_changed.connect(_on_progress)
	job.finished.connect(_on_finished)
	browse.pressed.connect(func() -> void: dialog.popup_centered_ratio(0.7))
	dialog.dir_selected.connect(func(path: String) -> void: directory.text = path)
	start_button.pressed.connect(_start_import)
	cancel_button.pressed.connect(func() -> void: job.cancel())
	play_button.pressed.connect(func() -> void: ready_to_play.emit())
	if auto_resume:
		if Guard.register_reader(cache_root) != OK:
			status.text = "缓存正被其他进程使用，请关闭后重启。"
			start_button.disabled = true
			return
		checking_cache = true
		status.text = "正在后台校验资源缓存…"
		start_button.disabled = true
		_cache_importer = TaskImport.new()
		_cache_thread = Thread.new()
		var error: Error = _cache_thread.start(_cache_importer.validate_cache.bind(cache_root, request_resource))
		if error == OK:
			return
		checking_cache = false
		start_button.disabled = false
	status.text = "请选择经典《魔兽争霸3》安装目录（包含 MPQ 文件）。"

func _process(_delta: float) -> void:
	if checking_cache and _cache_thread != null and not _cache_thread.is_alive():
		var valid: bool = bool(_cache_thread.wait_to_finish())
		checking_cache = false
		_cache_thread = null
		if valid:
			var installed: Dictionary = _cache_importer.restore_validated_cache()
			if installed.ok:
				_resume.call_deferred()
				return
		status.text = "缓存缺失或损坏，请选择原版目录重新导入。"
		start_button.disabled = false
		_cache_importer = null
	if job != null:
		job.poll()

func _exit_tree() -> void:
	if _cache_thread != null and _cache_thread.is_started():
		_cache_thread.wait_to_finish()
	if job != null:
		job.cancel()

func _start_import() -> void:
	if checking_cache:
		return
	if directory.text.strip_edges().is_empty():
		status.text = "请先选择原版安装目录。"
		return
	start_button.disabled = true
	browse.disabled = true
	directory.editable = false
	cancel_button.disabled = false
	play_button.disabled = true
	job.start(directory.text.strip_edges(), cache_root)

func _on_progress(stage: String, completed: int, total: int) -> void:
	status.text = stage + (" %s / %s" % [completed, total] if total > 0 else "…")
	progress.indeterminate = total <= 0
	progress.max_value = maxi(total, 1)
	progress.value = completed

func _on_finished(result: Dictionary) -> void:
	cancel_button.disabled = true
	progress.indeterminate = false
	if result.get("ok", false):
		if Guard.register_reader(cache_root) != OK:
			status.text = "不能保留缓存使用标记，请重启后重试。"
			return
		status.text = "导入完成，可以继续。已准备所选批次的游戏资源。"
		if result.has("diagnostics"):
			status.text += " " + str(result.diagnostics[0].get("message", ""))
		if not result.get("content", {}).get("coverage", {}).get("complete", true):
			status.text += " 存在未解析引用，详情见资源缓存中的 coverage.json。"
		play_button.disabled = false
		progress.value = progress.max_value
	else:
		status.text = "导入失败，请重试。"
		for diagnostic: Dictionary in result.get("diagnostics", []):
			if diagnostic.get("severity", "error") == "error":
				status.text = str(diagnostic.get("message", diagnostic.get("code", status.text)))
				if result.has("asset_id"):
					status.text += "：" + str(result.asset_id)
				break
		start_button.disabled = false
		browse.disabled = false
		directory.editable = true

func _resume() -> void:
	ready_to_play.emit()
