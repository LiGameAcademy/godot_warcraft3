extends SkeletonModifier3D
## Embedded into the PackedScene: no game singleton or external script path.
## Source bone pivots stay animated; only their camera-facing orientation changes.
@export_storage var entries: Array[Dictionary] = []

func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if skeleton == null or camera == null:
		return
	var camera_basis: Basis = skeleton.global_basis.inverse() * camera.global_basis
	# WC3 billboard planes face +X; after axis conversion Y remains vertical.
	var facing: Basis = Basis(camera_basis.z.normalized(), camera_basis.y.normalized(), -camera_basis.x.normalized())
	for entry: Dictionary in entries:
		var index: int = skeleton.find_bone(str(entry.name))
		if index < 0:
			continue
		var pivot: Vector3 = Vector3(entry.pivot[0], entry.pivot[1], entry.pivot[2])
		var pose: Transform3D = skeleton.get_bone_global_pose(index)
		var center: Vector3 = pose * pivot
		var billboard_basis: Basis = facing.scaled_local(pose.basis.get_scale())
		skeleton.set_bone_global_pose(index, Transform3D(billboard_basis, center - billboard_basis * pivot))
