extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed: PackedScene = load("res://boot.tscn") as PackedScene
	var viewer: Control = packed.instantiate() as Control
	root.add_child(viewer)
	await process_frame
	assert(viewer.catalog.records.size() == 3)
	for entry: Dictionary in viewer.catalog.records:
		assert(viewer.select_model(str(entry.id)))
		await process_frame
		var count: int = 0
		for node: Node in viewer.current_model.find_children("*", "MeshInstance3D", true, false):
			if node.has_meta("import_ribbon"):
				count += 1
		assert(count > 0)
		viewer.fit_model()
		viewer.reset_camera()
		viewer.team.item_selected.emit(3)
	viewer._clear_model()
	viewer.queue_free()
	await process_frame
	print("Ribbon viewer PASS")
	quit()
