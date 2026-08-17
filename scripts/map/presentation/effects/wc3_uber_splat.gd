class_name Wc3UberSplat
extends RefCounted

## 建筑 Art - Ground Texture：unitUI.uberSplat → UberSplatData → 脚底 Decal。
## 贴图优先 tileset 前缀（如 L_HumanTownHallUberSplat），回退无前缀默认图。
## HiveWE / 原作：摆放时**不**改 heightfield，只靠 UberSplat 做脚印过渡。
##
## Forward+ 下用 Decal 投到地形（cull_mask=TERRAIN），避免印到建筑墙体。
## （曾用 Mobile+PlaneMesh：同 mesh 最多 8 Decal，整图地形会丢脚印。）

const SPLAT_ROOT_NAME := "UberSplat"
## Decal 盒中心相对脚底；投影深度一半左右，保证盖住起伏地表
const Y_BIAS := 0.12
## 投影盒高度（Godot 单位）：过大易打到邻建筑，过小贴不稳坡地
const PROJECTION_DEPTH := 0.5
## 建筑贴地下沉上限（Godot）。过大（按完整 UberSplat geoset 高度）会把主城埋进地里。
const FOOT_SINK_MAX := 0.02
## 建筑整体略抬，避免脚底陷入地表（原作靠 moveHeight/贴地，不靠挖平地形）。
const BUILDING_Y_LIFT := 0.08
## SLK Scale 观感偏小（透明边 + 透视）；×2 接近原作脚印覆盖。
const SIZE_MUL := 2.0
## 贴花相对建筑本地 yaw（PlaneMesh 时代试过 π / +π/2；Decal 先沿用 +90°）
const YAW_LOCAL := PI * 0.5


static func attach_to(root: Node3D, type_id: String, tileset: String = "") -> Node3D:
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
		push_warning("Wc3UberSplat: 无 UberSplatData 行 type=%s code=%s" % [type_id, code])
		return null
	var def := row as UberSplatDef
	if def.file.is_empty() or def.scale <= 0.0:
		return null
	var tex := _load_splat_texture(def, tileset)
	if tex == null:
		push_warning(
			"Wc3UberSplat: 贴图未找到 type=%s code=%s file=%s tileset=%s"
			% [type_id, code, def.file, tileset]
		)
		return null
	# Scale 为 WC3 世界边长（HTOW=230）；与模型同一 WORLD_SCALE，再乘观感倍率
	var size_g := def.scale * Wc3Coords.WORLD_SCALE * SIZE_MUL
	var decal := Decal.new()
	decal.name = SPLAT_ROOT_NAME
	decal.texture_albedo = tex
	decal.modulate = Color.WHITE
	decal.albedo_mix = 1.0
	# Godot Decal：size.x/z = 水平范围，size.y = 沿本地 -Y 的投影深度
	decal.size = Vector3(size_g, PROJECTION_DEPTH, size_g)
	decal.cull_mask = Wc3Coords.RENDER_LAYER_TERRAIN
	decal.position = Vector3(0.0, Y_BIAS, 0.0)
	decal.rotation.y = YAW_LOCAL
	decal.set_meta("uber_splat_code", code)
	decal.set_meta("is_runtime_uber_splat", true)
	root.add_child(decal)
	# GLB 根常带 MODEL_SCALE=0.01；size 按世界尺度写，须抵消父缩放
	_cancel_parent_model_scale(decal, root)
	return decal


## 把贴花缩回世界尺度（父链上累计 scale）。
static func _cancel_parent_model_scale(node: Node3D, root: Node3D) -> void:
	if node == null or root == null:
		return
	var sx := absf(root.scale.x)
	var sy := absf(root.scale.y)
	var sz := absf(root.scale.z)
	if sx < 1e-8:
		sx = 1.0
	if sy < 1e-8:
		sy = 1.0
	if sz < 1e-8:
		sz = 1.0
	# 仅当父明显被模型缩放（远小于 1）时抵消；unit_data.scale≈1 不处理
	if sx > 0.5 and sy > 0.5 and sz > 0.5:
		return
	node.scale = Vector3(1.0 / sx, 1.0 / sy, 1.0 / sz)


## 父节点做了 Y 下沉/抬升后，把贴花补偿回贴地高度。
static func compensate_parent_y(node: Node3D, parent_y_delta: float) -> void:
	if node == null:
		return
	node.position.y = Y_BIAS - parent_y_delta


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
		if str(mi.name) == SPLAT_ROOT_NAME or bool(mi.get_meta("is_runtime_uber_splat", false)):
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
