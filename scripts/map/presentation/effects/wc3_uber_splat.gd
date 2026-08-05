class_name Wc3UberSplat
extends RefCounted

## 建筑 Art - Ground Texture：unitUI.uberSplat → UberSplatData → 地面贴花。
## 贴图优先 tileset 前缀（如 L_HumanTownHallUberSplat），回退无前缀默认图。

const SPLAT_ROOT_NAME := "UberSplat"
## 略抬离地，减轻与地形 z-fight
const Y_BIAS := 0.04
## 建筑贴地下沉上限（Godot）。过大（按完整 UberSplat geoset 高度）会把主城埋进地里。
const FOOT_SINK_MAX := 0.06


static func attach_to(root: Node3D, type_id: String, tileset: String = "") -> MeshInstance3D:
	if root == null or type_id.is_empty() or type_id == "sloc":
		return null
	var existing := root.get_node_or_null(SPLAT_ROOT_NAME)
	if existing != null:
		existing.queue_free()
	var code := _uber_splat_code(type_id)
	if code.is_empty() or code == "_":
		return null
	Wc3DefStore.ensure_table(UberSplatDef.TABLE_NAME)
	var row: Resource = Wc3DefStore.get_row(UberSplatDef.TABLE_NAME, code)
	if not (row is UberSplatDef):
		return null
	var def := row as UberSplatDef
	if def.file.is_empty() or def.scale <= 0.0:
		return null
	var tex := _load_splat_texture(def, tileset)
	if tex == null:
		return null
	var size_g := def.scale * Wc3Coords.WORLD_SCALE
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_g, size_g)
	plane.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	# BlendMode 0 = Blend；其它少见，先按 alpha 混合
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.render_priority = -8
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = SPLAT_ROOT_NAME
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, Y_BIAS, 0.0)
	mi.set_meta("uber_splat_code", code)
	root.add_child(mi)
	return mi


## 用模型内嵌 UberSplat geoset（即使已隐藏）估脚底高度，把建筑沉到贴地。
## 返回应从 position.y 减去的量（Godot 单位）；无则 0。
static func foot_sink_y(root: Node3D) -> float:
	if root == null:
		return 0.0
	var splat_min := INF
	var visible_min := INF
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if str(mi.name) == SPLAT_ROOT_NAME:
			continue
		if _is_under_pe2(mi):
			continue
		var local_aabb := _aabb_in_root(root, mi)
		var blob := _mesh_blob(mi)
		if blob.contains("ubersplat") or blob.contains("/splats/"):
			splat_min = minf(splat_min, local_aabb.position.y)
			continue
		if mi.visible:
			visible_min = minf(visible_min, local_aabb.position.y)
	# 优先模型脚底环；否则仅当可见底边明显高于原点时下沉（避免把地基抬出地面）
	var raw := 0.0
	if splat_min < INF and splat_min > 0.02:
		raw = splat_min
	elif visible_min < INF and visible_min > 0.15 and visible_min < 2.5:
		raw = visible_min
	return minf(raw, FOOT_SINK_MAX)


static func _uber_splat_code(type_id: String) -> String:
	Wc3DefStore.ensure_table(UnitUiDef.TABLE_NAME)
	var row: Resource = Wc3DefStore.get_row(UnitUiDef.TABLE_NAME, type_id)
	if row is UnitUiDef:
		return (row as UnitUiDef).uber_splat.strip_edges()
	return ""


static func _load_splat_texture(def: UberSplatDef, tileset: String) -> Texture2D:
	var file := def.file.get_file()
	if file.is_empty():
		file = def.file
	var dir := def.dir.strip_edges().trim_prefix("/").trim_suffix("/")
	var ts := tileset.strip_edges().to_upper()
	if ts.length() > 1:
		ts = ts.substr(0, 1)
	var candidates: Array[String] = []
	if not ts.is_empty():
		candidates.append("%s/%s_%s.png" % [dir, ts, file])
		candidates.append("%s/%s_%s" % [dir, ts, file])
	candidates.append("%s/%s.png" % [dir, file])
	candidates.append("%s/%s" % [dir, file])
	for rel in candidates:
		var tex: Texture2D = RuntimeAssets.load_converted_texture(rel)
		if tex != null:
			return tex
	return null


static func _aabb_in_root(root: Node3D, mi: MeshInstance3D) -> AABB:
	var local := mi.get_aabb()
	var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
	return xf * local


static func _mesh_blob(mi: MeshInstance3D) -> String:
	var blob := str(mi.name).to_lower()
	if mi.mesh == null:
		return blob
	for si in range(mi.mesh.get_surface_count()):
		var mat: Material = mi.get_active_material(si)
		if mat == null or not (mat is StandardMaterial3D):
			continue
		var sm := mat as StandardMaterial3D
		blob += " " + str(sm.resource_name).to_lower() + " " + str(sm.get_name()).to_lower()
		var tex: Texture2D = sm.albedo_texture
		if tex != null:
			blob += " " + str(tex.resource_path).replace("\\", "/").to_lower()
			blob += " " + str(tex.resource_name).to_lower()
	return blob


static func _is_under_pe2(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if str(p.name) == "Pe2Root":
			return true
		p = p.get_parent()
	return false
