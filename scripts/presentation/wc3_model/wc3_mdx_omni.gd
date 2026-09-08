class_name Wc3MdxOmni
extends RefCounted
## MDX OmniLight 烤进 .scn：Flash soft-orb 光晕 + pivot 偏离时吸回视觉中心。
## 层：presentation / bake（export_model_scenes · MapModelCache）。

const SOFT_ORB_SHADER := "res://assets/shaders/wc3_fx_soft_orb.gdshader"


static func make_soft_flash(light_color: Color, intensity: float, att_end_m: float) -> MeshInstance3D:
	var gain := clampf(intensity / 10.0, 0.55, 2.2)
	# Flash 是辅光晕，比 att_end 实心球小一圈，避免盖过火核
	var side := clampf(att_end_m * 0.28, 0.12, 0.75)
	var quad := QuadMesh.new()
	quad.size = Vector2(side, side)
	var sh: Shader = load(SOFT_ORB_SHADER) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter(
		"core_color",
		Color(light_color.r, light_color.g, light_color.b, 1.0)
	)
	mat.set_shader_parameter(
		"rim_color",
		Color(
			clampf(light_color.r * 0.95, 0.0, 1.0),
			clampf(light_color.g * 0.4, 0.0, 1.0),
			clampf(light_color.b * 0.12, 0.0, 1.0),
			1.0
		)
	)
	# 略低于主体 soft-orb，避免盖过火核；边缘更软
	mat.set_shader_parameter("intensity", 1.05 * gain)
	mat.set_shader_parameter("softness", 3.6)
	mat.set_shader_parameter("pulse_amp", 0.06)
	mat.set_shader_parameter("pulse_hz", 3.2)
	mat.set_shader_parameter("use_billboard", true)
	mat.resource_local_to_scene = true
	var flash := MeshInstance3D.new()
	flash.name = "Flash"
	flash.mesh = quad
	flash.material_override = mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.set_meta("wc3_omni_flash", true)
	flash.set_meta("wc3_omni_flash_side", side)
	return flash


static func proto_visual_mesh_aabb(proto: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	if proto == null:
		return acc
	for n in proto.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if bool(mi.get_meta("wc3_omni_flash", false)):
			continue
		var xf := xform_to_ancestor(mi, proto)
		var worldish: AABB = xf * mi.mesh.get_aabb()
		# 排除巨型 lensflare 广告牌（米制边长很大），否则 FireBall 阈值被撑爆
		if worldish.get_longest_axis_size() > 1.0:
			continue
		if not has:
			acc = worldish
			has = true
		else:
			acc = acc.merge(worldish)
	return acc if has else AABB()


static func xform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _resize_flash_to_core(flash: MeshInstance3D, aabb: AABB) -> void:
	if flash == null:
		return
	var cap := maxf(aabb.get_longest_axis_size() * 0.85, 0.12)
	if flash.mesh is QuadMesh:
		var q := flash.mesh as QuadMesh
		var side := minf(float(flash.get_meta("wc3_omni_flash_side", q.size.x)), cap)
		q.size = Vector2(side, side)
		flash.set_meta("wc3_omni_flash_side", side)
	elif flash.mesh is SphereMesh:
		# 旧烤本：就地升级为 soft-orb
		var col := Color(1.0, 0.9, 0.45)
		var mat := flash.material_override
		if mat is StandardMaterial3D:
			col = (mat as StandardMaterial3D).albedo_color
		var side := minf((flash.mesh as SphereMesh).radius * 2.0, cap)
		var fresh := make_soft_flash(col, 8.0, side)
		flash.mesh = fresh.mesh
		flash.material_override = fresh.material_override
		flash.set_meta("wc3_omni_flash_side", side)
		fresh.free()


## FireBall 等：原作 Light Z≈-90 → 米制 Y≈-0.9，Flash 会落在粒子下方。
static func snap_if_outlier(proto: Node3D, light: OmniLight3D) -> bool:
	if proto == null or light == null:
		return false
	var aabb := proto_visual_mesh_aabb(proto)
	if aabb.size.length() < 1e-4:
		return false
	var center := aabb.get_center()
	# 用「半边长」量级：光晕扁片已过滤，0.55×最长边足够抓偏移灯
	var thresh := maxf(aabb.get_longest_axis_size() * 0.55, 0.2)
	var snapped := false
	if light.position.distance_to(center) > thresh:
		light.set_meta("wc3_omni_pivot_raw", light.position)
		light.position = center
		light.set_meta("wc3_omni_pivot_snapped", true)
		snapped = true
	var flash := light.find_child("Flash", false, false) as MeshInstance3D
	if flash != null:
		_resize_flash_to_core(flash, aabb)
	return snapped


static func snap_all(proto: Node3D) -> int:
	if proto == null:
		return 0
	var n := 0
	for c in proto.find_children("*", "OmniLight3D", true, false):
		var L := c as OmniLight3D
		if L == null or not bool(L.get_meta("wc3_mdx_attachment", false)):
			continue
		# 始终按核心尺寸收 Flash；pivot 偏离才算 snap 计数
		var before := L.position
		snap_if_outlier(proto, L)
		if L.position != before:
			n += 1
		else:
			# 未偏移也要抛光/收尺寸
			var aabb := proto_visual_mesh_aabb(proto)
			var flash := L.find_child("Flash", false, false) as MeshInstance3D
			if flash != null and aabb.size.length() > 1e-4:
				_resize_flash_to_core(flash, aabb)
	return n
