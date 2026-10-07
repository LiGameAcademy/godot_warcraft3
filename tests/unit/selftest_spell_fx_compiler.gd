extends Node
const MaterialCompiler: GDScript = preload("res://tools/godot/import_material_compiler.gd")
const ParticleCompiler: GDScript = preload("res://tools/godot/import_particle_compiler.gd")
const FxScene: GDScript = preload("res://packages/gameplay/presentation/ability_fx_scene.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = Node3D.new()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Geoset_0"
	mesh.mesh = QuadMesh.new()
	mesh.mesh.material = StandardMaterial3D.new()
	scene.add_child(mesh)
	mesh.owner = scene
	var player: AnimationPlayer = AnimationPlayer.new()
	scene.add_child(player)
	player.owner = scene
	var library: AnimationLibrary = AnimationLibrary.new()
	var animation: Animation = Animation.new()
	animation.length = 1.0
	library.add_animation("Birth", animation)
	player.add_animation_library("", library)
	var alpha: Dictionary = {"LineType": 3, "GlobalSeqId": null, "Keys": [
		{"Frame": 0, "Vector": [0.0], "InTan": [0.0], "OutTan": [1.0]},
		{"Frame": 1000, "Vector": [0.0], "InTan": [1.0], "OutTan": [0.0]}]}
	var ir: Dictionary = {"materials": {"source_payload": [{"Layers": [{"FilterMode": 3, "Shading": 33, "TextureID": 0, "TVertexAnimId": null, "Alpha": alpha}]}],
		"geoset_bindings": [{"material_id": 0, "node": "Geoset_0"}]}, "textures": {"source_payload": [{}]},
		"animations": {"payload": {"sequences": [{"name": "Birth", "interval": [0,1000], "looping": false}]}}}
	var result: Dictionary = MaterialCompiler.compile(scene, ir)
	assert(result.compiled_surfaces == 1 and result.alpha_tracks == 1 and result.diagnostics.is_empty())
	assert(is_equal_approx(float(animation.value_track_interpolate(0, 0.5)), 0.75), "Bezier alpha must not become a linear zero curve")
	var material: ShaderMaterial = mesh.get_active_material(0) as ShaderMaterial
	assert(material.shader.code.contains("fog_disabled"))
	assert(material.shader.code.contains("color_add ? alpha"), "Color-add layers must respect fade alpha")
	var em: Dictionary = {"name": "Impact", "squirt": true, "unsupported": [], "texture_uri": "spark.png", "life_span": 1.0,
		"emission_rate": 35.0, "flags": 0, "frame_flags": 1, "speed": 10.0, "variation": 0.0, "latitude": 0.0,
		"gravity": 0.0, "width": 0.0, "length": 0.0, "particle_scaling": [1.0,1.0,1.0], "time_middle": 0.5,
		"segment_color": [[1,1,1],[1,1,1],[1,1,1]], "alpha": [255,255,0], "filter_mode": 0,
		"rows": 1, "columns": 1, "head_life_span_uv_anim": [0,0,1], "head_decay_uv_anim": [0,0,1],
		"clips": [{"name": "Birth", "keys": [{"time": 0.0, "position": [0,0,0], "rotation": [0,0,0,1], "scale": [1,1,1], "visible": true, "rate": 35.0, "width": 0.0, "length": 0.0}], "bursts": [{"time": 0.8, "count": 35}]}]}
	var image: Image = Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.save_png("user://spark.png")
	ir["particles"] = {"count": 1, "payload": {"emitters": [em]}}
	result = ParticleCompiler.compile(scene, ir, "user://")
	assert(result.emitters == 1 and not result.diagnostics.any(func(row: Dictionary) -> bool: return row.code == "particle_controls_pending"))
	var particles: GPUParticles3D = scene.get_node("Impact") as GPUParticles3D
	assert(particles.one_shot and particles.explosiveness == 1.0 and particles.has_method("emit_burst"))
	var events: int = animation.get_track_count()-1
	assert(animation.track_get_type(events) == Animation.TYPE_METHOD and is_equal_approx(animation.track_get_key_time(events, 0), 0.8))
	assert(animation.track_get_key_value(events, 0).args == [35])
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(scene) == OK)
	var a: Node3D = packed.instantiate() as Node3D
	var b: Node3D = packed.instantiate() as Node3D
	add_child(a)
	add_child(b)
	FxScene.play(a, "Birth", true)
	assert(AnimPlayback.find_animation_player(b).get_animation("Birth").loop_mode == Animation.LOOP_NONE)
	var pa: GPUParticles3D = a.get_node("Impact") as GPUParticles3D
	var pb: GPUParticles3D = b.get_node("Impact") as GPUParticles3D
	pa.process_material.gravity = Vector3.ONE
	assert(pb.process_material.gravity == Vector3.ZERO, "Particle simulation resources must be instance-owned")
	a.free()
	b.free()
	scene.free()
	print("PASS: native spell fog flags, Bezier fade, exact Squirt events and A/B resource isolation")
	get_tree().quit(0)
