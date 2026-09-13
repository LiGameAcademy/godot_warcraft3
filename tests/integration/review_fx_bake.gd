extends SceneTree
## Run with a real renderer (not --headless). Captures freshly loaded .scn files.
const CASES := [
	["TownHall", "Buildings/Human/TownHall/TownHall", "Birth", 12.0, Vector3(0, 1, 0)],
	["WaterElemental", "Units/Human/WaterElemental/WaterElemental", "Birth", 7.0, Vector3(0, 1, 0)],
	["WaterElementalAttack", "Units/Human/WaterElemental/WaterElemental", "Attack", 7.0, Vector3(0, 1, 0)],
	["FireBallMissile", "Abilities/Weapons/FireBallMissile/FireBallMissile", "Stand", 5.0, Vector3.ZERO],
	["FireBallImpact", "Abilities/Weapons/FireBallMissile/FireBallMissile", "Death", 5.0, Vector3.ZERO],
	["Brazier", "Doodads/LordaeronSummer/Props/brazierOmni/brazierOmni", "Stand", 5.0, Vector3(0, 1, 0)],
]
const OUTPUT := "res://.godot/fx-review"


func _initialize() -> void:
	root.hide()
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for entry in CASES:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960, 720)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var world := Node3D.new()
		viewport.add_child(world)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.055, 0.065, 0.085)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.6
		world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-55, -30, 0)
		world.add_child(light)
		var packed := RuntimeAssets.load_packed_scene("res://assets/asset-converted/" + entry[1] + ".scn")
		if packed == null:
			push_error("Missing review scene: " + entry[1])
			quit(1)
			return
		var model := packed.instantiate() as Node3D
		world.add_child(model)
		for p in model.find_children("*", "GPUParticles3D", true, false):
			p.use_fixed_seed = true
			p.seed = 42
		var ap := AnimPlayback.find_animation_player(model)
		if ap != null:
			var name := AnimPlayback.resolve(model, entry[2], ap)
			if not name.is_empty():
				ap.play(name)
				ap.advance(0.0)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = entry[3]
		world.add_child(camera)
		var target: Vector3 = entry[4]
		camera.position = target + Vector3(8, 7, 10)
		camera.look_at(target)
		camera.make_current()
		for frame in range(121):
			if entry[0] == "FireBallMissile":
				model.position.x = -1.0 + minf(float(frame) / 60.0, 1.5)
			await process_frame
			await RenderingServer.frame_post_draw
			if frame in [20, 60, 120]:
				var output := OUTPUT.path_join("%s_%03d.png" % [entry[0], frame])
				var image := viewport.get_texture().get_image()
				if image.save_png(output) != OK:
					push_error("Cannot save " + output)
					quit(1)
					return
		viewport.queue_free()
		await process_frame
	print("review_fx_bake: PASS → " + OUTPUT)
	quit(0)
