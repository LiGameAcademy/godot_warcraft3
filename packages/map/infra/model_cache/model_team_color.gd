extends RefCounted
## 管理只读队色纹理，按实例替换材质。

const Glow: GDScript = preload("model_team_glow.gd")

var _team_color_tex: Dictionary = {}


## 把 replaceable 队伍色占位贴图换成 TeamColorXX（对齐 WE / HiveWE 预览染色）。
## color_index: 0..15（TeamColor 序号）。中立建筑常由 unitUI.teamColor 固定为 0（红），
## 与地图 owner（如 15 Neutral Passive）无关。
## hide_team_glow：兼容旧调用；有正确 TeamGlow 贴图后默认不再隐藏英雄光晕。
## 仍隐藏预览不该出现的 UberSplat / Death 烟雾 / Portrait BackGround geoset。
##
## 两类 _rep1：
## - 纯队色占位：整面换成 TeamColorXX（步兵肩甲等）
## - 队色垫底（建筑旗帜等）：漫反射 alpha 下透队伍色 → ShaderMaterial
## _rep2 Team Glow：保留 TeamGlow 软圆贴图，用队伍色乘 albedo（Additive）。
func apply_team_color(root: Node, color_index: int = 0, hide_team_glow: bool = false) -> void:
	if root == null:
		return
	var idx: int = clampi(color_index, 0, 15)
	var tex: Texture2D = _team_color_texture(idx)
	var body_aabb: AABB = _non_team_color_aabb(root)
	var fallback: Color = MapPlaceholders.PLAYER_COLORS[
		clampi(idx, 0, MapPlaceholders.PLAYER_COLORS.size() - 1)
	]
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
		if _should_hide_preview_mesh(mi):
			mi.visible = false
			continue
		# 旧资源：纯队色占位被误当成 glow 的大面片 → 仍可隐藏
		if hide_team_glow and _is_exclusive_team_color_mesh(mi) and _looks_like_team_glow(mi, body_aabb):
			mi.visible = false
			continue
		for si: int in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(si)
			if mat == null:
				continue
			# 已 bake 过的队色垫底 ShaderMaterial：只换 team_color_tex，保留漫反射
			if mat is ShaderMaterial:
				var shm: ShaderMaterial = mat as ShaderMaterial
				if _is_team_color_underlay_shader(shm):
					var sh_out: ShaderMaterial = shm.duplicate() as ShaderMaterial
					if tex != null:
						sh_out.set_shader_parameter("team_color_tex", tex)
						sh_out.set_shader_parameter("use_team_texture", true)
					else:
						sh_out.set_shader_parameter("use_team_texture", false)
					sh_out.set_shader_parameter("team_color_fallback", fallback)
					mi.set_surface_override_material(si, sh_out)
				elif _is_team_glow_shader(shm):
					if not bool(mi.get_meta(Glow.META_GLOW_PRESENTED, false)):
						# 旧 bake：整片 glow shader，尚未拆脚底/杖尖
						var fake: StandardMaterial3D = StandardMaterial3D.new()
						fake.albedo_texture = shm.get_shader_parameter("glow_tex") as Texture2D
						fake.resource_name = "Material_fm3_rep2"
						Glow._present_team_glow_mesh(mi, fake, fallback, root)
					else:
						var glow_out: ShaderMaterial = shm.duplicate() as ShaderMaterial
						glow_out.set_shader_parameter(
							"team_color", Color(fallback.r, fallback.g, fallback.b, 1.0)
						)
						mi.set_surface_override_material(si, glow_out)
						# 已挂杖尖 billboard 的源十字面片应保持隐藏
						if Glow._root_has_team_glow_billboard(root):
							mi.visible = false
				continue
			if not (mat is StandardMaterial3D):
				continue
			var sm: StandardMaterial3D = mat as StandardMaterial3D
			if Glow._is_team_glow_material(sm):
				# 脚底贴地 + 杖尖 billboard（平行面片无法糊成球）
				Glow._present_team_glow_mesh(mi, sm, fallback, root)
				break
			if not _is_team_color_material(sm):
				continue
			if _is_team_color_underlay_material(sm):
				mi.set_surface_override_material(
					si, _make_team_color_underlay(sm, tex, fallback)
				)
			elif tex != null:
				var out: StandardMaterial3D = sm.duplicate() as StandardMaterial3D
				out.albedo_texture = tex
				out.albedo_color = Color.WHITE
				mi.set_surface_override_material(si, out)
	Glow._recolor_team_glow_billboards(root, fallback)


