class_name HeightfieldMesh
extends MeshInstance3D

## 高度场 Mesh 底层：WC3 格点采样 + 三角/四边形批建 + 材质挂载。
## Layer 负责「画什么」；本节点负责「怎么画进 ArrayMesh」与当前激活材质。


## 构建缓冲（begin_build → add_* → commit_build）
var _verts: PackedVector3Array = PackedVector3Array()						## 顶点
var _norms: PackedVector3Array = PackedVector3Array()						## 法线
var _uvs: PackedVector2Array = PackedVector2Array()							## 纹理坐标
var _custom0: PackedFloat32Array = PackedFloat32Array()						## 自定义数据0
var _custom1: PackedFloat32Array = PackedFloat32Array()						## 自定义数据1
var _indices: PackedInt32Array = PackedInt32Array()							## 索引
var _building: bool = false													## 是否正在构建
var _use_custom: bool = true												## 是否使用自定义数据

## 当前表面材质（由 apply_from_template 写入；调试栅格改此实例）
var active_material: ShaderMaterial = null

## 开始构建
## [param with_custom_rgba: bool] 是否使用自定义数据
func begin_build(with_custom_rgba: bool = true) -> void:
	_verts = PackedVector3Array()
	_norms = PackedVector3Array()
	_uvs = PackedVector2Array()
	_custom0 = PackedFloat32Array()
	_custom1 = PackedFloat32Array()
	_indices = PackedInt32Array()
	_use_custom = with_custom_rgba
	_building = true

## 添加三角形
## [param positions: PackedVector3Array] 顶点
## [param normal: Vector3] 法线
## [param uvs: PackedVector2Array] 纹理坐标
## [param custom0: PackedFloat32Array] 自定义数据0
## [param custom1: PackedFloat32Array] 自定义数据1
func add_triangle(
	positions: PackedVector3Array, normal: Vector3, uvs: PackedVector2Array, 
	custom0: PackedFloat32Array = PackedFloat32Array(), custom1: PackedFloat32Array = PackedFloat32Array()
	) -> void:
	assert(_building)
	assert(positions.size() >= 3 and uvs.size() >= 3)
	var n := normal
	if n.is_zero_approx():
		n = Vector3.UP
	_append_vert(positions[0], n, uvs[0], custom0, custom1)
	_append_vert(positions[1], n, uvs[1], custom0, custom1)
	_append_vert(positions[2], n, uvs[2], custom0, custom1)

## 添加四边形
## [param positions: PackedVector3Array] 顶点 长度 4，顺序 BL, BR, TL, TR。
## [param custom0: PackedFloat32Array] 自定义数据0
## [param custom1: PackedFloat32Array] 自定义数据1
## [param uvs: PackedVector2Array] 纹理坐标 可空：默认 WC3 viewer 局部 UV（两三角）。
func add_quad(
	positions: PackedVector3Array, custom0: PackedFloat32Array = PackedFloat32Array(), 
	custom1: PackedFloat32Array = PackedFloat32Array(), uvs: PackedVector2Array = PackedVector2Array()) -> void:
	assert(positions.size() >= 4)
	var p_bl := positions[0]
	var p_br := positions[1]
	var p_tl := positions[2]
	var p_tr := positions[3]
	var n0 := (p_tl - p_bl).cross(p_tr - p_bl).normalized()
	var n1 := (p_tr - p_bl).cross(p_br - p_bl).normalized()
	var uv0 := PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)])
	var uv1 := PackedVector2Array([Vector2(0, 0), Vector2(1, 1), Vector2(1, 0)])
	if uvs.size() >= 6:
		uv0 = PackedVector2Array([uvs[0], uvs[1], uvs[2]])
		uv1 = PackedVector2Array([uvs[3], uvs[4], uvs[5]])
	add_triangle(
		PackedVector3Array([p_bl, p_tl, p_tr]), n0, uv0, custom0, custom1
	)
	add_triangle(
		PackedVector3Array([p_bl, p_tr, p_br]), n1, uv1, custom0, custom1
	)

## 提交构建
## [return ArrayMesh] 构建好的网格
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

## 设置数组网格
## [param m: ArrayMesh] 网格
func set_array_mesh(m: ArrayMesh) -> void:
	mesh = m

## 清空网格
func clear_mesh() -> void:
	if mesh != null:
		for s in range(mesh.get_surface_count()):
			set_surface_override_material(s, null)
	mesh = null
	active_material = null
	_building = false

## 从模板 duplicate，写入运行时参数并挂到表面。
## [param template: ShaderMaterial] 模板
## [param params: Dictionary] 参数
## [return ShaderMaterial] 应用好的材质
func apply_from_template(template: ShaderMaterial, params: Dictionary = {}) -> ShaderMaterial:
	if template == null:
		push_warning("HeightfieldMesh: material template is null")
		return null
	var mat: ShaderMaterial = template.duplicate() as ShaderMaterial
	for k in params.keys():
		mat.set_shader_parameter(str(k), params[k])
	active_material = mat
	apply_material(mat)
	return mat

## 应用材质
## [param mat: Material] 材质
func apply_material(mat: Material) -> void:
	if mesh == null:
		return
	for s in range(mesh.get_surface_count()):
		set_surface_override_material(s, mat)

## 应用均匀材质
## [param mat: Material] 材质
func apply_uniform_material(mat: Material) -> void:
	apply_material(mat)


## 调试栅格（地面 / 水面等共用 shader uniform 名）。
## [param show_tile: bool] 是否显示格子
## [param show_path: bool] 是否显示路径
## [param show_fine: bool] 是否显示细节
func set_debug_grid(show_tile: bool, show_path: bool, show_fine: bool) -> void:
	if active_material == null:
		return
	active_material.set_shader_parameter("dbg_grid_tile", show_tile)
	active_material.set_shader_parameter("dbg_grid_path", show_path)
	active_material.set_shader_parameter("dbg_grid_fine", show_fine)


## 添加顶点
## [param pos: Vector3] 顶点
## [param normal: Vector3] 法线
## [param local_uv: Vector2] 纹理坐标
## [param custom0: PackedFloat32Array] 自定义数据0
## [param custom1: PackedFloat32Array] 自定义数据1
func _append_vert(pos: Vector3, normal: Vector3, local_uv: Vector2, custom0: PackedFloat32Array, custom1: PackedFloat32Array) -> void:
	var base := _verts.size()
	_verts.append(pos)
	_norms.append(normal)
	_uvs.append(local_uv)
	if _use_custom:
		for k in range(4):
			_custom0.append(custom0[k] if k < custom0.size() else -1.0)
			_custom1.append(custom1[k] if k < custom1.size() else 0.0)
	_indices.append(base)


## 采样顶点
## [param ix: int] 坐标 x
## [param iy: int] 坐标 y
## [param h: float] 高度
## [param center: Vector2] 中心
## [param tile_size: float] 格子大小
## [return Vector3] 顶点
static func sample_vert(ix: int, iy: int, h: float, center: Vector2, tile_size: float) -> Vector3:
	var xy := Wc3Coords.tilepoint_wc3(ix, iy, center, tile_size)
	return Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, h)
