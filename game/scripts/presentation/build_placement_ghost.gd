class_name BuildPlacementGhost
extends Node3D

## 建造预览（Present）— 对齐原作：
## - 落点吸附寻路格（PATHING_CELL=32；调试「小」格；「中」格=4×4 小格）
## - 底图按 footprint **逐格**贴地绘制：可建绿 / 不可建红（非整块变色）
## - 半透明建筑模型跟吸附中心

const COLOR_OK := Color(0.20, 1.00, 0.35, 0.55)
const COLOR_BAD := Color(1.00, 0.22, 0.18, 0.55)
const MODEL_ALPHA := 0.48
const CELL_Y_BIAS := 0.04 ## Godot：略抬离地表

var _cells_mmi: MultiMeshInstance3D = null
var _cell_mat: StandardMaterial3D = null
var _overlay_mat: StandardMaterial3D = null
var _model_root: Node3D = null
var _is_valid: bool = true
var _building_id: String = ""
var _cache: MapModelCache = null
var _catalog: Wc3IdCatalog = null
var _last_min_cell: Vector2i = Vector2i(999999, 999999)
var _last_fp_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	top_level = true
	_ensure_cell_drawer()
	_ensure_materials()
	visible = false


func configure(cache: MapModelCache, catalog: Wc3IdCatalog) -> void:
	_cache = cache
	_catalog = catalog


func set_building(building_id: String) -> void:
	_building_id = building_id.strip_edges()
	_last_min_cell = Vector2i(999999, 999999)
	_last_fp_size = Vector2i.ZERO
	_ensure_cell_drawer()
	_ensure_materials()
	_rebuild_model()
	_apply_model_tint()


## Director：用控制器采样结果 + heightfield 刷新逐格底图与模型位置。
func update_from_sample(
	sample: Dictionary,
	pathing: Wc3PathingMap,
	heightfield: Wc3Heightfield,
	site_wc3: Vector2
) -> void:
	if sample.is_empty() or pathing == null or not pathing.is_valid():
		if _cells_mmi != null:
			_cells_mmi.visible = false
		return
	var min_c: Vector2i = sample.get("min_cell", Vector2i.ZERO)
	var fp: Vector2i = sample.get("size", Vector2i.ZERO)
	var mask: PackedByteArray = sample.get("ok", PackedByteArray()) as PackedByteArray
	var all_ok := bool(sample.get("all_ok", false))
	_is_valid = all_ok
	_apply_model_tint()
	_rebuild_cells(min_c, fp, mask, pathing, heightfield)
	# 模型放在吸附中心（地表高度）
	if site_wc3 != Vector2.INF:
		var h_wc3 := 0.0
		if heightfield != null and heightfield.is_valid():
			h_wc3 = heightfield.interpolated_height(site_wc3.x, site_wc3.y)
		var gp := Wc3Coords.wc3_xy_to_godot(site_wc3.x, site_wc3.y, h_wc3)
		gp.y += CELL_Y_BIAS
		global_position = gp
		if _model_root != null:
			_model_root.position = Vector3.ZERO


func set_position_godot(world: Vector3) -> void:
	world.y += CELL_Y_BIAS
	global_position = world


func set_valid(ok: bool) -> void:
	if _is_valid == ok:
		return
	_is_valid = ok
	_apply_model_tint()


func set_visible_preview(v: bool) -> void:
	visible = v
	if _cells_mmi != null:
		_cells_mmi.visible = v
	if _model_root != null:
		_model_root.visible = v


func current_building_id() -> String:
	return _building_id


func _ensure_cell_drawer() -> void:
	if _cells_mmi != null:
		return
	_cells_mmi = MultiMeshInstance3D.new()
	_cells_mmi.name = "GhostFootCells"
	_cells_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 底图跟随本节点；用全局坐标写 instance transform 时设 top_level
	_cells_mmi.top_level = true
	add_child(_cells_mmi)


