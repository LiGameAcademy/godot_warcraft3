class_name HeightfieldMesh
extends MeshInstance3D

## 可复用的高度格点 Mesh 节点（地形 / 水体挂载）。
## ArrayMesh 由各 Domain Builder 生成；本节点只负责挂载与材质。


func set_array_mesh(m: ArrayMesh) -> void:
	mesh = m


func clear_mesh() -> void:
	# 先清材质再丢 mesh；mesh 已空时 get_surface_override_material_count 会越界
	if mesh != null:
		for s in range(mesh.get_surface_count()):
			set_surface_override_material(s, null)
	mesh = null


func apply_uniform_material(mat: Material) -> void:
	if mesh == null:
		return
	for s in range(mesh.get_surface_count()):
		set_surface_override_material(s, mat)
