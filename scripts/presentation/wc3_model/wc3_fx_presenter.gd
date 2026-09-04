class_name Wc3FxPresenter
extends RefCounted
## 飞弹 / 技能特效网格语义化（Present）。
## WC3 MDX 常用固定面片糊球/光晕；现代侧按语义选型，不写单位特例：
## - 正交十字 Additive 面片 → Additive billboard 软圆
## - 单张/少面 Additive·Transparent 广告牌 → Billboard（软圆或保留贴图）
## - 细长尾迹 / 实体武器网格 → 保留 mesh（仅材质修正由调用方做）
## - PE2 → 仍由 Wc3Pe2Particles / bake pe2 管线负责，本类不碰
##
## 层：presentation（`scripts/presentation/wc3_model/`）。

const META_PRESENTED := "wc3_fx_presented"
const META_MESH_KIND := "wc3_fx_mesh_kind"
const META_REPLACED := "wc3_fx_replaced_source"
const META_PLAN_B := "wc3_fx_plan_b"

enum MeshKind {
	KEEP = 0,
	SOFT_SPHERE = 1,
	FLAT_BILLBOARD = 2,
}


static func path_wants_fx_present(logical_path: String) -> bool:
	var p := logical_path.replace("\\", "/").strip_edges().to_lower()
	if p.contains("abilities/weapons/"):
		return true
	if p.contains("abilities/spells/"):
		return true
	if p.contains("objects/spawnmodels/"):
		return true
	if p.contains("/missile") or p.contains("missile."):
		return true
	return false


## 对根节点做语义 present；可重复调用（已处理则跳过）。
## 返回 { soft_sphere, flat_billboard, keep, pe2_nodes }。
static func present(root: Node3D) -> Dictionary:
	var stats := {"soft_sphere": 0, "flat_billboard": 0, "keep": 0, "pe2_nodes": 0}
	if root == null:
		return stats
	if bool(root.get_meta(META_PRESENTED, false)):
		stats["soft_sphere"] = int(root.get_meta("wc3_fx_soft_sphere_count", 0))
		stats["flat_billboard"] = int(root.get_meta("wc3_fx_flat_billboard_count", 0))
		return stats

	var soft_tex := RuntimeAssets.load_converted_texture(
		"ReplaceableTextures/TeamGlow/TeamGlow00.png"
	)
	var meshes: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if bool(mi.get_meta(META_PRESENTED, false)):
			continue
		if bool(mi.get_meta(META_REPLACED, false)):
			continue
		meshes.append(mi)

	for mi in meshes:
		var kind: int = classify_mesh(mi)
		mi.set_meta(META_MESH_KIND, kind)
		match kind:
			MeshKind.SOFT_SPHERE:
				if _replace_with_soft_sphere(root, mi, soft_tex, true):
					stats["soft_sphere"] = int(stats["soft_sphere"]) + 1
				else:
					stats["keep"] = int(stats["keep"]) + 1
			MeshKind.FLAT_BILLBOARD:
				var additive := _material_is_additive(mi.get_active_material(0))
				if additive:
					if _replace_with_soft_sphere(root, mi, soft_tex, true):
						stats["flat_billboard"] = int(stats["flat_billboard"]) + 1
					else:
						stats["keep"] = int(stats["keep"]) + 1
				elif _replace_with_textured_billboard(root, mi):
					stats["flat_billboard"] = int(stats["flat_billboard"]) + 1
				else:
					stats["keep"] = int(stats["keep"]) + 1
			_:
				stats["keep"] = int(stats["keep"]) + 1
				mi.set_meta(META_PRESENTED, true)

	for n in root.find_children("*", "GPUParticles3D", true, false):
		stats["pe2_nodes"] = int(stats["pe2_nodes"]) + 1

	root.set_meta(META_PRESENTED, true)
	root.set_meta("wc3_fx_profile", "projectile")
	root.set_meta("wc3_fx_soft_sphere_count", stats["soft_sphere"])
	root.set_meta("wc3_fx_flat_billboard_count", stats["flat_billboard"])
	return stats


## Plan B: 把 FxBillboard 提升到 SkinMeshes 同级，删除空 Geoset_* MI。
## 仅对「presenter 已替换的子树」做，其他原 MI 不动。
## 默认只在 FireBallMissile 上自动触发；其他武器留作显式 opt-in。
static func maybe_apply_plan_b(root: Node3D, source_path: String) -> bool:
	if root == null:
		return false
	if bool(root.get_meta(META_PLAN_B, false)):
		return false
	var p := source_path.replace("\\", "/").to_lower()
	if not p.contains("abilities/weapons/fireballmissile"):
		return false
	return apply_plan_b(root)


