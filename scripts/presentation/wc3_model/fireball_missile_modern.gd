class_name FireballMissileModern
extends RefCounted
## 大法师火球：语义现代化 Present（光核 + 曳迹 + 命中爆）。
## 不 1:1 复刻 MDX geoset/Head+Tail；保留 Stand 飞行 / Death 命中阶段。
## 层：presentation（`scripts/presentation/wc3_model/`）。

const META_APPLIED := "wc3_fireball_modern"
const NODE_ROOT := "ModernFX"
const NODE_CONTROLLER := "ModernController"

const SHADER_PATH := "res://assets/shaders/wc3_fx_soft_orb.gdshader"
const TEX_SMOKE := "Textures/Dust5ABlack.png"
const TEX_FLAME := "abilities/Weapons/FireBallMissile/Dust6ColorRed.png"
const TEX_FLAME_FALLBACK := "Textures/Dust6Color.png"


static func wants(source_path: String, root: Node = null) -> bool:
	# 整包替换依赖路径名 = 白名单，无法甄别法杖/光环/实体武器 → 已否决为主线。
	# 保留本类仅作 spike 对照；正式管线走 Wc3FxPresenter + soft_orb shader。
	return false
	# unreachable — 保留旧判定供文档/考古：
	# var p := source_path.replace("\\", "/").to_lower()
	# return p.contains("fireballmissile") or (
	# 	root != null and str(root.name).to_lower().contains("fireballmissile")
	# )


## 对已实例化的火球根做现代化；可重复调用。
static func apply(root: Node3D) -> bool:
	if root == null:
		return false
	if bool(root.get_meta(META_APPLIED, false)):
		return true
	_hide_legacy(root)
	var fx := _build_modern_fx(root)
	root.add_child(fx)
	_set_owner_recursive(fx, root)
	var ctrl := FireballModernController.new()
	ctrl.name = NODE_CONTROLLER
	fx.add_child(ctrl)
	ctrl.owner = root
	root.set_meta(META_APPLIED, true)
	root.set_meta("wc3_fx_profile", "fireball_modern")
	# 跳过旧 geoset present，避免再造 FxBillboard
	root.set_meta(Wc3FxPresenter.META_PRESENTED, true)
	return true


static func _set_owner_recursive(n: Node, owner: Node) -> void:
	n.owner = owner
	for c in n.get_children():
		_set_owner_recursive(c, owner)

static func _hide_legacy(root: Node3D) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		# 留给 ModernFX 自己的
		if _is_under_modern(mi):
			continue
		mi.visible = false
		mi.set_meta("wc3_fireball_legacy_hidden", true)
	for n in root.find_children("*", "GPUParticles3D", true, false):
		var p := n as GPUParticles3D
		if p == null or _is_under_modern(p):
			continue
		p.emitting = false
		p.visible = false
		p.set_meta("wc3_fireball_legacy_hidden", true)
	# Pe2Root 整棵藏掉（若存在）
	var pe2 := root.find_child(Wc3Pe2Particles.PE2_ROOT_NAME, true, false)
	if pe2 is Node3D:
		(pe2 as Node3D).visible = false


static func _is_under_modern(n: Node) -> bool:
	var cur: Node = n
	while cur != null:
		if str(cur.name) == NODE_ROOT:
			return true
		cur = cur.get_parent()
	return false


static func _build_modern_fx(root: Node3D) -> Node3D:
	var fx := Node3D.new()
	fx.name = NODE_ROOT

	var core := _make_soft_orb(
		"Core",
		36.0,
		Color(1.0, 0.88, 0.42),
		Color(1.0, 0.35, 0.05),
		2.8,
		2.4,
		0.12,
		6.0
	)
	fx.add_child(core)

	var halo := _make_soft_orb(
		"Halo",
		58.0,
		Color(1.0, 0.7, 0.25),
		Color(1.0, 0.2, 0.02),
		1.35,
		2.1,
		0.08,
		4.0
	)
	fx.add_child(halo)

	var smoke := _make_smoke_trail()
	fx.add_child(smoke)

	var flame := _make_flame_trail()
	fx.add_child(flame)

	var burst := _make_impact_burst()
	fx.add_child(burst)

	var light := OmniLight3D.new()
	light.name = "Omni"
	light.light_color = Color(1.0, 0.85, 0.45)
	light.light_energy = 1.8
	light.omni_range = 2.4
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	fx.add_child(light)

	# 略抬到模型前向中心（WC3 本地）
	fx.position = Vector3(0, 0, 0)
	return fx


