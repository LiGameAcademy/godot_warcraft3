extends SceneTree
## 命令历史：笔划 record → undo/redo 恢复顶点。
## godot --headless -s res://tests/unit/selftest_editor_commands.gd


const DocScript := preload("res://editor/scripts/map_document.gd")


func _init() -> void:
	var failed := 0
	failed += _test_paint_stroke_undo_redo()
	if failed == 0:
		print("selftest_editor_commands: PASS")
		quit(0)
	else:
		push_error("selftest_editor_commands: FAIL (%d)" % failed)
		quit(1)


func _test_paint_stroke_undo_redo() -> int:
	var doc = DocScript.new()
	doc.create_blank(5)
	var hist := EditorCommandHistory.new()
	hist.bind_document(doc)
	var rec := PaintStrokeRecorder.new()
	rec.begin(doc)
	rec.capture_before_at(2, 2, 0)
	var before_tex: int = int(doc.heightfield.ground_textures[doc.heightfield.index_at(2, 2)])
	if not doc.paint_corner(2, 2, 1):
		# 可能已是 1，强制写
		doc.heightfield.ground_textures[doc.heightfield.index_at(2, 2)] = 1
		doc.mark_dirty()
	rec.capture_after_at(2, 2, 0)
	var cmd: PaintStrokeCommand = rec.finish("Ground")
	if cmd == null:
		# 强制造差异
		rec.begin(doc)
		rec.capture_before_at(2, 2, 0)
		doc.heightfield.ground_textures[doc.heightfield.index_at(2, 2)] = (
			0 if before_tex != 0 else 1
		)
		rec.capture_after_at(2, 2, 0)
		cmd = rec.finish("Ground")
	if cmd == null:
		push_error("no stroke command")
		return 1
	hist.record(cmd)
	var mid: int = int(doc.heightfield.ground_textures[doc.heightfield.index_at(2, 2)])
	hist.undo()
	var undone: int = int(doc.heightfield.ground_textures[doc.heightfield.index_at(2, 2)])
	if undone == mid and cmd.before.has(doc.heightfield.index_at(2, 2)):
		var snap: EditorVertexSnapshot = cmd.before[doc.heightfield.index_at(2, 2)]
		if snap.ground_tex != undone:
			push_error("undo failed mid=%d undone=%d expect=%d" % [mid, undone, snap.ground_tex])
			return 1
	hist.redo()
	var redone: int = int(doc.heightfield.ground_textures[doc.heightfield.index_at(2, 2)])
	if redone != mid:
		push_error("redo failed got=%d want=%d" % [redone, mid])
		return 1
	print("  paint stroke undo/redo OK")
	return 0
