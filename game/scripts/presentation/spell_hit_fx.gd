class_name SpellHitFx
extends Node3D

## 技能命中附着特效（Present）：FrostDamage 等，短寿命。

const LIFETIME := 0.85
const FALLBACK_RADIUS := 0.35
const FALLBACK_COLOR := Color(0.55, 0.85, 1.0, 0.75)

var _age: float = 0.0
var _inst: Node3D = null


static func spawn_on(
	target: Node3D,
	art_rel: String,
	cache: MapModelCache = null,
	attach_name: String = "origin"
) -> SpellHitFx:
	if target == null or not is_instance_valid(target):
		return null
	var fx := SpellHitFx.new()
	fx.name = "SpellHitFx"
	target.add_child(fx)
	fx._play(art_rel, cache, attach_name)
	return fx


func _play(art_rel: String, cache: MapModelCache, attach_name: String) -> void:
	position = _attach_offset(get_parent() as Node3D, attach_name)
	_inst = _spawn_model(art_rel, cache)
	if _inst == null:
		_inst = _spawn_fallback()
	if _inst != null:
		add_child(_inst)
		_try_play_anim(_inst, art_rel)
	_age = 0.0
	set_process(true)


static func _attach_offset(target: Node3D, attach_name: String) -> Vector3:
	if target == null:
		return Vector3(0.0, 1.0, 0.0)
	var y := DamageFloatText._estimate_anchor_y(target) * 0.55
	return Vector3(0.0, y, 0.0)


func _spawn_model(art_rel: String, cache: MapModelCache) -> Node3D:
	var rel := art_rel.strip_edges()
	if rel.is_empty():
		return null
	var path := RuntimeAssets.converted_path(rel)
	if cache != null:
		var n := cache.instance_glb(path)
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
	var mesh := SphereMesh.new()
	mesh.radius = FALLBACK_RADIUS
	mesh.height = FALLBACK_RADIUS * 2.0
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 24
	mat.albedo_color = FALLBACK_COLOR
	mi.material_override = mat
	return mi


func _try_play_anim(root: Node, art_rel: String) -> void:
	var ap := AnimPlayback.find_animation_player(root)
	if ap == null:
		return
	ap.active = true
	var names := ap.get_animation_list()
	if not names.is_empty():
		ap.play(str(names[0]))
	if not art_rel.is_empty():
		var path := RuntimeAssets.converted_path(art_rel)
		if Wc3Pe2Particles.has_emitters(path):
			Wc3Pe2Particles.attach_to(root, path)
		Wc3Pe2Particles.apply_sequence(root, "Birth")


func _process(delta: float) -> void:
	_age += delta
	if _inst is MeshInstance3D:
		var mi := _inst as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			var t := clampf(_age / LIFETIME, 0.0, 1.0)
			mat.albedo_color.a = FALLBACK_COLOR.a * (1.0 - t)
		scale = Vector3.ONE * (1.0 + _age * 0.35)
	if _age >= LIFETIME:
		queue_free()
