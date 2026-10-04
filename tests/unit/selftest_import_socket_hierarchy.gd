extends SceneTree

const BoneNames: GDScript = preload("res://tools/godot/import_bone_names.gd")
const Compiler: GDScript = preload("res://tools/godot/import_skeleton_compiler.gd")

func _initialize() -> void:
	var source_ir: Dictionary = {"skeleton": {"rest_payload": {"bones": [{"name": "Cliff"}]}, "billboards": [{"name": "Cliff"}]}, "attachments": {"payload": {"attachments": [{"bone": "Cliff"}]}}}
	var aliases: Dictionary[String, String] = {"Cliff": "Cliff_2"}
	var mapped: Dictionary = BoneNames.remap(source_ir, aliases)
	assert(mapped.skeleton.rest_payload.bones[0].name == "Cliff_2")
	assert(mapped.skeleton.billboards[0].name == "Cliff_2")
	assert(mapped.attachments.payload.attachments[0].bone == "Cliff_2")
	assert(source_ir.skeleton.rest_payload.bones[0].name == "Cliff")
	assert(source_ir.attachments.payload.attachments[0].bone == "Cliff")
	var scene: Node3D = Node3D.new()
	var skeleton: Skeleton3D = Skeleton3D.new()
	scene.add_child(skeleton)
	skeleton.owner = scene
	var ir: Dictionary = {
		"identity": {"source_format": "mdx"},
		"skeleton": {"rest_payload": {"version": 2, "bones": []}},
		"attachments": {"payload": {"version": 1, "attachments": [
			{"name": "OverHead", "type": "attachment", "bone": "Origin", "pivot": [1, 4, 0]},
			{"name": "Origin", "type": "attachment", "bone": null, "pivot": [1, 1, 0]},
		]}},
	}
	assert(Compiler.compile(scene, ir).ok)
	var origin: Marker3D = scene.get_node("Origin") as Marker3D
	var overhead: Marker3D = origin.get_node("OverHead") as Marker3D
	assert(overhead.position.is_equal_approx(Vector3(0, 3, 0)))
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(scene) == OK)
	var restored: Node3D = packed.instantiate() as Node3D
	assert((restored.get_node("Origin/OverHead") as Marker3D).position.is_equal_approx(Vector3(0, 3, 0)))
	restored.free()
	scene.free()
	ir.attachments.payload.attachments[1].bone = "OverHead"
	scene = Node3D.new()
	scene.add_child(Skeleton3D.new())
	assert(Compiler.compile(scene, ir).diagnostics[0].code == "socket_parent_cycle")
	scene.free()
	print("PASS: reversed attachment order, root socket hierarchy, relative pivot, packed ownership, cycles rejected")
	quit(0)
