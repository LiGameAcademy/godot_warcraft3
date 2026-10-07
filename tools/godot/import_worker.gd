extends SceneTree

const SceneCompiler: GDScript = preload("import_scene_compiler.gd")

## 开发用 CLI；实际编译复用可导出的核心。
var _task_path: String = ""
var _result_path: String = ""


func _initialize() -> void:
	_parse_args()
	call_deferred("_run")


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		var arg: String = str(args[i])
		if arg == "--task" and i + 1 < args.size():
			i += 1
			_task_path = str(args[i])
		elif arg.begins_with("--task="):
			_task_path = arg.substr("--task=".length())
		elif arg == "--result" and i + 1 < args.size():
			i += 1
			_result_path = str(args[i])
		elif arg.begins_with("--result="):
			_result_path = arg.substr("--result=".length())
		i += 1
	if _result_path.is_empty() and not _task_path.is_empty():
		_result_path = _task_path.get_basename() + ".worker-result.json"


func _run() -> void:
	var compiler: RefCounted = SceneCompiler.new()
	var response: Dictionary = compiler.compile_task(_task_path)
	_finish(response.result, int(response.exit_code))


func _finish(result: Dictionary, exit_code: int) -> void:
	if not _result_path.is_empty():
		var result_dir: String = _result_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(result_dir)
		var file: FileAccess = FileAccess.open(_result_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(result, "  ") + "\n")
			file.close()
		else:
			push_error("import_worker: 无法写入结果文件")
			exit_code = 2
	quit(exit_code)
