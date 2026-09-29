extends SceneTree
## Run in the isolated FX project; scenes must reload without converter/game code.
var _held_materials: Array[Material] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(3, 2, 4)
	camera.look_at(Vector3(0, 0.5, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.07, 0.09, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	root.add_child(environment)
	for stem: String in ["PriestMissile", "FireBallMissile", "HeroArchMage"]:
		var packed: PackedScene = load("res://" + stem + ".scn")
		assert(packed != null)
		var instance: Node3D = packed.instantiate()
		var other: Node3D = packed.instantiate()
		root.add_child(instance)
		var particles: Array[Node] = instance.find_children("*", "GPUParticles3D", true, false)
		var others: Array[Node] = other.find_children("*", "GPUParticles3D", true, false)
		assert(particles.size() == (2 if stem == "PriestMissile" else 3))
		assert(particles[0].process_material != others[0].process_material)
		var original_gravity: Vector3 = others[0].process_material.gravity
		particles[0].process_material.gravity = Vector3(9, 8, 7)
		assert(others[0].process_material.gravity == original_gravity)
		particles[0].process_material.gravity = original_gravity
		var player: AnimationPlayer = instance.find_children("*", "AnimationPlayer", true, false)[0]
		var stand: String = "Stand1" if stem == "HeroArchMage" else "Stand"
		assert(player.get_animation(stand).loop_mode == Animation.LOOP_LINEAR)
		assert(player.get_animation("Death").loop_mode == Animation.LOOP_NONE)
		assert(player.get_animation(stand).get_meta("source_looping") == true)
		player.play(stand)
		player.advance(0)
		await process_frame
		_check_cycles(player, instance, stand)
		_check_billboard(instance, camera)
		_check_material_isolation(instance, other)
		assert(not particles[0].emitting if stem == "PriestMissile" or stem == "HeroArchMage" else particles[0].emitting)
		await create_timer(0.3).timeout
		await _capture(stem + "-Stand")
		player.play("Attack-1" if stem == "HeroArchMage" else "Death")
		player.advance(0)
		player.seek(0.1, true)
		await process_frame
		if stem == "PriestMissile":
			assert(particles[0].emitting and not particles[1].emitting)
		if stem == "FireBallMissile":
			assert(not particles[0].emitting and not particles[1].emitting and particles[2].emitting)
		await create_timer(0.1).timeout
		await _capture(stem + "-Action")
		player.play(stand)
		player.advance(0)
		assert(not particles[0].emitting if stem != "FireBallMissile" else particles[0].emitting)
		# Keep mesh override resources alive during rendering-instance teardown.
		for model: Node3D in [instance, other]:
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				for surface: int in range(mesh.mesh.get_surface_count()):
					_held_materials.append(mesh.get_active_material(surface))
			model.free()
	print("FX runtime PASS: standalone reload, clip emission reset, camera-facing pivot, ground bone unchanged, A/B material and particle isolation")
	quit()

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	assert(image.save_png("res://" + label + ".png") == OK)

func _check_billboard(instance: Node3D, camera: Camera3D) -> void:
	var skeleton: Skeleton3D = instance.find_children("*", "Skeleton3D", true, false)[0]
	var modifier: SkeletonModifier3D = skeleton.get_node("CameraFacingBones")
	var entry: Dictionary = modifier.get("entries")[0]
	var index: int = skeleton.find_bone(str(entry.name))
	var pivot: Vector3 = Vector3(entry.pivot[0], entry.pivot[1], entry.pivot[2])
	var before: Vector3 = skeleton.get_bone_global_pose(index) * pivot
	var ground_index: int = skeleton.find_bone("hero")
	var ground_pose: Transform3D = skeleton.get_bone_global_pose(ground_index) if ground_index >= 0 else Transform3D.IDENTITY
	modifier.call("_process_modification")
	var pose: Transform3D = skeleton.get_bone_global_pose(index)
	assert((pose * pivot).is_equal_approx(before))
	assert((skeleton.global_basis * pose.basis.x).normalized().dot(camera.global_basis.z.normalized()) > 0.999)
	if ground_index >= 0:
		assert(skeleton.get_bone_global_pose(ground_index).is_equal_approx(ground_pose))

func _check_material_isolation(instance: Node3D, other: Node3D) -> void:
	for mesh: MeshInstance3D in instance.find_children("*", "MeshInstance3D", true, false):
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(surface)
			if not material is ShaderMaterial or not material.has_meta("import_fx_material"):
				continue
			var counterpart: MeshInstance3D = other.get_node(instance.get_path_to(mesh))
			var other_material: ShaderMaterial = counterpart.get_active_material(surface)
			var initial: float = material.get_shader_parameter("layer_alpha")
			material.set_shader_parameter("layer_alpha", 0.123)
			assert(is_equal_approx(float(other_material.get_shader_parameter("layer_alpha")), initial))
			material.set_shader_parameter("layer_alpha", initial)

func _check_cycles(player: AnimationPlayer, instance: Node3D, stand: String) -> void:
	var skeleton: Skeleton3D = instance.find_children("*", "Skeleton3D", true, false)[0]
	var callback: AnimationMixer.AnimationCallbackModeProcess = player.callback_mode_process
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(stand)
	player.seek(0.137, true)
	skeleton.force_update_all_bone_transforms()
	var poses: Array[Transform3D] = []
	for index: int in range(skeleton.get_bone_count()):
		poses.append(skeleton.get_bone_global_pose(index))
	for cycle: int in range(3):
		player.advance(player.get_animation(stand).length)
		skeleton.force_update_all_bone_transforms()
		assert(absf(player.current_animation_position - 0.137) < 0.00001)
		for index: int in range(skeleton.get_bone_count()):
			assert(skeleton.get_bone_global_pose(index).is_equal_approx(poses[index]), "Bone drift after loop %d: %s" % [cycle, skeleton.get_bone_name(index)])
	player.callback_mode_process = callback
