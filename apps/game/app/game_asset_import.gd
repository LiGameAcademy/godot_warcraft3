extends RefCounted

const Content: GDScript = preload("res://app/asset_import_content.gd")
const Index: GDScript = preload("res://app/asset_import_index.gd")
var _validated_record: Dictionary = {}

const CachedCompiler: GDScript = preload("res://tools/godot/import_cached_compiler.gd")

## 同步命令行入口；后台任务复用 install_results 提交完整路径表。
func run_manifest(path: String, content_in_use: bool) -> Dictionary:
	if content_in_use:
		return _failure("content_in_use", "对局运行中不能导入资产")
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return _failure("manifest_invalid", "导入清单不是有效 JSON 对象")
	var manifest: Dictionary = parser.data
	if manifest.get("manifest_version") != 1 or not manifest.get("tasks") is Array or manifest.tasks.is_empty():
		return _failure("manifest_invalid", "清单版本不支持或 tasks 为空")
	var results: Array[Dictionary] = []
	var compiler: RefCounted = CachedCompiler.new()
	for entry: Variant in manifest.tasks:
		if not entry is String or entry.is_empty():
			return _failure("manifest_task_invalid", "tasks 必须是任务文件路径数组")
		var task_path: String = entry if entry.is_absolute_path() else path.get_base_dir().path_join(entry).simplify_path()
		var response: Dictionary = compiler.compile_task(task_path)
		results.append(response.result)
		if int(response.exit_code) != 0:
			return {"ok": false, "results": results, "diagnostics": response.result.diagnostics}
	return install_results(results, manifest.get("content", {}))

## Worker-thread entry: hashes only; no scene-tree access or scene loading.
func validate_cache(cache_root: String, request_resource: String) -> bool:
	_validated_record = Index.latest(cache_root, request_resource)
	return not _validated_record.is_empty()

## Call only after the validation thread has been joined. Consume once.
func restore_validated_cache() -> Dictionary:
	var record: Dictionary = _validated_record
	_validated_record = {}
	if record.is_empty():
		return _failure("cache_not_validated", "缓存未通过校验")
	var results: Array[Dictionary] = []
	for result: Dictionary in record.results:
		results.append(result)
	return _install_results(results, record.get("content", {}), true)

func install_results(results: Array[Dictionary], content: Dictionary = {}) -> Dictionary:
	return _install_results(results, content, false)

func _install_results(results: Array[Dictionary], content: Dictionary, restored: bool) -> Dictionary:
	if results.is_empty() or AssetProvider.runtime_content_sealed:
		return _failure("cache_install_invalid", "空索引或对局已开始")
	var content_started: int = Time.get_ticks_usec()
	if not restored and not Content.validate(content):
		return _failure("content_generation_invalid", "地图资源缓存缺失或损坏")
	if not restored:
		Content.trace("install_content_hashes", content_started, content.get("files", []).size())
	var scenes_started: int = Time.get_ticks_usec()
	var paths: Dictionary[String, String] = {}
	for result: Dictionary in results:
		if not result.get("ok", false) or not result.get("output_scene") is String:
			return _failure("cache_result_invalid", "编译结果无效")
		var asset_id: String = str(result.get("asset_id", "")).replace("\\", "/").to_lower()
		if asset_id.is_empty() or asset_id.is_absolute_path() or asset_id.split("/").has("..") or paths.has(asset_id + ".scn"):
			return _failure("asset_identity_invalid", "重复或非法资产身份：" + asset_id)
		if not restored:
			# Each compiler worker already reloads/instantiates its publication.
			# Verify that those bytes did not change before committing the batch.
			var scene_path: String = str(result.output_scene)
			var expected_hash: String = str(result.get("output_sha256", ""))
			if expected_hash.is_empty() or FileAccess.get_sha256(scene_path) != expected_hash:
				return _failure("cache_scene_hash_failed", "缓存场景缺失或已改变：" + asset_id)
		paths[asset_id + ".scn"] = str(result.output_scene)
	Content.trace("install_cached_paths" if restored else "install_scene_hashes", scenes_started, results.size())
	var installed: Error = ContentPaths.install_compiled_scenes(paths, str(content.get("root", "")))
	if installed != OK:
		return _failure("cache_install_failed", "缓存路径提交失败：%s" % installed)
	if not content.is_empty():
		Wc3DefStore.clear_loaded_tables()
	# Check the game's shared path resolver; legacy SCN probing is unrelated here.
	for logical: String in paths:
		var resolved: String = ContentPaths.resolve("res://assets/asset-converted/" + logical)
		if resolved != paths[logical]:
			return _failure("cache_resolution_failed", "游戏未选择新缓存：" + logical)
	return {"ok": true, "results": results, "paths": paths, "content": content, "deliverable": false}

func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "results": [], "diagnostics": [{"code": code, "severity": "error", "message": message}]}
