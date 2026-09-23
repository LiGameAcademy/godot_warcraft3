class_name MapPlaceholders
extends RefCounted

## 单位 / 装饰缺失 GLB 时的灰盒占位；以及 WE「Use Click Helper」粉黑棋盘辅助体。

const PLAYER_COLORS: Array[Color] = [
	Color(1.0, 0.1, 0.1),
	Color(0.1, 0.25, 1.0),
	Color(0.1, 0.85, 0.85),
	Color(0.55, 0.15, 0.85),
	Color(1.0, 0.55, 0.1),
	Color(1.0, 1.0, 0.2),
	Color(0.2, 0.7, 0.2),
	Color(0.9, 0.4, 0.7),
	Color(0.5, 0.5, 0.5),
	Color(0.7, 0.9, 1.0),
	Color(0.4, 0.2, 0.1),
	Color(0.2, 0.5, 0.2),
	Color(0.55, 0.55, 0.55),
	Color(0.7, 0.7, 0.7),
	Color(0.8, 0.8, 0.8),
	Color(0.95, 0.85, 0.2),
]

## WE 缺贴图 / Click Helper 经典洋红-黑棋盘
const CHECKER_MAGENTA := Color(1.0, 0.0, 1.0)
const CHECKER_BLACK := Color(0.0, 0.0, 0.0)
const DEFAULT_SEL_SIZE_WC3 := 64.0 ## selSize=0 时的默认辅助体边长（WC3 单位）

static var _checker_tex: ImageTexture = null


static func make_entity(type_id: String, owner_id: int, is_unit: bool) -> Node3D:
	var root := Node3D.new()
	var mesh_inst := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_for(type_id, owner_id, is_unit)
	mat.roughness = 0.7

	if type_id == "sloc":
		var m := PrismMesh.new()
		m.size = Vector3(1.2, 2.0, 1.2)
		mesh_inst.mesh = m
		mesh_inst.position.y = 1.0
	elif type_id == "ngol":
		var m := BoxMesh.new()
		m.size = Vector3(2.5, 1.2, 2.5)
		mesh_inst.mesh = m
		mesh_inst.position.y = 0.6
	elif type_id == "nfoh":
		var m := SphereMesh.new()
		m.radius = 1.0
		m.height = 2.0
		mesh_inst.mesh = m
		mesh_inst.position.y = 1.0
	elif is_unit:
		var m := CapsuleMesh.new()
		m.radius = 0.35
		m.height = 1.4
		mesh_inst.mesh = m
		mesh_inst.position.y = 0.7
	else:
		var m := CylinderMesh.new()
		m.top_radius = 0.15
		m.bottom_radius = 0.3
		m.height = 1.4
		mesh_inst.mesh = m
		mesh_inst.position.y = 0.7

	mesh_inst.material_override = mat
	root.add_child(mesh_inst)
	return root


## WE「Editor - Use Click Helper」粉黑棋盘立方体（编辑器可选中提示）。
## sel_size_wc3：SLK selSize；≤0 时用 DEFAULT_SEL_SIZE_WC3。
static func make_click_helper(sel_size_wc3: float = 0.0) -> MeshInstance3D:
	var size_wc3: float = sel_size_wc3 if sel_size_wc3 > 1.0 else DEFAULT_SEL_SIZE_WC3
	var s: float = size_wc3 * Wc3Coords.WORLD_SCALE
	var box := BoxMesh.new()
	box.size = Vector3(s, s, s)
	var mi := MeshInstance3D.new()
	mi.name = "ClickHelper"
	mi.mesh = box
	mi.position.y = s * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _checker_material()
	return mi


## 空壳 GLB（仅 PE2 / 无网格）时的简易上升粒子，近似气泡/蒸汽特效。
static func make_effect_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "EffectParticles"
	p.amount = 24
	p.lifetime = 2.2
	p.preprocess = 0.6
	p.visibility_aabb = AABB(Vector3(-1, -0.2, -1), Vector3(2, 3, 2))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	p.draw_pass_1 = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	p.material_override = mat
	var matp := ParticleProcessMaterial.new()
	matp.direction = Vector3(0, 1, 0)
	matp.spread = 18.0
	matp.initial_velocity_min = 0.25
	matp.initial_velocity_max = 0.55
	matp.gravity = Vector3(0, 0.15, 0)
	matp.scale_min = 0.4
	matp.scale_max = 1.1
	matp.color = Color(0.85, 0.95, 1.0, 0.7)
	p.process_material = matp
	p.emitting = true
	return p


## 按 SLK / 网格情况给实例挂编辑器辅助体（及空模粒子回退）。
## [param attach_click_helper] false=正式游戏：只保留特效，不挂粉黑 Box。
## 返回是否挂了 ClickHelper。
static func attach_editor_helpers(
	root: Node3D,
	info: Dictionary,
	has_visible_mesh: bool,
	attach_click_helper: bool = true,
) -> bool:
	if root == null:
		return false
	var hung_helper := false
	var want_helper: bool = bool(info.get("use_click_helper", false)) or not has_visible_mesh
	if attach_click_helper and want_helper and root.get_node_or_null("ClickHelper") == null:
		var sel: float = float(info.get("sel_size", 0.0))
		var helper := make_click_helper(sel)
		root.add_child(helper)
		_counter_parent_scale(helper, root)
		hung_helper = true
	# 无网格：补简易粒子（已有 PE2 旁路则跳过）——游戏与编辑器都需要可见特效
	if (
		not has_visible_mesh
		and root.get_node_or_null("EffectParticles") == null
		and root.get_node_or_null("Pe2Root") == null
	):
		var parts := make_effect_particles()
		root.add_child(parts)
		_counter_parent_scale(parts, root)
	return hung_helper


## GLB 根常含 MODEL_SCALE=0.01；子节点需反向放大才能保持世界尺寸。
static func _counter_parent_scale(child: Node3D, parent: Node3D) -> void:
	if child == null or parent == null:
		return
	var ps: Vector3 = parent.scale
	if absf(ps.x) < 1e-8 or absf(ps.y) < 1e-8 or absf(ps.z) < 1e-8:
		return
	child.scale = Vector3(1.0 / ps.x, 1.0 / ps.y, 1.0 / ps.z)


static func node_has_mesh(root: Node) -> bool:
	if root == null:
		return false
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			return true
	for c in root.get_children():
		if node_has_mesh(c):
			return true
	return false


static func color_for(type_id: String, owner_id: int, is_unit: bool) -> Color:
	if type_id == "sloc":
		return PLAYER_COLORS[clampi(owner_id, 0, PLAYER_COLORS.size() - 1)]
	if type_id == "ngol":
		return Color(0.95, 0.8, 0.15)
	if type_id == "nfoh":
		return Color(0.3, 0.85, 1.0)
	if is_unit:
		if owner_id >= 0 and owner_id < 12:
			return PLAYER_COLORS[owner_id]
		return Color(0.75, 0.35, 0.35)
	return Color(0.25, 0.5, 0.28)


static func _checker_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = _checker_texture()
	mat.uv1_scale = Vector3(4, 4, 4)
	return mat


static func _checker_texture() -> ImageTexture:
	if _checker_tex != null:
		return _checker_tex
	const N := 8
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	for y in range(N):
		for x in range(N):
			var c: Color = CHECKER_MAGENTA if ((x + y) % 2 == 0) else CHECKER_BLACK
			img.set_pixel(x, y, c)
	_checker_tex = ImageTexture.create_from_image(img)
	return _checker_tex
