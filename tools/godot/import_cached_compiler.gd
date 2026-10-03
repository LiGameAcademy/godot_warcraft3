extends RefCounted

const Compiler: GDScript = preload("import_scene_compiler.gd")
const Signature: GDScript = preload("import_cache_signature.gd")

## 独立版本 + 提交记录：目标不存在的 rename 才是发布点。
## output_scene 是逻辑缓存槽，消费者必须使用结果里的实际场景路径。
func compile_task(task_path: String) -> Dictionary:
	var prepared: Dictionary = Signature.prepare(task_path)
	if prepared.get("delegate", false):
		return Compiler.new().compile_task(task_path)
	if not prepared.ok:
		return _failure(str(prepared.get("asset_id", "")), str(prepared.code), str(prepared.message), 2)
	var task: Dictionary = prepared.task
	var output: String = prepared.output
	if output.get_extension() != "scn":
		return _failure(str(task.asset_id), "cache_output_format", "缓存输出必须为 .scn", 2)
	var directory: String = output + ".cache"
	var lookup: Dictionary = _lookup(directory, str(prepared.signature), task)
	if lookup.get("hit", false):
		return {"result": lookup.result, "exit_code": 0}
	var mkdir: Error = DirAccess.make_dir_recursive_absolute(directory)
	if mkdir != OK:
		return _failure(str(task.asset_id), "cache_directory_failed", "无法创建缓存目录", 1)
	var token: String = _generation(directory)
	var committed_scene: String = directory.path_join(token + ".scn")
	var committed_record: String = directory.path_join(token + ".json")
	var candidate: String = directory.path_join(token + ".pending.scn")
	var stage_task: String = candidate + ".task.json"
	var stage_record: String = candidate + ".cache.json"
	var staged: Dictionary = task.duplicate(true)
	staged.ir_path = prepared.ir_path
	staged.geometry_path = prepared.geometry
	staged.output_scene = candidate
	if not _write_json(stage_task, staged):
		_cleanup([stage_task])
		return _failure(str(task.asset_id), "cache_task_write_failed", "无法写入暂存任务", 1)
	var response: Dictionary = Compiler.new().compile_task(stage_task)
	_cleanup([stage_task])
	if int(response.exit_code) != 0:
		_cleanup([candidate])
		return response
	var result: Dictionary = response.result
	result.output_scene = ProjectSettings.globalize_path(committed_scene)
	result["cache"] = {"status": "rebuilt", "reason": lookup.reason, "signature": prepared.signature}
	var record: Dictionary = {"cache_version": Signature.CACHE_VERSION, "signature": prepared.signature,
		"output_sha256": result.output_sha256, "inputs": prepared.inputs, "result": result}
	if not _write_json(stage_record, record):
		_cleanup([candidate, stage_record])
		return _failure(str(task.asset_id), "cache_record_write_failed", "无法写入暂存缓存记录", 1)
	# A changed input during compilation must not be published with a stale key.
	var current: Dictionary = Signature.prepare(task_path)
	if not current.get("ok", false) or current.signature != prepared.signature:
		_cleanup([candidate, stage_record])
		return _failure(str(task.asset_id), "cache_inputs_changed", "编译期间输入发生变化，请重试", 1)
	var publish: Error = _publish(candidate, committed_scene)
	if publish != OK:
		_cleanup([candidate, stage_record])
		return _failure(str(task.asset_id), "cache_scene_replace_failed", "场景原子替换失败，旧缓存保留", 1)
	publish = _publish(stage_record, committed_record)
	if publish != OK:
		_cleanup([stage_record, committed_scene])
		return _failure(str(task.asset_id), "cache_record_replace_failed", "提交记录发布失败，旧缓存保留", 1)
	return response

func _lookup(directory: String, signature: String, task: Dictionary) -> Dictionary:
	if not DirAccess.dir_exists_absolute(directory):
		return {"hit": false, "reason": "scene_missing"}
	var files: PackedStringArray = DirAccess.get_files_at(directory)
	files.sort()
	files.reverse()
	var record_path: String = ""
	for file: String in files:
		if file.ends_with(".json") and not file.contains(".pending."):
			record_path = directory.path_join(file)
			break
	if record_path.is_empty():
		return {"hit": false, "reason": "record_missing"}
	var output: String = record_path.get_basename() + ".scn"
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(record_path)) != OK:
		return {"hit": false, "reason": "record_invalid"}
	var record: Variant = parser.data
	if not record is Dictionary or record.get("cache_version") != Signature.CACHE_VERSION or not record.get("result") is Dictionary:
		return {"hit": false, "reason": "record_invalid"}
	if str(record.get("signature", "")) != signature:
		return {"hit": false, "reason": "signature_changed"}
	if not FileAccess.file_exists(output):
		return {"hit": false, "reason": "scene_missing"}
	var hash: String = FileAccess.get_sha256(output)
	if hash.is_empty() or hash != str(record.get("output_sha256", "")):
		return {"hit": false, "reason": "scene_corrupt"}
	var result: Dictionary = record.result.duplicate(true)
	if (
		not result.get("ok", false)
		or result.get("output_sha256") != hash
		or result.get("asset_id") != task.asset_id
		or result.get("profile") != task.profile
		or result.get("compiler_version") != Compiler.COMPILER_VERSION
		or not result.get("inventory") is Dictionary
		or not result.get("diagnostics") is Array
	):
		return {"hit": false, "reason": "record_invalid"}
	result["output_scene"] = ProjectSettings.globalize_path(output)
	result["cache"] = {"status": "hit", "reason": "verified", "signature": signature}
	return {"hit": true, "result": result}

func _write_json(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK

func _cleanup(paths: Array[String]) -> void:
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _failure(asset: String, code: String, message: String, exit_code: int) -> Dictionary:
	return {"exit_code": exit_code, "result": {"result_version": 1, "ok": false, "asset_id": asset,
		"diagnostics": [{"code": code, "severity": "error", "message": message}]}}

func _publish(source: String, destination: String) -> Error:
	# Never overwrite: Windows DirAccess would delete the existing destination.
	if FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
		return ERR_ALREADY_EXISTS
	return DirAccess.rename_absolute(source, destination)

func _generation(directory: String) -> String:
	var stamp: int = int(Time.get_unix_time_from_system() * 1000000.0)
	# Clock rollback must not make a successful rebuild older than its predecessor.
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".json") and not file.contains(".pending."):
			var previous: String = file.get_slice("-", 0)
			if previous.is_valid_int():
				stamp = maxi(stamp, previous.to_int() + 1)
	return "%020d-%d-%d" % [stamp, OS.get_process_id(), Time.get_ticks_usec()]
