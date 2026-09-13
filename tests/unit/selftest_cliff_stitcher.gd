extends SceneTree
const Stitcher := preload("res://scripts/map/presentation/cliff/wc3_cliff_stitcher.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var doc = preload("res://editor/scripts/map_document.gd").new()
	doc.create_from_options({"width": 4, "height": 4, "main_tileset": "L"})
	var hf: Wc3Heightfield = doc.heightfield
	hf.center_offset = Vector2.ZERO
	hf.layer_heights.fill(2)
	hf.layer_heights[hf.width + 1] = 3
	var boost := PackedByteArray()
	boost.resize(hf.width * hf.height)
	boost[hf.width + 2] = 1
	var vertices := PackedVector3Array([Vector3(1.28, 1.28, -1.28), Vector3(1.92, 0.17, -1.28), Vector3(2.56, 0, -1.28), Vector3(1.92, 0.31, -1.92)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2(0.5, 0), Vector2.RIGHT, Vector2(0.5, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 3, 1, 2, 3])
	var source := ArrayMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var original := source.surface_get_arrays(0)
	var result: Mesh = Stitcher.build_mesh(source, Transform3D.IDENTITY, hf, {Vector2i(1, 0): true}, boost)
	var actual := result.surface_get_arrays(0)
	var moved: PackedVector3Array = actual[Mesh.ARRAY_VERTEX]
	check(is_equal_approx(moved[0].y, 1.28) and is_equal_approx(moved[1].y, 0.96) and is_equal_approx(moved[2].y, 0.64), "all shared edge vertices including diagonal grid corner match ramp")
	check(moved[3] == vertices[3], "interior rock profile preserved")
	check(actual[Mesh.ARRAY_TEX_UV] == original[Mesh.ARRAY_TEX_UV], "original UV coordinates preserved")
	check(actual[Mesh.ARRAY_INDEX] == original[Mesh.ARRAY_INDEX], "triangle connectivity preserved")
	check(source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == original[Mesh.ARRAY_VERTEX], "cached source mesh not mutated")
	check(Stitcher.build_mesh(source, Transform3D.IDENTITY, hf, {}, boost) == source, "unaffected mesh remains shared")
	print("selftest_cliff_stitcher: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
