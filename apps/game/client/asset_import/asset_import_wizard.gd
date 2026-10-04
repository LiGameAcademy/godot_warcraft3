extends Control

signal ready_to_play()

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
	var record: Dictionary = Index.latest(cache_root, request_resource)
	directory.text = str(record.get("game_dir", ""))
	if auto_resume and not record.is_empty():
		var importer: RefCounted = TaskImport.new()
		var results: Array[Dictionary] = []
		for result: Dictionary in record.results:
			results.append(result)
		var installed: Dictionary = importer.install_results(results, record.get("content", {}))
		if installed.ok:
			call_deferred("_resume")
			return
	status.text = "请选择经典《魔兽争霸3》安装目录（包含 MPQ 文件）。"

func _process(_delta: float) -> void:
	if job != null:
		job.poll()

func _exit_tree() -> void:
	if job != null:
		job.cancel()

func _start_import() -> void:
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
