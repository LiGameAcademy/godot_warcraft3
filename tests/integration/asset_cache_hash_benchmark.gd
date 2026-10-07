extends SceneTree

## Read-only benchmark of an existing published index. Does not mount its paths.
const Validation: GDScript = preload("res://app/asset_cache_validation.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	assert("--index" in args and "--report" in args)
	var index_path: String = args[args.find("--index") + 1]
	var report_path: String = args[args.find("--report") + 1]
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	var trials: Array[Dictionary] = []
	# Reverse the second pass to expose OS file-cache/order effects.
	for workers: int in [0, 1, 2, 4, 4, 2, 1, 0]:
		var started: int = Time.get_ticks_usec()
		var trial: Dictionary = {"workers": workers, "native_serial": workers == 0}
		var valid: bool = true
		if workers == 0:
			for entry: Dictionary in record.content.files:
				valid = valid and FileAccess.get_sha256(str(record.content.root).path_join(str(entry.path))) == entry.sha256
			trial["content_ms"] = (Time.get_ticks_usec() - started) / 1000.0
			var scenes_started: int = Time.get_ticks_usec()
			for entry: Dictionary in record.results:
				valid = valid and FileAccess.get_sha256(str(entry.output_scene)) == entry.output_sha256
			trial["scenes_ms"] = (Time.get_ticks_usec() - scenes_started) / 1000.0
		else:
			var checker: RefCounted = Validation.new(workers)
			valid = checker.validate_content(record.content)
			trial["content_ms"] = (Time.get_ticks_usec() - started) / 1000.0
			trial["content_bytes"] = checker.snapshot().bytes
			var scenes_started: int = Time.get_ticks_usec()
			valid = checker.validate_scenes(record.results) and valid
			trial["scenes_ms"] = (Time.get_ticks_usec() - scenes_started) / 1000.0
			trial["scene_bytes"] = checker.snapshot().bytes
		trial["total_ms"] = (Time.get_ticks_usec() - started) / 1000.0
		trial["valid"] = valid
		trials.append(trial)
		print("BENCHMARK: ", JSON.stringify(trial))
		assert(valid, "Existing cache failed full hash validation")
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify({
			"engine": Engine.get_version_info().string, "index": index_path,
			"content_files": record.content.files.size(), "scenes": record.results.size(),
			"note": "Repeated reads on the same machine; OS cache is not cleared.", "trials": trials,
		}, "  "))
		file.close()
	print("PASS: existing cache hashes agree across native serial and 1/2/4 streaming workers")
	quit(0)
