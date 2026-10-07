extends RefCounted

## Bounded batches reuse one engine process while cancellation remains process-owned.
static func compile_batch(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array or parsed.is_empty() or parsed.size() > 16:
		return {"ok": false, "diagnostics": [{"code": "worker_batch_invalid", "message": "编译批次无效"}]}
	var compiler: RefCounted = load("res://tools/godot/import_cached_compiler.gd").new()
	var results: Array[Dictionary] = []
	for task: Variant in parsed:
		if not task is String:
			return {"ok": false, "diagnostics": [{"code": "worker_batch_invalid", "message": "任务路径无效"}]}
		var response: Dictionary = compiler.compile_task(task)
		if int(response.exit_code) != 0:
			return response.result
		results.append(response.result)
	return {"ok": true, "results": results}
