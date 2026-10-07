extends Node
var _failures: int = 0
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var model: Node3D = Node3D.new()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Geoset_0"
	mesh.mesh = PlaneMesh.new()
	var shader: Shader = Shader.new()
	shader.code = "shader_type spatial; uniform bool color_add = true; uniform float geoset_alpha = 0.9; void fragment() { vec3 rgb = vec3(0.5); ALBEDO = color_add ? rgb * rgb : rgb; ALPHA = geoset_alpha; }"
	var original: ShaderMaterial = ShaderMaterial.new()
	original.shader = shader
	original.set_meta("import_fx_material", true)
	original.set_shader_parameter("color_add", true)
	original.set_shader_parameter("geoset_alpha", 0.9)
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
	_check(packed.pack(model) == OK, "Packed source template")
	var a: Node3D = packed.instantiate() as Node3D
	var b: Node3D = packed.instantiate() as Node3D
	add_child(a)
	add_child(b)
	var ap: AnimationPlayer = AnimPlayback.find_animation_player(a)
	ap.play("Stand")
	ap.advance(0.0)
	TeleportEffectPresentation.prepare(b, "Abilities/Spells/Other/GeneralAuraTarget/GeneralAuraTarget.mdx")
	_check(not b.has_meta("teleport_material_policy"), "Other effects remain unchanged")
	TeleportEffectPresentation.prepare(a, "Abilities/Spells/Human/MassTeleport/MassTeleportCaster.mdx")
	var am: ShaderMaterial = (a.get_node("Geoset_0") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	var bm: ShaderMaterial = (b.get_node("Geoset_0") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	_check(am != bm and am.shader != bm.shader, "A owns material and shader")
	_check(am.shader.code.contains("ALBEDO = rgb;") and shader.code.contains(TeleportEffectPresentation.SOURCE_EXPRESSION), "B/template retain source blend")
	_check(am.get_shader_parameter("color_add") == true, "Source alpha semantics preserved")
	ap.advance(1.0)
	_check(is_equal_approx(float(am.get_shader_parameter("geoset_alpha")), 0.3), "Animated alpha reaches enhanced material")
	_check(is_equal_approx(float(bm.get_shader_parameter("geoset_alpha")), 0.9), "Alpha animation isolated from B")
	TeleportEffectPresentation.prepare(a, "MassTeleportCaster.mdx")
	_check((a.get_node("Geoset_0") as MeshInstance3D).get_active_material(0) == am, "Policy is idempotent")
	var circle: BlizzardAreaDecal = BlizzardAreaDecal.spawn_preview(self, Vector2(100, 200), 200)
	var decal: Decal = circle.get_node("Decal") as Decal
	_check(circle.global_position.is_equal_approx(Wc3Coords.wc3_xy_to_godot(100, 200, 0)), "Ground lies at projection center")
	_check(decal.lower_fade == 0 and decal.upper_fade == 0, "Projection edges do not fade cue")
	circle._process(0.0)
	_check(decal.modulate.a >= 0.64, "Preview keeps readable alpha")
	circle.free()
	a.free()
	b.free()
	model.free()
	print("SPELL_VISIBILITY_TEST failures=", _failures)
	get_tree().quit(_failures)
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
