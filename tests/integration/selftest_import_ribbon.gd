extends SceneTree
var _materials: Array[Material] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://Resurrecttarget.scn") as PackedScene
	assert(packed != null)
	var first: Node3D = packed.instantiate() as Node3D
	var second: Node3D = packed.instantiate() as Node3D
	root.add_child(first)
	root.add_child(second)
	await process_frame
	var ribbons: Array[Node] = _ribbons(first)
	var others: Array[Node] = _ribbons(second)
	assert(ribbons.size() == 4)
	var player: AnimationPlayer = first.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("Stand")
	player.advance(0.0)
	for ribbon: Node in ribbons:
		ribbon.set_process(false)
		ribbon.call("update_trail")
	for index: int in range(12):
		player.advance(1.0 / 30.0)
		for ribbon: Node in ribbons:
			ribbon.call("update_trail")
	var trail: MeshInstance3D = ribbons[0] as MeshInstance3D
	assert(trail.mesh != null and trail.mesh.get_surface_count() == 1)
	var points: Array = trail.get("_points")
	assert(points.size() >= 10)
	if DisplayServer.get_name() != "headless":
		second.visible = false
		var camera: Camera3D = Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(12, 8, 16)
		camera.look_at(Vector3(0, 6, 0))
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 15.0
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://ribbon-render.png")
	var before: Array = points.duplicate(true)
	trail.call("update_trail")
	assert(before == trail.get("_points"), "Paused clock must freeze history")
	assert((others[0].get("_points") as Array).is_empty())
	var other_material: ShaderMaterial = (others[0] as MeshInstance3D).material_override as ShaderMaterial
	var material: ShaderMaterial = trail.material_override as ShaderMaterial
	assert(material != other_material)
	material.set_shader_parameter("color_add", false)
	assert(other_material.get_shader_parameter("color_add") == true)
	player.seek(0.1, true)
	trail.call("update_trail")
	assert((trail.get("_points") as Array).is_empty(), "Rewind clears old path")
	trail.set("emitting", true)
	trail.set("clock", 0.15)
	trail.call("update_trail")
	assert(not (trail.get("_points") as Array).is_empty())
	trail.set("emitting", false)
	for index: int in range(6):
		trail.set("clock", 0.25 + index * 0.1)
		trail.call("update_trail")
	assert((trail.get("_points") as Array).is_empty(), "Stopped emission expires")
	trail.set("emitting", true)
	trail.set("clock", 0.8)
	trail.call("update_trail")
	trail.set("clip", "another")
	trail.call("update_trail")
	assert((trail.get("_points") as Array).is_empty())
	for instance: Node3D in [first, second]:
		for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance: MeshInstance3D = node as MeshInstance3D
			if mesh_instance.material_override != null:
				_materials.append(mesh_instance.material_override)
		instance.queue_free()
	await process_frame
	await _check_moving_projectile()
	if DisplayServer.get_name() != "headless":
		await _capture_rejuvenation()
	print("Ribbon runtime PASS")
	quit()

func _ribbons(instance: Node3D) -> Array[Node]:
	var result: Array[Node] = []
	for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
		if node.has_meta("import_ribbon"):
			result.append(node)
	return result

func _check_moving_projectile() -> void:
	var packed: PackedScene = load("res://FragMissile.scn") as PackedScene
	var instance: Node3D = packed.instantiate() as Node3D
	root.add_child(instance)
	await process_frame

	var trail: MeshInstance3D = _ribbons(instance)[0] as MeshInstance3D
	trail.set_process(false)
	var player: AnimationPlayer = instance.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("Stand")
	player.advance(0.0)
	trail.call("reset_history")
	for index: int in range(10):
		instance.position.x += 0.1
		player.advance(0.05)
		trail.call("update_trail")
	assert(trail.mesh != null)
	var points: Array = trail.get("_points")
	assert((points.back().below as Vector3).x > (points.front().below as Vector3).x + 0.2, "Movement must leave world-space history")
	var old: Vector3 = points.front().below
	instance.position.x += 0.1
	player.advance(0.01)
	trail.call("update_trail")
	assert((trail.get("_points") as Array)[0].below == old, "Old points must not move with the projectile")
	player.play("Death")
	player.advance(0.0)
	trail.call("update_trail")
	assert(not bool(trail.get("emitting")))
	assert((trail.get("_points") as Array).is_empty())
	for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.material_override != null:
			_materials.append(mesh_instance.material_override)
	instance.queue_free()
	await process_frame

func _capture_rejuvenation() -> void:
	var packed: PackedScene = load("res://RejuvenationTarget.scn") as PackedScene
	var instance: Node3D = packed.instantiate() as Node3D
	root.add_child(instance)
	var camera: Camera3D = root.get_camera_3d()
	camera.position = Vector3(3, 2, 4)
	camera.look_at(Vector3(0, 0.6, 0))
	camera.size = 3.0
	var player: AnimationPlayer = instance.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.play("Stand")
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://rejuvenation-render.png")
	for node: Node in _ribbons(instance):
		_materials.append((node as MeshInstance3D).material_override)
	instance.queue_free()
	await process_frame
