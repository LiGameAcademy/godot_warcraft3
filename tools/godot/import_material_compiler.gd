extends RefCounted
## Unsupported combinations retain the GLTF fallback with diagnostics.
const AlphaCompiler: GDScript = preload("import_material_animation.gd")
const TeamCompiler: GDScript = preload("import_team_material.gd")

static func compile(scene: Node, ir: Dictionary, texture_base: String = "") -> Dictionary:
	var result: Dictionary = {"compiled_surfaces": 0, "team_surfaces": 0, "alpha_tracks": 0, "diagnostics": []}
	var materials: Array = ir.get("materials", {}).get("source_payload", [])
	var bindings: Array = ir.get("materials", {}).get("geoset_bindings", [])
	var textures: Array = ir.get("textures", {}).get("source_payload", [])
	var meshes: Dictionary = {}
	var players: Array[AnimationPlayer] = []
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			meshes[str(node.name)] = node
		if node is AnimationPlayer:
			players.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	if bindings.is_empty():
		_warn(result, "material_payload_missing", -1)
	for binding: Dictionary in bindings:
		var id: int = int(binding.get("material_id", -1))
		var mesh: MeshInstance3D = meshes.get(str(binding.node))
		if id < 0 or id >= materials.size() or mesh == null:
			_warn(result, "material_binding_missing", id)
			continue
		var layers: Array = materials[id].get("Layers", [])
		var team: bool = TeamCompiler.supported(layers, textures)
		if layers.size() != 1 and not team:
			_warn(result, "multilayer_pending", id)
			continue
		var layer: Dictionary = layers[1] if team else layers[0]
		if not _supported(layer) or (team and not _supported(layers[0])):
			_warn(result, "material_feature_pending", id)
			continue
		var animated: bool = layer.get("Alpha", 1) is Dictionary
		if animated and (players.size() != 1 or not AlphaCompiler.supported(players[0], layer.Alpha, ir)):
			_warn(result, "material_alpha_pending", id)
			continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.get_active_material(surface)
			if not original is StandardMaterial3D:
				_warn(result, "material_type_pending", id)
				continue
			var material: Material
			if team:
				material = TeamCompiler.compile(original, layers, textures, texture_base)
				if material == null:
					_warn(result, "team_texture_missing", id)
					continue
				result.team_surfaces += 1
			else:
				material = _single(original, layer)
			material.resource_local_to_scene = true
			material.set_meta("import_material_id", id)
			material.set_meta("import_filter_mode", int(layer.get("FilterMode", 0)))
			mesh.set_surface_override_material(surface, material)
			if animated:
				result.alpha_tracks += AlphaCompiler.compile(players[0], mesh, surface, layer.Alpha, ir, team)
			result.compiled_surfaces += 1
	return result

static func _warn(result: Dictionary, code: String, id: int) -> void:
	result.diagnostics.append({"code": code, "severity": "warning", "material": id})

static func _supported(layer: Dictionary) -> bool:
	var flags: int = int(layer.get("Shading", 0))
	var mode: int = int(layer.get("FilterMode", 0))
	return not layer.get("TextureID") is Dictionary and layer.get("TVertexAnimId") == null and flags & ~17 == 0 and mode >= 0 and mode <= 2 and int(layer.get("CoordId", 0)) == 0

static func _single(original: StandardMaterial3D, layer: Dictionary) -> StandardMaterial3D:
	var material: StandardMaterial3D = original.duplicate()
	var flags: int = int(layer.get("Shading", 0))
	var mode: int = int(layer.get("FilterMode", 0))
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if flags & 1 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if flags & 16 else BaseMaterial3D.CULL_BACK
	material.transparency = [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA][mode]
	material.alpha_scissor_threshold = 0.75
	material.albedo_color.a = 1.0 if layer.get("Alpha", 1) is Dictionary else float(layer.get("Alpha", 1))
	return material
