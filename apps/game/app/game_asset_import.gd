extends RefCounted

const Content: GDScript = preload("res://app/asset_import_content.gd")
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

func install_results(results: Array[Dictionary], content: Dictionary = {}) -> Dictionary:
	if results.is_empty() or AssetProvider.runtime_content_sealed:
		return _failure("cache_install_invalid", "空索引或对局已开始")
	var content_started: int = Time.get_ticks_usec()
	if not Content.validate(content):
		return _failure("content_generation_invalid", "地图资源缓存缺失或损坏")
	Content.trace("install_content_hashes", content_started, content.get("files", []).size())
	var scenes_started: int = Time.get_ticks_usec()
	var paths: Dictionary[String, String] = {}
	for result: Dictionary in results:
		if not result.get("ok", false) or not result.get("output_scene") is String:
			return _failure("cache_result_invalid", "编译结果无效")
		var asset_id: String = str(result.get("asset_id", "")).replace("\\", "/").to_lower()
		if asset_id.is_empty() or asset_id.is_absolute_path() or asset_id.split("/").has("..") or paths.has(asset_id + ".scn"):
			return _failure("asset_identity_invalid", "重复或非法资产身份：" + asset_id)
		var scene: PackedScene = RuntimeAssets.load_packed_scene(str(result.output_scene))
		if scene == null:
			return _failure("cache_scene_load_failed", "缓存场景不能由游戏加载：" + asset_id)
		paths[asset_id + ".scn"] = str(result.output_scene)
	Content.trace("install_scene_loads", scenes_started, results.size())
	var installed: Error = ContentPaths.install_compiled_scenes(paths, str(content.get("root", "")))
	if installed != OK:
		return _failure("cache_install_failed", "缓存路径提交失败：%s" % installed)
	if not content.is_empty():
		Wc3DefStore.clear_loaded_tables()
	# Check the same resolver used by the game's model cache, not a direct load.
	for logical: String in paths:
		var resolved: String = RuntimeAssets.resolve_model_scene(logical)
		if resolved != paths[logical]:
			return _failure("cache_resolution_failed", "游戏未选择新缓存：" + logical)
	return {"ok": true, "results": results, "paths": paths, "content": content, "deliverable": false}

func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "results": [], "diagnostics": [{"code": code, "severity": "error", "message": message}]}
