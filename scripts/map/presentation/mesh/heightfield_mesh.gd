class_name HeightfieldMesh
extends MeshInstance3D

## 高度场 Mesh 底层：WC3 格点采样 + 三角/四边形批建 + 材质挂载。
## Layer（地面/水面）负责「画什么」；本节点负责「怎么画进 ArrayMesh」。
## 勿再拆出仅一行转发的 MeshBuilder。


## 构建缓冲（begin_build → add_* → commit_build）
var _verts: PackedVector3Array = PackedVector3Array()
var _norms: PackedVector3Array = PackedVector3Array()
var _uvs: PackedVector2Array = PackedVector2Array()
var _custom0: PackedFloat32Array = PackedFloat32Array()
var _custom1: PackedFloat32Array = PackedFloat32Array()
var _indices: PackedInt32Array = PackedInt32Array()
var _building: bool = false
var _use_custom: bool = true


## WC3 tilepoint → Godot 顶点。
static func sample_vert(ix: int, iy: int, h: float, center: Vector2, tile_size: float) -> Vector3:
	var xy := Wc3Coords.tilepoint_wc3(ix, iy, center, tile_size)
	return Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, h)


func begin_build(with_custom_rgba: bool = true) -> void:
	_verts = PackedVector3Array()
	_norms = PackedVector3Array()
	_uvs = PackedVector2Array()
	_custom0 = PackedFloat32Array()
	_custom1 = PackedFloat32Array()
	_indices = PackedInt32Array()
	_use_custom = with_custom_rgba
	_building = true


## 追加三角面。custom0/custom1 为每顶点 RGBA float（长度 4）；空则写 0。
func add_triangle(
	pa: Vector3,
	pb: Vector3,
	pc: Vector3,
	normal: Vector3,
	uva: Vector2,
	uvb: Vector2,
	uvc: Vector2,
	custom0: PackedFloat32Array = PackedFloat32Array(),
	custom1: PackedFloat32Array = PackedFloat32Array()
) -> void:
	assert(_building)
	var n := normal
	if n.is_zero_approx():
		n = Vector3.UP
	_append_vert(pa, n, uva, custom0, custom1)
	_append_vert(pb, n, uvb, custom0, custom1)
	_append_vert(pc, n, uvc, custom0, custom1)


## 矩形面（两三角）：BL-TL-TR + BL-TR-BR；局部 UV 与 WC3 viewer 一致。
func add_quad(
	p_bl: Vector3,
	p_br: Vector3,
	p_tl: Vector3,
	p_tr: Vector3,
	custom0: PackedFloat32Array = PackedFloat32Array(),
	custom1: PackedFloat32Array = PackedFloat32Array()
) -> void:
	var n0 := (p_tl - p_bl).cross(p_tr - p_bl).normalized()
	var n1 := (p_tr - p_bl).cross(p_br - p_bl).normalized()
	add_triangle(
		p_bl, p_tl, p_tr, n0,
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1),
		custom0, custom1
	)
	add_triangle(
		p_bl, p_tr, p_br, n1,
		Vector2(0, 0), Vector2(1, 1), Vector2(1, 0),
		custom0, custom1
	)


## 提交为 ArrayMesh，赋给本节点并返回。
func commit_build() -> ArrayMesh:
	assert(_building)
	_building = false
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	var fmt := 0
	if _use_custom:
		arrays[Mesh.ARRAY_CUSTOM0] = _custom0
		arrays[Mesh.ARRAY_CUSTOM1] = _custom1
		fmt = (
			(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		)
	var out := ArrayMesh.new()
	if _verts.size() > 0:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	set_array_mesh(out)
	return out


func set_array_mesh(m: ArrayMesh) -> void:
	mesh = m


func clear_mesh() -> void:
	if mesh != null:
		for s in range(mesh.get_surface_count()):
			set_surface_override_material(s, null)
	mesh = null
	_building = false


## 全 surface 统一材质（如地面 ShaderMaterial）。
func apply_material(mat: Material) -> void:
	if mesh == null:
		return
	for s in range(mesh.get_surface_count()):
		set_surface_override_material(s, mat)


func apply_uniform_material(mat: Material) -> void:
	apply_material(mat)


func _append_vert(
	pos: Vector3,
	normal: Vector3,
	local_uv: Vector2,
	custom0: PackedFloat32Array,
	custom1: PackedFloat32Array
) -> void:
	var base := _verts.size()
	_verts.append(pos)
	_norms.append(normal)
	_uvs.append(local_uv)
	if _use_custom:
		for k in range(4):
			_custom0.append(custom0[k] if k < custom0.size() else -1.0)
			_custom1.append(custom1[k] if k < custom1.size() else 0.0)
	_indices.append(base)
