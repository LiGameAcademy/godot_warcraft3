class_name Wc3ShoreFoam
extends RefCounted
## Shoreline 泡沫：对齐 Shoreline0.mdx 主发射器（XYQuad + Additive）。
## 直边/角共用同一套参数，一个 MultiMesh 画完。


const TEX_FOAM := "Textures/ShorelineParticleXY.png"
const FOAM_SHADER: Shader = preload("res://shaders/wc3_shore_foam.gdshader")

const PARTICLES_PER := 6
const LIFE := 4.5
const SPEED_WC3 := 30.0
const LENGTH_WC3 := 100.0
const SCALE_WC3 := Vector3(30.0, 80.0, 70.0)
const CLIFF_SPEED_MUL := 0.35


static func build_systems(parent: Node3D, placements: Array) -> int:
	if placements.is_empty():
		return 0
	var tex := RuntimeAssets.load_converted_texture(TEX_FOAM)
	if tex == null:
		push_warning("Wc3ShoreFoam: 缺贴图 %s" % TEX_FOAM)
		return 0

	var s := Wc3Coords.WORLD_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = FOAM_SHADER
	mat.set_shader_parameter("foam_albedo", tex)
	mat.set_shader_parameter("life_span", LIFE)
	mat.set_shader_parameter("speed_mps", SPEED_WC3 * s)
	mat.set_shader_parameter("scale_mps", SCALE_WC3 * s)
	mat.render_priority = 8

	var count := placements.size() * PARTICLES_PER
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _unit_quad_xz()
	mm.instance_count = count

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5A0FE1
	var half_len := LENGTH_WC3 * s * 0.5
	var cliff_back := 0.35 * Wc3Coords.TILE_SIZE * s
	var idx := 0

	for rec in placements:
		var origin: Vector3 = rec["origin"]
		var emit: Vector3 = rec.get("emit_dir", Vector3(0, 0, -1))
		emit.y = 0.0
		if emit.length_squared() < 1e-6:
			emit = Vector3(0, 0, -1)
		emit = emit.normalized()
		var tangent := Vector3.UP.cross(emit)
		if tangent.length_squared() < 1e-6:
			tangent = Vector3.RIGHT
		tangent = tangent.normalized()

		var is_cliff := bool(rec.get("cliff", false))
		var base: Vector3 = (origin - emit * cliff_back) if is_cliff else origin
		var speed0 := CLIFF_SPEED_MUL if is_cliff else 1.0

		for _p in PARTICLES_PER:
			var yaw := rng.randf_range(-0.26, 0.26) # ~±15°
			var dir := emit.rotated(Vector3.UP, yaw).normalized()
			var pos := base + tangent * rng.randf_range(-half_len, half_len)
			var speed_mul := clampf(speed0 * rng.randf_range(0.5, 1.5), 0.12, 1.6)
			mm.set_instance_transform(idx, _orient(pos, dir))
			mm.set_instance_custom_data(idx, Color(rng.randf(), speed_mul, rng.randf_range(0.85, 1.15), 0.0))
			idx += 1

	var mi := MultiMeshInstance3D.new()
	mi.name = "Foam"
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return count


static func _unit_quad_xz() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5),
		Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## +X 沿岸，+Y 上，+Z 朝岸
static func _orient(origin: Vector3, landward: Vector3) -> Transform3D:
	var z := landward.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	return Transform3D(Basis(x, z.cross(x).normalized(), z), origin)
