class_name UnitRequiresCatalog
extends RefCounted

const DefinitionLayers: GDScript = preload("res://addons/rts_content/definitions/definition_layers.gd")

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
	var rows: Dictionary = DefinitionLayers.read_rows("Units/" + file_name)
	_loaded_files[full] = true
	for id: String in rows:
		var row: Dictionary = rows[id]
		var requires: PackedStringArray = []
		for piece: String in str(row.get("requires", "")).split(","):
			var value: String = piece.strip_edges()
			if not value.is_empty() and not requires.has(value):
				requires.append(value)
		_requires[id] = requires
