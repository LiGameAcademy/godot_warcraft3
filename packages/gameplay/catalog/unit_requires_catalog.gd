class_name UnitRequiresCatalog
extends RefCounted

## 解析 *UnitFunc.txt 的 Requires=（AND 列表）。
## 数据权威：assets/slk-exported/Units/*UnitFunc.txt
##
## 竖切用法：建造/训练按钮置灰 + tooltip「需要：…」。
## 不含 Requires1/Requires2（英雄科技档 / 升级档，后置）。

const FOLDER := "res://assets/slk-exported/Units"

static var _shared: UnitRequiresCatalog = null

## unit_id → PackedStringArray（Require 建筑/单位 id）
var _requires: Dictionary = {}
var _loaded_files: Dictionary = {}


static func get_shared() -> UnitRequiresCatalog:
	if _shared == null:
		_shared = UnitRequiresCatalog.new()
	return _shared


func _init() -> void:
	_ensure_file("HumanUnitFunc.txt")
	_ensure_file("OrcUnitFunc.txt")
	_ensure_file("UndeadUnitFunc.txt")
	_ensure_file("NightElfUnitFunc.txt")


## 该单位/建筑的 Requires= 列表（空 = 无前置建筑需求）。
func get_requires(unit_id: String) -> PackedStringArray:
	var uid := unit_id.strip_edges()
	if uid.is_empty():
		return PackedStringArray()
	var arr = _requires.get(uid, null)
	if arr == null:
		return PackedStringArray()
	var out := PackedStringArray()
	for r in arr:
		out.append(str(r))
	return out


## 测试用覆盖。
func register(unit_id: String, requires: PackedStringArray) -> void:
	_requires[unit_id.strip_edges()] = requires.duplicate()


func _ensure_file(file_name: String) -> void:
	var full := FOLDER.path_join(file_name)
	if _loaded_files.has(full):
		return
	var text := RuntimeAssets.read_utf8_text(full)
	_loaded_files[full] = true
	if text.is_empty():
		return
	_parse_file(text)


func _parse_file(text: String) -> void:
	var section := ""
	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges()
			continue
		if section.is_empty():
			continue
		# 只取键名恰好为 Requires（忽略 Requires1/Requires2/Requirescount）
		var eq := line.find("=")
		if eq <= 0:
			continue
		var key := line.substr(0, eq).strip_edges()
		if key != "Requires":
			continue
		var raw_val := line.substr(eq + 1).strip_edges()
		var list: Array = []
		var seen: Dictionary = {}
		for piece in raw_val.split(","):
			var s := String(piece).strip_edges()
			if s.is_empty() or seen.has(s):
				continue
			seen[s] = true
			list.append(s)
		_requires[section] = list
