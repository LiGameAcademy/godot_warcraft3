extends RefCounted

## 与当前导入单位表配套的游戏常量。地图自定义覆盖需由后续会话配置接入。
const SOURCE := "res://assets/slk-exported/Units/MiscGame.txt"
static var _values: Dictionary = {}
static var _loaded := false

static func parse_misc(text: String) -> Dictionary:
	var result := {}
	var section := ""
	for raw in text.trim_prefix("\ufeff").split("\n"):
		var line := str(raw).split("//", true, 1)[0].strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		if section != "Misc" or not line.contains("="):
			continue
		var parts := line.split("=", true, 1)
		var key := str(parts[0]).strip_edges()
		if not key.is_empty():
			result[key] = str(parts[1]).strip_edges()
	return result

static func _ensure_loaded() -> void:
	if not _loaded:
		_loaded = true
		_values = parse_misc(RuntimeAssets.read_utf8_text(SOURCE))

static func numbers(key: String) -> Array[float]:
	_ensure_loaded()
	var result: Array[float] = []
	for part in str(_values.get(key, "")).split(","):
		var value := str(part).strip_edges()
		if not value.is_valid_float():
			push_error("MeleeGameConstants: 无效列表 %s" % key)
			return []
		result.append(value.to_float())
	return result

static func number(key: String, fallback: float) -> float:
	_ensure_loaded()
	var value := str(_values.get(key, ""))
	if not value.is_valid_float():
		push_error("MeleeGameConstants: 缺少或无效常量 %s (%s)" % [key, SOURCE])
		return fallback
	return value.to_float()

static func revive_gold(original: int, level: int) -> int:
	var factor := number("ReviveBaseFactor", 0.4) + number("ReviveLevelFactor", 0.1) * (level - 1)
	var cost := original * minf(factor, number("ReviveMaxFactor", 4.0))
	return maxi(0, floori(minf(cost, number("HeroMaxReviveCostGold", 700.0)) + 0.000000001))

static func revive_seconds(original: float, level: int) -> float:
	return maxf(0.0, minf(minf(original * level * number("ReviveTimeFactor", 0.65),
		original * number("ReviveMaxTimeFactor", 2.0)), number("HeroMaxReviveTime", 150.0)))