## 双层队色垫底：材质名 _rep1 且漫反射不是纯占位 team_color。
func _is_team_color_underlay_material(sm: StandardMaterial3D) -> bool:
	var key: String = (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	if not key.contains("_rep1"):
		return false
	var tex: Texture2D = sm.albedo_texture
	if tex == null:
		return false
	return not _is_placeholder_team_color_texture(tex)


func _is_placeholder_team_color_texture(tex: Texture2D) -> bool:
	var p: String = str(tex.resource_path).replace("\\", "/").to_lower()
	var n: String = str(tex.resource_name).to_lower()
	return (
		p.contains("team_color")
		or p.contains("placeholders/team_color")
		or n.contains("team_color")
		or n.contains("teamcolor")
	)


func _material_resource_key(mat: Material) -> String:
	if mat == null:
		return ""
	return (str(mat.resource_name) + " " + str(mat.get_name())).to_lower()


func _make_team_color_underlay(
	src: StandardMaterial3D, team_tex: Texture2D, fallback: Color
) -> ShaderMaterial:
	var sh: Shader = load("res://assets/shaders/wc3_team_color_underlay.gdshader") as Shader
	var out: ShaderMaterial = ShaderMaterial.new()
	out.shader = sh
	# 与袍体同优先级即可；shader 已不进透明队列，勿靠提高 priority 治深度。
	out.render_priority = 0
	out.set_shader_parameter("diffuse_tex", src.albedo_texture)
	if team_tex != null:
		out.set_shader_parameter("team_color_tex", team_tex)
		out.set_shader_parameter("use_team_texture", true)
	else:
		out.set_shader_parameter("use_team_texture", false)
	out.set_shader_parameter("team_color_fallback", fallback)
	return out


func _is_team_color_underlay_shader(mat: ShaderMaterial) -> bool:
	if mat == null or mat.shader == null:
		return false
	var p: String = str(mat.shader.resource_path).replace("\\", "/").to_lower()
	return p.contains("wc3_team_color_underlay")


func _is_team_glow_shader(mat: ShaderMaterial) -> bool:
	if mat == null or mat.shader == null:
		return false
	var p: String = str(mat.shader.resource_path).replace("\\", "/").to_lower()
	return p.contains("wc3_team_glow")


func _is_exclusive_team_color_mesh(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.mesh.get_surface_count() <= 0:
		return false
	for si: int in range(mi.mesh.get_surface_count()):
		var mat: Material = mi.get_active_material(si)
		if mat == null:
			return false
		# 队色垫底（漫反射+队色，如人族集结旗）：有实体贴图，不是纯 Team Glow
		if mat is ShaderMaterial and _is_team_color_underlay_shader(mat as ShaderMaterial):
			return false
		if not (mat is StandardMaterial3D):
			return false
		var sm: StandardMaterial3D = mat as StandardMaterial3D
		if _is_team_color_underlay_material(sm):
			return false
		if not _is_team_color_material(sm):
			return false
	return true


func _non_team_color_aabb(root: Node) -> AABB:
	var acc: AABB = AABB()
	var has: bool = false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null or _is_exclusive_team_color_mesh(mi):
			continue
		var local: AABB = mi.mesh.get_aabb()
		var xf: Transform3D = mi.global_transform if mi.is_inside_tree() else mi.transform
		var world: AABB = xf * local
		if not has:
			acc = world
			has = true
		else:
			acc = acc.merge(world)
	return acc if has else AABB()


func _looks_like_team_glow(mi: MeshInstance3D, body_aabb: AABB) -> bool:
	if mi.mesh == null:
		return false
	var local: AABB = mi.mesh.get_aabb()
	var glow_size: float = local.size.length()
	if body_aabb.size.length() < 1e-4:
		# 无身体对照时：大面片（对角线偏大）视为 glow
		return glow_size > 1.5
	var body_size: float = body_aabb.size.length()
	# 圣骑士 glow geoset bbox 明显大于身体
	return glow_size > body_size * 1.15


func _should_hide_preview_mesh(mi: MeshInstance3D) -> bool:
	# 运行时挂上的地面贴花（Art - Ground Texture）必须保留
	if mi != null and (
		bool(mi.get_meta("is_runtime_uber_splat", false))
		or str(mi.name) == "UberSplat"
	):
		return false
	for si: int in range(mi.mesh.get_surface_count()):
		var mat: Material = mi.get_active_material(si)
		if mat == null or not (mat is StandardMaterial3D):
			continue
		var sm: StandardMaterial3D = mat as StandardMaterial3D
		var tex: Texture2D = sm.albedo_texture
		var blob: String = (str(sm.resource_name) + " " + str(sm.get_name()) + " " + str(mi.name)).to_lower()
		if tex != null:
			blob += " " + str(tex.resource_path).to_lower()
			blob += " " + str(tex.resource_name).to_lower()
		# 建筑脚底 UberSplat / 死亡烟雾 / 肖像背景板 — 游戏与 WE 场景不展示
		# （仅隐藏模型内嵌 geoset；运行时贴花见上方 early-out）
		# 注意：勿用笼统 "_portrait"——会把 peasant_Portrait 全身 mesh 全藏掉，HUD 只剩队色底。
		if (
			blob.contains("ubersplat")
			or blob.contains("/splats/")
			or blob.contains("deathsmug")
			or blob.contains("death_smug")
			or blob.contains("portraitbackground")
			or blob.contains("portrait_background")
			or blob.contains("portrait bg")
			or blob.contains("portraitback")
		):
			return true
		# 模型内嵌 Textures\Shadow.blp（地精商店脚底实心黑盘等）；真正建筑阴影走 unitUI.buildingShadow
		if _is_embedded_blob_shadow_tex(tex, blob):
			return true
		# Team Glow（_rep2）保留显示：法杖/脚底英雄光晕
	return false


## 识别 MDX 内嵌的半透明阴影盘贴图（非 ReplaceableTextures/Shadows 单位阴影）。
func _is_embedded_blob_shadow_tex(tex: Texture2D, blob: String) -> bool:
	if blob.contains("replaceabletextures/shadows"):
		return false
	if blob.contains("merchant_shadow") or blob.contains("/textures/shadow"):
		return true
	if tex == null:
		return false
	var n: String = str(tex.resource_name).to_lower().get_file().get_basename()
	var p: String = str(tex.resource_path).replace("\\", "/").to_lower().get_file().get_basename()
	return n == "shadow" or p == "shadow" or n.ends_with("_shadow") or p.ends_with("_shadow")


func _is_team_color_material(sm: StandardMaterial3D) -> bool:
	var tex: Texture2D = sm.albedo_texture
	var key: String = (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
	# Team Glow 不当作可染色队伍色
	if key.contains("_rep2") or key.contains("team_glow"):
		return false
	if tex == null:
		return key.contains("_rep1")
	var p: String = str(tex.resource_path).replace("\\", "/").to_lower()
	var n: String = str(tex.resource_name).to_lower()
	if p.contains("team_glow") or n.contains("team_glow"):
		return false
	# GLB 内嵌图常见 name: _placeholders/team_color.png
	return (
		key.contains("_rep1")
		or p.contains("team_color")
		or p.contains("/teamcolor/")
		or p.contains("placeholders/team_color")
		or n.contains("team_color")
		or n.contains("teamcolor")
	)


func _team_color_texture(owner_id: int) -> Texture2D:
	if _team_color_tex.has(owner_id):
		return _team_color_tex[owner_id] as Texture2D
	var logical: String = "ReplaceableTextures/TeamColor/TeamColor%02d.png" % owner_id
	var tex: Texture2D = RuntimeAssets.load_converted_texture(logical)
	if tex == null:
		# 无贴图时用玩家色纯色 1x1
		var c: Color = MapPlaceholders.PLAYER_COLORS[clampi(owner_id, 0, MapPlaceholders.PLAYER_COLORS.size() - 1)]
		var img: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(c)
		tex = ImageTexture.create_from_image(img)
	_team_color_tex[owner_id] = tex
	return tex
