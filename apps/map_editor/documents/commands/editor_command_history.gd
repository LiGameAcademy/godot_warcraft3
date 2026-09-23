class_name EditorCommandHistory
extends RefCounted

## 撤销/重做栈。笔划类命令用 record()（已落地）；其它用 execute()。


signal changed
## should_rebuild：record 为 false（笔刷会自己请求重建）；undo/redo/execute 为 true
signal command_applied(cmd: EditorCommand, is_undo: bool, should_rebuild: bool)

const DEFAULT_LIMIT := 64

var undo_stack: Array[EditorCommand] = []
var redo_stack: Array[EditorCommand] = []
var limit: int = DEFAULT_LIMIT
var document = null ## MapDocument


func bind_document(doc) -> void:
	document = doc


func clear() -> void:
	undo_stack.clear()
	redo_stack.clear()
	changed.emit()


func can_undo() -> bool:
	return not undo_stack.is_empty()


func can_redo() -> bool:
	return not redo_stack.is_empty()


## 执行尚未落地的命令。
func execute(cmd: EditorCommand) -> void:
	if cmd == null or document == null:
		return
	cmd.execute(document)
	_push_undo(cmd)
	redo_stack.clear()
	changed.emit()
	command_applied.emit(cmd, false, true)


## 笔划已写入 Document，只入栈（不触发重建，避免与笔刷 rebuild 打架）。
func record(cmd: EditorCommand) -> void:
	if cmd == null:
		return
	_push_undo(cmd)
	redo_stack.clear()
	changed.emit()
	command_applied.emit(cmd, false, false)


func undo() -> EditorCommand:
	if not can_undo() or document == null:
		return null
	var cmd: EditorCommand = undo_stack.pop_back()
	cmd.undo(document)
	redo_stack.append(cmd)
	changed.emit()
	command_applied.emit(cmd, true, true)
	return cmd


func redo() -> EditorCommand:
	if not can_redo() or document == null:
		return null
	var cmd: EditorCommand = redo_stack.pop_back()
	cmd.execute(document)
	undo_stack.append(cmd)
	changed.emit()
	command_applied.emit(cmd, false, true)
	return cmd


func _push_undo(cmd: EditorCommand) -> void:
	undo_stack.append(cmd)
	while undo_stack.size() > limit:
		undo_stack.pop_front()
