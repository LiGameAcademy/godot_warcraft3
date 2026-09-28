extends RefCounted
## Non-global step/linear alpha keys, clipped to their own sequence intervals.
static func supported(player: AnimationPlayer, alpha: Dictionary, ir: Dictionary) -> bool:
	var global_sequence: Variant = alpha.get("GlobalSeqId")
	if (global_sequence != null and int(global_sequence) >= 0) or int(alpha.get("LineType", 0)) not in [0, 1] or player.root_node != NodePath(".."):
		return false
	var sequences: Array = ir.get("animations", {}).get("payload", {}).get("sequences", [])
	if sequences.is_empty():
		return false
	for sequence: Dictionary in sequences:
		if not player.has_animation(str(sequence.name)):
			return false
		if player.get_animation(str(sequence.name)).length > (float(sequence.interval[1]) - float(sequence.interval[0])) / 1000.0 + 0.01:
			return false
	return true

static func compile(player: AnimationPlayer, mesh: MeshInstance3D, surface: int, alpha: Dictionary, ir: Dictionary, shader: bool) -> int:
	var count: int = 0
	var property: String = ":shader_parameter/layer_alpha" if shader else ":albedo_color:a"
	var target: NodePath = NodePath(str(player.get_parent().get_path_to(mesh)) + ":surface_material_override/%d" % surface + property)
	for sequence: Dictionary in ir.animations.payload.sequences:
		var animation: Animation = player.get_animation(str(sequence.name))
		var start: float = float(sequence.interval[0])
		var end: float = float(sequence.interval[1])
		var keys: Array[Dictionary] = []
		for key: Dictionary in alpha.get("Keys", []):
			if float(key.Frame) >= start and float(key.Frame) <= end:
				keys.append(key)
		var track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, target)
		animation.track_set_interpolation_loop_wrap(track, false)
		var stepped: bool = int(alpha.get("LineType", 0)) == 0
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST if stepped else Animation.INTERPOLATION_LINEAR)
		animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE if stepped else Animation.UPDATE_CONTINUOUS)
		# A clip without keys gets the source default, never the previous clip's tail.
		animation.track_insert_key(track, 0.0, float(keys[0].Vector[0]) if not keys.is_empty() else 1.0)
		for key: Dictionary in keys:
			animation.track_insert_key(track, (float(key.Frame) - start) / 1000.0, float(key.Vector[0]))
		count += 1
	return count
