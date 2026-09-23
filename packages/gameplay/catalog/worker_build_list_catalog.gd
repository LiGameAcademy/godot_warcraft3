class_name WorkerBuildListCatalog
extends RefCounted

## F2-D 数据驱动：解析 *UnitFunc.txt 里的 Builds= 字段。
## 数据权威：assets/slk-exported/Units/*UnitFunc.txt（同步自 sync-data-assets）。
##
## 来源：docs/design/game/BUILD_SYSTEM.md §2.1
##   "不在 UnitUI / UnitBalance 里，而在种族 Func。运行时权威路径
##    （经 sync-data-assets，禁止读 .cache）"
##
## 用法：
##   var builds: PackedStringArray = WorkerBuildListCatalog.get_builds("hpea")
##   if WorkerBuildListCatalog.can_build("hpea", "halt"):
##       CommandRouter.issue_build(builders, "halt", site_wc3)

const FOLDER := "res://assets/slk-exported/Units"

## unit_id (4 字符) → Builds 列表（去重 + 顺序保持）
var _by_unit: Dictionary = {}

## 缓存已解析的文件路径
var _loaded: Dictionary = {}


func _init() -> void:
	_ensure_loaded("hpea", "Human")
	_ensure_loaded("opeo", "Orc")
	_ensure_loaded("ewsp", "NightElf")
	_ensure_loaded("uaco", "Undead")
	_ensure_loaded("npea", "Naga")
	_ensure_loaded("nfoh", "Naga")
	_ensure_loaded("nmrl", "Naga")
	_ensure_loaded("nban", "Naga")


## 拿 unit_id 的 Builds 列表（4 字符建筑 id 数组）。
## 没记录 → 返空数组。
func get_builds(unit_id: String) -> PackedStringArray:
	if unit_id.is_empty():
		return PackedStringArray()
	var arr = _by_unit.get(unit_id, null)
	if arr == null:
		return PackedStringArray()
	var out := PackedStringArray()
	for b in arr:
		out.append(b)
	return out


## unit_id 能否造 building_id。
func can_build(unit_id: String, building_id: String) -> bool:
	if unit_id.is_empty() or building_id.is_empty():
		return false
	return _by_unit.get(unit_id, []).has(building_id)


## 注册 / 覆盖（测试用：selftest 直接构造数据）
func register(unit_id: String, buildings: PackedStringArray) -> void:
	_by_unit[unit_id] = buildings.duplicate()


## 全表 unit_id 列表（命令卡过滤可用）
func get_units() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _by_unit.keys():
		out.append(String(k))
	return out


func _ensure_loaded(unit_id: String, race: String) -> void:
	# 尝试多个文件前缀（Melee_V0/Custom_V0…），取第一个存在
	var race_files := {
		"Human": "HumanUnitFunc.txt",
		"Orc": "OrcUnitFunc.txt",
		"NightElf": "NightElfUnitFunc.txt",
		"Undead": "UndeadUnitFunc.txt",
		"Naga": "NagaUnitFunc.txt",
	}
	var fn: String = race_files.get(race, "")
	if fn.is_empty():
		return
	var full_path := FOLDER.path_join(fn)
	if _loaded.has(full_path):
		return
	var text := RuntimeAssets.read_utf8_text(full_path)
	if text.is_empty():
		return
	_loaded[full_path] = true
	_parse_into(text, unit_id)


## 极简 SLK 文本解析：定位 [unit_id] 段 → 找 Builds= 行
func _parse_into(text: String, target_unit: String) -> void:
	var in_section := false
	var lines := text.split("\n")
	for raw in lines:
		var line := String(raw).strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("[") and line.ends_with("]"):
			var section_id: String = line.substr(1, line.length() - 2).strip_edges()
			in_section = (section_id == target_unit)
			continue
		if not in_section:
			continue
		if line.begins_with("Builds="):
			var raw_val := line.substr("Builds=".length()).strip_edges()
			# 去重 + 保持顺序
			var seen: Dictionary = {}
			var list: Array = []
			for piece in raw_val.split(","):
				var s := String(piece).strip_edges()
				if s.is_empty():
					continue
				if seen.has(s):
					continue
				seen[s] = true
				list.append(s)
			_by_unit[target_unit] = list
			return
