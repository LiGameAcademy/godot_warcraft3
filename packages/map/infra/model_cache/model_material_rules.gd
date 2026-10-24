extends RefCounted
## WC3材质兼容规则与特效准备；不拥有模型实例。

const Geometry: GDScript = preload("model_geometry.gd")

const WC3_TRANSPARENT_MASK_THRESHOLD: float = 0.75
const WC3_BLEND_SCISSOR_THRESHOLD: float = 0.08
const META_FX_SPHERE_PRESENTED: String = "wc3_fx_presented"


static func _stamp_glb_model_meta(root: Node3D, path: String, unit_soft_blend: bool) -> void:
	if root == null or path.is_empty():
		return
	var logical: String = path.replace("\\", "/").trim_prefix("res://assets/asset-converted/")
	root.set_meta("wc3_glb_logical", logical)
	if unit_soft_blend and glb_path_uses_unit_soft_blend(logical):
		root.set_meta("wc3_unit_model", true)


static func _mark_waterish_if_needed(root: Node, path: String, unit_soft_blend: bool) -> void:
	if root == null or not unit_soft_blend:
		return
	var logical: String = path.replace("\\", "/").to_lower()
	if logical.contains("water"):
		root.set_meta("wc3_waterish_model", true)


## 烘焙 .scn 时无 typeId：Units/ 下非建筑目录名 → 单位软混合（fm2 保留 alpha）。
static func glb_path_uses_unit_soft_blend(logical_path: String) -> bool:
	var p: String = logical_path.replace("\\", "/").strip_edges().to_lower()
	if not p.begins_with("units/"):
		return false
	const BUILDING_MARKERS: Array[String] = [
		"townhall", "greathall", "stronghold", "fortress", "hall",
		"barracks", "altar", "blacksmith", "workshop", "arcanevault",
		"sanctuary", "tavern", "market", "guild", "tower", "temple",
		"crypt", "slaughterhouse", "beastiary", "goldmine", "mine",
		"farm", "house", "keep", "castle", "lumbermill", "mill",
		"foundry", "vault", "armory", "arcane", "shipyard", "foundry",
		"spirit", "lodge", "den", "voodoo", "troll", "hatchery",
		"spawning", "cannibal", "burrow", "ziggurat", "necropolis",
		"crypt", "slaughter", "temple", "treeoflife", "ancient",
		"hunters", "chimaera", "moonwell", "altarof", "huntershall",
	]
	for m: String in BUILDING_MARKERS:
		if p.contains("/%s" % m) or p.ends_with("/%s" % m):
			return false
	return true


## WC3 材质在 glTF/Godot 中的修正：
## - FilterMode Additive/AddAlpha：glTF 只能标 BLEND，需改成 ADD（否则黑底 Glow 变实心牌）
## - FilterMode Blend（建筑）：改 ALPHA_SCISSOR，避免酒馆/市场透视
## - FilterMode Blend（单位 _fm2）：DEPTH_PRE_PASS + 双面（水元素体、火枪披风等软 alpha）
## - FilterMode Transparent（单位 _fm1）：保持 MASK≈0.75 + 双面（贴近 WC3 Transparent；
##   勿 DEPTH_PRE_PASS——Priest 等与队色层共用图集，软 alpha 会把胸前镂空）
## - 默认双面（旧 convert）→ 非 TwoSided/非 Additive/非 fm1/fm2 强制 cull_back
static func _fix_wc3_blend_materials(root: Node, unit_soft_blend: bool = false) -> void:
	if root == null:
		return
	var waterish_model: bool = unit_soft_blend and _node_tree_looks_waterish(root)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si: int in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(si)
			if mat == null:
				continue
			var fixed: Material = _as_wc3_material_fix(mat, unit_soft_blend, waterish_model)
			if fixed != null and fixed != mat:
				mi.set_surface_override_material(si, fixed)


## 模型名 / 贴图路径 / meta 含 water（WaterElemental、WaterEnv…）；bake 内嵌贴图后仍可靠。
static func _node_tree_looks_waterish(root: Node) -> bool:
	if root == null:
		return false
	if bool(root.get_meta("wc3_waterish_model", false)):
		return true
	var key: String = str(root.name).to_lower()
	if key.contains("water"):
		return true
	var p: String = str(root.get_path()).to_lower() if root.is_inside_tree() else ""
	return p.contains("water")