func _ensure_materials() -> void:
	if _cell_mat == null:
		_cell_mat = StandardMaterial3D.new()
		_cell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cell_mat.vertex_color_use_as_albedo = true
		# 贴地绘制仍可能被地形咬边；关深度测试保证格色可见（格很小，不会整屏盖色）
		_cell_mat.no_depth_test = true
		_cell_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_cell_mat.render_priority = 12
	if _overlay_mat == null:
		_overlay_mat = StandardMaterial3D.new()
		_overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_overlay_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _rebuild_cells(
	min_c: Vector2i,
	fp: Vector2i,
	mask: PackedByteArray,
	pathing: Wc3PathingMap,
	heightfield: Wc3Heightfield
) -> void:
	_ensure_cell_drawer()
	_ensure_materials()
	if fp.x <= 0 or fp.y <= 0:
		_cells_mmi.visible = false
		return
	var n := fp.x * fp.y
	var cs_g := pathing.cell_size * Wc3Coords.WORLD_SCALE
	var need_new_mesh := (
		_cells_mmi.multimesh == null
		or _last_fp_size != fp
		or _cells_mmi.multimesh.instance_count != n
	)
	var mm: MultiMesh
	if need_new_mesh:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var pm := PlaneMesh.new()
		# 满格铺满，无缝（原作建造底图也是连续色块）
		pm.size = Vector2(cs_g, cs_g)
		mm.mesh = pm
		mm.instance_count = n
		_cells_mmi.multimesh = mm
		_cells_mmi.material_override = _cell_mat
		_last_fp_size = fp
	else:
		mm = _cells_mmi.multimesh
		if mm.mesh is PlaneMesh:
			(mm.mesh as PlaneMesh).size = Vector2(cs_g, cs_g)
	_last_min_cell = min_c
	_cells_mmi.visible = true
	for dy in range(fp.y):
		for dx in range(fp.x):
			var i := dy * fp.x + dx
			var px := min_c.x + dx
			var py := min_c.y + dy
			var center := pathing.cell_center_wc3(px, py)
			var h_wc3 := 0.0
			if heightfield != null and heightfield.is_valid():
				h_wc3 = heightfield.interpolated_height(center.x, center.y)
			var gp := Wc3Coords.wc3_xy_to_godot(center.x, center.y, h_wc3)
			gp.y += CELL_Y_BIAS
			var xf := Transform3D(Basis.IDENTITY, gp)
			mm.set_instance_transform(i, xf)
			var ok := i < mask.size() and int(mask[i]) != 0
			mm.set_instance_color(i, COLOR_OK if ok else COLOR_BAD)


func _clear_model() -> void:
	if _model_root == null:
		return
	_model_root.queue_free()
	_model_root = null


func _rebuild_model() -> void:
	_clear_model()
	if _building_id.is_empty() or _cache == null or _catalog == null:
		return
	var glb := _catalog.converted_glb_path(_building_id, 0)
	if glb.is_empty():
		return
	var inst: Node3D = null
	if _cache.has_cached(glb):
		inst = _cache.instance_glb(glb)
	else:
		inst = _cache.instance_glb_preview(glb, true)
	if inst == null:
		return
	inst.name = "GhostBuilding"
	_strip_runtime_fx(inst)
	_play_stand(inst)
	add_child(inst)
	_model_root = inst
	_ghostify_meshes(inst)


func _play_stand(root: Node3D) -> void:
	if _cache == null or root == null:
		return
	var want := BuildingVisual.sequence_name(_building_id, BuildingVisual.Phase.IDLE)
	var resolved := BuildingVisual.resolve_animation(root, want)
	if resolved.is_empty():
		_cache.autoplay_stand(root, false)
	else:
		_cache.play_animation(root, resolved, true)
	if _cache.has_method("snap_stand_geoset_visibility"):
		_cache.call("snap_stand_geoset_visibility", root)


func _strip_runtime_fx(root: Node) -> void:
	if root == null:
		return
	var kill: Array[Node] = []
	_collect_fx_nodes(root, kill)
	for n in kill:
		if is_instance_valid(n):
			n.queue_free()


func _collect_fx_nodes(n: Node, out: Array[Node]) -> void:
	var nm := n.name
	if (
		n is GPUParticles3D
		or n is CPUParticles3D
		or nm.begins_with("Pe2")
		or nm.begins_with("PE2")
		or nm.begins_with("UberSplat")
		or nm == "UberSplat"
	):
		out.append(n)
		return
	for c in n.get_children():
		_collect_fx_nodes(c, out)


func _ghostify_meshes(root: Node) -> void:
	if root == null:
		return
	if root is GeometryInstance3D:
		var gi := root as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.transparency = MODEL_ALPHA
		gi.material_overlay = _overlay_mat
	for c in root.get_children():
		_ghostify_meshes(c)


func _apply_model_tint() -> void:
	_ensure_materials()
	var c := COLOR_OK if _is_valid else COLOR_BAD
	_overlay_mat.albedo_color = Color(c.r, c.g, c.b, 0.28)
	if _model_root != null:
		_ghostify_meshes(_model_root)
