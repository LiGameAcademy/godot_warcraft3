class_name BuildingDeathSettings
extends Resource
## 以经典原版 MiscData 的 StructureDecayTime 为建筑残骸寿命。
@export var corpse_seconds: float = 30.0

static func from_source() -> BuildingDeathSettings:
	var settings: BuildingDeathSettings = BuildingDeathSettings.new()
	var path: String = RuntimeAssets.resolve("Units/MiscData.txt")
	if path.is_empty():
		AppLog.warn(AppLog.Layer.PRESENT, "BuildingDeath", "缺少 MiscData；使用经典建筑残骸时长 30 秒")
		return settings
	var section: String = ""
	for raw: String in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("["):
			section = line
		elif section == "[Misc]" and line.get_slice("=", 0).strip_edges() == "StructureDecayTime":
			var value: String = line.get_slice("=", 1).get_slice("//", 0).strip_edges()
			if value.is_valid_float() and float(value) > 0.0:
				settings.corpse_seconds = float(value)
				return settings
	AppLog.warn(AppLog.Layer.PRESENT, "BuildingDeath", "StructureDecayTime 无有效值；使用 30 秒")
	return settings
