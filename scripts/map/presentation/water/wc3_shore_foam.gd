class_name Wc3ShoreFoam
extends RefCounted
## Shoreline 泡沫：对齐 HiveWE PE2（XYQuad + Additive = SRC_ALPHA,ONE）。
## 参数来自 Shoreline*.mdx BlizParticle01；稳态粒子 ≈ emissionRate * lifeSpan。


const TEX_FOAM := "Textures/ShorelineParticleXY.png"
const FOAM_SHADER: Shader = preload("res://assets/shaders/wc3_shore_foam.gdshader")
const CLIFF_SPEED_MUL := 0.10
## 悬崖泡沫统一略退入水面（格）
const CLIFF_OUT_TILES := 0.10
## 斜坡不向水面退，贴岸靠 builder 的 ramp_pull
const RAMP_OUT_TILES := 0.0
const SCALE_VISUAL := 1.45
const TWIST_DEG := 55.0

static var _foam_tex_cache: Texture2D = null

## war3-model 解析 Shoreline0 / OutsideCorner0 / InsideCorner0 主 PE2
## yaw：HiveWE 非 line 发射器 rotZ∈±π，岸浪保留朝岸主方向，放宽锥角
const _KIND_PARAMS := {
	"S": {
		"life": 4.5,
		"speed": 30.0,
		"length": 100.0,
		"scale": Vector3(30.0, 80.0, 70.0),
		"particles": 5, # ceil(1.15 * 0.8 * 4.5)
		"yaw_deg": 42.0,
		"alpha_seg": Vector3(0.0, 1.0, 0.0),
		"time_middle": 0.5,
		"variation": 0.5,
	},
	"OC": {
		"life": 5.0,
		"speed": 30.0,
		"length": 100.0,
		"scale": Vector3(50.0, 60.0, 30.0),
		# OC 有两个主发射器（0.4+0.3）*5 ≈ 3.5，略多保外角不断
		"particles": 5,
		"yaw_deg": 55.0,
		"alpha_seg": Vector3(0.0, 1.0, 0.0),
		"time_middle": 0.5,
		"variation": 0.5,
	},
	"IC": {
		"life": 4.5,
		"speed": 20.0,
		"length": 30.0,
		"scale": Vector3(10.0, 60.0, 100.0),
		"particles": 3, # ceil(1.15 * 0.4 * 4.5)
		"yaw_deg": 40.0,
		"alpha_seg": Vector3(0.0, 180.0 / 255.0, 0.0),
		"time_middle": 0.5,
		"variation": 0.5,
	},
}


static func build_systems(parent: Node3D, placements: Array) -> int:
	if placements.is_empty():
		return 0
	var tex := _load_foam_texture()
	if tex == null:
		push_warning("Wc3ShoreFoam: 缺贴图 %s" % TEX_FOAM)
		return 0

	var by_kind := {"S": [], "OC": [], "IC": []}
	for rec in placements:
		var k := str(rec.get("kind", "S"))
		if not by_kind.has(k):
			k = "S"
		by_kind[k].append(rec)

	var total := 0
	total += _add_kind(parent, "FoamS", by_kind["S"], tex, _KIND_PARAMS["S"])
	total += _add_kind(parent, "FoamOC", by_kind["OC"], tex, _KIND_PARAMS["OC"])
	total += _add_kind(parent, "FoamIC", by_kind["IC"], tex, _KIND_PARAMS["IC"])
	return total


static func _load_foam_texture() -> Texture2D:
	if _foam_tex_cache != null and is_instance_valid(_foam_tex_cache):
		return _foam_tex_cache
	var img := RuntimeAssets.load_image(RuntimeAssets.converted_path(TEX_FOAM))
	if img == null:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_foam_tex_cache = ImageTexture.create_from_image(img)
	return _foam_tex_cache


static func _add_kind(
	parent: Node3D, node_name: String, list: Array, tex: Texture2D, p: Dictionary
) -> int:
	if list.is_empty():
		return 0

	var s := Wc3Coords.WORLD_SCALE
	var life: float = float(p["life"])
	var speed_wc3: float = float(p["speed"])
	var length_wc3: float = float(p["length"])
	var scale_wc3: Vector3 = (p["scale"] as Vector3) * SCALE_VISUAL
	var particles_per: int = int(p["particles"])
	var yaw_rad := deg_to_rad(float(p["yaw_deg"]))
	var twist_rad := deg_to_rad(TWIST_DEG)
	var alpha_seg: Vector3 = p["alpha_seg"] as Vector3
	var time_middle: float = float(p["time_middle"])
	var variation: float = float(p["variation"])

	var mat := ShaderMaterial.new()
	mat.shader = FOAM_SHADER
	mat.set_shader_parameter("foam_albedo", tex)
	mat.set_shader_parameter("life_span", life)
	mat.set_shader_parameter("speed_mps", speed_wc3 * s)
	mat.set_shader_parameter("scale_mps", scale_wc3 * s)
	mat.set_shader_parameter("alpha_seg", alpha_seg)
	mat.set_shader_parameter("time_middle", time_middle)
	mat.set_shader_parameter("keep_tint", 0.35)
	mat.render_priority = 16

	var count := list.size() * particles_per
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _unit_quad_xz()
	mm.instance_count = count

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node_name) ^ 0x5A0FE1
	var half_len := length_wc3 * s * 0.5
	var tile_s := Wc3Coords.TILE_SIZE * s
	var cliff_out := CLIFF_OUT_TILES * tile_s
	var ramp_out := RAMP_OUT_TILES * tile_s
	var idx := 0

	for rec in list:
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
		var is_ramp := bool(rec.get("ramp", false))
		var is_contour := bool(rec.get("contour", false))
		var base: Vector3 = origin
		if is_cliff:
			base = origin - emit * cliff_out
		elif is_ramp:
			base = origin - emit * ramp_out

		var along := half_len * (0.8 if is_cliff else (0.85 if is_ramp else (0.7 if is_contour else 1.0)))
		var speed0 := (
			CLIFF_SPEED_MUL if is_cliff else (0.55 if is_ramp else (0.9 if is_contour else 1.0))
		)

		for _p in particles_per:
			var yaw := rng.randf_range(-yaw_rad, yaw_rad)
			var dir := emit.rotated(Vector3.UP, yaw).normalized()
			var pos := base + tangent * rng.randf_range(-along, along)
			var speed_mul := clampf(
				speed0 * (1.0 + variation * rng.randf_range(-1.0, 1.0)), 0.08, 1.8
			)
			var twist := rng.randf_range(-twist_rad, twist_rad)
			mm.set_instance_transform(idx, _orient(pos, dir, twist))
			mm.set_instance_custom_data(
				idx, Color(rng.randf(), speed_mul, rng.randf_range(0.75, 1.3), 0.0)
			)
			idx += 1

	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
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
	# HiveWE head UV：与 XYQuad 速度方向一致，浪峰朝运动前方
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## +X 沿岸，+Y 上，+Z 朝岸（发射方向）；twist 绕竖直轴扭贴片
static func _orient(origin: Vector3, landward: Vector3, twist: float = 0.0) -> Transform3D:
	var z := landward.normalized()
	if absf(twist) > 1e-5:
		z = z.rotated(Vector3.UP, twist).normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	return Transform3D(Basis(x, z.cross(x).normalized(), z), origin)
