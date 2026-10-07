extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1440, 900)
	var packed: PackedScene = load("res://boot.tscn") as PackedScene
	var viewer: Control = packed.instantiate() as Control
	root.add_child(viewer)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://tmp")
	var assets: Array[String] = ["units/human/footman/footman", "abilities/weapons/priestmissile/priestmissile", "units/human/heroarchmage/heroarchmage", "abilities/spells/nightelf/rejuvenation/rejuvenationtarget"]
	for asset_id: String in assets:
		if not viewer.select_model(asset_id) or not viewer.current_model.has_meta("wc3_import_worker_version"):
			push_error("Cannot load source-import scene: " + asset_id)
			quit(1)
			return
		viewer.set_paused(false)
		await create_timer(0.6).timeout
		viewer.set_paused(true)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if image.save_png("res://tmp/source-" + asset_id.get_file() + ".png") != OK:
			quit(1)
			return
	viewer._clear_model()
	viewer.queue_free()
	await process_frame
	print("PASS: four release source-import scenes rendered in read-only viewer")
	quit(0)
