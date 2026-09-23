extends SceneTree
const Doc := preload("res://documents/map_document.gd")
const Sculpt := preload("res://addons/rts_map/logic/terrain/height_sculpt.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var doc = Doc.new()
	doc.create_blank(9)
	var hf: Wc3Heightfield = doc.heightfield
	var index := hf.index_at(4, 4)
	var layers := hf.layer_heights.duplicate()
	var water := hf.water_heights.duplicate()
	var points: Array = [Vector2i(4, 4), Vector2i(4, 4), Vector2i(-1, 0)]
	check(doc.sculpt_height(points, Sculpt.Tool.RAISE), "raise changes height")
	check(hf.heights[index] == 16, "one step, no duplicate point application")
	check(doc.sculpt_height(points, Sculpt.Tool.LOWER) and hf.heights[index] == 0, "lower reverses raise")
	check(doc.sculpt_height(points, Sculpt.Tool.PLATEAU, 48) and hf.heights[index] == 48, "plateau anchor offset")
	check(doc.sculpt_height(points, Sculpt.Tool.SMOOTH), "smooth changes peak")
	check(is_equal_approx(hf.heights[index], 48.0 * 5.0 / 9.0), "smooth uses immutable 3x3 average")
	var start: float = hf.heights[index]
	seed(1234)
	doc.sculpt_height(points, Sculpt.Tool.NOISE)
	check(absf(hf.heights[index] - start) <= Sculpt.STEP, "noise is bounded")
	check(hf.layer_heights == layers and hf.water_heights == water, "cliff layers and water planes unchanged")
	var a := Wc3Heightfield.from_dict(hf.to_dict())
	var b := Wc3Heightfield.from_dict(hf.to_dict())
	var adjacent: Array = [Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 4)]
	Sculpt.apply(a, adjacent, Sculpt.Tool.SMOOTH)
	adjacent.reverse()
	Sculpt.apply(b, adjacent, Sculpt.Tool.SMOOTH)
	check(a.heights == b.heights, "smooth independent of point order")
	var history := EditorCommandHistory.new()
	history.bind_document(doc)
	var recorder := PaintStrokeRecorder.new()
	recorder.begin(doc)
	recorder.capture_before_at(4, 4)
	var before := hf.heights.duplicate()
	doc.sculpt_height(points, Sculpt.Tool.RAISE)
	recorder.capture_after_at(4, 4)
	recorder.mark_cliff()
	history.record(recorder.finish("Height"))
	var after := hf.heights.duplicate()
	history.undo()
	check(hf.heights == before, "height undo exact")
	history.redo()
	check(hf.heights == after, "height redo exact")
	print("selftest_height_sculpt: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
