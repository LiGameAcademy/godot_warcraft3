extends RefCounted

signal progress_changed(stage: String, completed: int, total: int)
signal finished(result: Dictionary)

const TaskImport: GDScript = preload("res://app/game_asset_import.gd")
const Index: GDScript = preload("res://app/asset_import_index.gd")

var active: bool = false
var cache_root: String = "user://wc3-cache/source-import"
var _pid: int = -1
var _phase: String = ""
var _result_path: String = ""
var _progress_path: String = ""
var _tasks: Array[String] = []
var _results: Array[Dictionary] = []
var _game_dir: String = ""
var _session: String = ""
var _progress_text: String = ""
var _cancelling: bool = false

func start(game_dir: String, requested_cache: String = "user://wc3-cache/source-import") -> void:
	if active:
		return
	cache_root = ProjectSettings.globalize_path(requested_cache)
	_game_dir = game_dir
	var source_root: String = ProjectSettings.globalize_path(game_dir).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var destination: String = cache_root.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if destination == source_root or destination.begins_with(source_root + "/"):
		_fail("source_cache_overlap", "缓存目录不能位于原版安装目录内")
		return
	_cancelling = false
	_tasks.clear()
	_results.clear()
	if AssetProvider.runtime_content_sealed:
		_fail("content_in_use", "对局运行中不能导入资产")
		return
	var bundle: String = OS.get_executable_path().get_base_dir().path_join("asset-import-runtime")
	if OS.has_feature("editor") or OS.get_name() != "Windows" or not FileAccess.file_exists(bundle.path_join("node.exe")):
		_fail("source_runtime_missing", "请使用包含 asset-import-runtime 的 Windows 发布包")
		return
	_session = cache_root.path_join("sessions/%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(_session) != OK:
		_fail("source_cache_unwritable", "无法创建导入目录")
		return
	var request: String = _session.path_join("request.json")
	if not _write(request, FileAccess.get_file_as_string("res://config/asset_import_samples.source")):
		_fail("source_request_unwritable", "无法写入导入请求")
		return
	_progress_path = _session.path_join("progress.json")
	_result_path = _session.path_join("source.json")
	_phase = "source"
	active = true
	_progress_text = ""
	progress_changed.emit("检查原版资源目录", 0, 0)
	_pid = OS.create_process(bundle.path_join("node.exe"), PackedStringArray([bundle.path_join("tools/asset-convert/src/runtime-source-import.mjs"), game_dir, request, cache_root, _result_path, _progress_path]), false)
	if _pid < 0:
		_fail("source_process_failed", "不能启动源解析进程")

func poll() -> void:
	if not active:
		return
	if _phase == "source":
		var snapshots: PackedStringArray = DirAccess.get_files_at(_session)
		snapshots.sort()
		var latest: String = ""
		for filename: String in snapshots:
			if filename.begins_with("progress.json.") and filename.ends_with(".json"):
				latest = _session.path_join(filename)
		var progress: Dictionary = _read(latest)
		var text: String = JSON.stringify(progress)
		if not progress.is_empty() and text != _progress_text:
			_progress_text = text
			progress_changed.emit(str(progress.stage), int(progress.completed), int(progress.total))
	if _pid > 0 and OS.is_process_running(_pid):
		return
	var exit_code: int = OS.get_process_exit_code(_pid)
	_pid = -1
	if _cancelling:
		_complete({"ok": false, "cancelled": true, "diagnostics": [{"code": "cancelled", "message": "已取消；完成的场景缓存保留，下次可重试"}]})
		return
	var response: Dictionary = _read(_result_path)
	if exit_code != 0 or not response.get("ok", false):
		_complete(response if not response.is_empty() and not response.get("ok", false) else {"ok": false, "diagnostics": [{"code": "process_failed", "message": "导入子进程异常退出，请重试"}]})
		return
	if _phase == "source":
		var manifest: Dictionary = _read(str(response.get("manifest_path", "")))
		for task: Variant in manifest.get("tasks", []):
			if not task is String:
				_fail("manifest_invalid", "任务清单无效")
				return
			_tasks.append(task)
		if _tasks.is_empty():
			_fail("manifest_invalid", "任务清单为空")
			return
		_phase = "compile"
	else:
		_results.append(response)
	if _results.size() < _tasks.size():
		_start_worker()
		return
	progress_changed.emit("校验并安装缓存索引", _tasks.size(), _tasks.size())
	var importer: RefCounted = TaskImport.new()
	var result: Dictionary = importer.install_results(_results)
	if result.ok and Index.save(cache_root, _results, _game_dir) != OK:
		result["diagnostics"] = [{"code": "index_save_failed", "message": "本次导入可用，但下次启动需重新导入索引"}]
	_complete(result)

func cancel() -> void:
	if not active or _cancelling:
		return
	_cancelling = true
	progress_changed.emit("正在取消导入", 0, 0)
	if _pid > 0 and OS.is_process_running(_pid):
		var error: Error = OS.kill(_pid)
		if error != OK:
			_cancelling = false
			progress_changed.emit("取消失败，请再次尝试", 0, 0)

func _start_worker() -> void:
	_result_path = _session.path_join("worker-%s.json" % _results.size())
	progress_changed.emit("编译场景缓存", _results.size(), _tasks.size())
	_pid = OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--", "--asset-worker-task", _tasks[_results.size()], "--asset-worker-result", _result_path]), false)
	if _pid < 0:
		_fail("worker_start_failed", "不能启动场景编译进程")

func _complete(result: Dictionary) -> void:
	active = false
	finished.emit(result)

func _fail(code: String, message: String) -> void:
	_complete({"ok": false, "diagnostics": [{"code": code, "message": message}]})

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {}
	return parser.data

func _write(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true
