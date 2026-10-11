extends RefCounted
## 本机路径配置：编辑器和发布游戏共用；不保存密钥或写回工程设置。
const FILE: String = "user://asset_import.cfg"
const DEFAULT_CACHE: String = "user://wc3-cache/source-import"

static func read(path: String = FILE) -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	return config

static func argument(args: PackedStringArray, flag: String, fallback: String) -> String:
	var index: int = args.find(flag)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

static func cache_path(args: PackedStringArray) -> String:
	return argument(args, "--asset-import-cache", str(read().get_value("paths", "cache", DEFAULT_CACHE)))

static func runtime_bundle() -> String:
	if not OS.has_feature("editor"):
		return OS.get_executable_path().get_base_dir().path_join("asset-import-runtime")
	var configured: String = str(ProjectSettings.get_setting("warcraft3/asset_import_runtime", read().get_value("paths", "runtime", "")))
	var selected: String = argument(OS.get_cmdline_user_args(), "--asset-import-runtime", configured)
	return ProjectSettings.globalize_path(selected) if not selected.is_empty() else ""

static func save(cache: String, source: String, runtime: String, path: String = FILE) -> Error:
	var config: ConfigFile = read(path)
	config.set_value("paths", "cache", cache)
	config.set_value("paths", "source", source)
	config.set_value("paths", "runtime", runtime)
	return config.save(path)

static func needs_wizard(args: PackedStringArray) -> bool:
	return not "--warcraft-dir" in args and not "--asset-import-manifest" in args

static func worker_args(batch: String, result: String, editor: bool, project: String) -> PackedStringArray:
	var args: PackedStringArray = PackedStringArray(["--headless"])
	if editor:
		args.append_array(PackedStringArray(["--path", project]))
	args.append_array(PackedStringArray(["--", "--asset-worker-batch", batch, "--asset-worker-result", result]))
	return args
