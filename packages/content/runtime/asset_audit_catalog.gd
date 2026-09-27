class_name AssetAuditCatalog
extends RefCounted
## Read-only catalog. The viewer never triggers a lazy bake or loads raw MDX.

var records: Array[Dictionary] = []
var report: Dictionary = {}
var error: String = ""


func load_report(file_path: String) -> bool:
	records.clear()
	report.clear()
	error = ""
	var parsed: Dictionary = RuntimeAssets.read_json_dict(file_path)
	if int(parsed.get("schema_version", 0)) != 1 or not parsed.get("records") is Array:
		error = "审计报告不存在或版本不支持。请先运行资源审计。"
		return false
	for value: Variant in parsed["records"]:
		if not value is Dictionary:
			error = "审计记录格式错误。"
			records.clear()
			return false
		var row: Dictionary = value
		var scn_path: String = str(row.get("scn_path", ""))
		if not scn_path.is_empty() and (not is_safe_relative(scn_path) or scn_path.get_extension().to_lower() != "scn"):
			error = "审计记录包含非法场景路径。"
			records.clear()
			return false
		records.append(row)
	report = parsed
	return true


func scan_baked() -> void:
	records.clear()
	report.clear()
	error = ""
	var root_path: String = RuntimeAssets.project_abs(RuntimeAssets.CONVERTED_RES_ROOT)
	_scan_directory(root_path, "")
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))


static func is_safe_relative(value: String) -> bool:
	if value.is_empty() or value.is_absolute_path() or value.contains(":") or value.contains("\\"):
		return false
	for part: String in value.split("/"):
		if part in ["", ".", ".."]:
			return false
	return true


func _scan_directory(root_path: String, relative: String) -> void:
	var dir: DirAccess = DirAccess.open(root_path.path_join(relative))
	if dir == null:
		return
	for folder: String in dir.get_directories():
		if not folder.begins_with(".") and not dir.is_link(folder):
			_scan_directory(root_path, relative.path_join(folder))
	for file: String in dir.get_files():
		if file.get_extension().to_lower() != "scn":
			continue
		var logical: String = relative.path_join(file)
		records.append({"id": logical.get_basename().to_lower(), "logical_path": logical, "scn_path": logical, "severity": "unknown", "visual_status": "unverified", "profile": "legacy_unclassified", "issues": []})
