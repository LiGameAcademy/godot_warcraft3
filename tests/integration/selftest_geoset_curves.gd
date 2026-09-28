extends SceneTree
## Synthetic Blend fixture: independently animated layer alpha and Geoset RGB/A.
const Compiler: GDScript = preload("res://import_geoset_curves.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node3D = Node3D.new()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Geoset_0"
	mesh.mesh = QuadMesh.new()
	scene.add_child(mesh)
	mesh.owner = scene
	var original: StandardMaterial3D = StandardMaterial3D.new()
	original.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	original.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	original.set_meta("import_filter_mode", 2)
	mesh.set_surface_override_material(0, original)
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	scene.add_child(player)
	player.owner = scene
	var library: AnimationLibrary = AnimationLibrary.new()
	for name: String in ["Fade", "Stand"]:
		var animation: Animation = Animation.new()
		animation.length = 1.0
		var track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, NodePath("Geoset_0:surface_material_override/0:albedo_color:a"))
		animation.track_insert_key(track, 0.0, 0.8)
		animation.track_insert_key(track, 1.0, 0.4)
		library.add_animation(name, animation)
	player.add_animation_library("", library)
	var entry: Dictionary = {"flags": 2, "alpha": {"line_type": 1, "keys": [{"frame": 100, "vector": [0.2]}, {"frame": 1100, "vector": [0.8]}]}, "color": {"line_type": 1, "keys": [{"frame": 100, "vector": [1.0, 0.0, 0.0]}, {"frame": 1100, "vector": [0.0, 1.0, 0.0]}]}}
	var sequences: Array = [{"name": "Fade", "interval": [100, 1100]}, {"name": "Stand", "interval": [2000, 3000]}]
	var compiled: Dictionary = Compiler.compile(mesh, player, entry, sequences)
	assert(compiled.ok and compiled.tracks == 4)
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, "res://curves.scn") == OK)
	scene.free()
	packed = ResourceLoader.load("res://curves.scn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	scene = packed.instantiate()
	root.add_child(scene)
	player = scene.get_node("AnimationPlayer")
	mesh = scene.get_node("Geoset_0")
	var material: ShaderMaterial = mesh.get_active_material(0)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("Fade")
	player.seek(0.5, true)
	assert(is_equal_approx(material.get_shader_parameter("layer_alpha"), 0.6))
	assert(is_equal_approx(material.get_shader_parameter("geoset_alpha"), 0.5))
	assert((material.get_shader_parameter("geoset_color") as Vector3).is_equal_approx(Vector3(0.5, 0.5, 0.0)))
	var camera: Camera3D = Camera3D.new()
	camera.position.z = 2.0
	scene.add_child(camera)
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	var center: Color = pixels.get_pixel(pixels.get_width() / 2, pixels.get_height() / 2)
	assert(center.r > center.b + 0.02 and center.g > center.b + 0.02, "RGB curve must reach rendered pixels")
	player.play("Stand")
	player.seek(0.5, true)
	assert(is_equal_approx(material.get_shader_parameter("geoset_alpha"), 1.0))
	assert(material.get_shader_parameter("geoset_color") == Vector3.ONE)
	var other: Node3D = packed.instantiate()
	var other_material: ShaderMaterial = (other.get_node("Geoset_0") as MeshInstance3D).get_active_material(0)
	material.set_shader_parameter("geoset_alpha", 0.123)
	assert(not is_equal_approx(other_material.get_shader_parameter("geoset_alpha"), 0.123))
	other.free()
	scene.free()
	print("PASS: continuous Geoset RGB/alpha, layer alpha composition, reload, reset, rendered color and isolation")
	quit(0)