static func _make_soft_orb(
	node_name: String,
	side: float,
	core_col: Color,
	rim_col: Color,
	intensity: float,
	softness: float,
	pulse_amp: float,
	pulse_hz: float
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var quad := QuadMesh.new()
	quad.size = Vector2(side, side)
	mi.mesh = quad
	var sh: Shader = load(SHADER_PATH) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("core_color", core_col)
	mat.set_shader_parameter("rim_color", rim_col)
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("softness", softness)
	mat.set_shader_parameter("pulse_amp", pulse_amp)
	mat.set_shader_parameter("pulse_hz", pulse_hz)
	mat.set_shader_parameter("use_billboard", true)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("wc3_soft_orb", true)
	return mi


static func _load_tex(logical: String) -> Texture2D:
	var t: Texture2D = RuntimeAssets.load_converted_texture(logical)
	if t != null:
		return t
	var p := "res://assets/asset-converted/%s" % logical
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null


static func _particle_mat(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = (
		BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if tex != null:
		mat.albedo_texture = tex
	return mat


static func _make_smoke_trail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.amount = 24
	p.lifetime = 0.35
	p.explosiveness = 0.0
	p.randomness = 0.2
	p.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	var tex := _load_tex(TEX_SMOKE)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = _particle_mat(tex, false)
	p.draw_pass_1 = quad
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, -1, 0)
	proc.spread = 12.0
	proc.initial_velocity_min = 40.0
	proc.initial_velocity_max = 90.0
	proc.gravity = Vector3.ZERO
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 6.0
	proc.scale_min = 18.0
	proc.scale_max = 28.0
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.7))
	scale_curve.add_point(Vector2(1.0, 1.4))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.15, 0.12, 0.1, 0.55),
		Color(0.08, 0.06, 0.05, 0.25),
		Color(0.05, 0.04, 0.04, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	proc.color_ramp = ramp
	p.process_material = proc
	p.emitting = true
	return p


static func _make_flame_trail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "FlameTrail"
	p.amount = 36
	p.lifetime = 0.28
	p.explosiveness = 0.05
	p.randomness = 0.15
	p.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	var tex := _load_tex(TEX_FLAME)
	if tex == null:
		tex = _load_tex(TEX_FLAME_FALLBACK)
	var quad := QuadMesh.new()
	# 速度对齐拉长 → 现代 Tail（替代 Head+Tail 双套 Quad）
	quad.size = Vector2(0.55, 2.4)
	quad.material = _particle_mat(tex, true)
	p.draw_pass_1 = quad
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, -1, 0)
	proc.spread = 8.0
	proc.initial_velocity_min = 25.0
	proc.initial_velocity_max = 55.0
	proc.gravity = Vector3.ZERO
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 4.0
	proc.particle_flag_align_y = true
	proc.scale_min = 14.0
	proc.scale_max = 22.0
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.5, 0.55))
	scale_curve.add_point(Vector2(1.0, 0.15))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.55, 0.12, 1.0),
		Color(1.0, 0.85, 0.35, 0.85),
		Color(1.0, 0.15, 0.02, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	proc.color_ramp = ramp
	p.process_material = proc
	p.emitting = true
	return p


static func _make_impact_burst() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Burst"
	p.amount = 28
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.35
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-120, -120, -120), Vector3(240, 240, 240))
	var tex := _load_tex(TEX_FLAME_FALLBACK)
	if tex == null:
		tex = _load_tex(TEX_FLAME)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = _particle_mat(tex, true)
	p.draw_pass_1 = quad
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 180.0
	proc.initial_velocity_min = 120.0
	proc.initial_velocity_max = 280.0
	proc.gravity = Vector3(0, -40, 0)
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 8.0
	proc.scale_min = 28.0
	proc.scale_max = 48.0
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.35))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.9, 0.35, 1.0),
		Color(1.0, 0.35, 0.08, 0.75),
		Color(0.6, 0.05, 0.02, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	proc.color_ramp = ramp
	p.process_material = proc
	return p
