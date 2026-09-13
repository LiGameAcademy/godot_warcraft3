extends Node
var failed := 0


func check(value: bool, message: String) -> void:
	if not value:
		failed += 1
		push_error(message)


func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This test requires a real renderer: dummy MultiMesh readback does not report transforms.")
		get_tree().quit(1)
		return
	var scene = preload("res://editor/scenes/editor_main.tscn").instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var doc = editor.get_document()
	var layer = editor.map_root._doodads
	var entries: Array = []
	for i in range(8):
		var entry: Dictionary = doc.make_doodad_entry("LTlt", i * 128, 0)
		entry.creationNumber = i + 1
		entry.angle = deg_to_rad(23.0 + i * 37.0)
		entries.append(entry)
	# Explicitly build a batch from the original model to exercise the batch branch,
	# even if catalog animation flags select single instances in normal loading.
	var glb: String = editor.map_root.get_id_catalog().converted_glb_path("LTlt", 0)
	check(layer._place_multimesh_group("LTlt", 0, glb, entries), "original mesh batch builds")
	doc.heightfield.heights.fill(128.0)
	layer.refresh_heights(doc.heightfield)
	for cn in range(1, 9):
		_check_batch_height(layer, cn, 128.0)
	var promoted: Node3D = layer.ensure_promoted(1)
	check(promoted != null, "batch member can be promoted")
	check(promoted.basis.x.normalized().distance_to(Vector3(cos(entries[0].angle), 0, -sin(entries[0].angle))) < 0.0001, "promotion preserves source facing")
	check(is_equal_approx(promoted.position.y, 128.0 * Wc3Coords.WORLD_SCALE), "promotion retains updated terrain height")
	check(layer.remove_by_creation_number(2), "remove batch member")
	doc.heightfield.heights.fill(256.0)
	layer.refresh_heights(doc.heightfield)
	for cn in range(3, 9):
		_check_batch_height(layer, cn, 256.0)
	check(is_equal_approx(promoted.position.y, 256.0 * Wc3Coords.WORLD_SCALE), "promoted node follows next terrain edit")
	var batch: Dictionary = layer._mm_by_cn[3]
	for child in batch.root.get_children():
		if child is MultiMeshInstance3D:
			check(is_zero_approx(child.multimesh.get_instance_transform(0).basis.determinant()), "promoted batch slot stays hidden")
			check(is_zero_approx(child.multimesh.get_instance_transform(1).basis.determinant()), "deleted batch slot stays hidden")
	doc.heightfield.heights.fill(0.0)
	layer.refresh_heights(doc.heightfield)
	for cn in range(3, 9):
		_check_batch_height(layer, cn, 0.0)
	check(is_zero_approx(promoted.position.y), "returning terrain to original height restores promoted node")
	await get_tree().process_frame
	print("selftest_doodad_batch_height: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	get_tree().quit(0 if failed == 0 else 1)


func _check_batch_height(layer, cn: int, height: float) -> void:
	var info: Dictionary = layer._mm_by_cn[cn]
	for child in info.root.get_children():
		if child is MultiMeshInstance3D:
			var xf: Transform3D = child.multimesh.get_instance_transform(info.index)
			check(is_equal_approx(xf.origin.y, height * Wc3Coords.WORLD_SCALE), "batch geometry follows terrain height")
			var angle := float(info.entry.angle)
			check(xf.basis.x.normalized().distance_to(Vector3(cos(angle), 0, -sin(angle))) < 0.0001, "GPU batch transform preserves source facing")
	check(is_equal_approx(float(info.entry.position.z), height), "batch entry updated for later promotion")
