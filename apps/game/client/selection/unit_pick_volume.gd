extends RefCounted
class_name UnitPickVolume

## Bounds are broad phase only. Selection requires a visible mesh triangle.
const CACHE_KEY := "selection_body_bounds"
const EXCLUDED := ["SelectionRing", "DeathDropRing", "UberSplat", "Pe2Root", "RibbonRoot", "Attachments", "Model_Old"]

static func ray_distance(host: Node3D, origin: Vector3, direction: Vector3) -> float:
	var model := host.get_node_or_null("Model") as Node3D
	var root := model if model != null else host
	# WC3 model scales are small: a valid 0.005 scale has determinant 1.25e-7.
	# An absolute epsilon would silently reject peasants while larger buildings work.
	if root.global_basis.determinant() == 0.0:
		return INF
	var box := model_bounds(root)
	if not box.has_volume():
		return INF
	var inverse := root.global_transform.affine_inverse()
	var hit: Variant = box.intersects_ray(inverse * origin, inverse.basis * direction)
	if not hit is Vector3:
		return INF
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	var nearest := INF
	for instance in meshes:
		nearest = minf(nearest, _mesh_distance(instance, origin, direction))
	return nearest

static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if str(node.name) in EXCLUDED or node is GPUParticles3D or node is CPUParticles3D:
		return
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh != null and instance.is_visible_in_tree() and not instance.has_meta("wc3_omni_flash") and instance.transparency < 0.99:
			out.append(instance)
	for child in node.get_children():
		_collect_meshes(child, out)

static func _mesh_distance(instance: MeshInstance3D, origin: Vector3, direction: Vector3) -> float:
	if instance.global_basis.determinant() == 0.0:
		return INF
	var inverse := instance.global_transform.affine_inverse()
	var local_origin := inverse * origin
	var local_direction := (inverse.basis * direction).normalized()
	var geometry: Mesh = instance.mesh
	# Query only broad-phase candidates. Pose snapshots are reused within the frame.
	var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D if not instance.skeleton.is_empty() else null
	var surfaces: Array
	var bounds: AABB
	if skeleton != null and instance.skin != null:
		# CPU skinning uses cached source arrays, avoiding GPU mesh readback on hover.
		var frame := Engine.get_process_frames()
		if instance.get_meta("selection_pose_frame", -1) != frame:
			instance.set_meta("selection_pose_query", _skin_query(instance, skeleton))
			instance.set_meta("selection_pose_frame", frame)
		var posed: Dictionary = instance.get_meta("selection_pose_query")
		surfaces = posed.surfaces
		bounds = posed.bounds
	elif geometry is ArrayMesh and geometry.get_blend_shape_count() > 0:
		var frame := Engine.get_process_frames()
		if instance.get_meta("selection_pose_frame", -1) != frame:
			var posed := instance.bake_mesh_from_current_blend_shape_mix()
			instance.set_meta("selection_pose_frame", frame)
			instance.set_meta("selection_pose_mesh", posed)
		geometry = instance.get_meta("selection_pose_mesh") as Mesh
		if geometry == null:
			return INF
		surfaces = _surface_queries(geometry)
		bounds = geometry.get_aabb()
	else:
		surfaces = _surface_queries(geometry)
		bounds = geometry.get_aabb()
	if bounds.intersects_ray(local_origin, local_direction) == null:
		return INF
	var nearest := INF
	for entry in surfaces:
		var material := instance.get_active_material(int(entry.surface))
		var from := local_origin
		var tree: TriangleMesh = entry.tree
		# Transparent pixels can expose another triangle of the same mesh.
		for attempt in range(32):
			var result := tree.intersect_ray(from, local_direction)
			if result.is_empty():
				break
			var point: Vector3 = result.position
			if _opaque_at(material, entry, int(result.face_index), point):
				var distance := (instance.global_transform * point - origin).dot(direction)
				if distance >= 0.0:
					nearest = minf(nearest, distance)
				break
			from = point + local_direction * 0.0001
	return nearest

static func _source_arrays(mesh: Mesh) -> Array:
	if not mesh.has_meta("selection_source_arrays"):
		var arrays: Array = []
		for surface in range(mesh.get_surface_count()):
			arrays.append(mesh.surface_get_arrays(surface))
		mesh.set_meta("selection_source_arrays", arrays)
	return mesh.get_meta("selection_source_arrays") as Array

