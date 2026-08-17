class_name BuildPlacementGhost
extends Node3D

## 建造预览（Present）— 对齐原作：
## - 落点吸附寻路格（PATHING_CELL=32；调试「小」格；「中」格=4×4 小格）
## - 底图按 footprint **逐格**上色（可建绿 / 不可建红），几何为**共享顶点网格** → 无分块缝
## - 半透明建筑模型跟吸附中心

const COLOR_OK := Color(0.20, 1.00, 0.35, 0.55)
const COLOR_BAD := Color(1.00, 0.22, 0.18, 0.55)
## 落点确认后钉在工地：无绿/红/淡蓝染色，仅半透明幽灵（与建成实体区分）
const COLOR_PINNED_OVERLAY := Color(0.0, 0.0, 0.0, 0.0)
## GeometryInstance3D.transparency：0=不透明，1=全透明；下面是「透明度」不是 opacity
const MODEL_TRANSPARENCY := 0.55
const MODEL_TRANSPARENCY_PINNED := 0.62
const MODEL_ALBEDO_ALPHA := 0.42
const MODEL_ALBEDO_ALPHA_PINNED := 0.38
const CELL_Y_BIAS := 0.04 ## Godot：略抬离地表

var _cells_mi: MeshInstance3D = null
var _cell_mat: StandardMaterial3D = null
var _overlay_mat: StandardMaterial3D = null
var _model_root: Node3D = null
var _is_valid: bool = true
## true：工地钉住幽灵（开工前）— 模型不染色，格网可藏
var _pinned_style: bool = false
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
	_pinned_style = false
	_last_min_cell = Vector2i(999999, 999999)
	_last_fp_size = Vector2i.ZERO
	_ensure_cell_drawer()
	_ensure_materials()
	_rebuild_model()
	_apply_model_tint()


## 落点确认后钉在工地：纯半透明，去掉瞄准时的绿/红染色。
func set_pinned_style(on: bool) -> void:
	if _pinned_style == on:
		return
	_pinned_style = on
	if _cells_mi != null:
		# 钉住期间只留建筑幽灵，不再刷绿/红格
		_cells_mi.visible = not on and visible
	_apply_model_tint()


## Director：用控制器采样结果 + heightfield 刷新逐格底图与模型位置。
func update_from_sample(
	sample: Dictionary,
	pathing: Wc3PathingMap,
	heightfield: Wc3Heightfield,
	site_wc3: Vector2
) -> void:
	if sample.is_empty() or pathing == null or not pathing.is_valid():
		if _cells_mi != null:
			_cells_mi.visible = false
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
	if _cells_mi != null:
		_cells_mi.visible = v and not _pinned_style
	if _model_root != null:
		_model_root.visible = v
	# 模型曾加载失败时，再次显示时重试一次
	if v and _model_root == null and not _building_id.is_empty():
		_rebuild_model()
		if _model_root != null:
			_model_root.visible = true


func current_building_id() -> String:
	return _building_id


func _ensure_cell_drawer() -> void:
	if _cells_mi != null:
		return
	_cells_mi = MeshInstance3D.new()
	_cells_mi.name = "GhostFootCells"
	_cells_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 底图用全局顶点；与 ghost 根分离，避免跟模型旋转
	_cells_mi.top_level = true
	add_child(_cells_mi)


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
		_cells_mi.visible = false
		return
	_last_min_cell = min_c
	_last_fp_size = fp
	_cells_mi.visible = true
	_cells_mi.material_override = _cell_mat
	# 顶点已是世界坐标；保持 identity，避免跟 ghost 根叠变换
	_cells_mi.global_transform = Transform3D.IDENTITY

	# 共享顶点网格：邻格共边 → 无几何缝；角点色取邻格平均 → 同色区视觉整块
	var gw := fp.x + 1
	var gh := fp.y + 1
	var corners: PackedVector3Array = PackedVector3Array()
	corners.resize(gw * gh)
	var cs := pathing.cell_size
	for iy in range(gh):
		for ix in range(gw):
			var wx := pathing.origin_wc3.x + float(min_c.x + ix) * cs
			var wy := pathing.origin_wc3.y + float(min_c.y + iy) * cs
			var h_wc3 := 0.0
			if heightfield != null and heightfield.is_valid():
				h_wc3 = heightfield.interpolated_height(wx, wy)
			var gp := Wc3Coords.wc3_xy_to_godot(wx, wy, h_wc3)
			gp.y += CELL_Y_BIAS
			corners[iy * gw + ix] = gp

	var corner_cols: PackedColorArray = PackedColorArray()
	corner_cols.resize(gw * gh)
	var corner_w: PackedFloat32Array = PackedFloat32Array()
	corner_w.resize(gw * gh)
	for i in range(gw * gh):
		corner_cols[i] = Color(0, 0, 0, 0)
		corner_w[i] = 0.0
	for dy in range(fp.y):
		for dx in range(fp.x):
			var ci := dy * fp.x + dx
			var ok := ci < mask.size() and int(mask[ci]) != 0
			var col := COLOR_OK if ok else COLOR_BAD
			for oy in range(2):
				for ox in range(2):
					var k := (dy + oy) * gw + (dx + ox)
					var c := corner_cols[k]
					corner_cols[k] = Color(c.r + col.r, c.g + col.g, c.b + col.b, c.a + col.a)
					corner_w[k] = corner_w[k] + 1.0
	for i in range(gw * gh):
		var w := corner_w[i]
		if w > 0.0:
			var c := corner_cols[i]
			corner_cols[i] = Color(c.r / w, c.g / w, c.b / w, c.a / w)
		else:
			corner_cols[i] = COLOR_OK

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(gw * gh)
	colors.resize(gw * gh)
	for i in range(gw * gh):
		verts[i] = corners[i]
		colors[i] = corner_cols[i]
	indices.resize(fp.x * fp.y * 6)
	var ti := 0
	for dy in range(fp.y):
		for dx in range(fp.x):
			var i00 := dy * gw + dx
			var i10 := dy * gw + dx + 1
			var i01 := (dy + 1) * gw + dx
			var i11 := (dy + 1) * gw + dx + 1
			indices[ti] = i00
			indices[ti + 1] = i10
			indices[ti + 2] = i11
			indices[ti + 3] = i00
			indices[ti + 4] = i11
			indices[ti + 5] = i01
			ti += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cells_mi.mesh = am


