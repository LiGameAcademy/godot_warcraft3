extends Node
class_name AssetProviderNode
## 逻辑路径 → 物理文件 解析层（开发态读 .cache；预留 mod overlay）。
## 玩家端首次解包（GDExtension + StormLib → user://wc3_cache）尚未接入。

const SETTINGS_CACHE_DIR := "warcraft3/asset_cache_dir"

## { "id": String, "root": String }，后注册者优先。
var _overlays: Array[Dictionary] = []


func _ready() -> void:
	pass


func get_cache_root() -> String:
	var configured: String = str(ProjectSettings.get_setting(SETTINGS_CACHE_DIR, ""))
	if not configured.is_empty():
		return configured.replace("\\", "/").simplify_path()
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if project_root.ends_with("/"):
		project_root = project_root.left(project_root.length() - 1)
	return project_root.path_join(".cache/wc3-assets").simplify_path()


func normalize_logical_path(logical_path: String) -> String:
	var p := logical_path.replace("\\", "/")
	while p.begins_with("/"):
		p = p.substr(1)
	return p


## 解析逻辑路径到绝对磁盘路径；找不到时返回空字符串。
func resolve(logical_path: String) -> String:
	var logical := normalize_logical_path(logical_path)
	if logical.is_empty():
		return ""

	# 后注册的 overlay 优先（与计划中的 mod 覆盖语义一致）。
	for i in range(_overlays.size() - 1, -1, -1):
		var overlay: Dictionary = _overlays[i]
		var candidate: String = str(overlay.get("root", "")).path_join(logical).simplify_path()
		if FileAccess.file_exists(candidate):
			return candidate

	var from_cache := get_cache_root().path_join(logical).simplify_path()
	if FileAccess.file_exists(from_cache):
		return from_cache
	return ""


func exists(logical_path: String) -> bool:
	return not resolve(logical_path).is_empty()


## 以只读方式打开逻辑路径对应文件；失败返回 null。
func open(logical_path: String) -> FileAccess:
	var abs_path := resolve(logical_path)
	if abs_path.is_empty():
		return null
	return FileAccess.open(abs_path, FileAccess.READ)


## 注册 mod 覆盖根目录。同 logical_path 下后注册者优先。
## TODO: 第三步接入 mods/<id>/ 自动扫描与 mod.json。
func register_overlay(mod_id: String, root: String) -> void:
	if mod_id.is_empty() or root.is_empty():
		push_warning("AssetProvider.register_overlay: mod_id/root 不能为空")
		return
	for i in range(_overlays.size() - 1, -1, -1):
		if str(_overlays[i].get("id", "")) == mod_id:
			_overlays.remove_at(i)
	_overlays.append({"id": mod_id, "root": root.replace("\\", "/").simplify_path()})


func clear_overlays() -> void:
	_overlays.clear()


func get_overlay_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for overlay in _overlays:
		ids.append(str(overlay.get("id", "")))
	return ids
