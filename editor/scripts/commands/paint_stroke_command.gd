class_name PaintStrokeCommand
extends EditorCommand

## 一次笔划（按下→抬起）内改动的顶点 before/after。
## 数据在笔刷过程中已写入 Document；record 时不再 execute。


var before: Dictionary = {} ## int index → EditorVertexSnapshot
var after: Dictionary = {}
var _affects_cliff: bool = false
var _label: String = "Paint"


func _init(
	p_before: Dictionary = {},
	p_after: Dictionary = {},
	p_affects_cliff: bool = false,
	p_label: String = "Paint"
) -> void:
	before = p_before
	after = p_after
	_affects_cliff = p_affects_cliff
	_label = p_label


func get_label() -> String:
	return "%s (%d verts)" % [_label, after.size()]


func affects_cliffs_water() -> bool:
	return _affects_cliff


func execute(document) -> void:
	_apply_map(document, after)


func undo(document) -> void:
	_apply_map(document, before)


func _apply_map(document, snaps: Dictionary) -> void:
	if document == null or document.heightfield == null:
		return
	var hf: Wc3Heightfield = document.heightfield
	for k in snaps.keys():
		var snap: EditorVertexSnapshot = snaps[k] as EditorVertexSnapshot
		if snap != null:
			snap.apply(hf)
	if document.has_method("mark_dirty"):
		document.mark_dirty()
