extends RefCounted

const Content: GDScript = preload("res://app/asset_import_content.gd")
const DEFAULT_REQUEST: String = "res://config/development_asset_request.source"

static func build_key(request_resource: String = DEFAULT_REQUEST) -> String:
	var bundle: String = OS.get_executable_path().get_base_dir().path_join("asset-import-runtime/runtime-bundle.json")
	var signature: String = Engine.get_version_info().string + "|player-index-v2|"
	for source: String in ["import_compiler.source", "import_billboard_pose.gd.source", "import_ribbon_runtime.gd.source"]:
		signature += FileAccess.get_sha256("res://tools/godot/" + source)
	signature += FileAccess.get_sha256(request_resource)
	signature += FileAccess.get_sha256(bundle) if FileAccess.file_exists(bundle) else ""
	return signature.sha256_text()

static func latest(cache_root: String, request_resource: String = DEFAULT_REQUEST) -> Dictionary:
	var directory: String = ProjectSettings.globalize_path(cache_root).path_join("indexes")
	var files: PackedStringArray = DirAccess.get_files_at(directory) if DirAccess.dir_exists_absolute(directory) else PackedStringArray()
	files.sort()
	files.reverse()
	for filename: String in files:
		if not filename.ends_with(".json"):
			continue
		var parser: JSON = JSON.new()
		if parser.parse(FileAccess.get_file_as_string(directory.path_join(filename))) != OK or not parser.data is Dictionary:
			return {}
		var record: Dictionary = parser.data
		if record.get("version") != 1 or record.get("build") != build_key(request_resource) or not record.get("results") is Array or record.results.is_empty():
			return {}
		if not record.get("content", {}) is Dictionary or not Content.validate(record.get("content", {})):
			return {}
		if request_resource == DEFAULT_REQUEST and record.get("content", {}).is_empty():
			return {}
		for entry: Variant in record.results:
			if not entry is Dictionary:
				return {}
			var result: Dictionary = entry
			var scene: String = str(result.get("output_scene", ""))
			if not FileAccess.file_exists(scene) or FileAccess.get_sha256(scene) != result.get("output_sha256", ""):
				return {}
		return record
	return {}

static func save(cache_root: String, results: Array[Dictionary], game_dir: String, content: Dictionary = {}, request_resource: String = DEFAULT_REQUEST) -> Error:
	var directory: String = ProjectSettings.globalize_path(cache_root).path_join("indexes")
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	var timestamp: int = int(Time.get_unix_time_from_system() * 1000000)
	# Keep new publications newest even after the system clock moves backwards.
	for filename: String in DirAccess.get_files_at(directory):
		if filename.ends_with(".json"):
			timestamp = maxi(timestamp, filename.get_slice("-", 0).to_int() + 1)
	var token: String = "%020d-%s-%s" % [timestamp, OS.get_process_id(), Time.get_ticks_usec()]
	var target: String = directory.path_join(token + ".json")
	var file: FileAccess = FileAccess.open(target + ".pending", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": 1, "build": build_key(request_resource), "content": content, "results": results, "game_dir": game_dir}, "  "))
	file.close()
	return DirAccess.rename_absolute(target + ".pending", target)
