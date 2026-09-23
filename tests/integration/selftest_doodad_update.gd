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
	var scene = preload("res://scenes/editor_main.tscn").instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var doc = editor.get_document()
	var loader = editor.map_root
	var hf: Dictionary = doc.as_build_dict()
	var entry: Dictionary = doc.make_doodad_entry("LTlt", 0, 0)
	entry.creationNumber = 77
	entry.variation = 0
	entry.scale = {"x": 1.5, "y": 0.75, "z": 2.0}
	check(loader.add_doodad_instance(entry, hf), "add original tree")
	var original: Node3D = loader.find_doodad_node(77)
	check(original != null and loader._doodads.last_placeholder == 0, "original asset instantiated")
	var initial_scale: Vector3 = original.scale
	for i in range(20):
		var changed := entry.duplicate(true)
		changed.position.x = 128.0 * (i + 1)
		changed.angle = deg_to_rad(15.0 * i)
		check(loader.update_doodad_instance(changed, hf), "update tree %d" % i)
		var current: Node3D = loader.find_doodad_node(77)
		check(current == original, "transform preserves model identity")
		check(current.scale.is_equal_approx(initial_scale), "repeated update does not compound scale")
		check(is_equal_approx(current.position.x, changed.position.x * Wc3Coords.WORLD_SCALE), "model follows new position")
		check(is_equal_approx(current.rotation.y, Wc3Coords.yaw_wc3_to_godot(changed.angle)), "model follows new facing")
		var footprints: Array = loader.get_pathing_doodad_entries()
		check(footprints.size() == 1 and footprints[0].position.x == changed.position.x, "only current footprint retained")
		await get_tree().process_frame
	var variant := entry.duplicate(true)
	variant.variation = 1
	check(loader.update_doodad_instance(variant, hf), "variant change rebuilds model")
	check(loader.find_doodad_node(77) != original, "different variant replaces instance")
	check(loader.get_pathing_doodad_entries().size() == 1, "variant replacement keeps one footprint")
	await get_tree().process_frame
	check(not is_instance_valid(original), "replaced model freed after frame")
	check(loader.remove_doodad_instance(77), "delete replacement")
	check(loader.find_doodad_node(77) == null and loader.get_pathing_doodad_entries().is_empty(), "deletion removes model and footprint immediately")
	await get_tree().process_frame
	print("selftest_doodad_update: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	get_tree().quit(0 if failed == 0 else 1)