static func _as_wc3_material_fix(
	mat: Material, unit_soft_blend: bool = false, waterish_model: bool = false
) -> Material:
	var add: Material = _as_wc3_additive_material(mat)
	if add != mat:
		return add
	if unit_soft_blend:
		var soft: Material = _as_wc3_unit_fm2_soft_fix(mat, waterish_model)
		# _fm2 已软化时 soft 可能 == mat；绝不能再落入建筑 scissor。
		if soft != mat:
			return soft
		if mat is StandardMaterial3D:
			var key: String = (
				str((mat as StandardMaterial3D).resource_name)
				+ " "
				+ str((mat as StandardMaterial3D).get_name())
			).to_lower()
			if key.contains("_fm2"):
				return mat
		# 单位袍体 _fm1：WC3 Transparent ≈ MASK@0.75 + 双面（可从旧 DEPTH_PRE_PASS 拉回）。
		var fm1: Material = _as_wc3_unit_fm1_mask_fix(mat)
		if fm1 != mat:
			return fm1
		# 已是 MASK 目标态：勿再落入建筑 scissor（阈值 0.08 会误伤）。
		if mat is StandardMaterial3D:
			var sm_done: StandardMaterial3D = mat as StandardMaterial3D
			var k_done: String = (
				str(sm_done.resource_name) + " " + str(sm_done.get_name())
			).to_lower()
			if k_done.contains("_fm1"):
				return mat
			# 仅保留 _fm2 soft 目标态短路（DEPTH_PRE_PASS + 双面）；_fm1 不再走 soft。
			if (
				sm_done.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				and sm_done.cull_mode == BaseMaterial3D.CULL_DISABLED
				and sm_done.blend_mode != BaseMaterial3D.BLEND_MODE_ADD
			):
				return mat
	var scissor: Material = _as_wc3_blend_scissor_fix(mat)
	var cull: Material = _as_wc3_cull_back_fix(scissor)
	return _as_wc3_transparent_two_sided_fix(cull)


