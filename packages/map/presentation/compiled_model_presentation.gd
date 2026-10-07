class_name CompiledModelPresentation
extends RefCounted
## Compiled materials use source metadata; legacy presentation remains separate.

static func is_compiled(root: Node) -> bool:
	return root != null and root.has_meta("wc3_import_worker_version")

static func instantiate(path: String, cache: MapModelCache, unit_soft: bool = false, portrait: bool = false) -> Node3D:
	var scene_path: String = RuntimeAssets.resolve_model_scene(path)
	if not scene_path.is_empty():
		var packed: PackedScene = ResourceLoader.load(scene_path, "PackedScene") as PackedScene
		if packed != null:
			var root: Node3D = packed.instantiate() as Node3D
			if is_compiled(root):
				if cache != null:
					cache.last_scn_hits += 1
				hide_backgrounds(root)
				return root
			if root != null:
				root.free()
	return cache.instance_glb_hud(path) if portrait else cache.instance_glb(path, unit_soft)

static func hide_backgrounds(root: Node3D) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if bool(mesh.get_meta("wc3_portrait_background", false)):
			# Source visibility animation may re-enable visible; zero render layers stay hidden.
			mesh.layers = 0
			mesh.visible = false

static func apply_team(root: Node3D, index: int, cache: MapModelCache) -> void:
	if not is_compiled(root):
		cache.apply_team_color(root, index, false)
		return
	var color: Color = Color(40.0 / 255.0, 40.0 / 255.0, 40.0 / 255.0) if index >= 12 else MapPlaceholders.PLAYER_COLORS[clampi(index, 0, 11)]
	var logical: String = "ReplaceableTextures/TeamColor/TeamColor%02d.png" % clampi(index, 0, 15)
	var texture: Texture2D = null
	if not RuntimeAssets.resolve(logical).is_empty():
		texture = RuntimeAssets.load_converted_texture(logical)
	if texture == null:
		var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(color)
		texture = ImageTexture.create_from_image(image)
	else:
		color = texture.get_image().get_pixel(0, 0)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			var source: Material = mesh.get_active_material(surface)
			if source == null:
				continue
			var replaceable: int = int(source.get_meta("import_replaceable_id", 0))
			if source is ShaderMaterial and bool(source.get_meta("import_team_underlay", false)):
				var material: ShaderMaterial = source.duplicate() as ShaderMaterial
				material.set_shader_parameter("team_color_tex", texture)
				material.set_shader_parameter("use_team_texture", true)
				material.set_shader_parameter("team_color_fallback", color)
				mesh.set_surface_override_material(surface, material)
			elif source is ShaderMaterial and bool(source.get_meta("import_team_glow", false)):
				var material: ShaderMaterial = source.duplicate() as ShaderMaterial
				material.set_shader_parameter("team_color_fallback", color)
				material.set_shader_parameter("recolor", true)
				mesh.set_surface_override_material(surface, material)
			elif source is StandardMaterial3D and replaceable == 1:
				var material: StandardMaterial3D = source.duplicate() as StandardMaterial3D
				material.albedo_texture = texture
				mesh.set_surface_override_material(surface, material)
	root.set_meta("wc3_runtime_team_color", index)
	hide_backgrounds(root)
