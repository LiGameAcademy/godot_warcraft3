extends RefCounted

const Index: GDScript = preload("res://app/asset_import_index.gd")
const TaskImport: GDScript = preload("res://app/game_asset_import.gd")
const DEFAULT_REQUEST: String = "res://config/development_asset_request.source"

## 随发布包携带的适配运行时；不调用 PATH 中的 Node 或 Godot。
func run_source(game_dir: String, request_path: String, cache_root: String, content_in_use: bool) -> Dictionary:
	if content_in_use:
		return _failure("content_in_use", "对局运行中不能导入资产")
	if OS.has_feature("editor") or OS.get_name() != "Windows":
		return _failure("source_platform_unsupported", "源资产入口目前仅验证 Windows 发布包")
	var bundle: String = OS.get_executable_path().get_base_dir().path_join("asset-import-runtime")
	var executable: String = bundle.path_join("node.exe")
	var entry: String = bundle.path_join("tools/asset-convert/src/runtime-source-import.mjs")
	if not FileAccess.file_exists(executable) or not FileAccess.file_exists(entry):
		return _failure("source_runtime_missing", "发布包缺少 asset-import-runtime")
	var root_path: String = ProjectSettings.globalize_path(cache_root)
	var source_root: String = ProjectSettings.globalize_path(game_dir).replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	var destination: String = root_path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	if destination == source_root or destination.begins_with(source_root + "/"):
		return _failure("source_cache_overlap", "缓存目录不能位于原版安装目录内")
	if DirAccess.make_dir_recursive_absolute(root_path) != OK:
		return _failure("source_cache_unwritable", "不能创建源导入缓存目录")
	var request: String = request_path
	if request.is_empty():
		request = root_path.path_join("source-request.json")
		var file: FileAccess = FileAccess.open(request, FileAccess.WRITE)
		if file == null:
			return _failure("source_request_unwritable", "不能写出导入清单")
		file.store_string(FileAccess.get_file_as_string(DEFAULT_REQUEST))
		file.close()
	var result_path: String = root_path.path_join("source-result-%s-%s.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	var output: Array = []
	var exit_code: int = OS.execute(executable, PackedStringArray([entry, game_dir, request, root_path, result_path]), output, true, false)
	var parser: JSON = JSON.new()
	if not FileAccess.file_exists(result_path) or parser.parse(FileAccess.get_file_as_string(result_path)) != OK or not parser.data is Dictionary:
		return _failure("source_process_failed", "适配器没有返回有效结果，退出码：%s；%s" % [exit_code, output])
	var prepared: Dictionary = parser.data
	if exit_code != 0 or not prepared.get("ok", false):
		return prepared if not prepared.get("ok", false) else _failure("source_process_failed", "适配器异常退出")
	var importer: RefCounted = TaskImport.new()
	var result: Dictionary = importer.run_manifest(str(prepared.manifest_path), content_in_use)
	if result.ok:
		var saved_results: Array[Dictionary] = []
		for entry_result: Dictionary in result.results:
			saved_results.append(entry_result)
		var request_resource: String = DEFAULT_REQUEST if request_path.is_empty() else request_path
		if Index.save(cache_root, saved_results, game_dir, prepared.get("content", {}), request_resource) != OK:
			result["diagnostics"] = [{"code": "index_save_failed", "message": "本次导入可用，但下次启动需重新导入索引"}]
	result["source"] = prepared
	return result

func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "results": [], "diagnostics": [{"code": code, "severity": "error", "message": message}]}
