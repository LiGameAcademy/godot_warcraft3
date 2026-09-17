extends Node
class DragBrush extends "res://editor/scripts/tools/unit_brush.gd":
	var hit := Vector3.ZERO
	func _ground_at(_screen: Vector2) -> Vector3:
		return hit
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	var scene = preload("res://editor/scenes/editor_main.tscn").instantiate()
	add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var brush = editor.unit_brush
	var doc = editor.get_document()
	var raw := Vector2(173.3, -218.7)
	var catalog = editor.map_root.get_id_catalog()
	for id in ["hhou", "htow", "ngol", "hpea"]:
		var info: Dictionary = catalog.lookup(id)
		var snapped: Vector2 = brush._snap_position(raw, id)
		if id == "hpea":
			check(snapped == raw, "ordinary units keep exact coordinates")
		else:
			check(snapped != raw, "building snaps " + id)
			var fp := UnitPlacementRules.footprint_cells(info)
			var minimum: Vector2 = (snapped - doc.pathing.origin_wc3) / doc.pathing.cell_size - Vector2(fp)*0.5
			check(minimum.distance_to(minimum.round()) < 0.001, "footprint edges align " + id)
		brush.type_id = id
		brush.random_rotation = false
		var destination := raw + Vector2(1200 * doc.units.count(), 0)
		var expected: Vector2 = brush._snap_position(destination, id)
		var before: int = doc.units.count()
		brush._place_one(destination.x, destination.y)
		check(doc.units.count() == before + 1, "placement succeeds " + id)
		if doc.units.count() > before:
			var p: Dictionary = doc.get_unit(before).position
			check(Vector2(p.x,p.y).distance_to(expected) < 0.001, "saved location matches preview snapping " + id)
	var drag := DragBrush.new()
	add_child(drag)
	drag.setup(doc, editor.camera_rig.get_camera(), get_viewport().world_3d, editor.get_history(), editor.map_root)
	var entry: Dictionary = doc.get_unit(0).duplicate(true)
	var cn := int(entry.creationNumber)
	drag._selected_cns = PackedInt32Array([cn])
	drag._begin_drag(cn)
	drag.hit = Wc3Coords.wc3_xy_to_godot(-541.7, -803.2)
	drag._drag_to(Vector2.ZERO)
	drag._end_drag()
	var moved: Dictionary = drag._entry_by_cn(cn).duplicate(true)
	var expected_drag: Vector2 = drag._snap_position(Vector2(-541.7,-803.2), "hhou")
	check(Vector2(moved.position.x,moved.position.y).distance_to(expected_drag) < 0.001, "drag uses building grid")
	editor.get_history().undo()
	check(drag._entry_by_cn(cn).position == entry.position, "undo restores pre-drag position")
	editor.get_history().redo()
	check(drag._entry_by_cn(cn).position == moved.position, "redo restores snapped position")
	drag.queue_free()
	var odd := {"is_building": true, "path_tex": "PathTextures\\3x5.tga"}
	var p := UnitPlacementRules.snap_editor_position(Vector2(-17, 53), odd, Vector2(-64,-64), 32)
	var fp := UnitPlacementRules.footprint_cells(odd)
	var minimum: Vector2 = (p - Vector2(-64,-64))/32 - Vector2(fp)*0.5
	check(minimum.distance_to(minimum.round()) < 0.001, "odd footprint and negative coordinates")
	print("selftest_building_snap: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

