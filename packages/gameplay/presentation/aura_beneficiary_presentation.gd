class_name AuraBeneficiaryPresentation
extends RefCounted

## 游戏内受益提示：保留源纹理/颜色/尺寸/动画，用 AddAlpha 提升亮地面的可读性。
## 这是运行时表现策略，不改已编译 SCN，也不影响施法者 Brilliance 双环。
const POLICY: String = "beneficiary_add_alpha"

static func prepare(root: Node3D) -> void:
	if root == null or root.has_meta("aura_beneficiary_policy"):
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
			# 动画继续写相同的 uniform 路径；只复制需要修改的材质，纹理/Shader 共享只读。
			var owned: ShaderMaterial = material.duplicate() as ShaderMaterial
			owned.set_shader_parameter("color_add", false)
			mesh.set_surface_override_material(surface, owned)
			adjusted += 1
	root.set_meta("aura_beneficiary_policy", POLICY if adjusted > 0 else "source_material")
	if adjusted > 0:
		# Stand 已在挂载时启动；清除旧资源绑定，让后续透明度/颜色曲线写独占材质。
		var player: AnimationPlayer = AnimPlayback.find_animation_player(root)
		if player != null:
			player.clear_caches()
		AppLog.info(AppLog.Layer.PRESENT, "AuraBeneficiary", "%s: %d surface(s), source size/animation retained" % [POLICY, adjusted])