static func _skin_query(instance: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var skin := instance.skin
	var palette: Array[Transform3D] = []
	for bind in range(skin.get_bind_count()):
		var bone_name := skin.get_bind_name(bind)
		var bone := skeleton.find_bone(bone_name) if not bone_name.is_empty() else skin.get_bind_bone(bind)
		palette.append(skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind) if bone >= 0 else Transform3D.IDENTITY)
	var source := _source_arrays(instance.mesh)
	var surfaces: Array = []
	var bounds := AABB()
	var first := true
	for surface in range(source.size()):
		var arrays: Array = source[surface].duplicate()
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var influences := bones.size() / maxi(1, vertices.size())
		var posed := PackedVector3Array()
		for vertex in range(vertices.size()):
			var point := vertices[vertex]
			if influences > 0 and weights.size() == bones.size():
				point = Vector3.ZERO
				for influence in range(influences):
					var index := vertex * influences + influence
					if weights[index] > 0.0 and bones[index] < palette.size():
						point += (palette[bones[index]] * vertices[vertex]) * weights[index]
			posed.append(point)
			bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
			first = false
		arrays[Mesh.ARRAY_VERTEX] = posed
		var entry := _query_from_arrays(arrays, surface)
		if not entry.is_empty():
			surfaces.append(entry)
	return {"surfaces": surfaces, "bounds": bounds}

static func _surface_queries(mesh: Mesh) -> Array:
	if mesh.has_meta("selection_triangles"):
		return mesh.get_meta("selection_triangles") as Array
	var out: Array = []
	var source := _source_arrays(mesh)
	for surface in range(source.size()):
		var entry := _query_from_arrays(source[surface], surface)
		if not entry.is_empty():
			out.append(entry)
	mesh.set_meta("selection_triangles", out)
	return out

static func _query_from_arrays(arrays: Array, surface: int) -> Dictionary:
	if arrays.is_empty():
		return {}
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var faces := PackedVector3Array()
	var face_uv := PackedVector2Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for i in range(count):
		var index := indices[i] if not indices.is_empty() else i
		faces.append(vertices[index])
		face_uv.append(uv[index] if index < uv.size() else Vector2.ZERO)
	if faces.is_empty() or faces.size() % 3 != 0:
		return {}
	var tree := TriangleMesh.new()
	if tree.create_from_faces(faces):
		return {"surface": surface, "tree": tree, "faces": faces, "uv": face_uv}
	return {}

static func _opaque_at(material: Material, entry: Dictionary, face: int, point: Vector3) -> bool:
	if not material is BaseMaterial3D:
		# The current team-colour shader fills texture alpha with team colour (opaque).
		return true
	var mat := material as BaseMaterial3D
	if mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		return true
	var threshold := mat.alpha_scissor_threshold if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.1
	var alpha := mat.albedo_color.a
	if alpha < threshold:
		return false
	var texture := mat.albedo_texture
	if texture == null:
		return true
	var image: Image
	if texture.has_meta("selection_alpha_image"):
		image = texture.get_meta("selection_alpha_image") as Image
	else:
		image = texture.get_image()
		if image != null and image.is_compressed():
			if image.decompress() != OK:
				return true
		if image != null:
			texture.set_meta("selection_alpha_image", image)
	if image == null or image.is_empty():
		return true
	var index := face * 3
	var faces: PackedVector3Array = entry.faces
	var uv: PackedVector2Array = entry.uv
	var weights := Geometry3D.get_triangle_barycentric_coords(point, faces[index], faces[index + 1], faces[index + 2])
	var texcoord := uv[index] * weights.x + uv[index + 1] * weights.y + uv[index + 2] * weights.z
	texcoord = texcoord * Vector2(mat.uv1_scale.x, mat.uv1_scale.y) + Vector2(mat.uv1_offset.x, mat.uv1_offset.y)
	if mat.texture_repeat:
		texcoord = Vector2(fposmod(texcoord.x, 1.0), fposmod(texcoord.y, 1.0))
	else:
		texcoord = texcoord.clamp(Vector2.ZERO, Vector2.ONE)
	var pixel := Vector2i(mini(int(texcoord.x * image.get_width()), image.get_width() - 1), mini(int(texcoord.y * image.get_height()), image.get_height() - 1))
	return alpha * image.get_pixelv(pixel).a >= threshold

static func model_bounds(root: Node3D) -> AABB:
	# Cache lives on the Model, so replacement/removal automatically invalidates it.
	# No empty caching: asynchronously attached visuals must remain discoverable.
	if root.name == "Model" and root.has_meta(CACHE_KEY):
		return root.get_meta(CACHE_KEY) as AABB
	var boxes: Array[AABB] = []
	_collect(root, root.global_transform.affine_inverse(), boxes)
	var bounds := AABB()
	for box in boxes:
		bounds = box if not bounds.has_volume() else bounds.merge(box)
	if root.name == "Model" and bounds.has_volume():
		root.set_meta(CACHE_KEY, bounds)
	return bounds

static func _collect(node: Node, inverse: Transform3D, boxes: Array[AABB]) -> void:
	if str(node.name) in EXCLUDED or node is GPUParticles3D or node is CPUParticles3D:
		return
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.is_visible_in_tree() and not mesh_node.has_meta("wc3_omni_flash"):
			var box := inverse * mesh_node.global_transform * mesh_node.get_aabb()
			# Flat ground decals/team glow must not inflate the body pick volume.
			if box.size.y > 0.05 and box.has_volume():
				boxes.append(box)
	for child in node.get_children():
		_collect(child, inverse, boxes)
