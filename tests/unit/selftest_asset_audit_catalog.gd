extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: AssetAuditCatalog = AssetAuditCatalog.new()
	var file_path: String = "res://tmp/catalog-test.json"
	DirAccess.make_dir_recursive_absolute("res://tmp")
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1, "records": [{"id": "model", "scn_path": "Units/Model.scn"}]}))
	file.close()
	assert(catalog.load_report(file_path))
	assert(catalog.records.size() == 1)
	file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1, "records": [{"scn_path": "../outside.scn"}]}))
	file.close()
	assert(not catalog.load_report(file_path))
	assert(catalog.records.is_empty())
	assert(not catalog.load_report("res://tmp/no-such-report.json"))
	assert(not AssetAuditCatalog.is_safe_relative("C:/outside.scn"))
	assert(not AssetAuditCatalog.is_safe_relative("res://outside.scn"))
	DirAccess.remove_absolute(file_path)
	print("selftest_asset_audit_catalog PASS")
	quit(0)
