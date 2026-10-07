extends RefCounted
const EmbeddedScript: GDScript = preload("import_embedded_script.gd")
const Particles: GDScript = preload("import_particle_compiler.gd")
const BillboardPose: GDScript = preload("import_billboard_pose.gd")
const Ribbons: GDScript = preload("import_ribbon_compiler.gd")

static func compile(scene: Node3D, ir: Dictionary, texture_base: String) -> Dictionary:
	var result: Dictionary = Particles.compile(scene, ir, texture_base)
	result["billboards"] = 0
	var entries: Array[Dictionary] = []
	for entry: Dictionary in ir.get("skeleton", {}).get("billboards", []):
		if int(entry.flags) & 0x70 or not int(entry.flags) & 8:
			result.diagnostics.append({"code": "billboard_axis_lock_pending", "severity": "warning", "bone": entry.name})
		else:
			entries.append(entry)
	var skeletons: Array[Node] = scene.find_children("*", "Skeleton3D", true, false)
	if not entries.is_empty() and skeletons.size() == 1:
		# An embedded script survives loading from another Godot project/export.
		var script: GDScript = EmbeddedScript.create(BillboardPose)
		if script != null:
			var modifier: SkeletonModifier3D = SkeletonModifier3D.new()
			modifier.set_script(script)
			modifier.set("entries", entries)
			modifier.name = "CameraFacingBones"
			skeletons[0].add_child(modifier)
			modifier.owner = scene
			result.billboards = entries.size()
			result.diagnostics.append({"code": "billboard_orientation_approximation", "severity": "info", "message": "Preserves animated pivot and scale; camera orientation replaces source bone rotation"})
		else:
			result.diagnostics.append({"code": "billboard_script_invalid", "severity": "error"})
	var ribbons: Dictionary = Ribbons.compile(scene, ir, texture_base)
	result["ribbons"] = ribbons.ribbons
	result.diagnostics.append_array(ribbons.diagnostics)
	return result
