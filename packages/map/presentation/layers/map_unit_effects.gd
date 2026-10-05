class_name MapUnitEffects
extends RefCounted
## Unit animation phases, ground decoration and render layers.
var _cache: MapModelCache
const DROP_RING_TEX: String = "ReplaceableTextures/Selection/SelectionCircleMed.png"
const DROP_RING_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)
const DROP_RING_Y_BIAS: float = 0.15

func configure(cache: MapModelCache) -> void:
	_cache = cache

func _apply_unit_render_layers(root: Node) -> void:
	if root == null:
		return
	for n: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if gi == null:
			continue
		# 运行时 UberSplat Decal 本身不参与 layers 绘制（Decal 用 cull_mask）
		if bool(gi.get_meta("is_runtime_uber_splat", false)):
			continue
		gi.layers = 0 if bool(gi.get_meta("wc3_portrait_background", false)) else Wc3Coords.RENDER_LAYER_UNITS


## 建筑：地面 UberSplat 贴花 + 按模型脚底环下沉，减轻「悬空」。
## 不改 heightfield（对齐 HiveWE：只插值贴地 + UberSplat 过渡，不平整地形）。
func _apply_building_ground(node: Node3D, type_id: String, hf: Wc3Heightfield) -> void:
	if node == null:
		return
	var tileset: String = ""
	if hf != null:
		tileset = str(hf.main_tileset)
	# 先估下沉再挂贴花，便于把贴花补偿回地表
	var sink: float = Wc3UberSplat.foot_sink_y(node)
	var y_delta: float = Wc3UberSplat.BUILDING_Y_LIFT - sink
	node.set_meta("building_foot_sink", sink)
	node.set_meta("building_y_delta", y_delta)
	if absf(y_delta) > 1e-5:
		node.position.y += y_delta
	var splat: Node3D = Wc3UberSplat.attach_to(node, type_id, tileset)
	if splat != null:
		Wc3UberSplat.compensate_parent_y(splat, y_delta)


func _refresh_one_height(node: Node, hf: Wc3Heightfield) -> void:
	if node == null or not (node is Node3D) or hf == null or not hf.is_valid():
		return
	var d: Dictionary = node.get_meta("unit_data", {})
	if d.is_empty():
		return
	var pos: Dictionary = d.get("position", {})
	var wx: float = float(pos.get("x", 0.0))
	var wy: float = float(pos.get("y", 0.0))
	var new_z_wc3: float = hf.interpolated_height(wx, wy)
	var n3: Node3D = node as Node3D
	n3.position = Wc3Coords.wc3_xy_to_godot(wx, wy, new_z_wc3)
	var y_delta: float = float(n3.get_meta("building_y_delta", 0.0))
	if absf(y_delta) <= 1e-5:
		# 兼容旧 meta：仅有 foot_sink
		var sink: float = float(n3.get_meta("building_foot_sink", 0.0))
		y_delta = Wc3UberSplat.BUILDING_Y_LIFT - sink
	if absf(y_delta) > 1e-5:
		n3.position.y += y_delta
	var splat: Node3D = n3.get_node_or_null(Wc3UberSplat.SPLAT_ROOT_NAME) as Node3D
	if splat != null:
		Wc3UberSplat.compensate_parent_y(splat, y_delta)
	pos = pos.duplicate()
	pos["z"] = new_z_wc3
	d = d.duplicate(true)
	d["position"] = pos
	node.set_meta("unit_data", d)


## unitUI.teamColor：≥0 时强制该队色（雇佣兵营/酒馆等中立建筑固定红=0）；
## <0（常见 -1）时跟地图 owner。
static func resolve_team_color_index(type_id: String, owner_id: int) -> int:
	if type_id.is_empty():
		return 15 if owner_id >= 12 or owner_id < 0 else clampi(owner_id, 0, 15)
	var store: Node = _def_store()
	if store == null:
		return 15 if owner_id >= 12 or owner_id < 0 else clampi(owner_id, 0, 15)
	store.ensure_table(UnitUiDef.TABLE_NAME)
	var row: Resource = store.get_row(UnitUiDef.TABLE_NAME, type_id)
	if row is UnitUiDef:
		var tc: int = (row as UnitUiDef).team_color
		if tc >= 0:
			return clampi(tc, 0, 15)
	return 15 if owner_id >= 12 or owner_id < 0 else clampi(owner_id, 0, 15)


static func _def_store() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


func _unit_anim_blend(type_id: String) -> float:
	var store: Node = _def_store()
	if store == null:
		return 0.15
	store.ensure_table(UnitUiDef.TABLE_NAME)
	var row: UnitUiDef = store.get_row(UnitUiDef.TABLE_NAME, type_id) as UnitUiDef
	if row != null and row.blend > 0.0:
		return row.blend
	return 0.15


