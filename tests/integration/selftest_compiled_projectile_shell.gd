extends Node

var _imported_fx: GDScript
var _output: String = ""
var _report: Array[Dictionary] = []
var _materials: Array[Material] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_imported_fx = load("res://packages/gameplay/features/combat/presentation/imported_projectile_fx.gd")
	var shell_scene: PackedScene = load("res://packages/gameplay/features/combat/presentation/combat_projectile_shell.tscn")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index_path: String = args[args.find("--index") + 1]
	_output = args[args.find("--output") + 1]
	DirAccess.make_dir_recursive_absolute(_output)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	var paths: Dictionary[String, String] = {}
	for entry: Dictionary in record.results:
		paths[str(entry.asset_id) + ".scn"] = str(entry.output_scene)
	assert(ContentPaths.install_compiled_scenes(paths) == OK)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	var world: Node3D = Node3D.new()
	viewport.add_child(world)
	var legacy_geometry: GDScript = load("res://packages/gameplay/features/combat/presentation/legacy_projectile_geometry.gd")
	var legacy: Node3D = Node3D.new()
	var legacy_mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(4.0, 0.2, 0.2)
	legacy_mesh.mesh = box
	legacy.add_child(legacy_mesh)
	world.add_child(legacy)
	var holder: Node3D = Node3D.new()
	legacy_geometry.align(legacy, holder)
	assert((holder.basis * Vector3.RIGHT).is_equal_approx(Vector3.FORWARD))
	legacy_geometry.fit_scale(legacy)
	assert(legacy.scale.is_equal_approx(Vector3.ONE * Wc3Coords.WORLD_SCALE))
	legacy.free()
	holder.free()
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	camera.position = Vector3(3, 3, 4)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06, 0.08, 0.1)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	for stem: String in ["PriestMissile", "FireBallMissile"]:
		var art: String = "Abilities/Weapons/%s/%s.mdx" % [stem, stem]
		var shell: Node3D = shell_scene.instantiate()
		world.add_child(shell)
		shell.play(Vector3.ZERO, Vector3(3000, 0, 0), 4.0, true, art, null, null, art, 0.0, 100.0)
		shell.set_process(false)
		var model: Node3D = shell.get_node("MissileModel").get_child(0)
		assert(_imported_fx.is_compiled(model))
		assert(not model.has_meta("wc3_fx_replaced_source"))
		assert(model.find_child("Pe2Root", true, false) == null)
		var particles: Array[Node] = model.find_children("*", "GPUParticles3D", true, false)
		assert(particles.size() == (2 if stem == "PriestMissile" else 3))
		var player: AnimationPlayer = AnimPlayback.find_animation_player(model)
		assert(player.get_animation("Stand").loop_mode == Animation.LOOP_LINEAR)
		for particle: GPUParticles3D in particles:
			assert(particle.emitting == (particle == particles[1] if stem == "PriestMissile" else particle != particles[2]))
		await _capture(viewport, stem + "-flight", shell)
		assert(shell.position.length() > 0.0)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.play("Stand")
		player.seek(0.137, true)
		var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		skeleton.force_update_all_bone_transforms()
		var poses: Array[Transform3D] = []
		for bone: int in range(skeleton.get_bone_count()):
			poses.append(skeleton.get_bone_global_pose(bone))
		for cycle: int in range(3):
			player.advance(player.get_animation("Stand").length)
			skeleton.force_update_all_bone_transforms()
			assert(absf(player.current_animation_position - 0.137) < 0.00001)
			for bone: int in range(skeleton.get_bone_count()):
				assert(skeleton.get_bone_global_pose(bone).is_equal_approx(poses[bone]))
		shell.call("_spawn_impact")
		var impact: Node3D = world.get_node("CombatImpactFx")
		var impact_model: Node3D = impact.get_child(0)
		var impact_player: AnimationPlayer = AnimPlayback.find_animation_player(impact_model)
		assert(impact_player.current_animation == "Death")
		assert(impact_player.get_animation("Death").loop_mode == Animation.LOOP_NONE)
		_hold_materials(model)
		shell.free()
		await _capture(viewport, stem + "-impact")
		_hold_materials(impact_model)
		impact.free()
		_report.append({"asset": art, "particles": particles.size(), "checks": ["actual_projectile_shell", "no_legacy_emitters", "source_loops", "three_cycles_without_drift", "impact_death"]})
	var hero: Node3D = _imported_fx.instantiate("Units/Human/HeroArchMage/HeroArchMage.mdx")
	assert(hero != null)
	world.add_child(hero)
	_imported_fx.play(hero, PackedStringArray(["Stand"]))
	var glow_count: int = 0
	for mesh: MeshInstance3D in hero.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(surface)
			if material != null and material.has_meta("import_team_glow"):
				glow_count += 1
	assert(glow_count > 0)
	camera.size = 7.0
	await _capture(viewport, "HeroArchMage-glow-oblique")
	camera.position = Vector3(0, 5, 0.01)
	camera.look_at(Vector3.ZERO)
	await _capture(viewport, "HeroArchMage-glow-top")
	_report.append({"asset": "Units/Human/HeroArchMage/HeroArchMage.mdx", "glow_surfaces": glow_count, "visual": "unverified_against_original_game"})
	_hold_materials(hero)
	hero.free()
	viewport.free()
	var output: FileAccess = FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(_report, "  "))
	output.close()
	print("PASS: actual projectile shell preserves compiled controls; cycles, impact and hero glow captured")
	get_tree().quit(0)

func _capture(viewport: SubViewport, label: String, moving_shell: Node3D = null) -> void:
	for frame: int in range(20):
		if moving_shell != null:
			moving_shell.call("_process", 1.0 / 60.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(_output.path_join(label + ".png")) == OK)

func _hold_materials(model: Node3D) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			_materials.append(mesh.get_active_material(surface))
