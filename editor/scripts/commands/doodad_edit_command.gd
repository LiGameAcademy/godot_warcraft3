extends EditorCommand
## 装饰物增删改命令。笔刷操作已写入 Document 时用 history.record()；undo/redo 走 execute/undo。
## （不用 class_name；由 doodad_brush preload 引用）


enum Op { ADD, REMOVE, MODIFY }

var _op: int = Op.ADD
var _entries: Array = [] ## ADD/REMOVE: [{ entry }]；MODIFY: [{ before, after }]
var _label: String = "Doodad"


func get_label() -> String:
	return _label


func affects_doodads() -> bool:
	return true


## 已 add 到 Document 的条目；undo 时按 creationNumber 删除。
static func make_add(entries: Array, label: String = "Place Doodad") -> EditorCommand:
	var cmd = new()
	cmd._op = Op.ADD
	cmd._label = label
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		cmd._entries.append({"entry": (e as Dictionary).duplicate(true)})
	return cmd


## 已从 Document 删除的条目；undo 时按原样加回。
static func make_remove(entries: Array, label: String = "Delete Doodad") -> EditorCommand:
	var cmd = new()
	cmd._op = Op.REMOVE
	cmd._label = label
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		cmd._entries.append({"entry": (e as Dictionary).duplicate(true)})
	return cmd


## 已修改 Document；undo 恢复 before，redo 应用 after（按 creationNumber 对齐）。
static func make_modify(befores: Array, afters: Array, label: String = "Edit Doodad") -> EditorCommand:
	var cmd = new()
	cmd._op = Op.MODIFY
	cmd._label = label
	var n: int = mini(befores.size(), afters.size())
	for i in range(n):
		if typeof(befores[i]) != TYPE_DICTIONARY or typeof(afters[i]) != TYPE_DICTIONARY:
			continue
		cmd._entries.append({
			"before": (befores[i] as Dictionary).duplicate(true),
			"after": (afters[i] as Dictionary).duplicate(true),
		})
	return cmd


func execute(document) -> void:
	if document == null:
		return
	match _op:
		Op.ADD:
			for item in _entries:
				var entry: Dictionary = item.get("entry", {})
				if entry.is_empty():
					continue
				document.add_doodad(entry.duplicate(true))
		Op.REMOVE:
			for item in _entries:
				var entry2: Dictionary = item.get("entry", {})
				var cn: int = int(entry2.get("creationNumber", -1))
				if cn >= 0:
					document.remove_doodad_by_creation_number(cn)
		Op.MODIFY:
			for item in _entries:
				var after: Dictionary = item.get("after", {})
				var cn2: int = int(after.get("creationNumber", -1))
				if cn2 >= 0 and not after.is_empty():
					document.update_doodad_by_creation_number(cn2, after.duplicate(true))


func undo(document) -> void:
	if document == null:
		return
	match _op:
		Op.ADD:
			for item in _entries:
				var entry: Dictionary = item.get("entry", {})
				var cn: int = int(entry.get("creationNumber", -1))
				if cn >= 0:
					document.remove_doodad_by_creation_number(cn)
		Op.REMOVE:
			for item in _entries:
				var entry2: Dictionary = item.get("entry", {})
				if entry2.is_empty():
					continue
				document.add_doodad(entry2.duplicate(true))
		Op.MODIFY:
			for item in _entries:
				var before: Dictionary = item.get("before", {})
				var cn3: int = int(before.get("creationNumber", -1))
				if cn3 >= 0 and not before.is_empty():
					document.update_doodad_by_creation_number(cn3, before.duplicate(true))
