extends RefCounted
const Curves: GDScript = preload("import_geoset_curves.gd")
## Exact binary, non-global GeosetAnim alpha. Continuous alpha needs composition
## with material-layer alpha and must not be silently reduced to a boolean.
static func compile(scene: Node, ir: Dictionary) -> Dictionary:
	var result: Dictionary = {"meshes": 0, "visibility_tracks": 0, "curve_tracks": 0, "diagnostics": []}
	var payload: Dictionary = ir.get("animations", {}).get("payload", {})
	var meshes: Dictionary = {}
	var players: Array[AnimationPlayer] = []
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			meshes[str(node.name)] = node
		if node is AnimationPlayer:
			players.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	for entry: Dictionary in payload.get("geoset_anims", []):
		var id: int = int(entry.get("geoset_id", -1))
		var mesh: MeshInstance3D = meshes.get("Geoset_%d" % id)
		if mesh == null:
			_warn(result, "geoset_binding_missing", id)
			continue
		var alpha: Dictionary = entry.get("alpha", {}) if entry.get("alpha") is Dictionary else {}
		var sequences: Array = payload.get("sequences", [])
		if (not _supported(alpha) or int(entry.get("flags", 0)) & 2) and players.size() == 1 and _clips_supported(players[0], sequences):
			var curves: Dictionary = Curves.compile(mesh, players[0], entry, sequences)
			if curves.ok:
				result.meshes += 1
				result.curve_tracks += curves.tracks
				continue
		if int(entry.get("flags", 0)) & 2:
			_warn(result, "geoset_color_pending", id)
		if not _supported(alpha):
			_warn(result, "geoset_alpha_pending", id)
			continue
		if alpha.has("static") or alpha.is_empty():
			mesh.visible = _scalar(alpha.get("static", 1.0)) > 0.0
			result.meshes += 1
			continue
		if players.size() != 1 or not _clips_supported(players[0], sequences):
			_warn(result, "geoset_animation_layout_pending", id)
			continue
		var player: AnimationPlayer = players[0]
		var target: NodePath = NodePath(str(player.get_parent().get_path_to(mesh)) + ":visible")
		for sequence: Dictionary in sequences:
			var animation: Animation = player.get_animation(str(sequence.name))
			var start: float = float(sequence.interval[0])
			var end: float = float(sequence.interval[1])
			var keys: Array[Dictionary] = []
			var carry: float = -1.0
			for key: Dictionary in alpha.get("keys", []):
				var frame: float = float(key.frame)
				if frame < start:
					carry = _scalar(key.vector)
				elif frame <= end:
					keys.append(key)
			# No keys means source default. Before a delayed first key, retain
			# source carry-in, matching the converter's sequence-scoped sampler.
			var initial: bool = true
			if not keys.is_empty():
				initial = (_scalar(keys[0].vector) if float(keys[0].frame) == start or carry < 0.0 else carry) > 0.0
			var track: int = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track, target)
			animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
			animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
			animation.track_set_interpolation_loop_wrap(track, false)
			animation.track_insert_key(track, 0.0, initial)
			for key: Dictionary in keys:
				animation.track_insert_key(track, (float(key.frame) - start) / 1000.0, _scalar(key.vector) > 0.0)
			result.visibility_tracks += 1
			# A newly instantiated scene gets a deterministic initial pose too.
			if sequence == sequences[0]:
				mesh.visible = initial
		result.meshes += 1
	return result

static func _scalar(value: Variant) -> float:
	return float(value[0]) if value is Array and not value.is_empty() else float(value)

static func _supported(alpha: Dictionary) -> bool:
	if alpha.has("static"):
		return _scalar(alpha.static) in [0.0, 1.0]
	var global_sequence: Variant = alpha.get("global_seq_id")
	if (global_sequence != null and int(global_sequence) >= 0) or int(alpha.get("line_type", 0)) != 0:
		return false
	for key: Dictionary in alpha.get("keys", []):
		if _scalar(key.vector) not in [0.0, 1.0]:
			return false
	return true

static func _clips_supported(player: AnimationPlayer, sequences: Array) -> bool:
	if player.root_node != NodePath("..") or sequences.is_empty():
		return false
	for sequence: Dictionary in sequences:
		if not player.has_animation(str(sequence.name)):
			return false
		var duration: float = (float(sequence.interval[1]) - float(sequence.interval[0])) / 1000.0
		if absf(player.get_animation(str(sequence.name)).length - duration) > 0.01:
			return false
	return true

static func _warn(result: Dictionary, code: String, id: int) -> void:
	result.diagnostics.append({"code": code, "severity": "warning", "geoset": id})
