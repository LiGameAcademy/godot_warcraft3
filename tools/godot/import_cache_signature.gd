extends RefCounted

const Compiler: GDScript = preload("import_scene_compiler.gd")
const CACHE_VERSION: int = 1

static func resolve_path(value: String, base: String) -> String:
	if value.is_absolute_path():
		return value.simplify_path()
	return base.path_join(value).simplify_path()

static func prepare(task_path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(task_path))
	if not parsed is Dictionary:
		return {"delegate": true}
	var task: Dictionary = parsed
	if not Compiler.validate_task(task).is_empty():
		return {"delegate": true}
	var prepared: Dictionary = _prepare_inputs(task, task_path)
	prepared["asset_id"] = str(task.asset_id)
	return prepared

static func _prepare_inputs(task: Dictionary, task_path: String) -> Dictionary:
	var ir_path: String = resolve_path(str(task.ir_path), task_path.get_base_dir())
	var geometry: String = resolve_path(str(task.geometry_path), task_path.get_base_dir())
	var ir: Variant = JSON.parse_string(FileAccess.get_file_as_string(ir_path))
	if not ir is Dictionary or ir.get("schema_version") != 1 or not ir.get("identity") is Dictionary or ir.identity.get("asset_id") != task.asset_id:
		return {"delegate": true}
	var gltf: Variant = JSON.parse_string(FileAccess.get_file_as_string(geometry))
	if not gltf is Dictionary:
		return _error("cache_geometry_invalid", "缓存输入必须是有效的 glTF JSON")
	var paths: Array[String] = [ir_path, geometry]
	var logical_ir: String = str(ir.identity.get("logical_path", "")).get_basename() + ".ir.json"
	var input_root: String = task_path.get_base_dir()
	if not logical_ir.is_empty() and ir_path.ends_with(logical_ir):
		input_root = ir_path.substr(0, ir_path.length() - logical_ir.length())
	for dependencies: Variant in [ir.get("dependencies", []), task.get("dependencies", [])]:
		if not dependencies is Array:
			return _error("cache_dependencies_invalid", "dependencies 必须为路径数组")
		for dependency: Variant in dependencies:
			if not dependency is String:
				return _error("cache_dependencies_invalid", "dependency 必须为路径字符串")
			paths.append(resolve_path(dependency, input_root))
	for section: String in ["buffers", "images"]:
		for entry: Dictionary in gltf.get(section, []):
			var uri: String = str(entry.get("uri", ""))
			if not uri.is_empty() and not uri.begins_with("data:"):
				paths.append(resolve_path(uri.uri_decode(), geometry.get_base_dir()))
	if not ir.get("textures", {}) is Dictionary:
		return {"delegate": true}
	for entry: Dictionary in ir.get("textures", {}).get("source_payload", []):
		var uri: String = str(entry.get("uri", ""))
		if not uri.is_empty():
			paths.append(resolve_path(uri, ir_path.get_base_dir()))
	if not str(task.get("source_path", "")).is_empty():
		paths.append(resolve_path(str(task.source_path), task_path.get_base_dir()))
	paths.sort()
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	for path: String in paths:
		if seen.has(path):
			continue
		seen[path] = true
		if not FileAccess.file_exists(path):
			return _error("cache_dependency_missing", "依赖不存在：" + path)
		var hash: String = FileAccess.get_sha256(path)
		if hash.is_empty():
			return _error("cache_dependency_unreadable", "无法读取依赖：" + path)
		entries.append({"path": path, "sha256": hash})
	var build: String = _build_signature()
	if build.is_empty():
		return _error("compiler_signature_missing", "发布包缺少 import_compiler.source")
	var payload: Dictionary = {"cache_version": CACHE_VERSION, "compiler_version": Compiler.COMPILER_VERSION,
		"compiler_build": build, "engine": Engine.get_version_info().get("string", ""),
		"asset_id": task.asset_id, "profile": task.profile, "schema_version": ir.schema_version,
		"rules_version": task.get("rules_version", ""), "expected_signature": task.get("expected_signature", ""),
		"inputs": entries}
	return {"ok": true, "task": task, "ir_path": ir_path, "geometry": geometry,
		"output": resolve_path(str(task.output_scene), task_path.get_base_dir()),
		"signature": JSON.stringify(payload).sha256_text(), "inputs": entries}

static func _build_signature() -> String:
	var directory: String = Compiler.resource_path.get_base_dir()
	var manifest: String = directory.path_join("import_compiler.source")
	if FileAccess.file_exists(manifest):
		return FileAccess.get_sha256(manifest)
	var files: PackedStringArray = DirAccess.get_files_at(directory)
	files.sort()
	var hashes: Array[String] = []
	for file: String in files:
		if file.begins_with("import_") and file.ends_with(".gd"):
			hashes.append(file + ":" + FileAccess.get_sha256(directory.path_join(file)))
	if hashes.is_empty():
		return ""
	hashes.append(FileAccess.get_sha256("res://packages/map/presentation/wc3_model/wc3_pe2_material.gd"))
	return JSON.stringify(hashes).sha256_text()

static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
