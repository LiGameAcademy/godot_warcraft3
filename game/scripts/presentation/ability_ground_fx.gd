class_name AbilityGroundFx
extends Node3D

## 点地技能地面特效（Present）：WC3 Effectart → GLB + PE2。

const FALLBACK_DIAM := 3.6
const FALLBACK_COLOR := Color(0.55, 0.75, 1.0, 0.55)

var _cache: MapModelCache = null
var _inst: Node3D = null
var _art_rel: String = ""
var _age: float = 0.0
var _lifetime: float = 3.0


static func spawn(
	parent: Node,
	wc3_xy: Vector2,
	art_rel: String,
	lifetime_sec: float,
	cache: MapModelCache,
	heightfield: Wc3Heightfield = null
) -> AbilityGroundFx:
	if parent == null or wc3_xy == Vector2.INF:
		return null
	var fx := AbilityGroundFx.new()
	fx.name = "AbilityGroundFx"
	parent.add_child(fx)
	fx._play(wc3_xy, art_rel, lifetime_sec, cache, heightfield)
	return fx


func _play(
	wc3_xy: Vector2,
	art_rel: String,
	lifetime_sec: float,
	cache: MapModelCache,
	heightfield: Wc3Heightfield
) -> void:
	_cache = cache
	_art_rel = art_rel.strip_edges()
	_lifetime = maxf(lifetime_sec, 0.35)
	_age = 0.0
	var z := 0.0
	if heightfield != null and heightfield.is_valid():
		z = heightfield.interpolated_height(wc3_xy.x, wc3_xy.y)
	global_position = Wc3Coords.wc3_xy_to_godot(wc3_xy.x, wc3_xy.y, z + 4.0)
	_inst = _spawn_model(_art_rel)
	if _inst == null:
		_inst = _spawn_fallback()
	if _inst == null:
		queue_free()
		return
	add_child(_inst)
	_try_play_anim(_inst)
	set_process(true)


func _spawn_model(art_rel: String) -> Node3D:
	var rel := art_rel.strip_edges()
	if rel.is_empty():
		return null
	var path := RuntimeAssets.converted_path(rel)
	if _cache != null:
		var n := _cache.instance_glb(path)
		if n != null:
			return n
	if ResourceLoader.exists(path):
		var packed := load(path)
		if packed is PackedScene:
			return (packed as PackedScene).instantiate() as Node3D
	return null


func _spawn_fallback() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(FALLBACK_DIAM, FALLBACK_DIAM)
	plane.orientation = PlaneMesh.FACE_Y
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 22
	mat.albedo_color = FALLBACK_COLOR
	mi.material_override = mat
	return mi


func _try_play_anim(root: Node) -> void:
	var ap := AnimPlayback.find_animation_player(root)
	if ap == null:
		return
	ap.active = true
	var names := ap.get_animation_list()
	if names.is_empty():
		return
	var pick := str(names[0])
	for n in names:
		var leaf := str(n)
		var slash := leaf.rfind("/")
		if slash >= 0:
			leaf = leaf.substr(slash + 1)
		var low := leaf.to_lower()
		if low.begins_with("stand") or low.begins_with("birth") or low.contains("loop"):
			pick = str(n)
			break
	ap.play(pick)
	if not _art_rel.is_empty():
		var path := RuntimeAssets.converted_path(_art_rel)
		if Wc3Pe2Particles.has_emitters(path):
			Wc3Pe2Particles.attach_to(root, path)
		Wc3Pe2Particles.apply_sequence(root, "Stand")


func _process(delta: float) -> void:
	_age += delta
	if _inst is MeshInstance3D:
		var mi := _inst as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			var a := clampf(1.0 - (_age / _lifetime), 0.0, 1.0)
			mat.albedo_color.a = FALLBACK_COLOR.a * a
	if _age >= _lifetime:
		queue_free()
