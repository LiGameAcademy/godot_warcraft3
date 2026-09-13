extends SceneTree
const Replacement := preload("res://scripts/map/presentation/doodad_texture.gd")
const SUMMER := "ReplaceableTextures/LordaeronTree/LordaeronSummerTree.png"
const WINTER := "ReplaceableTextures/LordaeronTree/LordaeronWinterTree.png"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func definition(path: String) -> Dictionary:
	return {"tex_id": 31, "tex_file": path, "id": "test"}


func _run() -> void:
	var original := StandardMaterial3D.new()
	original.resource_name = "Material_0_fm1_rep31"
	var mesh := BoxMesh.new()
	mesh.material = original
	var summer := MeshInstance3D.new()
	summer.mesh = mesh
	var winter := MeshInstance3D.new()
	winter.mesh = mesh
	Replacement.apply(summer, definition(SUMMER))
	Replacement.apply(winter, definition(WINTER))
	var summer_material := summer.get_active_material(0)
	var winter_material := winter.get_active_material(0)
	check(summer_material.get_meta("wc3_replacement_path", "") == SUMMER, "summer texture")
	check(winter_material.get_meta("wc3_replacement_path", "") == WINTER, "winter texture")
	check(summer_material != winter_material and summer_material != original, "per-definition material isolation")
	check(original.albedo_texture == null, "cached source unchanged")
	var multi := MultiMeshInstance3D.new()
	multi.multimesh = MultiMesh.new()
	multi.multimesh.mesh = mesh
	Replacement.apply(multi, definition(SUMMER))
	check(multi.multimesh.mesh != mesh, "multimesh copies affected mesh")
	check(multi.multimesh.mesh.surface_get_material(0).get_meta("wc3_replacement_path", "") == SUMMER, "multimesh texture")
	var override_multi := MultiMeshInstance3D.new()
	override_multi.multimesh = MultiMesh.new()
	override_multi.multimesh.mesh = mesh
	override_multi.material_override = original
	Replacement.apply(override_multi, definition(WINTER))
	check(override_multi.material_override.get_meta("wc3_replacement_path", "") == WINTER, "multimesh override texture")
	var unrelated := StandardMaterial3D.new()
	unrelated.resource_name = "Material_0_fm1_rep310"
	var other := MeshInstance3D.new()
	other.mesh = mesh
	other.set_surface_override_material(0, unrelated)
	Replacement.apply(other, definition(SUMMER))
	check(other.get_active_material(0) == unrelated, "slot 31 does not match 310")
	for node in [summer, winter, multi, override_multi, other]:
		node.free()
	print("selftest_doodad_texture: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
