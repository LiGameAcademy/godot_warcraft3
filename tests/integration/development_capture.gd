extends Node
## Release-only acceptance probe; copied into the temporary export by the JS test.
var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var deadline: int = Time.get_ticks_msec() + 240000
	var game: GameMain
	while Time.get_ticks_msec() < deadline:
		game = get_tree().current_scene as GameMain
		if game != null and game.is_session_ready():
			break
		await get_tree().process_frame
	if game == null or not game.has_playable_match():
		_fail("Release startup verification failed")
		get_tree().quit(1)
		return
	_check(not FileAccess.file_exists("res://assets/map-parsed/echoisles/info.json"), "Map data must come from the published cache")
	_check(not FileAccess.file_exists("res://assets/slk-exported/Units/UnitUI.json"), "Definitions must come from the published cache")
	_check(RuntimeAssets.load_texture("res://assets/asset-converted/ReplaceableTextures/CommandButtons/BTNPeasant.png") != null, "Release icon must load")
	_verify_idle_geometry(game)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var capture: String = args[args.find("--capture-game") + 1]
	await _save(capture)
	if "--asset-review" in args:
		await _review(game, capture)
	print("PASS: release rendered map and icons without packaged original assets" if _failures == 0 else "FAIL: release presentation")
	get_tree().quit(0 if _failures == 0 else 1)

func _review(game: GameMain, capture: String) -> void:
	var layer: MapUnitLayer = game.map_root.get_unit_layer()
	var samples: Dictionary = {}
	var backgrounds: int = 0
	var seed: Dictionary = {}
	for actor: Node in layer.get_children():
		var data: Dictionary = actor.get_meta("unit_data", {})
		if str(data.get("typeId", "")) == "hmpr":
			seed = data.duplicate(true)
			break
	if not seed.is_empty():
		for tid: String in ["hfoo", "hbar"]:
			var entry: Dictionary = seed.duplicate(true)
			entry.typeId = tid
			entry.creationNumber = 98000 + (1 if tid == "hbar" else 0)
			entry.position.x = float(entry.position.x) + (512.0 if tid == "hbar" else -96.0)
			_check(game.map_root.add_unit_instance(entry, game.map_root.get_heightfield_dict()) != null, "Runtime spawn: " + tid)
	for actor: Node in layer.get_children():
		var data: Dictionary = actor.get_meta("unit_data", {})
		var tid: String = str(data.get("typeId", ""))
		var model: Node3D = actor.get_node_or_null("Model") as Node3D
		if not CompiledModelPresentation.is_compiled(model):
			continue
		if tid in ["hmpr", "Hamg"]:
			var position: Dictionary = data.get("position", {})
			_check(game.map_root.get_pathing_map().can_walk_at(float(position.x), float(position.y)), "Review unit starts on walkable ground: " + tid)
		var owner: int = int(data.get("owner", -1))
		var team: int = MapUnitLayer.resolve_team_color_index(tid, owner)
		if tid in ["htow", "Hamg", "hfoo", "hbar", "hpea"]:
			_check_team_materials(model, team, tid)
		_check(int(model.get_meta("wc3_runtime_team_color", -1)) == MapUnitLayer.resolve_team_color_index(tid, owner), "Runtime team color: " + tid)
		for mesh: Node in model.find_children("*", "MeshInstance3D", true, false):
			if bool(mesh.get_meta("wc3_portrait_background", false)):
				backgrounds += 1
				_check((mesh as MeshInstance3D).layers == 0, "Background must stay outside the battlefield")
		if tid in ["hmpr", "Hamg", "htow", "nmer", "hfoo", "hbar"] and not samples.has(tid):
			samples[tid] = actor
	_check(backgrounds > 0, "Real source portrait background was tagged")
	_check(samples.has("hmpr") and samples.has("Hamg"), "Review start must contain Priest and Archmage")
	for logical: String in ["PathTextures/12x12Simple.tga", "PathTextures/16x16Simple.tga"]:
		var image: Image = Wc3PathingTextures.load_image(logical)
		_check(image != null, "Published pathing texture: " + logical)
		if image == null:
			continue
		var walkable_fringe: bool = false
		var solid_body: bool = false
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				var color: Color = image.get_pixel(x, y)
				walkable_fringe = walkable_fringe or (color.b > 0.5 and color.r < 0.5)
				solid_body = solid_body or (color.b > 0.5 and color.r > 0.5)
		_check(walkable_fringe and solid_body, "Source footprint distinguishes no-build fringe and no-walk body")
	for tid: String in ["htow", "hbar", "nmer", "hfoo", "hmpr", "Hamg"]:
		if not samples.has(tid):
			continue
		game.unit_selector.select_node(samples[tid] as Node3D)
		await get_tree().process_frame
		var views: Array[UnitPortraitView] = []
		for control: Node in game.game_hud.find_children("*", "Control", true, false):
			if control is UnitPortraitView:
				views.append(control as UnitPortraitView)
		_check(not views.is_empty(), "Selected unit has a portrait view")
		if not views.is_empty():
			var view: UnitPortraitView = views[0] as UnitPortraitView
			var deadline: int = Time.get_ticks_msec() + 15000
			while view._settled_gen != view._load_gen and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			await get_tree().create_timer(0.5).timeout
			_check(view._model_root != null, "Portrait model loaded: " + tid)
			if tid in ["htow", "hbar"] and view._model_root != null:
				_check(not (view._model_root.get_meta("wc3_portrait_cameras", []) as Array).is_empty(), "Building source camera retained")
				_check(view._animation.player != null and str(view._animation.player.current_animation).to_lower().contains("portrait"), "Building uses Portrait sequence")
		await _save(capture.get_basename() + "-" + tid + ".png")
	print("PASS: compiled source backgrounds, ownership, native pathing textures and review portraits" if _failures == 0 else "FAIL: asset review")