## Plan B: 提升 FxBillboard。返回被删除的空 MI 数 + 被提升的 BB 数。
static func apply_plan_b(root: Node3D) -> bool:
	if root == null:
		return false
	var empty_parents: Array[MeshInstance3D] = []
	var billboards: Array[MeshInstance3D] = []
	_find_plan_b_targets(root, empty_parents, billboards)
	if billboards.is_empty():
		root.set_meta(META_PLAN_B, true)
		return false
	for bb in billboards:
		var parent: Node = bb.get_parent()
		if parent == null:
			continue
		var grandparent: Node = parent.get_parent()
		if grandparent == null:
			continue
		# proto 可能没在 SceneTree（如 bake 期）：退回 local 累加
		var local_xf: Transform3D
		if bb.is_inside_tree() and grandparent.is_inside_tree():
			var world_xf: Transform3D = bb.global_transform
			local_xf = grandparent.global_transform.affine_inverse() * world_xf
		else:
			local_xf = parent.transform * bb.transform
		var idx: int = parent.get_index()
		var target_name: String = parent.name
		# 1) 摘除 bb
		parent.remove_child(bb)
		bb.owner = null
		# 2) 摘除 parent（geoset 空壳），释放同名空间
		grandparent.remove_child(parent)
		parent.free()
		# 3) 改名 + add 到 grandparent（此时无同名兄弟）
		bb.name = target_name
		grandparent.add_child(bb)
		bb.transform = local_xf
		bb.owner = root
		var new_idx := grandparent.get_child_count() - 1
		grandparent.move_child(bb, min(idx, new_idx))
		bb.set_meta(META_MESH_KIND, int(bb.get_meta(META_MESH_KIND, MeshKind.KEEP)))
	root.set_meta(META_PLAN_B, true)
	root.set_meta("wc3_fx_plan_b_promoted", billboards.size())
	return true


static func _find_plan_b_targets(
	n: Node,
	empty_parents: Array,
	billboards: Array
) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var has_child_bb: bool = false
			var child_count := 0
			for gc in mi.get_children():
				child_count += 1
				if gc is MeshInstance3D and String(gc.name) == "FxBillboard":
					has_child_bb = true
			# 已被 presenter 替换（mesh == null 且 meta REPLACED=true）且带 FxBillboard 子节点
			if mi.mesh == null and bool(mi.get_meta(META_REPLACED, false)) and has_child_bb and child_count == 1:
				empty_parents.append(mi)
				for gc in mi.get_children():
					if gc is MeshInstance3D and String(gc.name) == "FxBillboard":
						billboards.append(gc)
		_find_plan_b_targets(c, empty_parents, billboards)


static func classify_mesh(mi: MeshInstance3D) -> int:
	if mi == null or mi.mesh == null:
		return MeshKind.KEEP
	var faces := mi.mesh.get_faces()
	var tri_count := faces.size() / 3
	if tri_count <= 0:
		return MeshKind.KEEP
	var aabb := mi.get_aabb()
	var sx := maxf(aabb.size.x, 1e-3)
	var sy := maxf(aabb.size.y, 1e-3)
	var sz := maxf(aabb.size.z, 1e-3)
	var mx := maxf(sx, maxf(sy, sz))
	var mn := minf(sx, minf(sy, sz))
	var aspect := mx / mn
	var mat := mi.get_active_material(0)
	var additive := _material_is_additive(mat)

	# 单四边形 / 极少面 → 广告牌（须先于 aspect 判定：扁圆盘 aspect 极大）
	if tri_count <= 4:
		return MeshKind.FLAT_BILLBOARD

	# 细长尾迹：保留（Ribbon 未接前也先留 mesh）
	if aspect > 6.0 and tri_count <= 64:
		# 两轴接近、第三轴极薄 = 圆盘广告牌，不是尾迹
		var axes := [sx, sy, sz]
		axes.sort()
		if axes[0] / axes[2] < 0.15 and axes[1] / axes[2] > 0.55:
			return MeshKind.FLAT_BILLBOARD
		return MeshKind.KEEP

	# Additive 且近似正方体的少面片 → 十字糊球
	if additive and tri_count <= 56 and aspect <= 4.0:
		# 极扁圆盘（单轴很薄）走广告牌软圆
		if mn / mx < 0.12 and tri_count <= 12:
			return MeshKind.FLAT_BILLBOARD
		return MeshKind.SOFT_SPHERE

	# 非 Additive 的扁圆盘（箭矢贴图等）
	if not additive and tri_count <= 8 and mn / mx < 0.2:
		return MeshKind.FLAT_BILLBOARD

	return MeshKind.KEEP


