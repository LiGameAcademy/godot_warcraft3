class_name HeightfieldMesh
extends MeshInstance3D

## 可复用的高度格点 Mesh 节点（地形 / 水体均可挂载）。
## 几何由 HeightfieldMeshBuilder（ArrayMesh）生成。

## 设置 ArrayMesh
func set_array_mesh(m: ArrayMesh) -> void:
	mesh = m


## 清除 Mesh
func clear_mesh() -> void:
	mesh = null
	for s in range(get_surface_override_material_count()):
		set_surface_override_material(s, null)


## 应用统一材质
func apply_uniform_material(mat: Material) -> void:
	if mesh == null:
		return
	for s in range(mesh.get_surface_count()):
		set_surface_override_material(s, mat)


## 应用表面材质
func apply_surface_materials(mats: Array) -> void:
	if mesh == null:
		return
	for s in range(mini(mesh.get_surface_count(), mats.size())):
		set_surface_override_material(s, mats[s])
