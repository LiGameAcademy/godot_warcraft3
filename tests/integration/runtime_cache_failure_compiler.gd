extends "res://import_cached_compiler.gd"

## 故障注入仅属于测试应用，不随生产编译器发布。
var phase: String = ""
var changing_input: String = ""

func _publish(source: String, destination: String) -> Error:
	if (phase == "--fail-scene-commit" and destination.ends_with(".scn")) or (phase == "--fail-record-commit" and destination.ends_with(".json")):
		return FAILED
	return super._publish(source, destination)

func _write_json(path: String, value: Dictionary) -> bool:
	var written: bool = super._write_json(path, value)
	if phase == "--change-input" and path.ends_with(".cache.json"):
		var input: FileAccess = FileAccess.open(changing_input, FileAccess.WRITE)
		input.store_string("changed during compilation")
		input.close()
	return written
