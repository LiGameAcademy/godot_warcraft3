extends RefCounted
## Converted PNGs are intentionally outside Godot's import database.
## Scene metadata keeps the original logical path; RuntimeAssets resolves overlays.

static func apply(root: Node) -> void:
	var cache: Dictionary = {}
	_apply_recursive(root, cache)


static func _apply_recursive(node: Node, cache: Dictionary) -> void:
	if (node is Button or node is TextureButton) and node.has_meta("wc3_icon"):
		var logical: String = str(node.get_meta("wc3_icon"))
		if not cache.has(logical):
			cache[logical] = RuntimeAssets.load_texture(RuntimeAssets.resolve(logical))
		var texture: Texture2D = cache[logical]
		if texture != null:
			if node is TextureButton:
				node.texture_normal = texture
			else:
				node.icon = texture
		else:
			push_warning("WorldEdit icon missing: %s" % logical)
			node.tooltip_text += "\n缺少图标：" + logical
	for child in node.get_children():
		_apply_recursive(child, cache)