static func _material_is_additive(mat: Material) -> bool:
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
			return true
		var key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
		if key.contains("_fm3") or key.contains("_fm4"):
			return true
	if mat is ShaderMaterial:
		var shm := mat as ShaderMaterial
		if shm.shader != null:
			var p := str(shm.shader.resource_path).to_lower()
			if p.contains("wc3_team_glow"):
				return true
	return false


static func _replace_with_soft_sphere(
	root: Node3D, mi: MeshInstance3D, fallback_tex: Texture2D, prefer_src_tex: bool
) -> bool:
	var src_mat := mi.get_active_material(0)
	var glow_tex: Texture2D = fallback_tex
	var tint := Color(1.0, 0.85, 0.45, 1.0)
	var intensity := 2.8
	if src_mat is StandardMaterial3D:
		var sm := src_mat as StandardMaterial3D
		if prefer_src_tex and sm.albedo_texture != null:
			glow_tex = sm.albedo_texture
			tint = Color.WHITE
		else:
			tint = Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b, 1.0)
		# MDX Layer.Alpha（如 lensflare≈0.3）压亮度
		if sm.albedo_color.a < 0.99:
			intensity = maxf(0.6, 2.8 * sm.albedo_color.a)
	var aabb := mi.get_aabb()
	var side := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	side = maxf(side, 8.0)
	var center := aabb.get_center()
	# 清空源 mesh，但保持 mi.visible 由 geosetvis 控制；Billboard 作子节点随显隐。
	mi.mesh = null
	mi.set_meta(META_PRESENTED, true)
	mi.set_meta(META_REPLACED, true)
	var bb := MeshInstance3D.new()
	bb.name = "FxBillboard"
	var quad := QuadMesh.new()
	quad.size = Vector2(side, side)
	bb.mesh = quad
	bb.position = center
	bb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bb.set_meta(META_PRESENTED, true)
	bb.set_meta(META_MESH_KIND, MeshKind.SOFT_SPHERE)
	bb.set_surface_override_material(
		0, _make_additive_billboard_material(glow_tex, tint, intensity)
	)
	mi.add_child(bb)
	bb.owner = root
	return true


static func _replace_with_textured_billboard(root: Node3D, mi: MeshInstance3D) -> bool:
	var src_mat := mi.get_active_material(0)
	if not (src_mat is StandardMaterial3D):
		return false
	var sm := src_mat as StandardMaterial3D
	var aabb := mi.get_aabb()
	var side := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	side = maxf(side, 8.0)
	var center := aabb.get_center()
	mi.mesh = null
	mi.set_meta(META_PRESENTED, true)
	mi.set_meta(META_REPLACED, true)
	var bb := MeshInstance3D.new()
	bb.name = "FxBillboard"
	var quad := QuadMesh.new()
	quad.size = Vector2(side, side)
	bb.mesh = quad
	bb.position = center
	bb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bb.set_meta(META_PRESENTED, true)
	bb.set_meta(META_MESH_KIND, MeshKind.FLAT_BILLBOARD)
	var out := sm.duplicate() as StandardMaterial3D
	out.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	out.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if out.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		out.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		out.alpha_scissor_threshold = 0.1
	bb.set_surface_override_material(0, out)
	mi.add_child(bb)
	bb.owner = root
	return true


static func _make_additive_billboard_material(
	glow_tex: Texture2D, tint: Color, intensity: float = 2.8
) -> ShaderMaterial:
	var sh: Shader = load("res://assets/shaders/wc3_team_glow.gdshader") as Shader
	var out := ShaderMaterial.new()
	out.shader = sh
	out.set_shader_parameter("glow_tex", glow_tex)
	out.set_shader_parameter("team_color", Color(tint.r, tint.g, tint.b, 1.0))
	out.set_shader_parameter("intensity", intensity)
	out.set_shader_parameter("use_billboard", true)
	out.resource_local_to_scene = true
	return out