func _clear_model() -> void:
	if _model_root == null:
		return
	_model_root.queue_free()
	_model_root = null


func _rebuild_model() -> void:
	_clear_model()
	if _building_id.is_empty() or _cache == null or _catalog == null:
		push_warning("BuildPlacementGhost: 缺 cache/catalog/id，无法刷幽灵模型")
		return
	var glb := _catalog.converted_glb_path(_building_id, 0)
	if glb.is_empty():
		push_warning("BuildPlacementGhost: 无 converted 模型 path id=%s" % _building_id)
		return
	var inst: Node3D = null
	if _cache.has_cached(glb):
		inst = _cache.instance_glb(glb)
	else:
		inst = _cache.instance_glb_preview(glb, true)
	if inst == null:
		push_warning("BuildPlacementGhost: instance 失败 id=%s path=%s" % [_building_id, glb])
		return
	inst.name = "GhostBuilding"
	_strip_runtime_fx(inst)
	_play_stand(inst)
	add_child(inst)
	_model_root = inst
	# 与完工建筑同一默认朝向（bj_UNIT_FACING = 270°）
	_model_root.rotation.y = Wc3Coords.yaw_wc3_unit_to_godot(deg_to_rad(270.0))
	_model_root.visible = true
	_ghostify_meshes(inst)
	_apply_model_tint()


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
		# 队色 shader 写死 ALPHA=1，instance.transparency 无效；改走表面材质 alpha
		gi.transparency = 0.0
		if _pinned_style:
			gi.material_overlay = null
		else:
			gi.material_overlay = _overlay_mat
		if root is MeshInstance3D:
			_force_mesh_alpha(root as MeshInstance3D)
	for c in root.get_children():
		_ghostify_meshes(c)


## 用半透明 StandardMaterial 替换表面（含队色 ShaderMaterial），否则幽灵看不出透明。
func _force_mesh_alpha(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null:
		return
	var a := MODEL_ALBEDO_ALPHA_PINNED if _pinned_style else MODEL_ALBEDO_ALPHA
	for si in range(mi.mesh.get_surface_count()):
		var base: Material = mi.get_active_material(si)
		var tex := _extract_albedo_tex(base)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.albedo_color = Color(1.0, 1.0, 1.0, a)
		if tex != null:
			sm.albedo_texture = tex
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mi.set_surface_override_material(si, sm)


func _extract_albedo_tex(mat: Material) -> Texture2D:
	if mat == null:
		return null
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_texture
	if mat is ShaderMaterial:
		var shm := mat as ShaderMaterial
		for key in ["diffuse_tex", "albedo_texture", "texture_albedo", "albedo_tex"]:
			var v: Variant = shm.get_shader_parameter(key)
			if v is Texture2D:
				return v as Texture2D
	return null


func _apply_model_tint() -> void:
	_ensure_materials()
	if _pinned_style:
		_overlay_mat.albedo_color = COLOR_PINNED_OVERLAY
	else:
		var c := COLOR_OK if _is_valid else COLOR_BAD
		_overlay_mat.albedo_color = Color(c.r, c.g, c.b, 0.28)
	if _model_root != null:
		_ghostify_meshes(_model_root)
