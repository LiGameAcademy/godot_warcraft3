extends RefCounted

## Compiled effects own their scale, materials, particles and animation flags.
static func is_compiled(model: Node) -> bool:
	return model.has_meta("wc3_import_worker_version")

static func instantiate(art_path: String) -> Node3D:
	var logical: String = art_path
	if logical.to_lower().ends_with(".mdx") or logical.to_lower().ends_with(".mdl"):
		logical = logical.get_basename() + ".gltf"
	var scene_path: String = RuntimeAssets.resolve_model_scene(logical)
	if scene_path.is_empty():
		return null
	var packed: PackedScene = RuntimeAssets.load_packed_scene(scene_path)
	if packed == null:
		return null
	var model: Node3D = packed.instantiate() as Node3D
	if model != null and is_compiled(model):
		return model
	if model != null:
		model.free()
	return null

static func play(model: Node3D, preferred: PackedStringArray) -> float:
	var player: AnimationPlayer = AnimPlayback.find_animation_player(model)
	if player == null:
		return 0.0
	for sequence: String in preferred:
		var name: String = AnimPlayback.resolve(model, sequence, player)
		if not name.is_empty():
			player.play(name)
			player.advance(0.0)
			return player.get_animation(name).length
	return 0.0
