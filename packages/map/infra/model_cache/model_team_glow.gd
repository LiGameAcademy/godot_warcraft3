extends RefCounted
## 队伍光晕的挂点、贴地盘和广告牌表现。

const GlowMesh: GDScript = preload("model_glow_mesh.gd")

const META_GLOW_PRESENTED: String = "wc3_team_glow_presented"
const META_GLOW_BILLBOARD: String = "wc3_team_glow_billboard"
const META_GLOW_CATEGORY: String = "wc3_team_glow_category"


## ReplaceableId=2 / TeamGlow 软圆光晕材质。
static func _is_team_glow_material(sm: StandardMaterial3D) -> bool:
	if sm == null:
		return false
	var key: String = (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	if key.contains("_rep2") or key.contains("team_glow"):
		return true
	var tex: Texture2D = sm.albedo_texture
	if tex == null:
		return false
	var p: String = str(tex.resource_path).replace("\\", "/").to_lower()
	var n: String = str(tex.resource_name).to_lower()
	return p.contains("team_glow") or n.contains("team_glow") or p.contains("/teamglow/")


static func _make_team_glow_shader_material(
	glow_tex: Texture2D, team_color: Color, intensity: float, billboard: bool
) -> ShaderMaterial:
	var shader_path: String = (
		"res://assets/shaders/wc3_team_glow.gdshader"
		if billboard
		else "res://assets/shaders/wc3_team_glow_ground.gdshader"
	)
	var sh: Shader = load(shader_path) as Shader
	var out: ShaderMaterial = ShaderMaterial.new()
	out.shader = sh
	out.set_shader_parameter("glow_tex", glow_tex)
	out.set_shader_parameter(
		"team_color", Color(team_color.r, team_color.g, team_color.b, 1.0)
	)
	out.set_shader_parameter("intensity", intensity)
	out.set_shader_parameter("use_billboard", billboard)
	out.resource_local_to_scene = true
	return out


## 脚底 TeamGlow：贴地软圆（Additive + 贴图 RGB 软边）。
static func _make_team_glow_material(src: StandardMaterial3D, team_color: Color) -> ShaderMaterial:
	return _make_team_glow_shader_material(src.albedo_texture, team_color, 2.4, false)


## 杖尖：同一 shader，允许 albedo>1；billboard 在 vertex 里做。
static func _make_team_glow_billboard_material(glow_tex: Texture2D, team_color: Color) -> ShaderMaterial:
	return _make_team_glow_shader_material(glow_tex, team_color, 3.6, true)


static func _root_has_team_glow_billboard(root: Node) -> bool:
	if root == null:
		return false
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi != null and bool(mi.get_meta(META_GLOW_BILLBOARD, false)):
			return true
	return false


## 把 Team Glow geoset 拆成：脚底贴地网格 + 杖尖 billboard。
## MDX 杖尖是多张平行四边形，斜看必露卡片；billboard 软圆才像球形光晕。
static func _present_team_glow_mesh(
	mi: MeshInstance3D, src_mat: StandardMaterial3D, team_color: Color, root: Node
) -> void:
	if mi == null or src_mat == null:
		return
	if bool(mi.get_meta(META_GLOW_PRESENTED, false)):
		mi.set_surface_override_material(0, _make_team_glow_material(src_mat, team_color))
		return
	var glow_tex: Texture2D = src_mat.albedo_texture
	var split: Dictionary = GlowMesh._split_team_glow_by_normal(mi.mesh)
	var foot_mesh: ArrayMesh = split.get("foot", null) as ArrayMesh
	var tip_aabb: AABB = split.get("tip_aabb", AABB()) as AABB
	var has_tip: bool = bool(split.get("has_tip", false))
	var has_foot: bool = foot_mesh != null and foot_mesh.get_surface_count() > 0
	mi.set_meta(META_GLOW_PRESENTED, true)
	var host: Node3D = null
	if has_tip and tip_aabb.size.length() >= 1e-4:
		host = _resolve_team_glow_tip_host(root, mi)
	# 有武器挂点 + 杖尖：整片十字面片改 billboard，不再保留「误判脚底」残留
	if host != null and has_tip:
		mi.visible = false
		var side: float = maxf(12.0, tip_aabb.size.length() * 0.55)
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(side, side)
		var tip_bb: MeshInstance3D = MeshInstance3D.new()
		tip_bb.name = "TeamGlowBillboard"
		tip_bb.mesh = quad
		tip_bb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tip_bb.set_meta(META_GLOW_BILLBOARD, true)
		tip_bb.set_meta(META_GLOW_CATEGORY, "weapon_socket")
		tip_bb.set_surface_override_material(0, _make_team_glow_billboard_material(glow_tex, team_color))
		var tip: Node3D = host.get_node_or_null("Tip") as Node3D
		if tip != null:
			tip.add_child(tip_bb)
			tip_bb.owner = root
			tip_bb.transform = Transform3D.IDENTITY
		else:
			host.add_child(tip_bb)
			tip_bb.owner = root
			tip_bb.position = _team_glow_tip_local_offset(host, tip_aabb, root)
		return
	if has_foot:
		mi.mesh = foot_mesh
		mi.set_meta(META_GLOW_CATEGORY, "hero_ground")
		mi.set_surface_override_material(0, _make_team_glow_material(src_mat, team_color))
		mi.visible = true
	elif has_tip:
		# 无武器挂点的 tip-only（少见）：保留 mesh，避免光晕直接消失
		mi.set_surface_override_material(0, _make_team_glow_material(src_mat, team_color))
		mi.set_meta(META_GLOW_CATEGORY, "floating_orb_fallback")
		mi.visible = true
	else:
		# 肖像背景板等
		mi.set_surface_override_material(0, _make_team_glow_material(src_mat, team_color))
		mi.set_meta(META_GLOW_CATEGORY, "unclassified_team_glow")
		mi.visible = true


## BoneAttachment 跟骨原点；杖尖在 pivot_delta / tip AABB。
static func _team_glow_tip_local_offset(host: Node3D, tip_aabb: AABB, root: Node) -> Vector3:
	if host == null:
		return tip_aabb.get_center()
	if host.has_meta("wc3_pivot_delta"):
		var d: Variant = host.get_meta("wc3_pivot_delta")
		if d is Vector3:
			return d as Vector3
	var tip_node: Node3D = host.get_node_or_null("Tip") as Node3D
	if tip_node != null and tip_node.position != Vector3.ZERO:
		return tip_node.position
	var center: Vector3 = tip_aabb.get_center()
	if not (host is BoneAttachment3D):
		return center
	var ba: BoneAttachment3D = host as BoneAttachment3D
	var skeleton: Skeleton3D = null
	if ba.use_external_skeleton:
		var sk_path: NodePath = ba.external_skeleton
		if not sk_path.is_empty():
			skeleton = ba.get_node_or_null(sk_path) as Skeleton3D
	else:
		skeleton = ba.get_parent() as Skeleton3D
	if skeleton == null and root != null:
		for c: Node in root.find_children("*", "Skeleton3D", true, false):
			if c is Skeleton3D:
				skeleton = c as Skeleton3D
				break
	if skeleton == null:
		return center
	var bi: int = skeleton.find_bone(ba.bone_name)
	if bi < 0:
		return center
	var bone_rest: Transform3D = skeleton.get_bone_global_rest(bi)
	return bone_rest.affine_inverse() * center


static func _recolor_team_glow_billboards(root: Node, team_color: Color) -> void:
	if root == null:
		return
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or not bool(mi.get_meta(META_GLOW_BILLBOARD, false)):
			continue
		var mat: Material = mi.get_active_material(0)
		var glow_tex: Texture2D = null
		if mat is StandardMaterial3D:
			glow_tex = (mat as StandardMaterial3D).albedo_texture
		elif mat is ShaderMaterial:
			glow_tex = (mat as ShaderMaterial).get_shader_parameter("glow_tex") as Texture2D
		if glow_tex == null:
			glow_tex = RuntimeAssets.load_converted_texture(
				"ReplaceableTextures/TeamGlow/TeamGlow00.png"
			)
		mi.set_surface_override_material(0, _make_team_glow_billboard_material(glow_tex, team_color))


## 优先：Weapon / Staff，再 Hand Right。必须扫完全部 BA 再按 prefer 排名，
## 不能「第一个匹配就 return」——Paladin 树里 Hand Right 在 Weapon 前面。
static func _resolve_team_glow_tip_host(root: Node, glow_mi: MeshInstance3D) -> Node3D:
	if root == null:
		return null
	var prefer: Array[String] = [
		"attachweaponref",
		"attachweapon",
		"weaponref",
		"weapon",
		"magestaff",
		"attachhandrightref",
		"handrightref",
	]
	var best: BoneAttachment3D = null
	var best_rank: int = prefer.size()
	for n: Node in root.find_children("*", "BoneAttachment3D", true, false):
		var ba: BoneAttachment3D = n as BoneAttachment3D
		if ba == null:
			continue
		var key: String = str(ba.name).replace(" ", "").replace("-", "").replace("_", "").to_lower()
		var bone_key: String = str(ba.bone_name).replace(" ", "").replace("-", "").replace("_", "").to_lower()
		for i: int in range(prefer.size()):
			var p: String = str(prefer[i])
			if key.contains(p) or bone_key.contains(p):
				if i < best_rank:
					best_rank = i
					best = ba
				break
	if best != null:
		return best
	# 按骨名直接建 BoneAttachment
	var skeleton: Skeleton3D = null
	for c: Node in root.find_children("*", "Skeleton3D", true, false):
		if c is Skeleton3D:
			skeleton = c as Skeleton3D
			break
	if skeleton == null:
		return null
	for bone_want: String in ["Mage_Staff", "Weapon", "Bone_Hand_R", "Hand Right"]:
		var bi: int = skeleton.find_bone(bone_want)
		if bi < 0:
			continue
		var ba2: BoneAttachment3D = BoneAttachment3D.new()
		ba2.name = "BA_TeamGlowTip"
		ba2.bone_name = bone_want
		ba2.use_external_skeleton = true
		var pe2: Node = root.find_child("Pe2Root", true, false)
		var parent: Node = pe2 if pe2 != null else glow_mi.get_parent()
		if parent == null:
			parent = root
		parent.add_child(ba2)
		ba2.owner = root
		var skel_path: NodePath = NodePath()
		var walk: Node = ba2
		var seen: Dictionary = {}
		while walk != null:
			seen[walk] = true
			walk = walk.get_parent()
		walk = skeleton
		while walk != null:
			if seen.has(walk):
				skel_path = ba2.get_path_to(skeleton)
				break
			walk = walk.get_parent()
		if skel_path.is_empty():
			ba2.queue_free()
			return null
		ba2.external_skeleton = skel_path
		return ba2
	return null
