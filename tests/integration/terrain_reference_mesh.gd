extends HeightfieldMesh
# Frozen pre-optimization quad and vertex append paths.
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