static func _as_wc3_unit_fm1_mask_fix(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm: StandardMaterial3D = mat as StandardMaterial3D
	if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return mat
	var key: String = (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	var looks_fm1: bool = key.contains("_fm1")
	# bake 吃旧 scn 时 override 可能丢名；高阈值 MASK 也可识别为 Transparent
	if (
		not looks_fm1
		and sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		and sm.alpha_scissor_threshold >= 0.5
	):
		looks_fm1 = true
	if not looks_fm1:
		return mat
	var want_transp: BaseMaterial3D.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	if (
		sm.transparency == want_transp
		and sm.cull_mode == BaseMaterial3D.CULL_DISABLED
		and absf(sm.alpha_scissor_threshold - WC3_TRANSPARENT_MASK_THRESHOLD) < 0.001
	):
		return mat
	var out: StandardMaterial3D = sm.duplicate() as StandardMaterial3D
	if out.resource_name.is_empty() and not key.strip_edges().is_empty():
		out.resource_name = sm.resource_name if not sm.resource_name.is_empty() else sm.get_name()
	out.transparency = want_transp
	out.alpha_scissor_threshold = WC3_TRANSPARENT_MASK_THRESHOLD
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	out.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	out.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	return out


## 单位 FilterMode=2 Blend（_fm2）：保留软 alpha，对齐 WC3 水元素/披风。
## 水体模型/贴图走真 Alpha Blend，比 DEPTH_PRE_PASS 更通透。
static func _as_wc3_unit_fm2_soft_fix(mat: Material, waterish_model: bool = false) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm: StandardMaterial3D = mat as StandardMaterial3D
	if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return mat
	var key: String = (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	if not key.contains("_fm2"):
		return mat
	var needs: bool = (
		sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	)
	if not needs:
		return mat
	var tex_key: String = ""
	if sm.albedo_texture != null:
		tex_key = (
			str(sm.albedo_texture.resource_path) + " " + str(sm.albedo_texture.resource_name)
		).to_lower()
	var waterish: bool = (
		waterish_model
		or tex_key.contains("water")
		or key.contains("water")
	)
	var want_transp: BaseMaterial3D.Transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
		if waterish
		else BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	)
	var want_depth: BaseMaterial3D.DepthDrawMode = (
		BaseMaterial3D.DEPTH_DRAW_DISABLED
		if waterish
		else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	)
	var want_a: float = sm.albedo_color.a
	if waterish:
		# WC3 Blend 中段 alpha 偏「实」；略压整体 alpha 更像流体体积
		want_a = clampf(sm.albedo_color.a * 0.48, 0.22, 0.62)
	if (
		sm.transparency == want_transp
		and sm.cull_mode == BaseMaterial3D.CULL_DISABLED
		and sm.depth_draw_mode == want_depth
		and absf(sm.albedo_color.a - want_a) < 0.01
	):
		return mat
	var out: StandardMaterial3D = sm.duplicate() as StandardMaterial3D
	out.transparency = want_transp
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	out.depth_draw_mode = want_depth
	out.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	if waterish:
		var c: Color = out.albedo_color
		c.a = want_a
		out.albedo_color = c
		out.roughness = minf(out.roughness, 0.22)
		out.metallic = 0.05
		# 略抬高 albedo 亮度，半透明下更像水体折射
		out.albedo_color = Color(
			minf(c.r * 1.08, 1.0),
			minf(c.g * 1.12, 1.0),
			minf(c.b * 1.15, 1.0),
			want_a
		)
	return out


static func _as_wc3_blend_scissor_fix(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm: StandardMaterial3D = mat as StandardMaterial3D
	# Additive 由另一路径处理
	if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return mat
	var needs: bool = (
		sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		or sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	)
	if not needs:
		return mat
	# 已是目标 scissor 且阈值合适 → 跳过
	if (
		sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		and absf(sm.alpha_scissor_threshold - WC3_BLEND_SCISSOR_THRESHOLD) < 0.001
	):
		return mat
	var out: StandardMaterial3D = sm.duplicate() as StandardMaterial3D
	out.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	out.alpha_scissor_threshold = WC3_BLEND_SCISSOR_THRESHOLD
	out.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	out.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	return out


## 旧 GLB 一律 doubleSided；非 Additive / 非 Transparent 改回 cull_back（屋顶背面不再透出发黑）。
static func _as_wc3_cull_back_fix(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm: StandardMaterial3D = mat as StandardMaterial3D
	if sm.cull_mode != BaseMaterial3D.CULL_DISABLED:
		return mat
	if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return mat
	var key: String = (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	# fm1 Transparent / fm2 软混合 / Additive：保留双面
	if key.contains("_fm1") or key.contains("_fm2") or key.contains("_fm3") or key.contains("_fm4") or key.contains("_rep2"):
		return mat
	var out: StandardMaterial3D = sm.duplicate() as StandardMaterial3D
	out.cull_mode = BaseMaterial3D.CULL_BACK
	return out


## FilterMode=1 Transparent：MDX 常不标 TwoSided，但袍/披风是单面壳；
## cull_back 会把前胸多数三角剔掉，只剩侧面轮廓，并能透视到背后披风（hmpr 等）。
static func _as_wc3_transparent_two_sided_fix(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm: StandardMaterial3D = mat as StandardMaterial3D
	var key: String = (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	if not key.contains("_fm1"):
		return mat
	if sm.cull_mode == BaseMaterial3D.CULL_DISABLED:
		return mat
	var out: StandardMaterial3D = sm.duplicate() as StandardMaterial3D
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	return out


static func _as_wc3_additive_material(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var sm: StandardMaterial3D = mat as StandardMaterial3D
	var key: String = str(sm.resource_name) + " " + str(sm.get_name())
	var key_l: String = key.to_lower()
	var tex: Texture2D = sm.albedo_texture
	var tex_path: String = ""
	if tex != null:
		tex_path = (str(tex.resource_path) + " " + str(tex.resource_name)).to_lower()
	var is_team_glow: bool = (
		key_l.contains("_rep2")
		or key_l.contains("team_glow")
		or tex_path.contains("team_glow")
		or tex_path.contains("teamglow")
		or tex_path.contains("/teamglow/")
	)
	var want_add: bool = (
		is_team_glow
		or key_l.contains("_fm3")
		or key_l.contains("_fm4")
		or tex_path.contains("glow")
	)
	if not want_add:
		return mat
	# 已是目标态则跳过（避免 instance 时反复 duplicate）
	var want_alpha: BaseMaterial3D.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var want_no_depth: bool = is_team_glow
	if (
		sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
		and sm.transparency == want_alpha
		and sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		and sm.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED
		and sm.no_depth_test == want_no_depth
		and sm.cull_mode == BaseMaterial3D.CULL_DISABLED
	):
		return mat
	var out: StandardMaterial3D = sm.duplicate() as StandardMaterial3D
	out.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	out.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# 必须开 ALPHA：TeamGlow / 软边 Additive 贴图靠 alpha 藏面片边；
	# DISABLED 时只会按 RGB 叠加，交叉四边形棱线从斜角非常明显。
	out.transparency = want_alpha
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	out.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# 英雄脚底/杖尖 TeamGlow 是多片交叉面：关深度测试减轻片间遮挡棱线
	out.no_depth_test = want_no_depth
	return out


## 飞弹 / 命中 FX：材质修正 + 语义 present（软球/广告牌）+ 必要时 WORLD_SCALE。
## 已 bake 的 .scn（子节点 scale=0.01）不要二次缩放。
## source_path：逻辑路径（如 Abilities/Weapons/FireBallMissile/...），用于选型 modern present。
static func prepare_fx_model(root: Node3D, source_path: String = "") -> void:
	if root == null:
		return
	_fix_wc3_blend_materials(root, false)
	var path: String = source_path.strip_edges()
	if path.is_empty():
		path = str(root.get_meta("wc3_source_path", ""))
	if FireballMissileModern.wants(path, root):
		FireballMissileModern.apply(root)
	else:
		Wc3FxPresenter.present(root)
	# 整体覆盖优先于表面覆盖；去掉不可见的重复引用，规避 Godot #85817。
	# 包含烘焙后改名为 Geoset 的广告牌，不依赖节点名。
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.material_override != null and mesh_instance.mesh != null:
			for surface: int in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface, null)
	if bool(root.get_meta("wc3_fx_scaled", false)):
		return
	# 已有 MODEL_SCALE 子根（convert 写入）→ 世界 AABB 应 < ~2m
	var worldish: AABB = Geometry._node_visual_aabb(root)
	if worldish.size.length() <= 2.5:
		root.set_meta("wc3_fx_scaled", true)
		return
	root.scale = root.scale * Wc3Coords.WORLD_SCALE
	root.set_meta("wc3_fx_scaled", true)


## 兼容旧调用：转交 Wc3FxPresenter。
static func _present_fx_sphere_billboards(root: Node) -> void:
	if root is Node3D:
		Wc3FxPresenter.present(root as Node3D)
