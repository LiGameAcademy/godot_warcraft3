extends RefCounted
## First material consumer: static single-layer opaque/masked/alpha surfaces.
## Texture loading remains owned by GLTFDocument; source semantics come from IR.
static func compile(scene: Node, ir: Dictionary) -> Dictionary:
	var result: Dictionary = {"compiled_surfaces": 0, "diagnostics": []}
	var materials: Array = ir.get("materials", {}).get("source_payload", [])
	var bindings: Array = ir.get("materials", {}).get("geoset_bindings", [])
	var meshes: Dictionary = {}
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			meshes[str(node.name)] = node
		for child: Node in node.get_children():
			pending.append(child)
	if bindings.is_empty():
		result.diagnostics.append({"code": "material_payload_missing", "severity": "warning"})
	for binding: Dictionary in bindings:
		var id: int = int(binding.get("material_id", -1))
		var mesh: MeshInstance3D = meshes.get(str(binding.node))
		if id < 0 or id >= materials.size() or mesh == null:
			result.diagnostics.append({"code": "material_binding_missing", "severity": "warning", "node": binding.node})
			continue
		var layers: Array = materials[id].get("Layers", [])
		if layers.size() != 1:
			result.diagnostics.append({"code": "multilayer_pending", "severity": "warning", "material": id})
			continue
		var layer: Dictionary = layers[0]
		var flags: int = int(layer.get("Shading", 0))
		var mode: int = int(layer.get("FilterMode", 0))
		if layer.get("Alpha", 1) is Dictionary or layer.get("TextureID") is Dictionary or layer.get("TVertexAnimId") != null or flags & ~17 != 0 or mode > 2 or int(layer.get("CoordId", 0)) != 0:
			result.diagnostics.append({"code": "material_feature_pending", "severity": "warning", "material": id})
			continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.get_active_material(surface)
			if not original is StandardMaterial3D:
				result.diagnostics.append({"code": "material_type_pending", "severity": "warning", "material": id})
				continue
			var material: StandardMaterial3D = original.duplicate()
			material.resource_local_to_scene = true
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if flags & 1 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
			material.cull_mode = BaseMaterial3D.CULL_DISABLED if flags & 16 else BaseMaterial3D.CULL_BACK
			material.transparency = [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA][mode]
			material.alpha_scissor_threshold = 0.75
			material.albedo_color.a = float(layer.get("Alpha", 1.0))
			material.set_meta("import_material_id", id)
			material.set_meta("import_filter_mode", mode)
			mesh.set_surface_override_material(surface, material)
			result.compiled_surfaces += 1
	return result
