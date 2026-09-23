extends RefCounted
## Content signatures include removed dependencies and converter changes, not
## just mtimes. One instance per bake run caches shared texture/source hashes.
const CODE_ROOTS := ["res://tools/godot", "res://addons/rts_map/presentation/wc3_model", "res://addons/rts_map/infra", "res://addons/rts_map/presentation/effects", "res://assets/shaders", "res://tools/asset-convert/src"]
var _hashes: Dictionary = {}
var _code_signature := ""


func signature(model_path: String) -> String:
	if _code_signature.is_empty():
		var sources: Array[String] = []
		for directory in CODE_ROOTS:
			_collect_sources(directory, sources)
		sources.sort()
		var source_parts: Array[String] = [JSON.stringify(Engine.get_version_info())]
		for source in sources:
			source_parts.append(source + ":" + _hash(source))
		_code_signature = "\n".join(source_parts).sha256_text()
	var deps: Dictionary = {model_path: true}
	var stem := model_path.get_basename()
	deps["res://assets/fx-overrides/" + stem.trim_prefix("res://assets/asset-converted/") + ".json"] = true
	var directory := DirAccess.open(RuntimeAssets.project_abs(model_path.get_base_dir()))
	if directory != null:
		for file in directory.get_files():
			if file.begins_with(stem.get_file() + ".") and file.ends_with(".json") and not file.ends_with(".scn.bake.json"):
				var sidecar := model_path.get_base_dir().path_join(file)
				deps[sidecar] = true
				_collect_texture_refs(_read_json(sidecar), deps)
	if model_path.to_lower().ends_with(".gltf"):
		var gltf := _read_json(model_path)
		for group in ["buffers", "images"]:
			for entry in gltf.get(group, []):
				var uri := str(entry.get("uri", ""))
				if not uri.is_empty() and not uri.begins_with("data:"):
					deps[model_path.get_base_dir().path_join(uri.uri_decode()).simplify_path()] = true
	var paths: Array = deps.keys()
	paths.sort()
	var parts: Array[String] = [_code_signature]
	for path in paths:
		parts.append(str(path) + ":" + _hash(str(path)))
	return "\n".join(parts).sha256_text()


func is_current(scene_path: String, expected: String) -> bool:
	scene_path = RuntimeAssets.project_abs(scene_path)
	if not FileAccess.file_exists(scene_path):
		return false
	var manifest := _read_json(scene_path + ".bake.json")
	return manifest.get("signature", "") == expected and manifest.get("scene_hash", "") == FileAccess.get_sha256(scene_path)


func record(scene_path: String, expected: String) -> Error:
	scene_path = RuntimeAssets.project_abs(scene_path)
	if not FileAccess.file_exists(scene_path):
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(scene_path + ".bake.json", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"signature": expected, "scene_hash": FileAccess.get_sha256(scene_path)}, "\t"))
	return OK


func _hash(path: String) -> String:
	path = RuntimeAssets.project_abs(path)
	if not _hashes.has(path):
		_hashes[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	return str(_hashes[path])


static func _read_json(path: String) -> Dictionary:
	path = RuntimeAssets.project_abs(path)
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


static func _collect_texture_refs(value: Variant, deps: Dictionary) -> void:
	if value is Dictionary:
		for key in value:
			var child: Variant = value[key]
			if str(key) == "texture" and child is String and not child.is_empty():
				deps["res://assets/asset-converted/" + child] = true
			else:
				_collect_texture_refs(child, deps)
	elif value is Array:
		for child in value:
			_collect_texture_refs(child, deps)


static func _collect_sources(path: String, paths: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file in directory.get_files():
		if file.get_extension() in ["gd", "gdshader", "gdshaderinc", "js"]:
			paths.append(path.path_join(file))
	for child in directory.get_directories():
		_collect_sources(path.path_join(child), paths)
