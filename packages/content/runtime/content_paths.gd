class_name ContentPaths
extends RefCounted

## 编译结果在进局前一次提交；后续只读，防止进行中的对局切换资产。
static var _compiled_scenes: Dictionary[String, String] = {}
static var _compiled_sealed: bool = false
static var _content_root: String = ""

static func install_compiled_scenes(paths: Dictionary[String, String], content_root: String = "") -> Error:
	if _compiled_sealed:
		return ERR_BUSY
	for logical: String in paths:
		if not logical.ends_with(".scn") or not FileAccess.file_exists(paths[logical]):
			return ERR_INVALID_DATA
	if not content_root.is_empty() and not DirAccess.dir_exists_absolute(content_root):
		return ERR_INVALID_DATA
	_content_root = content_root
	_compiled_scenes = paths.duplicate()
	_compiled_sealed = true
	return OK

## External loose assets are independent of the application's res:// root.
static func resolve(path: String) -> String:
	if path.begins_with("res://assets/asset-converted/"):
		var logical: String = path.trim_prefix("res://assets/asset-converted/").to_lower()
		if _compiled_scenes.has(logical):
			return _compiled_scenes[logical]
	if path.begins_with("res://assets/"):
		var root: String = _external_root()
		if not root.is_empty():
			return root.path_join(path.trim_prefix("res://assets/")).replace("\\", "/")
	return ProjectSettings.globalize_path(path).replace("\\", "/")

## 路径解析可能发生在 boot 之前的 Autoload 初始化中。
static func _external_root() -> String:
	if not _content_root.is_empty():
		return _content_root
	var root: String = str(ProjectSettings.get_setting("warcraft3/asset_root", ""))
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size() - 1):
		if args[index] == "--asset-root":
			root = args[index + 1]
	return root
