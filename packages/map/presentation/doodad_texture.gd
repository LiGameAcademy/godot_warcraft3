extends RefCounted
## DestructableData texID/texFile override the model's baked replaceable default.
## Clone only affected materials/meshes; cached scenes must remain unchanged.
static var _textures: Dictionary = {}


static func apply(root: Node, definition: Dictionary) -> void:
	var slot := int(definition.get("tex_id", 0))
	var path := str(definition.get("tex_file", "")).replace("\\", "/").strip_edges()
	if slot <= 0 or path.is_empty() or path == "_":
		return
	if path.get_extension().is_empty():
		path += ".png"
	else:
		path = path.get_basename() + ".png"
	if not _textures.has(path):
		var texture := RuntimeAssets.load_texture(RuntimeAssets.resolve(path))
		if texture == null:
			root.set_meta("missing_replaceable_texture", path)
			push_warning("缺少物体替换纹理 %s：%s" % [definition.get("id", ""), path])
			return
		_textures[path] = texture
	var pattern := RegEx.new()
	pattern.compile("_rep%d(?:_|$)" % slot)
	_apply_node(root, pattern, _textures[path], path)


static func _material(source: Material, pattern: RegEx, texture: Texture2D, path: String) -> Material:
	if source == null or pattern.search(source.resource_name) == null:
		return source
	if source is StandardMaterial3D:
		var copy := source.duplicate() as StandardMaterial3D
		copy.albedo_texture = texture
		copy.set_meta("wc3_replacement_path", path)
		return copy
	push_warning("未支持的物体替换材质：" + source.resource_name)
	return source


static func _apply_node(node: Node, pattern: RegEx, texture: Texture2D, path: String) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for index in range(node.mesh.get_surface_count()):
			var original: Material = node.get_active_material(index)
			var replaced := _material(original, pattern, texture, path)
			if replaced != original:
				node.set_surface_override_material(index, replaced)
	elif node is MultiMeshInstance3D and node.multimesh != null:
		if node.material_override != null:
			node.material_override = _material(node.material_override, pattern, texture, path)
		elif node.multimesh.mesh != null:
			var mesh: Mesh = node.multimesh.mesh
			var copy: Mesh = null
			for index in range(mesh.get_surface_count()):
				var original: Material = mesh.surface_get_material(index)
				var replaced := _material(original, pattern, texture, path)
				if replaced != original:
					if copy == null:
						copy = mesh.duplicate()
					copy.surface_set_material(index, replaced)
			if copy != null:
				node.multimesh.mesh = copy
	for child in node.get_children():
		_apply_node(child, pattern, texture, path)
