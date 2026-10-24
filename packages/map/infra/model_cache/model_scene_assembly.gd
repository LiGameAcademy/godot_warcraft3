extends RefCounted
## 组装模型表现并保存原型；不拥有运行时缓存。

const Queries: GDScript = preload("model_animation_queries.gd")
const Rules: GDScript = preload("model_material_rules.gd")
const Tracks: GDScript = preload("model_animation_tracks.gd")



static func _try_load_scn_packed(glb_path: String, prefer_visuals: bool = true) -> PackedScene:
	# prefer_visuals=true：从 .scn 运行时组装配方（anim / geoset / PE2）。
	# 不再依赖 assets/visuals/*.tscn（薄继承已过时；D3 亦不入 git）。
	if prefer_visuals:
		var composed: PackedScene = _compose_visual_packed(glb_path)
		if composed != null:
			return composed
	var scn_path: String = RuntimeAssets.resolve_model_scene(glb_path)
	if scn_path.is_empty():
		return null
	return RuntimeAssets.load_packed_scene(scn_path)


## 从 bake .scn 组装运行时模型（PE2 / Wc3AnimPlayer / geoset / Wc3ModelScene）。
static func _compose_visual_packed(glb_path: String) -> PackedScene:
	var scn_path: String = RuntimeAssets.resolve_model_scene(glb_path)
	if scn_path.is_empty():
		return null
	var base: PackedScene = RuntimeAssets.load_packed_scene(scn_path)
	if base == null:
		return null
	var root_n: Node = base.instantiate()
	if root_n == null or not (root_n is Node3D):
		if root_n:
			root_n.free()
		return null
	var root: Node3D = root_n as Node3D
	var logical: String = glb_path.replace("\\", "/").trim_prefix("res://assets/asset-converted/")
	Rules._fix_wc3_blend_materials(root, Rules.glb_path_uses_unit_soft_blend(logical))
	var ap: AnimationPlayer = Queries._find_animation_player(root)
	if ap != null:
		ap.autoplay = ""
		ap.stop()
		const _Anim: GDScript = preload("res://packages/map/presentation/wc3_model/wc3_anim_player.gd")
		if ap.get_script() != _Anim:
			ap.set_script(_Anim)
	Tracks._inject_geoset_vis_tracks(glb_path, root)
	const _Pe2: GDScript = preload("res://packages/map/presentation/effects/wc3_pe2_particles.gd")
	const _Model: GDScript = preload("res://packages/map/presentation/wc3_model/wc3_model_scene.gd")
	if _Pe2.has_emitters(glb_path):
		_Pe2.attach_to(root, glb_path)
	# PE2 就位后再剪悬空轨（含旧 bake 写进 Stand 的 Death-only :emitting）
	if ap != null and ap.has_method("prune_unresolved_tracks"):
		ap.call("prune_unresolved_tracks")
	root.set_script(_Model)
	var packed: PackedScene = PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return null
	root.free()
	return packed


## bake 直前：根挂 Wc3ModelScene，AP 挂 Wc3AnimPlayer。
static func _ensure_model_scene_scripts(root: Node) -> void:
	if root == null:
		return
	const _Model: GDScript = preload("res://packages/map/presentation/wc3_model/wc3_model_scene.gd")
	const _Anim: GDScript = preload("res://packages/map/presentation/wc3_model/wc3_anim_player.gd")
	if root.get_script() != _Model:
		root.set_script(_Model)
	var ap: AnimationPlayer = Queries._find_animation_player(root)
	if ap != null and ap.get_script() != _Anim:
		ap.set_script(_Anim)


static func _save_model_scene(proto: Node3D, glb_path: String, team: RefCounted) -> String:
	# 材质修正必须进 .scn：编辑器直接打开 scn 不会再走 instance_glb 修正。
	# （export 里 instance_glb_preview 修的是临时 dup，bake 烤的是 proto。）
	var logical: String = glb_path.replace("\\", "/").trim_prefix("res://assets/asset-converted/")
	var unit_soft: bool = Rules.glb_path_uses_unit_soft_blend(logical)
	if unit_soft and logical.to_lower().contains("water"):
		proto.set_meta("wc3_waterish_model", true)
	Rules._stamp_glb_model_meta(proto, glb_path, unit_soft)
	Rules._fix_wc3_blend_materials(proto, unit_soft)
	# 飞弹/技能特效：语义 present（软球 / 广告牌）；PE2 已由 pe2 bake 写入
	if FireballMissileModern.wants(logical, proto):
		FireballMissileModern.apply(proto)
		proto.set_meta("wc3_fx_scaled", true)
	elif Wc3FxPresenter.path_wants_fx_present(logical):
		Wc3FxPresenter.present(proto)
		Wc3FxPresenter.maybe_apply_plan_b(proto, logical)
		proto.set_meta("wc3_fx_scaled", true)
	Wc3MdxOmni.snap_all(proto)
	Tracks.apply_bone_rest_sidecar(proto, glb_path)
	team.apply_team_color(proto, 0, false)
	# 门面脚本必须在 pack 直前挂上（export 里 set_script 曾未写入 .scn）
	_ensure_model_scene_scripts(proto)
	var res_p: String = RuntimeAssets.model_scene_path(glb_path)
	var user_p: String = RuntimeAssets.model_scene_user_path(glb_path)
	var saved_path: String = ""
	var err: Error = RuntimeAssets.save_packed_scene(proto, res_p)
	if err == OK:
		saved_path = res_p
	else:
		err = RuntimeAssets.save_packed_scene(proto, user_p)
		if err == OK:
			saved_path = user_p
	return saved_path if err == OK else ""
