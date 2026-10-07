extends SceneTree
const Timing: GDScript = preload("res://tools/godot/import_sequence_timing.gd")
const Visibility: GDScript = preload("res://tools/godot/import_geoset_visibility.gd")
const CameraTracks: GDScript = preload("res://client/hud/portrait_camera_tracks.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node3D = Node3D.new()
	root.add_child(scene)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Geoset_0"
	mesh.mesh = QuadMesh.new()
	mesh.scale = Vector3.ZERO
	scene.add_child(mesh)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.set_meta("import_replaceable_id", 2)
	mesh.mesh.material = material
	var player: AnimationPlayer = AnimationPlayer.new()
	scene.add_child(player)
	var library: AnimationLibrary = AnimationLibrary.new()
	var animation: Animation = Animation.new()
	animation.length = 6.667
	var original: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(original, NodePath(".:rotation"))
	animation.track_insert_key(original, 0, Quaternion.IDENTITY)
	animation.track_insert_key(original, 6.667, Quaternion(Vector3.UP, 1))
	library.add_animation("Stand", animation)
	var portrait: Animation = Animation.new()
	portrait.length = 1
	library.add_animation("Portrait", portrait)
	player.add_animation_library("", library)
	var sequences: Array = [{"name": "Stand", "interval": [0, 333], "looping": true}, {"name": "Portrait", "interval": [1000, 2000], "looping": true}]
	var snapshot: Dictionary = Timing.snapshot(scene)
	var ir: Dictionary = {"animations": {"payload": {"sequences": sequences, "geoset_anims": [{"geoset_id": 0, "flags": 0, "alpha": {"line_type": 0, "keys": [{"frame": 0, "vector": [0]}, {"frame": 100, "vector": [1]}, {"frame": 200, "vector": [0]}, {"frame": 1000, "vector": [1]}]}}]}}}
	var result: Dictionary = Visibility.compile(scene, ir)
	assert(result.visibility_tracks == 2 and result.diagnostics.is_empty())
	assert(mesh.scale == Vector3.ONE, "Legacy alpha-scale must not hide the native visible pose")
	assert(Timing.repeat_controls(scene, sequences, snapshot) == 1)
	assert(is_equal_approx(animation.length, 6.667) and animation.track_get_key_count(original) == 2, "Global bone bake must be retained")
	assert(animation.value_track_interpolate(1, 0.11) == true)
	assert(animation.value_track_interpolate(1, 0.44) == true, "Local visibility must repeat inside the global bake")
	assert(animation.value_track_interpolate(1, 0.60) == false)
	# Only a four-vertex replaceable quad visible exclusively in Portrait is a board.
	var alpha: Dictionary = {"line_type": 0, "keys": [{"frame": 0, "vector": [0]}, {"frame": 1000, "vector": [1]}]}
	assert(Visibility._portrait_board(mesh, alpha, sequences))
	var curve: Dictionary = {"line_type": 1, "keys": [{"frame": 1000, "vector": [0,0,0]}, {"frame": 2000, "vector": [2,0,0]}]}
	assert(CameraTracks.sample(curve, 1500, 1000, 2000).is_equal_approx(Vector3(1,0,0)))
	assert(CameraTracks.sample(curve, 500, 0, 900) == Vector3.ZERO, "Camera keys from another sequence must not leak")
	var bezier: Dictionary = {"line_type": 3, "keys": [{"frame": 1000, "vector": [0,0,0], "out_tan": [100,0,0]}, {"frame": 2000, "vector": [1,0,0], "in_tan": [100,0,0]}]}
	assert(CameraTracks.sample(bezier, 1500, 1000, 2000).is_equal_approx(Vector3(0.875,0,0)), "Camera tangents use the same converted coordinate basis")
	scene.free()
	print("PASS: extended global bake retains repeated local controls, portrait-only boards and camera sampling")
	quit(0)
