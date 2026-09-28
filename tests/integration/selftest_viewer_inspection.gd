extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var viewer: Control = load("res://boot.tscn").instantiate()
	root.add_child(viewer)
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	assert(args.size() > 0, "Provide a real .scn absolute path")
	assert(viewer.preview_scene(args[0]))
	var frame_panel: HBoxContainer = _named(viewer, "AnimationFrames")
	var frame_input: SpinBox = _named(frame_panel, "CurrentFrame")
	assert(frame_input.editable and frame_input.max_value == 45)
	frame_input.value = 15
	assert(viewer.pause_button.button_pressed)
	assert(is_equal_approx(viewer.player.current_animation_position, 0.5))
	frame_input.value = frame_input.max_value
	assert(is_equal_approx(viewer.player.current_animation_position, 1.5))
	viewer.set_paused(false)
	viewer.player.advance(2.0)
	frame_panel._process(0.0)
	assert(frame_input.value == 45)
	viewer.player.seek(0.2, true)
	frame_panel._process(0.0)
	assert(frame_input.value == 6)
	for index: int in range(viewer.animations.item_count):
		if viewer.animations.get_item_text(index) == "DecayBone":
			viewer.animations.select(index)
			viewer._play_animation(index)
	frame_input.value = 1800
	for index: int in range(viewer.animations.item_count):
		if viewer.animations.get_item_text(index) == "Stand-1":
			viewer.animations.select(index)
			viewer._play_animation(index)
	assert(frame_input.value == 0 and frame_input.max_value == 45)
	assert(not viewer.pause_button.button_pressed)
	(_named(viewer, "ShowReport") as CheckButton).button_pressed = false
	assert(not viewer.details.visible)
	(_named(viewer, "ShowReport") as CheckButton).button_pressed = true
	assert(viewer.details.visible)
	var nodes: Tree = _named(viewer, "SceneNodes")
	assert(nodes.get_root() != null)
	nodes.get_root().select(0)
	viewer._inspect_node()
	assert("Node3D" in (_named(viewer, "NodeInfo") as RichTextLabel).text)
	(_named(viewer, "ShowNodes") as CheckButton).button_pressed = true
	(_named(viewer, "ShowAnimation") as CheckButton).button_pressed = true
	assert((_named(viewer, "Inspection") as Control).visible)
	assert("轨道数" in (_named(viewer, "AnimationInfo") as RichTextLabel).text)
	var camera: Camera3D = viewer.camera
	for direction: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		viewer.set_camera_view(direction)
		assert(camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
		assert(camera.basis.is_finite())
		assert(camera.basis.z.is_equal_approx(direction))
	viewer.reset_camera()
	assert(camera.projection == Camera3D.PROJECTION_PERSPECTIVE)
	viewer._restart()
	assert(nodes.get_root() != null)
	viewer._clear_model()
	assert(not frame_input.editable and frame_input.value == 0 and frame_input.max_value == 0)
	assert(nodes.get_root() == null)
	assert((_named(viewer, "AnimationInfo") as RichTextLabel).text == "无动画。")
	assert(viewer.preview_scene(args[0]))
	var team: OptionButton = _named(viewer, "Team")
	team.select(2)
	team.item_selected.emit(2)
	for node: Node in viewer._nodes(viewer.current_model):
		if node is MeshInstance3D and node.mesh != null:
			for surface: int in range(node.mesh.get_surface_count()):
				var material: Material = node.get_active_material(surface)
				if material is ShaderMaterial and material.has_meta("import_team_underlay"):
					assert(material.get_shader_parameter("use_team_texture") or material.get_shader_parameter("team_color_fallback") == MapPlaceholders.PLAYER_COLORS[1])
	await process_frame
	await process_frame
	if "--capture" in args:
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(args[0].get_base_dir().path_join("viewer-inspection.png"))
	print("PASS: frame display/seek/end/switch/clear, scene tree, animation metadata, six views and reload")
	quit(0)

func _named(start: Node, wanted: String) -> Node:
	var pending: Array[Node] = [start]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.name == wanted:
			return node
		for child: Node in node.get_children():
			pending.append(child)
	return null
