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


## 瞄准预览：lifetime=0 不自动消失。
static func spawn_preview(
	parent: Node,
	wc3_xy: Vector2,
	art_rel: String,
	cache: MapModelCache,
	heightfield: Wc3Heightfield = null
) -> AbilityGroundFx:
	if parent == null or wc3_xy == Vector2.INF:
		return null
	var fx := AbilityGroundFx.new()
	fx.name = "AbilityGroundFxPreview"
	parent.add_child(fx)
	fx._play(wc3_xy, art_rel, 0.0, cache, heightfield)
	return fx


func reposition(wc3_xy: Vector2, heightfield: Wc3Heightfield = null) -> void:
	if wc3_xy == Vector2.INF:
		return
	var z := 0.0
	if heightfield != null and heightfield.is_valid():
		z = heightfield.interpolated_height(wc3_xy.x, wc3_xy.y)
	global_position = Wc3Coords.wc3_xy_to_godot(wc3_xy.x, wc3_xy.y, z + 4.0)


func _play(
	wc3_xy: Vector2,
	art_rel: String,
	lifetime_sec: float,
	cache: MapModelCache,
	heightfield: Wc3Heightfield
) -> void:
	_cache = cache
	_art_rel = art_rel.strip_edges()
	# 0 = 预览常驻
	_lifetime = lifetime_sec if lifetime_sec <= 0.0 else maxf(lifetime_sec, 0.35)
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
	if _cache != null and not _art_rel.is_empty():
		_cache.prepare_fx_model(_inst, RuntimeAssets.converted_path(_art_rel))
	_try_play_anim(_inst)
	# 预览：Birth 循环，避免播完粒子熄灭
	if _lifetime <= 0.0:
		var ap := AnimPlayback.find_animation_player(_inst)
		if ap != null and not str(ap.current_animation).is_empty():
			var cur := str(ap.current_animation)
			if ap.has_animation(cur):
				var anim := ap.get_animation(cur)
				if anim != null:
					anim.loop_mode = Animation.LOOP_LINEAR
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
	var pick := "Birth"
	if ap != null:
		ap.active = true
		var names := ap.get_animation_list()
		if not names.is_empty():
			pick = str(names[0])
			var birth_pick := ""
			var stand_pick := ""
			for n in names:
				var leaf := str(n)
				var slash := leaf.rfind("/")
				if slash >= 0:
					leaf = leaf.substr(slash + 1)
				var low := leaf.to_lower()
				if low.begins_with("birth") and birth_pick.is_empty():
					birth_pick = str(n)
				elif (
					(low.begins_with("stand") or low.contains("loop"))
					and stand_pick.is_empty()
				):
					stand_pick = str(n)
			# 技能地面特效优先 Birth（暴风雪等无 Stand）
			if not birth_pick.is_empty():
				pick = birth_pick
			elif not stand_pick.is_empty():
				pick = stand_pick
			ap.play(pick)
	var seq_leaf := pick
	var slash2 := seq_leaf.rfind("/")
	if slash2 >= 0:
		seq_leaf = seq_leaf.substr(slash2 + 1)
	if not _art_rel.is_empty():
		var path := RuntimeAssets.converted_path(_art_rel)
		if Wc3Pe2Particles.has_emitters(path):
			Wc3Pe2Particles.attach_to(root, path)
		# 暴风雪等只有 Birth：切 Stand 会关掉粒子
		Wc3Pe2Particles.apply_sequence(root, seq_leaf)


func _process(delta: float) -> void:
	_age += delta
	if _inst is MeshInstance3D:
		var mi := _inst as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			var a := 1.0
			if _lifetime > 0.0:
				a = clampf(1.0 - (_age / _lifetime), 0.0, 1.0)
			mat.albedo_color.a = FALLBACK_COLOR.a * a
	if _lifetime <= 0.0:
		return
	if _age >= _lifetime:
		queue_free()
