extends RefCounted
const Timing: GDScript = preload("import_sequence_timing.gd")
## Consumer for the legacy flat WC3 skeleton (identity inverse bind matrices).
## Payloads are embedded in IR; no game singletons or sidecar path resolution.

static func compile(scene: Node3D, ir: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "rests": 0, "sockets": 0, "visibility_tracks": 0, "diagnostics": []}
	if ir.get("identity", {}).get("source_format", "") not in ["mdx", "mdl"]:
		result.diagnostics.append({"code": "unsupported_skeleton_adapter", "severity": "error"})
		return result
	var skeletons: Array[Skeleton3D] = []
	var players: Array[AnimationPlayer] = []
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Skeleton3D:
			skeletons.append(node)
		if node is AnimationPlayer:
			players.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	var rest: Variant = ir.get("skeleton", {}).get("rest_payload")
	var attachments: Variant = ir.get("attachments", {}).get("payload")
	if not rest is Dictionary or not attachments is Dictionary:
		result.diagnostics.append({"code": "missing_skeleton_payload", "severity": "error"})
		return result
	if rest.get("version") != 2 or attachments.get("version") != 1 or skeletons.size() > 1 or (skeletons.is_empty() and not rest.get("bones", []).is_empty()):
		result.diagnostics.append({"code": "unsupported_skeleton_layout", "severity": "error"})
		return result
	var skeleton: Skeleton3D = skeletons[0] if not skeletons.is_empty() else null
	for entry: Dictionary in rest.get("bones", []):
		var index: int = skeleton.find_bone(str(entry.get("name", "")))
		if index < 0 or skeleton.get_bone_parent(index) != -1:
			result.diagnostics.append({"code": "bone_mapping_failed", "severity": "error", "bone": str(entry.get("name", "")), "index": index})
			return result
		var rotation: Array = entry.rotation
		var basis: Basis = Basis(Quaternion(rotation[0], rotation[1], rotation[2], rotation[3]))
		skeleton.set_bone_rest(index, Transform3D(basis.scaled(_vec(entry.scale)), _vec(entry.translation)))
		skeleton.reset_bone_pose(index)
		result.rests += 1
	if skeleton != null:
		skeleton.force_update_all_bone_transforms()
	var socket_entries: Array[Dictionary] = []
	var declared: Dictionary[String, Dictionary] = {}
	var markers: Dictionary[String, Marker3D] = {}
	for entry: Dictionary in attachments.get("attachments", []):
		if entry.get("type") == "attachment":
			socket_entries.append(entry)
			declared[str(entry.name)] = entry
	while not socket_entries.is_empty():
		var before: int = socket_entries.size()
		for entry: Dictionary in socket_entries.duplicate():
			var bone: String = str(entry.get("bone", ""))
			if declared.has(bone) and not markers.has(bone):
				continue
			if not _socket(scene, skeleton, players, ir, result, entry, declared, markers):
				return result
			socket_entries.erase(entry)
		if before == socket_entries.size():
			result.diagnostics.append({"code": "socket_parent_cycle", "severity": "error"})
			return result
	result.ok = true
	return result


static func _socket(scene: Node3D, skeleton: Skeleton3D, players: Array[AnimationPlayer], ir: Dictionary, result: Dictionary, entry: Dictionary, declared: Dictionary[String, Dictionary], markers: Dictionary[String, Marker3D]) -> bool:
	var bone: String = str(entry.get("bone", ""))
	var index: int = skeleton.find_bone(bone) if skeleton != null else -1
	if not bone.is_empty() and bone != "<null>" and index < 0 and not declared.has(bone):
		result.diagnostics.append({"code": "socket_bone_missing", "severity": "error", "bone": bone})
		return false
	var marker: Marker3D = Marker3D.new()
	var unit_scale: float = 1.0
	if markers.has(bone):
		var parent_marker: Marker3D = markers[bone]
		unit_scale = float(parent_marker.get_meta("import_socket_unit_scale"))
		parent_marker.add_child(marker)
		marker.name = str(entry.name)
		marker.position = (_vec(entry.pivot) - _vec(declared[bone].pivot)) * unit_scale
	elif index >= 0:
		var socket: BoneAttachment3D = BoneAttachment3D.new()
		socket.name = str(entry.name)
		skeleton.add_child(socket)
		socket.owner = scene
		socket.bone_name = bone
		socket.bone_idx = index
		socket.add_child(marker)
		marker.name = "Tip"
		# Legacy geometry remains in model units beneath the 0.01 root.
		unit_scale = 1.0 / 0.01
		marker.position = _vec(entry.pivot) * unit_scale
	else:
		scene.add_child(marker)
		marker.name = str(entry.name)
		marker.position = _vec(entry.pivot)
	markers[str(entry.name)] = marker
	marker.set_meta("import_socket_unit_scale", unit_scale)
	marker.owner = scene
	marker.visible = bool(entry.get("visibility_default", true))
	marker.set_meta("import_socket", str(entry.name))
	marker.set_meta("source_object_id", entry.get("object_id", -1))
	if entry.has("visibility"):
		if players.size() != 1 or not _visibility(players[0], marker, entry, ir, result):
			result.diagnostics.append({"code": "socket_visibility_not_compiled", "severity": "warning", "socket": str(entry.name)})
	result.sockets += 1
	return true


static func _vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func _visibility(player: AnimationPlayer, marker: Marker3D, entry: Dictionary, ir: Dictionary, result: Dictionary) -> bool:
	var visibility: Dictionary = entry.visibility
	# Continuous/global tracks require a clock-aware consumer; never approximate silently.
	if visibility.get("global_seq_id") != null or int(visibility.get("line_type", 0)) != 0:
		return false
	if player.root_node != NodePath(".."):
		return false
	var sequences: Array = ir.get("animations", {}).get("payload", {}).get("sequences", [])
	if sequences.is_empty():
		return false
	for sequence: Dictionary in sequences:
		if not player.has_animation(str(sequence.name)):
			return false
		if not Timing.compatible(player, sequence):
			return false
	var target: NodePath = NodePath(str(player.get_parent().get_path_to(marker)) + ":visible")
	for sequence: Dictionary in sequences:
		var name: String = str(sequence.name)
		if not player.has_animation(name):
			return false
		var animation: Animation = player.get_animation(name)
		var start_ms: float = float(sequence.interval[0])
		var end_ms: float = float(sequence.interval[1])
		var track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, target)
		animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
		# Seed each clip so switching from Death cannot leave Stand's sockets hidden.
		var initial: bool = bool(entry.get("visibility_default", true))
		if visibility.has("static"):
			var value: Variant = visibility.static
			initial = float(value[0] if value is Array else value) >= 0.5
		animation.track_insert_key(track, 0.0, initial)
		for key: Dictionary in visibility.get("keys", []):
			var frame: float = float(key.frame)
			if frame >= start_ms and frame <= end_ms:
				animation.track_insert_key(track, (frame - start_ms) / 1000.0, float(key.vector[0]) >= 0.5)
		result.visibility_tracks += 1
	return true
