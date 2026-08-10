extends Node
class_name AssetProviderNode
## 逻辑路径 → 物理文件。
## 查找顺序：mod overlay → asset-converted → slk-exported（数据车道）。
## 不读 .cache/wc3-assets（extract 中间态；见 docs/architecture/ASSET_LANES.md）。
## 转换产物扩展名：.blp→.png，.mdx/.mdl→.glb。


const SETTINGS_CACHE_DIR := "warcraft3/asset_cache_dir"
const SETTINGS_CONVERTED_DIR := "warcraft3/asset_converted_dir"
const SETTINGS_DATA_DIR := "warcraft3/asset_data_dir"
const DEFAULT_CONVERTED_RES := "res://assets/asset-converted"
const DEFAULT_DATA_RES := "res://assets/slk-exported"

## { "id": String, "root": String }，后注册者优先。
var _overlays: Array[Dictionary] = []


func _ready() -> void:
	pass


## extract 中间态根（仅工具/诊断用；resolve 不使用）。
func get_cache_root() -> String:
	var configured: String = str(ProjectSettings.get_setting(SETTINGS_CACHE_DIR, ""))
	if not configured.is_empty():
		return configured.replace("\\", "/").simplify_path()
	return _project_join(".cache/wc3-assets")


func get_converted_root() -> String:
	var configured: String = str(ProjectSettings.get_setting(SETTINGS_CONVERTED_DIR, ""))
	if not configured.is_empty():
		return configured.replace("\\", "/").simplify_path()
	return ProjectSettings.globalize_path(DEFAULT_CONVERTED_RES).replace("\\", "/")


## 数据车道：SLK JSON + UnitFunc/UI txt（tools/sync-data-assets 写入）。
func get_data_root() -> String:
	var configured: String = str(ProjectSettings.get_setting(SETTINGS_DATA_DIR, ""))
	if not configured.is_empty():
		return configured.replace("\\", "/").simplify_path()
	return ProjectSettings.globalize_path(DEFAULT_DATA_RES).replace("\\", "/")


func _project_join(rel: String) -> String:
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if project_root.ends_with("/"):
		project_root = project_root.left(project_root.length() - 1)
	return project_root.path_join(rel).simplify_path()


func normalize_logical_path(logical_path: String) -> String:
	var p := logical_path.replace("\\", "/")
	while p.begins_with("/"):
		p = p.substr(1)
	# 允许误传 res://assets/asset-converted/X 或 slk-exported/X
	const PREFIXES: Array[String] = [
		"res://assets/asset-converted/",
		"assets/asset-converted/",
		"asset-converted/",
		"res://assets/slk-exported/",
		"assets/slk-exported/",
		"slk-exported/",
		"res://.cache/wc3-assets/",
		".cache/wc3-assets/",
	]
	for pre in PREFIXES:
		if p.begins_with(pre):
			p = p.substr(pre.length())
			break
	return p


## 解析逻辑路径到绝对磁盘路径；找不到时返回空字符串。
## 不回退 .cache（缺文件 → 跑 bootstrap / sync-data-assets）。
func resolve(logical_path: String) -> String:
	var logical := normalize_logical_path(logical_path)
	if logical.is_empty():
		return ""

	for i in range(_overlays.size() - 1, -1, -1):
		var overlay: Dictionary = _overlays[i]
		var hit := _first_existing(str(overlay.get("root", "")), logical)
		if not hit.is_empty():
			return hit

	var from_converted := _first_existing(get_converted_root(), logical)
	if not from_converted.is_empty():
		return from_converted

	var from_data := _first_existing(get_data_root(), logical)
	if not from_data.is_empty():
		return from_data
	return ""


func _first_existing(root: String, logical: String) -> String:
	if root.is_empty():
		return ""
	for rel in _candidate_relatives(logical):
		var candidate: String = root.path_join(rel).simplify_path()
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## 同一逻辑路径在 converted / data 下的可能相对名。
func _candidate_relatives(logical: String) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(logical)
	var lower := logical.to_lower()
	if lower.ends_with(".blp"):
		out.append(logical.substr(0, logical.length() - 4) + ".png")
	elif lower.ends_with(".mdx") or lower.ends_with(".mdl"):
		var stem := logical.substr(0, logical.length() - 4)
		out.append(stem + ".gltf")
		out.append(stem + ".glb")
	elif logical.get_extension().is_empty():
		out.append(logical + ".png")
		out.append(logical + ".gltf")
		out.append(logical + ".glb")
	return out


func exists(logical_path: String) -> bool:
	return not resolve(logical_path).is_empty()


## 以只读方式打开逻辑路径对应文件；失败返回 null。
func open(logical_path: String) -> FileAccess:
	var abs_path := resolve(logical_path)
	if abs_path.is_empty():
		return null
	return FileAccess.open(abs_path, FileAccess.READ)


## 注册 mod 覆盖根目录。同 logical_path 下后注册者优先。
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
