class_name TeleportEffectPresentation
extends RefCounted

## 游戏内传送可读性增强：线性加法颜色，保留源纹理、尺寸和 Alpha 动画。
## 原始 SCN/查看器继续使用源 SRC_COLOR/ONE；不改变其他技能或 PE2 材质。
const POLICY: String = "teleport_linear_add"
const MODELS: Array[String] = ["massteleportcaster", "massteleporttarget", "massteleportto"]
const SOURCE_EXPRESSION: String = "ALBEDO = color_add ? rgb * rgb : rgb;"

static func prepare(root: Node3D, art: String) -> void:
	if root == null or root.has_meta("teleport_material_policy"):
		return
	if art.replace("\\", "/").get_file().get_basename().to_lower() not in MODELS:
		return
	var adjusted: int = 0
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: ShaderMaterial = mesh.get_active_material(surface) as ShaderMaterial
			if material == null or not material.has_meta("import_fx_material"):
				continue
			if material.get_shader_parameter("color_add") != true:
				continue
			if material.shader == null or not material.shader.code.contains(SOURCE_EXPRESSION):
				push_warning("Teleport enhancement skipped: unsupported mesh shader in " + art)
				continue
			var owned: ShaderMaterial = material.duplicate() as ShaderMaterial
			var shader: Shader = material.shader.duplicate() as Shader
			shader.code = shader.code.replace(SOURCE_EXPRESSION, "ALBEDO = rgb;")
			owned.shader = shader
			# color_add 保持 true：保留原来的 Alpha 语义，不额外乘纹理 Alpha。
			mesh.set_surface_override_material(surface, owned)
			adjusted += 1
	root.set_meta("teleport_material_policy", POLICY if adjusted > 0 else "source_material")
	if adjusted > 0:
		var player: AnimationPlayer = AnimPlayback.find_animation_player(root)
		if player != null:
			player.clear_caches()
		AppLog.info(AppLog.Layer.PRESENT, "TeleportMaterial", "%s: %d surface(s), source alpha/animation retained" % [POLICY, adjusted])
