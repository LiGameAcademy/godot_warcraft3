extends SceneTree
## Exercise the read-only sample report through the real viewer, not a mock UI.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1440, 900)
	var packed: PackedScene = load("res://boot.tscn")
	var viewer: Control = packed.instantiate()
	root.add_child(viewer)
	await process_frame
	assert(viewer.catalog.records.size() == 3)
	for entry: Dictionary in viewer.catalog.records:
		assert(viewer.select_model(str(entry.id)))
		assert(viewer.current_model.has_meta("wc3_import_worker_version"))
		assert(viewer.models_root.get_child_count() == 1)
		assert(viewer.frame_controls.loop_toggle.button_pressed)
		viewer.team.select(3)
		viewer.team.item_selected.emit(3)
		viewer.set_camera_view(Vector3.UP)
		await process_frame
		viewer.reset_camera()
		if str(entry.id).ends_with("heroarchmage"):
			var glow_found: bool = false
			for mesh: MeshInstance3D in viewer.current_model.find_children("*", "MeshInstance3D", true, false):
				for surface: int in range(mesh.mesh.get_surface_count()):
					var material: Material = mesh.get_active_material(surface)
					if material is ShaderMaterial and material.has_meta("import_team_glow"):
						assert(material.get_shader_parameter("recolor") == true)
						glow_found = true
			assert(glow_found)
	print("FX viewer PASS: sample report, three selections, recoloring and camera controls")
	viewer._clear_model()
	viewer.queue_free()
	await process_frame
	quit()
