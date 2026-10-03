extends Node

const Compiler: GDScript = preload("res://import_scene_compiler.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3 or args[0] not in ["--compile", "--reload"]:
		get_tree().quit(2)
		return
	var result: Dictionary = {}
	var exit_code: int = 0
	if args[0] == "--compile":
		var compiler: RefCounted = Compiler.new()
		var response: Dictionary = compiler.compile_task(args[1])
		result = response.result
		exit_code = int(response.exit_code)
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		if not parsed is Dictionary or not parsed.get("ok", false):
			get_tree().quit(2)
			return
		result = parsed
		var packed: PackedScene = ResourceLoader.load(str(result.output_scene), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed == null:
			get_tree().quit(1)
			return
		var first: Node = packed.instantiate()
		var second: Node = packed.instantiate()
		add_child(first)
		add_child(second)
		await get_tree().process_frame
		await get_tree().process_frame
		result["reloaded"] = true
		result["runtime_features"] = _features(first)
		var particles_a: Array[Node] = first.find_children("*", "GPUParticles3D", true, false)
		var particles_b: Array[Node] = second.find_children("*", "GPUParticles3D", true, false)
		if not particles_a.is_empty():
			var material_a: ParticleProcessMaterial = particles_a[0].process_material
			var material_b: ParticleProcessMaterial = particles_b[0].process_material
			var previous: float = material_b.initial_velocity_min
			material_a.initial_velocity_min = previous + 1.0
			result["particle_isolation"] = material_b.initial_velocity_min == previous
			if not result.particle_isolation:
				exit_code = 1
		# Keep materials alive while rendering instances tear down.
		var retained: Array[Material] = []
		_retain_materials(first, retained)
		_retain_materials(second, retained)
		first.queue_free()
		second.queue_free()
		await get_tree().process_frame
	var file: FileAccess = FileAccess.open(args[2], FileAccess.WRITE)
	if file == null:
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(result, "  ") + "\n")
	file.close()
	print("EXPORTED IMPORT %s: %s" % [args[0], "PASS" if exit_code == 0 else "FAIL"])
	get_tree().quit(exit_code)

func _features(scene: Node) -> Dictionary:
	var ribbons: int = 0
	var billboards: int = 0
	for node: Node in scene.find_children("*", "", true, false):
		if node.has_meta("import_ribbon"):
			ribbons += 1
		if node.name == "CameraFacingBones":
			billboards += 1
	return {"particles": scene.find_children("*", "GPUParticles3D", true, false).size(), "ribbons": ribbons, "billboard_nodes": billboards}

func _retain_materials(scene: Node, retained: Array[Material]) -> void:
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override != null:
			retained.append(mesh.material_override)
		if mesh.mesh == null:
			continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(surface)
			if material != null:
				retained.append(material)