func _save(path: String) -> void:
	for frame: int in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "Screenshot save: " + path)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	_failures += 1
	push_error(message)

func _check_team_materials(model: Node3D, team: int, tid: String) -> void:
	var texture: Texture2D = RuntimeAssets.load_converted_texture("ReplaceableTextures/TeamColor/TeamColor%02d.png" % team)
	_check(texture != null, "Source team texture available: " + tid)
	if texture == null:
		return
	var expected: Color = texture.get_image().get_pixel(0, 0)
	var colored: int = 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null or bool(mesh.get_meta("wc3_portrait_background", false)):
			continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(surface)
			var actual: Color
			if material is ShaderMaterial and bool(material.get_meta("import_team_underlay", false)):
				var underlay: Texture2D = (material as ShaderMaterial).get_shader_parameter("team_color_tex") as Texture2D
				_check(underlay != null, "Team underlay texture: " + tid)
				if underlay == null:
					continue
				actual = underlay.get_image().get_pixel(0, 0)
			elif material is ShaderMaterial and bool(material.get_meta("import_team_glow", false)):
				actual = (material as ShaderMaterial).get_shader_parameter("team_color_fallback")
			elif material is StandardMaterial3D and int(material.get_meta("import_replaceable_id", 0)) == 1:
				actual = (material as StandardMaterial3D).albedo_texture.get_image().get_pixel(0, 0)
			else:
				continue
			colored += 1
			_check(actual.is_equal_approx(expected), "Source team color applied: " + tid)
	_check(colored > 0, "Real team surfaces recognized: " + tid)

func _verify_idle_geometry(game: GameMain) -> void:
	var checked: int = 0
	for actor: Node in game.map_root.get_unit_layer().get_children():
		var data: Dictionary = actor.get_meta("unit_data", {})
		if str(data.get("typeId", "")) != "htow":
			continue
		var model: Node3D = actor.get_node_or_null("Model") as Node3D
		var player: AnimationPlayer = AnimPlayback.find_animation_player(model)
		_check(player != null and str(player.current_animation) == "Stand", "First-tier TownHall must play Stand")
		if player == null:
			continue
		var animation: Animation = player.get_animation("Stand")
		var native_tracks: int = 0
		for track: int in range(animation.get_track_count()):
			if not str(animation.track_get_path(track)).ends_with(":visible"):
				continue
			native_tracks += 1
		_check(native_tracks >= 30, "TownHall geoset visibility must compile despite extended global clocks")
		var board: MeshInstance3D = model.find_child("Geoset_1", true, false) as MeshInstance3D
		_check(board != null and not board.visible and board.layers == 0, "TownHall portrait-only board must be hidden")
		checked += 1
	_check(checked > 0, "At least one real first-tier TownHall verified")
