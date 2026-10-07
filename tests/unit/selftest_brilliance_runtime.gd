extends Node
## 从未学习到学习/洗点/死亡/复活；不依赖技能面板或 GM 手工重新 configure。
var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var host: Node3D = Node3D.new()
	add_child(host)
	var caster: Node3D = _actor(host, "Hamg", 0, 100)
	var priest: Node3D = _actor(host, "hmpr", 0, 100)
	priest.position.x = 2.0
	var footman: Node3D = _actor(host, "hfoo", 0, 0)
	var foe: Node3D = _actor(host, "hmpr", 1, 100)
	var ctrl: BrillianceAuraController = BrillianceAuraController.ensure_on(caster)
	ctrl.configure(func() -> Node: return host)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(ctrl.is_processing(), "Unlearned aura remains ready to observe learning")
	_check(BuffQuery.mana_regen_bonus(priest) == 0.0, "Unlearned aura grants nothing")
	_check(bool(HeroSkill.learn(caster, "AHab").get("ok", false)), "Ordinary HeroSkill.learn succeeds")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_equal_approx(BuffQuery.mana_regen_bonus(priest), 0.75), "Learning activates priest buff without reconfigure")
	_check(BuffQuery.mana_regen_bonus(footman) == 0.0 and BuffQuery.mana_regen_bonus(foe) == 0.0, "No-mana and enemy units excluded")
	priest.position.x = 20.0
	ctrl._process(0.1)
	_check(BuffQuery.mana_regen_bonus(priest) == 0.0, "Leaving range clears buff")
	priest.position.x = 2.0
	ctrl._process(0.1)
	_check(BuffQuery.mana_regen_bonus(priest) > 0.0, "Reentering range restores buff")
	caster.set_meta(AbilityCatalog.META_ABILITY_LEVELS, {})
	ctrl._process(0.1)
	_check(BuffQuery.mana_regen_bonus(priest) == 0.0, "Unlearning clears buff")
	caster.set_meta(AbilityCatalog.META_ABILITY_LEVELS, {"AHab": 1})
	ctrl._process(0.1)
	_check(BuffQuery.mana_regen_bonus(priest) > 0.0, "Relearning restores buff")
	caster.set_meta("life", 0.0)
	ctrl._process(0.1)
	_check(BuffQuery.mana_regen_bonus(priest) == 0.0, "Dead aura source clears buff")
	caster.set_meta("life", 100.0)
	ctrl._process(0.1)
	_check(BuffQuery.mana_regen_bonus(priest) > 0.0, "Revival restores aura")
	caster.free()
	_check(BuffQuery.mana_regen_bonus(priest) == 0.0, "Removing source clears its buff")
	host.free()
	_test_material_isolation()
	print("PASS: Brilliance learning, range, life and material isolation" if _failures == 0 else "FAIL: Brilliance runtime %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _actor(host: Node3D, type_id: String, owner: int, mana: int) -> Node3D:
	var unit: Node3D = Node3D.new()
	unit.set_meta("unit_data", {"typeId": type_id, "owner": owner})
	unit.set_meta("life", 100.0)
	unit.set_meta("max_life", 100.0)
	unit.set_meta(UnitMana.META_MAX_MANA, mana)
	unit.set_meta(UnitMana.META_MANA, mana)
	unit.set_meta(AbilityCatalog.META_HERO_LEVEL, 1)
	unit.set_meta(AbilityCatalog.META_ABILITY_LEVELS, {})
	host.add_child(unit)
	return unit

func _test_material_isolation() -> void:
	var shader: Shader = Shader.new()
	shader.code = "shader_type spatial; uniform bool color_add=true; uniform float geoset_alpha=1.0; void fragment(){ ALBEDO=vec3(1.0); }"
	var original: ShaderMaterial = ShaderMaterial.new()
	original.shader = shader
	original.set_meta("import_fx_material", true)
	original.set_shader_parameter("color_add", true)
	original.set_shader_parameter("geoset_alpha", 0.9)
	var model: Node3D = Node3D.new()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Geoset_0"
	mesh.mesh = PlaneMesh.new()
	mesh.set_surface_override_material(0, original)
	model.add_child(mesh)
	mesh.owner = model
	var player: AnimationPlayer = AnimationPlayer.new()
	model.add_child(player)
	player.owner = model
	var animation: Animation = Animation.new()
	animation.length = 1.0
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("Geoset_0:surface_material_override/0:shader_parameter/geoset_alpha"))
	animation.track_insert_key(track, 0.0, 0.9)
	animation.track_insert_key(track, 1.0, 0.3)
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation("Stand", animation)
	player.add_animation_library("", library)
	var packed: PackedScene = PackedScene.new()
	_check(packed.pack(model) == OK, "Material template packed")
	var a: Node3D = packed.instantiate() as Node3D
	var b: Node3D = packed.instantiate() as Node3D
	add_child(a)
	add_child(b)
	var ap: AnimationPlayer = AnimPlayback.find_animation_player(a)
	ap.play("Stand")
	ap.advance(0.0)
	AuraBeneficiaryPresentation.prepare(a)
	var am: ShaderMaterial = (a.get_node("Geoset_0") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	var bm: ShaderMaterial = (b.get_node("Geoset_0") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	_check(am != bm and am != original, "Adjusted A owns its material")
	_check(am.get_shader_parameter("color_add") == false and bm.get_shader_parameter("color_add") == true and original.get_shader_parameter("color_add") == true, "A does not change B/template")
	ap.advance(1.0)
	_check(is_equal_approx(float(am.get_shader_parameter("geoset_alpha")), 0.3), "Running source animation writes replacement material after cache reset")
	_check(is_equal_approx(float(bm.get_shader_parameter("geoset_alpha")), 0.9), "Animated alpha remains isolated")
	AuraBeneficiaryPresentation.prepare(a)
	_check((a.get_node("Geoset_0") as MeshInstance3D).get_active_material(0) == am, "Repeated sync does not allocate new materials")
	a.free()
	b.free()
	model.free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
