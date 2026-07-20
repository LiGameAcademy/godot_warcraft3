class_name Wc3ShoreFoam
extends RefCounted
## Shoreline 泡沫：每放置点多层 MeshInstance（弧形 + 相位/周期错开）。


const TEX_FOAM := "res://assets/asset-converted/Textures/ShorelineParticleXY.png"
const FOAM_SHADER: Shader = preload("res://shaders/wc3_shore_foam.gdshader")

## 泡沫四边形边长（Godot 米）。1 格 ≈ 1.28m。
const QUAD_METERS := 3.2
## 每个岸点叠几层泡沫（尺寸/相位/偏航不同 → 层次）
const LAYERS := 3
## 朝岸偏航抖动（度），打破横平竖直
const YAW_JITTER_DEG := 28.0


static func build_systems(parent: Node3D, placements: Dictionary) -> int:
	var tex := RuntimeAssets.load_texture(TEX_FOAM)
	if tex == null:
		push_warning("Wc3ShoreFoam: 缺贴图 %s" % TEX_FOAM)
		return 0

	var mesh := _make_subdivided_quad(QUAD_METERS, 10, 6)

	var mat := ShaderMaterial.new()
	mat.shader = FOAM_SHADER
	mat.set_shader_parameter("foam_albedo", tex)
	mat.set_shader_parameter("travel_meters", QUAD_METERS * 0.5)
	mat.set_shader_parameter("cycle_seconds", 4.8)
	mat.set_shader_parameter("alpha_boost", 1.25)
	mat.set_shader_parameter("quad_meters", QUAD_METERS)
	mat.render_priority = 10

	var total := 0
	total += _add_group(
		parent, "FoamStraight", placements.get("straight", []) as Array, mesh, mat, 1.0
	)
	total += _add_group(
		parent, "FoamOutside", placements.get("outside", []) as Array, mesh, mat, 0.9
	)
	total += _add_group(
		parent, "FoamInside", placements.get("inside", []) as Array, mesh, mat, 0.9
	)
	return total


static func _add_group(
	parent: Node3D,
	group_name: String,
	list: Array,
	mesh: ArrayMesh,
	mat: ShaderMaterial,
	base_size: float
) -> int:
	if list.is_empty():
		return 0

	var group := Node3D.new()
	group.name = group_name
	parent.add_child(group)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(group_name) ^ 0xF0A11

	var spawned := 0
	for i in range(list.size()):
		var rec: Dictionary = list[i]
		var origin: Vector3 = rec["origin"] as Vector3
		var emit: Vector3 = rec.get("emit_dir", Vector3(0, 0, -1)) as Vector3
		emit.y = 0.0
		if emit.length_squared() < 0.0001:
			emit = Vector3(0, 0, -1)
		emit = emit.normalized()
		var tangent := Vector3.UP.cross(emit)
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.RIGHT
		tangent = tangent.normalized()

		for layer in range(LAYERS):
			var yaw_deg := rng.randf_range(-YAW_JITTER_DEG, YAW_JITTER_DEG)
			# 外层更偏、更慢、更散
			yaw_deg += float(layer - 1) * rng.randf_range(-8.0, 8.0)
			var landward := emit.rotated(Vector3.UP, deg_to_rad(yaw_deg)).normalized()

			var along := tangent * rng.randf_range(-0.55, 0.55) * QUAD_METERS * 0.35
			var back := -emit * (0.12 + float(layer) * 0.18) * QUAD_METERS * 0.25
			var pos := origin + along + back + Vector3.UP * (0.03 + float(layer) * 0.025)

			var mi := MeshInstance3D.new()
			mi.name = "F%d_L%d" % [i, layer]
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = _foam_transform(pos, landward)
			# 相位/周期错开，避免整岸同步呼吸
			mi.set_instance_shader_parameter("phase", rng.randf())
			mi.set_instance_shader_parameter(
				"size_mul", base_size * rng.randf_range(0.7, 1.2) * (1.0 - float(layer) * 0.12)
			)
			mi.set_instance_shader_parameter(
				"travel_mul", rng.randf_range(0.75, 1.35) * (1.0 + float(layer) * 0.08)
			)
			mi.set_instance_shader_parameter("cycle_mul", rng.randf_range(0.7, 1.45))
			mi.set_instance_shader_parameter("arc_mul", rng.randf_range(0.45, 1.15))
			mi.set_instance_shader_parameter("sway_mul", rng.randf_range(0.5, 1.4))
			group.add_child(mi)
			spawned += 1

	return spawned


## 细分 XY 四边形，便于顶点弧度平滑（非直线边）。
static func _make_subdivided_quad(size: float, seg_x: int, seg_y: int) -> ArrayMesh:
	var sx := maxi(seg_x, 2)
	var sy := maxi(seg_y, 2)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	var hx := size * 0.5
	var hy := size * 0.5
	for iy in range(sy + 1):
		var v := float(iy) / float(sy)
		var y := lerpf(-hy, hy, v)
		for ix in range(sx + 1):
			var u := float(ix) / float(sx)
			var x := lerpf(-hx, hx, u)
			verts.append(Vector3(x, y, 0.0))
			uvs.append(Vector2(u, 1.0 - v))
			norms.append(Vector3(0, 0, 1))
	for iy in range(sy):
		for ix in range(sx):
			var i00 := iy * (sx + 1) + ix
			var i10 := i00 + 1
			var i01 := i00 + (sx + 1)
			var i11 := i01 + 1
			indices.append(i00)
			indices.append(i01)
			indices.append(i11)
			indices.append(i00)
			indices.append(i11)
			indices.append(i10)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 局部：+X 沿岸切向，+Y 上，+Z 朝岸。
static func _foam_transform(origin: Vector3, landward: Vector3) -> Transform3D:
	var z := landward.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	return Transform3D(Basis(x, y, z), origin)
