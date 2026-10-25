class_name MapModelCache
extends RefCounted
## Stable model-loading API. The scene cache owns prototypes; handed-out instances belong to callers.
const Scenes: GDScript = preload("model_cache/model_scene_cache.gd")
const Preloads: GDScript = preload("model_cache/model_preload_queue.gd")
const Rules: GDScript = preload("model_cache/model_material_rules.gd")
const Tracks: GDScript = preload("model_cache/model_animation_tracks.gd")
const Pose: GDScript = preload("model_cache/model_animation_pose.gd")
const Queries: GDScript = preload("model_cache/model_animation_queries.gd")
const Geometry: GDScript = preload("model_cache/model_geometry.gd")
const DEFAULT_BAKE_TEAM_COLOR: int = 0
const META_FX_SPHERE_PRESENTED: String = Rules.META_FX_SPHERE_PRESENTED
const META_GLOW_PRESENTED: String = "wc3_team_glow_presented"
const META_GLOW_BILLBOARD: String = "wc3_team_glow_billboard"
const META_GLOW_CATEGORY: String = "wc3_team_glow_category"
const TEAM_GLOW_FOOT_NY: float = 0.65
const WC3_TRANSPARENT_MASK_THRESHOLD: float = Rules.WC3_TRANSPARENT_MASK_THRESHOLD
const WC3_BLEND_SCISSOR_THRESHOLD: float = Rules.WC3_BLEND_SCISSOR_THRESHOLD
var _preloader: RefCounted = Preloads.new()
var _scenes: RefCounted = Scenes.new(_preloader)

## Setter参数由属性的int类型固定；GDScript setter不接受独立类型注解。
var last_scn_hits: int:
	get:
		return _scenes.last_scn_hits
	set(value):
		_scenes.last_scn_hits = value

var last_gltf_loads: int:
	get:
		return _scenes.last_gltf_loads
	set(value):
		_scenes.last_gltf_loads = value

var last_cache_hits: int:
	get:
		return _scenes.last_cache_hits
	set(value):
		_scenes.last_cache_hits = value


func reset_load_stats() -> void:
	_scenes.reset_load_stats()


func instance_glb(path: String, unit_soft_blend: bool = false) -> Node3D:
	return _scenes.instance_glb(path, unit_soft_blend)


func instance_glb_hud(path: String) -> Node3D:
	return _scenes.instance_glb_hud(path)


func has_cached(path: String) -> bool:
	return _scenes.has_cached(path)


func get_proto(path: String) -> Node3D:
	return _scenes.get_proto(path)


func has_model_scene(path: String) -> bool:
	return _scenes.has_model_scene(path)


func evict(path: String) -> void:
	_scenes.evict(path)


func register_external_packed(glb_path: String, packed: PackedScene) -> void:
	_scenes.register_external_packed(glb_path, packed)


func request_preload_many(paths: PackedStringArray) -> void:
	for path: String in paths:
		request_preload(path)


func request_preload(glb_path: String) -> void:
	_preloader.request_preload(glb_path, _scenes.has_cached(glb_path.strip_edges()))


func is_preload_pending(glb_path: String) -> bool:
	return _preloader.is_preload_pending(glb_path)


func preload_pending_count() -> int:
	return _preloader.preload_pending_count()


func cancel_preloads() -> void:
	_preloader.cancel_preloads()


func poll_preloads(gltf_budget: int = 1) -> int:
	return _preloader.poll_preloads(gltf_budget, _scenes.has_cached, _scenes.register_external_packed, _scenes._finish_gltf_preload)


func has_bytes_cached(path: String) -> bool:
	return _preloader.has_bytes_cached(path)


func store_bytes(path: String, bytes: PackedByteArray) -> void:
	_preloader.store_bytes(path, bytes)


func take_cached_bytes(path: String) -> PackedByteArray:
	return _preloader.take_cached_bytes(path)


func instance_glb_preview(
	path: String, prefer_visuals: bool = true, unit_soft_blend: bool = false
) -> Node3D:
	return _scenes.instance_glb_preview(path, prefer_visuals, unit_soft_blend)


static func glb_path_uses_unit_soft_blend(logical_path: String) -> bool:
	return Rules.glb_path_uses_unit_soft_blend(logical_path)


func instance_glb_from_bytes_preview(path: String, bytes: PackedByteArray) -> Node3D:
	return _scenes.instance_glb_from_bytes_preview(path, bytes)


func instance_glb_from_bytes(path: String, bytes: PackedByteArray) -> Node3D:
	return _scenes.instance_glb_from_bytes(path, bytes)


func process_lazy_bake_one() -> bool:
	return _scenes.process_lazy_bake_one()


static func apply_bone_rest_sidecar(proto: Node, glb_path: String) -> void:
	Tracks.apply_bone_rest_sidecar(proto, glb_path)


func bake_model_scene(glb_path: String, force: bool = false) -> bool:
	return _scenes.bake_model_scene(glb_path, force)


func reinject_geoset_vis_tracks(glb_path: String) -> bool:
	return _scenes.reinject_geoset_vis_tracks(glb_path)


func apply_team_color(root: Node, color_index: int = 0, hide_team_glow: bool = false) -> void:
	_scenes.apply_team_color(root, color_index, hide_team_glow)


func prepare_fx_model(root: Node3D, source_path: String = "") -> void:
	Rules.prepare_fx_model(root, source_path)


func glb_has_animation(path: String) -> bool:
	return _scenes.glb_has_animation(path)


func autoplay_stand(root: Node, random_phase: bool = true) -> bool:
	return Queries.autoplay_stand(root, random_phase)


func list_animations(root: Node, _for_preview: bool = false) -> PackedStringArray:
	return Queries.list_animations(root, _for_preview)


func play_animation(root: Node, anim_name: String, loop: bool = true) -> bool:
	return Queries.play_animation(root, anim_name, loop)


func glb_has_mesh(path: String) -> bool:
	return _scenes.glb_has_mesh(path)


func node_has_mesh(root: Node) -> bool:
	return Geometry.node_has_mesh(root)


func mesh_from_glb(path: String) -> Mesh:
	return _scenes.mesh_from_glb(path)


func mesh_parts_from_glb(path: String) -> Array:
	return _scenes.mesh_parts_from_glb(path)


func reveal_hidden_geosets_public(root: Node) -> void:
	Pose.reveal_hidden_geosets_public(root)


func snap_stand_geoset_visibility(root: Node) -> void:
	Pose.snap_stand_geoset_visibility(root)


func snap_geoset_visibility_for(
	root: Node, anim_name: String, at_time: float = 0.0, hide_zero_scale: bool = true
) -> void:
	Pose.snap_geoset_visibility_for(root, anim_name, at_time, hide_zero_scale)
