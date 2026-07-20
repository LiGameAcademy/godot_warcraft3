class_name MapPlaceholders
extends RefCounted
## 单位 / 装饰缺失 GLB 时的灰盒占位。


const PLAYER_COLORS: Array[Color] = [
	Color(1.0, 0.1, 0.1),
	Color(0.1, 0.25, 1.0),
	Color(0.1, 0.85, 0.85),
	Color(0.55, 0.15, 0.85),
	Color(1.0, 0.55, 0.1),
	Color(1.0, 1.0, 0.2),
	Color(0.2, 0.7, 0.2),
	Color(0.9, 0.4, 0.7),
	Color(0.5, 0.5, 0.5),
	Color(0.7, 0.9, 1.0),
	Color(0.4, 0.2, 0.1),
	Color(0.2, 0.5, 0.2),
	Color(0.55, 0.55, 0.55),
	Color(0.7, 0.7, 0.7),
	Color(0.8, 0.8, 0.8),
	Color(0.95, 0.85, 0.2),
]


static func make_entity(type_id: String, owner_id: int, is_unit: bool) -> Node3D:
	var root := Node3D.new()
	var mesh_inst := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_for(type_id, owner_id, is_unit)
	mat.roughness = 0.7

	if type_id == "sloc":
		var m := PrismMesh.new()
		m.size = Vector3(1.2, 2.0, 1.2)
		mesh_inst.mesh = m
		mesh_inst.position.y = 1.0
	elif type_id == "ngol":
		var m := BoxMesh.new()
		m.size = Vector3(2.5, 1.2, 2.5)
		mesh_inst.mesh = m
		mesh_inst.position.y = 0.6
	elif type_id == "nfoh":
		var m := SphereMesh.new()
		m.radius = 1.0
		m.height = 2.0
		mesh_inst.mesh = m
		mesh_inst.position.y = 1.0
	elif is_unit:
		var m := CapsuleMesh.new()
		m.radius = 0.35
		m.height = 1.4
		mesh_inst.mesh = m
		mesh_inst.position.y = 0.7
	else:
		var m := CylinderMesh.new()
		m.top_radius = 0.15
		m.bottom_radius = 0.3
		m.height = 1.4
		mesh_inst.mesh = m
		mesh_inst.position.y = 0.7

	mesh_inst.material_override = mat
	root.add_child(mesh_inst)
	return root


static func color_for(type_id: String, owner_id: int, is_unit: bool) -> Color:
	if type_id == "sloc":
		return PLAYER_COLORS[clampi(owner_id, 0, PLAYER_COLORS.size() - 1)]
	if type_id == "ngol":
		return Color(0.95, 0.8, 0.15)
	if type_id == "nfoh":
		return Color(0.3, 0.85, 1.0)
	if is_unit:
		if owner_id >= 0 and owner_id < 12:
			return PLAYER_COLORS[owner_id]
		return Color(0.75, 0.35, 0.35)
	return Color(0.25, 0.5, 0.28)
