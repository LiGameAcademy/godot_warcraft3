extends SceneTree
const TeamCompiler: GDScript = preload("res://tools/godot/import_team_material.gd")
const MaterialCompiler: GDScript = preload("res://tools/godot/import_material_compiler.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var cache: MapModelCache = MapModelCache.new()
	var template: Node3D = Node3D.new()
	template.set_meta("wc3_import_worker_version", "2")
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.set_meta("import_replaceable_id", 1)
	mesh.mesh.material = material
	template.add_child(mesh)
	var a: Node3D = template.duplicate() as Node3D
	var b: Node3D = template.duplicate() as Node3D
	CompiledModelPresentation.apply_team(a, 1, cache)
	CompiledModelPresentation.apply_team(b, 15, cache)
	var am: StandardMaterial3D = a.get_child(0).get_active_material(0)
	var bm: StandardMaterial3D = b.get_child(0).get_active_material(0)
	assert(am != bm and material.albedo_texture == null, "Team colors must be isolated")
	var blue: Color = am.albedo_texture.get_image().get_pixel(0, 0)
	assert(blue.b > 0.8 and blue.r < 0.3, "Blue owner must recolor the surface")
	var neutral: Color = bm.albedo_texture.get_image().get_pixel(0, 0)
	assert(neutral.r < 0.3 and neutral.g < 0.3 and neutral.b < 0.3, "Neutral uses a dark team texture")
	var board: MeshInstance3D = a.get_child(0)
	board.set_meta("wc3_portrait_background", true)
	CompiledModelPresentation.hide_backgrounds(a)
	board.visible = true
	assert(board.layers == 0, "Animation must not reveal portrait backgrounds")
	var pathing: Wc3PathingMap = Wc3PathingMap.new()
	pathing.width = 8
	pathing.height = 8
	pathing.cells.resize(64)
	pathing.cells.fill(0)
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLUE)
	image.set_pixel(1, 1, Color.MAGENTA)
	pathing.blit_pathing_image(1, 1, 0, image)
	assert((pathing.flag_at(2, 2) & Wc3PathingMap.FLAG_NO_BUILD) != 0)
	assert(pathing.can_walk_cell(2, 2), "Build-only fringe must stay walkable")
	assert(not pathing.can_walk_cell(3, 4), "Body pixel must block walking")
	_check_peasant_team_layers()
	_check_source_background()
	_check_shader_isolation(cache)
	a.free()
	b.free()
	template.free()
	print("PASS: compiled team instance isolation, hidden backgrounds, separate pathing channels")
	quit(0)

func _check_source_background() -> void:
	var root: Node3D = Node3D.new()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Geoset_0"
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	var ir: Dictionary = {"materials": {
		"source_payload": [{"Layers": [{"TextureID": 0, "Shading": 32}]}],
		"geoset_bindings": [{"node": "Geoset_0", "material_id": 0}]},
		"textures": {"source_payload": [{"Image": "Textures\\BackGround.blp"}]}}
	MaterialCompiler.compile(root, ir)
	assert(bool(mesh.get_meta("wc3_portrait_background", false)), "Source Background.blp must be classified even when the material falls back")
	CompiledModelPresentation.hide_backgrounds(root)
	assert(mesh.layers == 0)
	root.free()

func _check_shader_isolation(cache: MapModelCache) -> void:
	for marker: String in ["import_team_underlay", "import_team_glow"]:
		var root: Node3D = Node3D.new()
		root.set_meta("wc3_import_worker_version", "2")
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		var source: ShaderMaterial = ShaderMaterial.new()
		var shader: Shader = Shader.new()
		shader.code = "shader_type spatial; uniform sampler2D team_color_tex; uniform bool use_team_texture; uniform bool recolor; uniform vec4 team_color_fallback; void fragment() { ALBEDO = team_color_fallback.rgb; }"
		source.shader = shader
		source.set_meta(marker, true)
		mesh.mesh.material = source
		root.add_child(mesh)
		var red: Node3D = root.duplicate() as Node3D
		var blue: Node3D = root.duplicate() as Node3D
		CompiledModelPresentation.apply_team(red, 0, cache)
		CompiledModelPresentation.apply_team(blue, 1, cache)
		var red_material: ShaderMaterial = red.get_child(0).get_active_material(0)
		var blue_material: ShaderMaterial = blue.get_child(0).get_active_material(0)
		assert(red_material != blue_material and red_material != source, "Inline shader materials must be isolated")
		var red_color: Color = red_material.get_shader_parameter("team_color_fallback")
		var blue_color: Color = blue_material.get_shader_parameter("team_color_fallback")
		assert(red_color.r > 0.8 and blue_color.b > 0.8 and blue_color.r < 0.3)
		red.free()
		blue.free()
		root.free()

func _check_peasant_team_layers() -> void:
	var layers: Array = [{"TextureID": 0, "FilterMode": 1, "Shading": 17, "Alpha": 1}, {"TextureID": 1, "FilterMode": 2, "Shading": 0, "Alpha": 1}]
	var textures: Array = [{"ReplaceableId": 1, "Flags": 0, "uri": "selftest-team.png"}, {"ReplaceableId": 0, "Flags": 0}]
	assert(TeamCompiler.supported(layers, textures), "Peasant alpha-tested, double-sided team base must be supported")
	var sided: Array = layers.duplicate(true)
	sided[0].FilterMode = 0
	sided[0].Shading = 0
	assert(TeamCompiler.supported(sided, textures), "Existing single-sided opaque combinations remain supported")
	sided[1].Shading = 16
	assert(not TeamCompiler.supported(sided, textures), "An unbacked transparent top must retain its fallback")
	var image: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	assert(image.save_png(ProjectSettings.globalize_path("res://tmp/selftest-team.png")) == OK)
	var original: StandardMaterial3D = StandardMaterial3D.new()
	original.albedo_texture = ImageTexture.create_from_image(image)
	var material: ShaderMaterial = TeamCompiler.compile(original, layers, textures, ProjectSettings.globalize_path("res://tmp"))
	assert(material != null and material.get_meta("import_team_underlay", false))
	assert(material.shader.code.contains("FRONT_FACING") and material.shader.code.contains("cull_disabled"), "Diffuse backfaces must not overwrite the double-sided team base")
	image.set_pixel(0, 0, Color.TRANSPARENT)
	assert(image.save_png(ProjectSettings.globalize_path("res://tmp/selftest-team.png")) == OK)
	assert(TeamCompiler.compile(original, layers, textures, ProjectSettings.globalize_path("res://tmp")) == null, "Transparent bases must not be silently treated as opaque")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://tmp/selftest-team.png"))
