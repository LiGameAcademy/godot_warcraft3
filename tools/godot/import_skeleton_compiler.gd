extends RefCounted
## Consumer for the legacy flat WC3 skeleton (identity inverse bind matrices).
## Payloads are embedded in IR; no game singletons or sidecar path resolution.

static func compile(scene: Node3D, ir: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "rests": 0, "sockets": 0, "diagnostics": []}
	if ir.get("identity", {}).get("source_format", "") not in ["mdx", "mdl"]:
		result.diagnostics.append({"code": "unsupported_skeleton_adapter", "severity": "error"})
		return result
	var skeletons: Array[Skeleton3D] = []
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Skeleton3D:
			skeletons.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	var rest: Variant = ir.get("skeleton", {}).get("rest_payload")
	var attachments: Variant = ir.get("attachments", {}).get("payload")
	if not rest is Dictionary or not attachments is Dictionary:
		result.diagnostics.append({"code": "missing_skeleton_payload", "severity": "error"})
		return result
	if rest.get("version") != 2 or attachments.get("version") != 1 or skeletons.size() != 1:
		result.diagnostics.append({"code": "unsupported_skeleton_layout", "severity": "error"})
		return result
	var skeleton: Skeleton3D = skeletons[0]
	for entry: Dictionary in rest.get("bones", []):
		var index: int = skeleton.find_bone(str(entry.get("name", "")))
		if index < 0 or skeleton.get_bone_parent(index) != -1:
			result.diagnostics.append({"code": "bone_mapping_failed", "severity": "error"})
			return result
		var rotation: Array = entry.rotation
		var basis: Basis = Basis(Quaternion(rotation[0], rotation[1], rotation[2], rotation[3]))
		skeleton.set_bone_rest(index, Transform3D(basis.scaled(_vec(entry.scale)), _vec(entry.translation)))
		skeleton.reset_bone_pose(index)
		result.rests += 1
	skeleton.force_update_all_bone_transforms()
	for entry: Dictionary in attachments.get("attachments", []):
		if entry.get("type") != "attachment":
			continue
		var bone: String = str(entry.get("bone", ""))
		var index: int = skeleton.find_bone(bone)
		if not bone.is_empty() and bone != "<null>" and index < 0:
			result.diagnostics.append({"code": "socket_bone_missing", "severity": "error", "bone": bone})
			return result
		var marker: Marker3D = Marker3D.new()
		if index >= 0:
			var socket: BoneAttachment3D = BoneAttachment3D.new()
			socket.name = str(entry.name)
			skeleton.add_child(socket)
			socket.owner = scene
			socket.bone_name = bone
			socket.bone_idx = index
			socket.add_child(marker)
			marker.name = "Tip"
			# Legacy geometry remains in model units beneath the 0.01 root.
			marker.position = _vec(entry.pivot) / 0.01
		else:
			scene.add_child(marker)
			marker.name = str(entry.name)
			marker.position = _vec(entry.pivot)
		marker.owner = scene
		marker.visible = bool(entry.get("visibility_default", true))
		marker.set_meta("import_socket", str(entry.name))
		marker.set_meta("source_object_id", entry.get("object_id", -1))
		if entry.has("visibility"):
			result.diagnostics.append({"code": "socket_visibility_not_compiled", "severity": "warning", "socket": str(entry.name)})
		result.sockets += 1
	result.ok = true
	return result


static func _vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
