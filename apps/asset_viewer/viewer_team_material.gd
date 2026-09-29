extends RefCounted
## Preview-only recoloring of the new worker's embedded team shader.
static func apply(root: Node, index: int) -> void:
	var texture: Texture2D = RuntimeAssets.load_converted_texture("ReplaceableTextures/TeamColor/TeamColor%02d.png" % index)
	var fallback: Color = MapPlaceholders.PLAYER_COLORS[clampi(index, 0, MapPlaceholders.PLAYER_COLORS.size() - 1)]
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)
		if not node is MeshInstance3D or node.mesh == null:
			continue
		for surface: int in range(node.mesh.get_surface_count()):
			var source: Material = node.get_active_material(surface)
			if not source is ShaderMaterial or not (source.has_meta("import_team_underlay") or source.has_meta("import_team_glow")):
				continue
			var material: ShaderMaterial = source.duplicate()
			material.resource_local_to_scene = true
			material.set_shader_parameter("team_color_fallback", fallback)
			if source.has_meta("import_team_glow"):
				material.set_shader_parameter("recolor", true)
			else:
				material.set_shader_parameter("use_team_texture", texture != null)
				material.set_shader_parameter("team_color_tex", texture)
			node.set_surface_override_material(surface, material)