func _play_unit_birth_then_stand(unit_root: Node3D, type_id: String, glb: String) -> void:
	if _cache == null or unit_root == null:
		return
	var model: Wc3ModelScene = Wc3ModelScene.find_on(unit_root)
	var body: Node = model if model != null else unit_root
	var blend: float = _unit_anim_blend(type_id)
	var played: Dictionary
	if model != null:
		played = model.play_logical(
			"Birth", 0.0, _cache, AnimSequenceResolver.Activity.BIRTH, ["Stand"]
		)
	else:
		played = AnimPlayback.play_logical(
			body,
			"Birth",
			0.0,
			_cache,
			AnimSequenceResolver.Activity.BIRTH,
			["Stand"]
		)
	if not bool(played.get("ok", false)):
		_cache.autoplay_stand(unit_root)
		if _cache.has_method("snap_stand_geoset_visibility"):
			_cache.call("snap_stand_geoset_visibility", unit_root)
		if not CompiledModelPresentation.is_compiled(unit_root.get_node_or_null("Model")) and not glb.is_empty():
			Wc3Pe2Particles.apply_sequence(unit_root, "Stand")
		return
	var snap_root: Node = model if model != null else unit_root
	if _cache.has_method("snap_geoset_visibility_for"):
		_cache.call(
			"snap_geoset_visibility_for",
			snap_root,
			str(played.get("played_as", "Birth"))
		)
	# 先按 Birth 关闸/开闸，再 restart 让 Birth 爆发粒子立刻可见
	if not CompiledModelPresentation.is_compiled(unit_root.get_node_or_null("Model")) and not glb.is_empty():
		Wc3Pe2Particles.apply_sequence(unit_root, "Birth")
	if not CompiledModelPresentation.is_compiled(unit_root.get_node_or_null("Model")):
		_restart_pe2_emitters(unit_root)
	var ap: AnimationPlayer = AnimPlayback.find_animation_player(body)
	if ap == null:
		_finish_unit_birth_to_stand(unit_root, glb, blend)
		return
	var birth_resolved: String = str(played.get("resolved", ""))
	var on_finished: Callable = func(anim_name: StringName) -> void:
		if not is_instance_valid(unit_root):
			return
		if not birth_resolved.is_empty() and str(anim_name) != birth_resolved:
			var leaf: String = AnimPlayback.compact_seq_name(str(anim_name))
			if not leaf.begins_with("birth"):
				return
		_finish_unit_birth_to_stand(unit_root, glb, blend)
	ap.animation_finished.connect(on_finished, CONNECT_ONE_SHOT)


func _finish_unit_birth_to_stand(unit_root: Node3D, glb: String, blend: float) -> void:
	if _cache == null or unit_root == null:
		return
	var model: Wc3ModelScene = Wc3ModelScene.find_on(unit_root)
	var body: Node = model if model != null else unit_root
	if model != null:
		model.play_logical("Stand", blend, _cache, AnimSequenceResolver.Activity.IDLE, [])
	else:
		AnimPlayback.play_logical(
			body, "Stand", blend, _cache, AnimSequenceResolver.Activity.IDLE, []
		)
	var snap_root: Node = model if model != null else unit_root
	if _cache.has_method("snap_stand_geoset_visibility"):
		_cache.call("snap_stand_geoset_visibility", snap_root)
	elif _cache.has_method("snap_geoset_visibility_for"):
		_cache.call("snap_geoset_visibility_for", snap_root, "Stand")
	if not CompiledModelPresentation.is_compiled(unit_root.get_node_or_null("Model")) and not glb.is_empty():
		Wc3Pe2Particles.apply_sequence(unit_root, "Stand")


func _restart_pe2_emitters(root: Node, sequence_name: String = "Birth") -> void:
	if root == null:
		return
	for n: Node in root.find_children("*", "GPUParticles3D", true, false):
		if not (n is GPUParticles3D):
			continue
		var p: GPUParticles3D = n as GPUParticles3D
		if not Wc3Pe2Particles.emitting_for_sequence(p, sequence_name):
			continue
		p.restart()
		p.emitting = true


## 地图 scale 乘在 Model 上，避免把选框等逻辑子节点一并缩放。
func _sync_drop_ring(node: Node3D, u: Dictionary, show_drop_rings: bool) -> void:
	if node == null:
		return
	var existing: Node = node.get_node_or_null("DeathDropRing")
	var want: bool = show_drop_rings and Wc3DroppedItemEntry.has_any_drops(u.get("droppedItemSets", []))
	if not want:
		if existing != null:
			existing.queue_free()
		return
	var ring: MeshInstance3D = existing as MeshInstance3D
	if ring == null:
		ring = MeshInstance3D.new()
		ring.name = "DeathDropRing"
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(1.2, 1.2)
		plane.orientation = PlaneMesh.FACE_Y
		ring.mesh = plane
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.render_priority = 25
		mat.albedo_color = DROP_RING_COLOR
		var tex: Texture2D = RuntimeAssets.load_converted_texture(DROP_RING_TEX)
		if tex != null:
			mat.albedo_texture = tex
		ring.material_override = mat
		node.add_child(ring)
	var height: float = _estimate_unit_height(node)
	ring.position = Vector3(0.0, height + DROP_RING_Y_BIAS, 0.0)


func _estimate_unit_height(node: Node3D) -> float:
	var aabb: AABB = AABB()
	var first: bool = true
	for c: Node in node.find_children("*", "VisualInstance3D", true, false):
		var vi: VisualInstance3D = c as VisualInstance3D
		if vi == null:
			continue
		var local: AABB = vi.get_aabb()
		var xf: Transform3D = node.global_transform.affine_inverse() * vi.global_transform
		var world_aabb: AABB = xf * local
		if first:
			aabb = world_aabb
			first = false
		else:
			aabb = aabb.merge(world_aabb)
	if first:
		return 2.0
	return maxf(aabb.size.y, 1.0)
