class_name AbilityFxScene
extends RefCounted
## Retain immutable compiled scenes across repeated casts; instances own mutable resources.
static var _scenes: Dictionary[String, PackedScene] = {}
static var scene_loads: int = 0
static var _loads_by_path: Dictionary[String, int] = {}

static func instantiate(art: String, cache: MapModelCache) -> Node3D:
	var path: String = RuntimeAssets.resolve_model_scene(RuntimeAssets.converted_path(_model_path(art)))
	if not path.is_empty():
		if not _scenes.has(path):
			var scene: PackedScene = RuntimeAssets.load_packed_scene(path)
			if scene != null:
				_scenes[path] = scene
				scene_loads += 1
				_loads_by_path[path] = int(_loads_by_path.get(path, 0)) + 1
		if _scenes.has(path):
			var root: Node3D = _scenes[path].instantiate() as Node3D
			if CompiledModelPresentation.is_compiled(root):
				CompiledModelPresentation.hide_backgrounds(root)
				TeleportEffectPresentation.prepare(root, art)
				return root
			if root != null:
				if cache == null:
					return root
				root.free()
	if cache == null:
		return null
	var root: Node3D = cache.instance_glb(RuntimeAssets.converted_path(_model_path(art)))
	if root != null:
		cache.prepare_fx_model(root, RuntimeAssets.converted_path(_model_path(art)))
	return root

static func play(root: Node3D, logical: String, loop: bool = false) -> String:
	var player: AnimationPlayer = AnimPlayback.find_animation_player(root)
	if player == null:
		return ""
	var clip: String = AnimPlayback.resolve(root, logical, player)
	if clip.is_empty():
		return ""
	# Loop policy belongs to this instance, never mutate the retained scene template.
	var library_name: String = clip.get_slice("/", 0) if clip.contains("/") else ""
	var leaf: String = clip.get_slice("/", 1) if clip.contains("/") else clip
	var library: AnimationLibrary = player.get_animation_library(library_name).duplicate() as AnimationLibrary
	var animation: Animation = player.get_animation(clip).duplicate() as Animation
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	library.remove_animation(leaf)
	library.add_animation(leaf, animation)
	player.remove_animation_library(library_name)
	player.add_animation_library(library_name, library)
	player.active = true
	player.play(clip)
	player.advance(0.0)
	return clip

static func warm_for_ability(id: String, cache: MapModelCache) -> void:
	for art: String in [AbilityFxCatalog.ground_effect_art(id), AbilityFxCatalog.caster_art(id), AbilityFxCatalog.special_art(id), AbilityFxCatalog.hit_effect_art(id)]:
		if not art.is_empty():
			var root: Node3D = instantiate(art, cache)
			if root != null:
				root.free()

static func clear() -> void:
	_scenes.clear()

static func _model_path(art: String) -> String:
	var path: String = art.strip_edges().replace("\\", "/")
	return path.get_basename() + ".gltf" if path.get_extension().to_lower() in ["mdx", "mdl"] else path

static func load_count(art: String) -> int:
	var path: String = RuntimeAssets.resolve_model_scene(RuntimeAssets.converted_path(_model_path(art)))
	return int(_loads_by_path.get(path, 0))
