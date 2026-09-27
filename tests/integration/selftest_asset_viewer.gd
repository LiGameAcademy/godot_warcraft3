extends SceneTree
## Uses real installed assets. Optional --capture saves real rendered UI evidence.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var scene: PackedScene = load("res://boot.tscn") as PackedScene
	var viewer: Control = scene.instantiate() as Control
	root.add_child(viewer)
	await process_frame
	_check(viewer.catalog.records.size() > 0, "No installed assets; viewer integration requires an audit or baked library")
	_check(viewer.environment.environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "Preview must have color ambient light without a sky")
	_check(viewer.model_tree.visible and not viewer.models.visible, "Tree should be the default browser")
	for model_id: String in ["abilities/weapons/priestmissile/priestmissile", "abilities/weapons/fireballmissile/fireballmissile", "units/human/heroarchmage/heroarchmage"]:
		_check(viewer.select_model(model_id), "Cannot load " + model_id)
		if viewer.current_model == null:
			continue
		_check(viewer.models_root.get_child_count() == 1, "Selection retained old model")
		viewer.set_paused(true)
		var before: float = viewer.player.current_animation_position if viewer.player != null else 0.0
		await create_timer(0.05).timeout
		if viewer.player != null:
			_check(is_equal_approx(before, viewer.player.current_animation_position), "Animation advanced while paused")
		viewer.set_paused(false)
		viewer._restart()
		_check(viewer.models_root.get_child_count() == 1, "Restart retained old instance")
		for frame: int in range(30):
			await process_frame
	viewer.search.text = "HeroArchMage"
	viewer.search.text_changed.emit(viewer.search.text)
	_check(viewer.models.item_count > 0 and viewer.models.item_count < viewer.catalog.records.size(), "Search did not filter")
	viewer.team.select(2)
	viewer.team.item_selected.emit(2)
	_check(viewer.current_model != null, "Team color change lost model")
	var previous_instance: int = viewer.current_model.get_instance_id()
	viewer.set_paused(true)
	viewer.set_browser_mode(1)
	_check(viewer.models.visible and not viewer.model_tree.visible, "List mode did not switch")
	viewer.set_browser_mode(0)
	_check(viewer.current_model.get_instance_id() == previous_instance and viewer.pause_button.button_pressed, "Browser mode switch restarted the model")
	_check(viewer.model_tree.get_selected() == viewer._tree_items.get(str(viewer.selected_record["id"])), "Tree did not preserve selection")
	viewer.search.text = "Footman"
	viewer.search.text_changed.emit(viewer.search.text)
	_check(viewer._tree_items.size() == viewer.models.item_count, "Tree and list filters disagree")
	var footman: TreeItem = viewer._tree_items.get("units/human/footman/footman") as TreeItem
	_check(footman != null, "Footman tree leaf missing")
	if footman != null:
		footman.select(0)
		viewer.model_tree.item_selected.emit()
		_check(viewer.selected_record.get("id") == "units/human/footman/footman", "Tree selection did not load Footman")
		_check(viewer.current_model != null, "Footman scene failed to load")
	viewer._set_tree_expanded(false)
	_check((viewer._folder_items.get("Units") as TreeItem).collapsed, "Collapse folders failed")
	viewer._set_tree_expanded(true)
	_check(not (viewer._folder_items.get("Units") as TreeItem).collapsed, "Expand folders failed")
	viewer.team.select(3)
	viewer.team.item_selected.emit(3)
	for index: int in range(viewer.animations.item_count):
		if viewer.animations.get_item_text(index) == "Attack-1":
			viewer.animations.select(index)
			viewer.animations.item_selected.emit(index)
			break
	for frame: int in range(30):
		await process_frame
	if "--capture" in OS.get_cmdline_user_args() and failures.is_empty():
		viewer.set_paused(true)
		# Reproduce the previous lighting with exactly the same model, pose and camera.
		viewer.environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		viewer.environment.environment.ambient_light_sky_contribution = 1.0
		for frame: int in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var before_image: Image = viewer.viewport.get_texture().get_image()
		DirAccess.make_dir_recursive_absolute("res://tmp")
		_check(root.get_texture().get_image().save_png("res://tmp/asset-viewer-footman-before.png") == OK, "Before screenshot failed")
		viewer.environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		viewer.environment.environment.ambient_light_sky_contribution = 0.0
		for frame: int in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var after_image: Image = viewer.viewport.get_texture().get_image()
		var before_light: float = _center_light(before_image)
		var after_light: float = _center_light(after_image)
		_check(after_light > before_light * 1.03, "Color ambient light did not improve the rendered Footman")
		print("Footman center luminance: %.4f -> %.4f" % [before_light, after_light])
		var error: Error = root.get_texture().get_image().save_png("res://tmp/asset-viewer-footman-after.png")
		_check(error == OK, "Screenshot save failed")
	viewer.queue_free()
	await process_frame
	print("selftest_asset_viewer %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)


func _center_light(image: Image) -> float:
	var light: float = 0.0
	var samples: int = 0
	for y: int in range(image.get_height() / 4, image.get_height() * 3 / 4, 3):
		for x: int in range(image.get_width() / 4, image.get_width() * 3 / 4, 3):
			light += image.get_pixel(x, y).get_luminance()
			samples += 1
	return light / maxf(samples, 1)
